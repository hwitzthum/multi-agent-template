#!/usr/bin/env bash
# Deterministischer Orchestrator: fuehrt den vom Router gewaehlten Modus aus.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/agent/common.sh"
. "$script_dir/agent/ledger.sh"
. "$script_dir/agent/route.sh"

project_dir=$(agent_project_root "$script_dir") || exit 1
selection=''
requested_task=''
manual_mode=''
dry_run=false
allow_dirty=false
lock_held=false
scratch_dir=''
run_active=false
call_sequence=0
run_state=''
run_outcome=''

usage() {
  echo "Verwendung: $0 (--task ID | --next | --dry-run) [--mode MODUS] [--allow-dirty] [--project-dir PFAD]" >&2
  exit 2
}

case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 (--task ID | --next | --dry-run) [--mode MODUS] [--allow-dirty] [--project-dir PFAD]"
    echo "  --dry-run zeigt nur Route, Limits und geplante Rollen; er schreibt nichts."
    exit 0 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) [ "$#" -ge 2 ] || usage; [ -z "$selection" ] || usage; selection=task; requested_task=$2; shift 2 ;;
    --next) [ -z "$selection" ] || usage; selection=next; shift ;;
    --dry-run) dry_run=true; shift ;;
    --mode) [ "$#" -ge 2 ] || usage; manual_mode=$2; shift 2 ;;
    --allow-dirty) allow_dirty=true; shift ;;
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    *) echo "orchestrate: unbekannte Option $1" >&2; usage ;;
  esac
done
[ -n "$selection" ] || { [ "$dry_run" = true ] && selection=next || usage; }
case "$manual_mode" in ''|single|verified|managed) ;; *) echo "orchestrate: unbekannter Modus '$manual_mode'" >&2; exit 1 ;; esac

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "orchestrate: Projektpfad fehlt" >&2; exit 1; }
validator="$script_dir/validate-ledger.sh"
config_reader="$script_dir/agent/config.sh"
status_gate="$script_dir/agent/status.sh"
verification_gateway="$script_dir/verify-task.sh"
context_builder="$script_dir/agent/context.sh"
output_tool="$script_dir/agent/output.sh"
runner_adapter="$script_dir/agent/runner.sh"
runner=${ORCHESTRATOR_RUNNER:-$runner_adapter}
tasks_dir="$project_dir/docs/tasks"
verification_dir="$project_dir/docs/verification"
notes_file="$project_dir/docs/state/notes.md"
lock_dir="$project_dir/.agent-runs/.orchestrator-lock"

[ -x "$runner" ] || { echo "orchestrate: Runner ist nicht ausführbar: $runner" >&2; exit 1; }
"$config_reader" --check "$project_dir/.agent/config.env" || exit 1
"$validator" --project-dir "$project_dir" >/dev/null || exit 1
max_iterations=$("$config_reader" --get MAX_GLOBAL_ITERATIONS "$project_dir/.agent/config.env") || exit 1
max_task_attempts=$("$config_reader" --get MAX_TASK_ATTEMPTS "$project_dir/.agent/config.env") || exit 1
max_no_progress=$("$config_reader" --get MAX_NO_PROGRESS "$project_dir/.agent/config.env") || exit 1
verify_timeout=$("$config_reader" --get VERIFY_TIMEOUT_SECONDS "$project_dir/.agent/config.env") || exit 1
max_infra_retries=$("$config_reader" --get MAX_INFRA_RETRIES "$project_dir/.agent/config.env") || exit 1
retry_backoff=$("$config_reader" --get RETRY_BACKOFF_SECONDS "$project_dir/.agent/config.env") || exit 1

task_is_ready() {
  candidate=$1
  candidate_file=$(ledger_task_path_by_id "$tasks_dir" "$candidate") || return 1
  candidate_status=$(ledger_scalar "$candidate_file" status) || return 1
  [ "$candidate_status" = todo ] || return 1
  candidate_attempts=$(ledger_scalar "$candidate_file" attempts) || return 1
  [ "$candidate_attempts" -lt "$max_task_attempts" ] || return 1
  while IFS= read -r dependency; do
    [ -n "$dependency" ] || continue
    dependency_file=$(ledger_task_path_by_id "$tasks_dir" "$dependency") || return 1
    [ "$(ledger_scalar "$dependency_file" status)" = done ] || return 1
  done <<EOF
$(ledger_list "$candidate_file" depends_on)
EOF
}

select_next_task() {
  "$script_dir/next-tasks.sh" --project-dir "$project_dir" | awk -F '[ |]+' '$1 == "READY:" { print $2; exit }'
}

# Das harte Limit der Konfiguration gilt auch dann, wenn ein Task ein hoeheres
# max_attempts traegt.
task_max_attempts() {
  value=$(ledger_scalar "$task_file" max_attempts) || return 1
  [ "$value" -le "$max_task_attempts" ] || value=$max_task_attempts
  printf '%s\n' "$value"
}

# Der Laufzustand ist unversioniert: eine flache KEY=VALUE-Datei im Laufordner.
# Sie wird nie gelesen, um einen Lauf fortzusetzen, sondern nur, um innerhalb
# eines Aufrufs Phase, Runde und Fortschritt zu fuehren und am Ende einen
# Beleg zu hinterlassen.
run_state_get() {
  [ -f "$run_state" ] || return 1
  awk -F= -v wanted="$1" '$1 == wanted { print substr($0, length(wanted) + 2); found=1; exit } END { if (!found) exit 1 }' "$run_state"
}

run_state_set() {
  key=$1
  value=$2
  case "$value" in *$'\n'*) return 1 ;; esac
  temporary="$run_dir/.run.env.tmp"
  awk -F= -v wanted="$key" -v replacement="$value" '
    $1 == wanted { print wanted "=" replacement; seen=1; next }
    { print }
    END { if (!seen) print wanted "=" replacement }
  ' "$run_state" > "$temporary" || { rm -f "$temporary"; return 1; }
  mv -f "$temporary" "$run_state"
}

create_run_state() {
  {
    echo "run_id=$run_id"
    echo "task_id=$task_id"
    echo "mode=$mode"
    echo "phase=plan"
    echo "iteration=1"
    echo "attempt=${run_attempt:-1}"
    echo "last_progress_fingerprint=none"
    echo "started_at=$started_at"
    echo "human_gate=$human_gate"
    echo "outcome="
  } > "$run_state"
}

# Eine Zeile pro Lauf, append-only, unversioniert. Keine Migration, kein
# Schema-Gate: der Beleg dient dem Nachlesen, nicht der Steuerung.
append_run_metric() {
  outcome=$1
  metrics_file="$project_dir/.agent-runs/metrics.csv"
  [ -f "$metrics_file" ] || printf '%s\n' 'run_id,task_id,mode,attempt,outcome,started_at,finished_at' > "$metrics_file"
  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "$run_id" "$task_id" "$mode" "$(run_state_get attempt 2>/dev/null || echo 0)" \
    "$outcome" "$started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$metrics_file"
}

task_control_snapshot() {
  destination=$1
  : > "$destination"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    printf '%s|%s|%s|%s|%s\n' \
      "$(ledger_scalar "$file" id)" "$(ledger_scalar "$file" status)" \
      "$(ledger_scalar "$file" attempts)" "$(ledger_scalar "$file" last_verification)" \
      "$(ledger_scalar "$file" blocked_reason)" >> "$destination"
  done <<EOF
$(ledger_task_files "$tasks_dir")
EOF
}

# Setzt Pfade auf den Stand eines Manifests zurueck. Was das Manifest nicht
# kennt, ist nach dem Snapshot entstanden und wandert in die Quarantaene des
# Laufs statt geloescht zu werden.
restore_paths() {
  manifest=$1
  shift
  [ "$#" -gt 0 ] || return 0
  mkdir -p "$run_dir/quarantine" || return 1
  agent_snapshot_restore "$project_dir" "$manifest" "$run_dir/quarantine" "$@"
}

restore_changed_paths() {
  manifest=$1
  changes_file=$2
  restore_list=()
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    restore_list+=("$changed")
  done < "$changes_file"
  [ "${#restore_list[@]}" -gt 0 ] || return 0
  restore_paths "$manifest" "${restore_list[@]}"
}

path_in_task_scope() {
  path=$1
  touches=$(ledger_list "$task_file" touches 2>/dev/null || true)
  [ -n "$touches" ] || return 0
  while IFS= read -r allowed; do
    [ -n "$allowed" ] || continue
    allowed=${allowed%/}
    case "$path" in "$allowed"|"$allowed"/*) return 0 ;; esac
  done <<EOF
$touches
EOF
  return 1
}

check_role_changes() {
  role=$1
  changes_file=$2
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    "$script_dir/agent/policy.sh" role-write "$role" "$changed" >/dev/null 2>&1 || {
      echo "orchestrate: Rolle $role änderte verbotenen Pfad $changed" >&2
      return 1
    }
    case "$role" in worker-task|worker-fresh)
      path_in_task_scope "$changed" || { echo "orchestrate: Pfad $changed liegt außerhalb des Task-Umfangs" >&2; return 1; } ;;
    esac
  done < "$changes_file"
}

run_role() {
  role=$1
  role_task=${2:-}
  phase=$3
  run_state_set phase "$phase" || return 1
  call_sequence=$((call_sequence + 1))
  label=$(printf '%02d-%s' "$call_sequence" "$role")
  raw="$run_dir/outputs/$label.raw"
  metadata="$run_dir/metadata/$label.env"
  # Das Vorher-Manifest liegt ausserhalb des Arbeitsbaums, solange der Agent
  # laeuft: unter .agent-runs/ koennte er es passend zu seinen Aenderungen
  # umschreiben und so den Abgleich entwerten.
  before="$scratch_dir/$label.before"
  after="$run_dir/manifests/$label.after"
  changes="$run_dir/manifests/$label.changed"
  controls_before="$scratch_dir/$label.controls-before"
  controls_after="$run_dir/manifests/$label.controls-after"
  mkdir -p "$run_dir/outputs" "$run_dir/metadata" "$run_dir/manifests" || return 1

  context_args=(build --project-dir "$project_dir" --role "$role" --run-id "$run_id")
  if [ -n "$role_task" ]; then context_args+=(--task-id "$role_task"); fi
  case "$role" in worker-task|worker-fresh)
    while IFS= read -r include; do [ -n "$include" ] && context_args+=(--include "$include"); done <<EOF
$(ledger_list "$task_file" touches 2>/dev/null || true)
EOF
    ;;
  esac
  context=$("$context_builder" "${context_args[@]}") || return 1
  agent_repo_manifest "$project_dir" "$before" || return 1
  task_control_snapshot "$controls_before" || return 1
  # Nur ein Providerfehler wird wiederholt: Exit ungleich null oder
  # output_status=error. Eine leere oder abgeschnittene Antwort ist eine Aussage
  # des Modells und wird nie als Infrastrukturfehler umgedeutet. Ein Retry
  # zaehlt keinen Task-Versuch.
  infra_retry=0
  while :; do
    "$runner" run_agent "$role" "$context" "$project_dir" "$raw" "$metadata"
    runner_status=$?
    "$runner_adapter" validate_metadata "$metadata" >/dev/null 2>&1 || { run_outcome=infrastructure_error; echo "orchestrate: ungültige Runner-Metadaten für $role" >&2; return 1; }
    output_status=$(awk -F= '$1 == "output_status" { print $2; exit }' "$metadata")
    if [ "$runner_status" -eq 0 ] && [ "$output_status" != error ]; then break; fi
    if [ "$infra_retry" -ge "$max_infra_retries" ]; then
      run_outcome=infrastructure_error
      echo "orchestrate: Agentenaufruf $role scheiterte endgültig (Exit $runner_status, Ausgabe $output_status)" >&2
      return 1
    fi
    infra_retry=$((infra_retry + 1))
    sleep "$retry_backoff"
  done
  [ "$output_status" = ok ] || { run_outcome=infrastructure_error; echo "orchestrate: Agentenausgabe $role ist leer, abgeschnitten oder fehlerhaft" >&2; return 1; }
  "$output_tool" validate "$role" "$raw" >/dev/null || return 1
  agent_repo_manifest "$project_dir" "$after" || return 1
  agent_manifest_changes "$before" "$after" > "$changes"
  mv -f "$before" "$run_dir/manifests/$label.before" || return 1
  mv -f "$controls_before" "$run_dir/manifests/$label.controls-before" || return 1
  before="$run_dir/manifests/$label.before"
  controls_before="$run_dir/manifests/$label.controls-before"
  if ! check_role_changes "$role" "$changes"; then
    restore_changed_paths "$before" "$changes" || echo "orchestrate: Ruecksetzen nach Regelverstoss scheiterte" >&2
    return 1
  fi
  task_control_snapshot "$controls_after" || return 1
  case "$role" in manager-plan|manager-manage|worker-brainstorm|worker-task|worker-fresh|finalizer)
    case "$role" in manager-plan|manager-manage)
      while IFS= read -r protected_line; do
        grep -Fqx "$protected_line" "$controls_after" || { echo "orchestrate: Manager änderte geschützte Task-Steuerfelder" >&2; return 1; }
      done < "$controls_before"
      while IFS= read -r current_line; do
        grep -Fqx "$current_line" "$controls_before" && continue
        case "$current_line" in *'|todo|0|never|'*) ;; *) echo "orchestrate: neuer Manager-Task besitzt unzulässige Steuerwerte" >&2; return 1 ;; esac
      done < "$controls_after" ;;
    esac
    ;;
  esac
  "$validator" --project-dir "$project_dir" >/dev/null || return 1
  last_raw=$raw
  last_changes=$changes
}

output_value() {
  key=$1
  file=$2
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0,length(wanted)+2); exit }' "$file"
}

manager_value() {
  key=$1
  file=$2
  awk -v wanted="$key" 'index($0,wanted ":") == 1 { value=substr($0,length(wanted)+2); sub(/^[[:space:]]*/,"",value); print value; exit }' "$file"
}

verify_candidate() {
  run_state_set phase verify || return 1
  call_sequence=$((call_sequence + 1))
  mkdir -p "$run_dir/outputs" || return 1
  verify_log="$run_dir/outputs/$(printf '%02d' "$call_sequence")-verify.log"
  attempt_value=$(ledger_scalar "$task_file" attempts) || return 1
  attempt_value=$((attempt_value + 1))
  if "$verification_gateway" --project-dir "$project_dir" --run-id "$run_id" --attempt "$attempt_value" --timeout "$verify_timeout" "$task_id" > "$verify_log" 2>&1; then
    verification_result=green
  else
    verification_result=red
  fi
  [ "$verification_result" = green ]
}

append_failure_note() {
  finding="Task $task_id: Verifikation rot; siehe docs/verification/latest.md."
  grep -Fq -- "- finding: $finding" "$notes_file" && return 0
  lock="$project_dir/docs/state/.notes-write-lock"
  mkdir "$lock" 2>/dev/null || { echo "orchestrate: Notes werden bereits geschrieben" >&2; return 1; }
  temp=$(mktemp "$project_dir/docs/state/.notes.tmp.XXXXXX") || { rmdir "$lock"; return 1; }
  cp "$notes_file" "$temp" || { rm -f "$temp"; rmdir "$lock"; return 1; }
  next=$(awk '/^## N-[0-9]+[[:space:]]/ { id=$2; sub(/^N-/,"",id); if (id+0>max) max=id+0 } END { printf "%04d", max+1 }' "$notes_file")
  {
    echo
    echo "## N-$next — Fehlgeschlagene Verifikation"
    echo "- tasks: [$task_id]"
    echo "- date: $(date -u +%Y-%m-%d)"
    echo '- source: orchestrator'
    echo '- confidence: observed'
    echo '- status: active'
    echo '- evidence: `docs/verification/latest.md`'
    echo "- finding: $finding"
  } >> "$temp"
  agent_atomic_write "$notes_file" "$temp" || { rm -f "$temp"; rmdir "$lock"; return 1; }
  rm -f "$temp"
  rmdir "$lock" 2>/dev/null || true
}

record_failure() {
  attempts=$(ledger_scalar "$task_file" attempts) || return 1
  max_attempts=$(task_max_attempts) || return 1
  [ "$attempts" -lt "$max_attempts" ] || return 1
  new_attempts=$((attempts + 1))
  validate_task_candidate() { "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null; }
  ledger_atomic_replace_scalar "$task_file" attempts "$new_attempts" validate_task_candidate || return 1
  run_state_set attempt "$((new_attempts + 1))" || return 1
  append_failure_note || return 1
}

finish_success() {
  human_review=$(ledger_scalar "$task_file" human_review) || return 1
  if [ "$human_review" = true ] || [ "$(run_state_get human_gate 2>/dev/null || echo false)" = true ]; then target=review; else target=done; fi
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" "$target" in_progress || return 1
  if [ "$target" = review ]; then run_outcome=review; else run_outcome=success; fi
  run_state_set phase finished || return 1
  run_active=false
  echo "orchestrate: Task $task_id ist $target"
}

finish_single_red() {
  record_failure || true
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress || return 1
  if [ "$(ledger_scalar "$verification_dir/latest.md" failure_kind 2>/dev/null || true)" = verifier ]; then run_outcome=verification_error; else run_outcome=blocked; fi
  run_state_set phase finished || return 1
  run_active=false
  echo "orchestrate: Task $task_id blieb nach roter Prüfung offen" >&2
  return 1
}

block_current_task() {
  reason=$1
  safe_reason=$(printf '%s' "$reason" | tr -cd 'A-Za-z0-9_.:-' | cut -c1-120)
  [ -n "$safe_reason" ] || safe_reason=ORCHESTRATION_BLOCKED
  validate_task_candidate() { "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null; }
  ledger_atomic_replace_scalar "$task_file" blocked_reason "$safe_reason" validate_task_candidate || return 1
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" blocked in_progress || return 1
  case "$safe_reason" in
    NO_PROGRESS) run_outcome=no_progress ;;
    *VERIFY_ERROR*) run_outcome=verification_error ;;
    *) run_outcome=blocked ;;
  esac
  run_state_set phase finished || return 1
  run_active=false
  echo "orchestrate: Task $task_id blockiert ($safe_reason)" >&2
}

progress_fingerprint() {
  decision_file=$1
  product="$run_dir/.progress-product"
  task_state="$run_dir/.progress-tasks"
  agent_product_manifest "$project_dir" "$product" || return 1
  : > "$task_state"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    printf '%s|%s|%s\n' "$(ledger_scalar "$file" id)" "$(ledger_scalar "$file" status)" "$(ledger_scalar "$file" last_verification)" >> "$task_state"
  done <<EOF
$(ledger_task_files "$tasks_dir")
EOF
  {
    cat "$product"
    cat "$task_state"
    shasum -a 256 "$project_dir/scripts/verify.sh"
    printf 'verification=%s\n' "${verification_result:-none}"
    awk '/^## N-[0-9]+[[:space:]]/ { print $2 }' "$notes_file"
    [ -f "$decision_file" ] && cat "$decision_file"
  } | shasum -a 256 | awk '{print $1}'
}

run_finalizer_role() {
  run_state_set phase finalize || return 1
  finalizer_context=$("$context_builder" build --project-dir "$project_dir" --role finalizer --run-id "$run_id" --task-id "$task_id") || return 1
  finalizer_workspace=$(mktemp -d "${TMPDIR:-/tmp}/agent-finalizer.XXXXXX") || return 1
  mkdir -p "$finalizer_workspace/.agent" "$finalizer_workspace/.agent-runs/$run_id/outputs" "$finalizer_workspace/.agent-runs/$run_id/metadata" || { rm -rf "$finalizer_workspace"; return 1; }
  cp -R "$project_dir/docs" "$finalizer_workspace/docs" || { rm -rf "$finalizer_workspace"; return 1; }
  cp -R "$project_dir/scripts" "$finalizer_workspace/scripts" || { rm -rf "$finalizer_workspace"; return 1; }
  cp "$project_dir/.agent/config.env" "$finalizer_workspace/.agent/config.env" || { rm -rf "$finalizer_workspace"; return 1; }
  finalizer_context_copy="$finalizer_workspace/.agent-runs/$run_id/finalizer.context.md"
  cp "$finalizer_context" "$finalizer_context_copy" || { rm -rf "$finalizer_workspace"; return 1; }
  # Die Arbeitskopie braucht ein eigenes Git, weil Manifeste Dateiliste und
  # Hashes von Git beziehen. Der Laufordner bleibt dabei aussen vor.
  printf '%s\n' '.agent-runs/' > "$finalizer_workspace/.gitignore" || { rm -rf "$finalizer_workspace"; return 1; }
  git -C "$finalizer_workspace" init -q || { rm -rf "$finalizer_workspace"; return 1; }
  finalizer_raw="$finalizer_workspace/.agent-runs/$run_id/outputs/finalizer.raw"
  finalizer_metadata="$finalizer_workspace/.agent-runs/$run_id/metadata/finalizer.env"
  before="$scratch_dir/finalizer.before"
  after="$finalizer_workspace/.agent-runs/$run_id/after.manifest"
  changes="$finalizer_workspace/.agent-runs/$run_id/changed-paths.txt"
  agent_repo_manifest "$finalizer_workspace" "$before" || { rm -rf "$finalizer_workspace"; return 1; }
  ORCHESTRATOR_PROJECT_DIR="$project_dir" "$runner" run_agent finalizer "$finalizer_context_copy" "$finalizer_workspace" "$finalizer_raw" "$finalizer_metadata"
  finalizer_status=$?
  "$runner_adapter" validate_metadata "$finalizer_metadata" >/dev/null 2>&1 || { rm -rf "$finalizer_workspace"; return 1; }
  [ "$finalizer_status" -eq 0 ] && [ "$(awk -F= '$1 == "output_status" { print $2; exit }' "$finalizer_metadata")" = ok ] || { rm -rf "$finalizer_workspace"; return 1; }
  "$output_tool" validate finalizer "$finalizer_raw" >/dev/null || { rm -rf "$finalizer_workspace"; return 1; }
  agent_repo_manifest "$finalizer_workspace" "$after" || { rm -rf "$finalizer_workspace"; return 1; }
  agent_manifest_changes "$before" "$after" > "$changes"
  mv -f "$before" "$finalizer_workspace/.agent-runs/$run_id/before.manifest" || { rm -rf "$finalizer_workspace"; return 1; }
  check_role_changes finalizer "$changes" || { rm -rf "$finalizer_workspace"; return 1; }
  "$validator" --project-dir "$finalizer_workspace" >/dev/null || { rm -rf "$finalizer_workspace"; return 1; }
  cp "$project_dir/docs/state/handoff.md" "$run_dir/finalizer-handoff.before" || { rm -rf "$finalizer_workspace"; return 1; }
  cp "$project_dir/docs/state/notes.md" "$run_dir/finalizer-notes.before" || { rm -rf "$finalizer_workspace"; return 1; }
  agent_atomic_write "$project_dir/docs/state/handoff.md" "$finalizer_workspace/docs/state/handoff.md" || { rm -rf "$finalizer_workspace"; return 1; }
  agent_atomic_write "$project_dir/docs/state/notes.md" "$finalizer_workspace/docs/state/notes.md" || {
    agent_atomic_write "$project_dir/docs/state/handoff.md" "$run_dir/finalizer-handoff.before" || true
    rm -rf "$finalizer_workspace"
    return 1
  }
  if ! "$validator" --project-dir "$project_dir" >/dev/null; then
    agent_atomic_write "$project_dir/docs/state/handoff.md" "$run_dir/finalizer-handoff.before" || true
    agent_atomic_write "$project_dir/docs/state/notes.md" "$run_dir/finalizer-notes.before" || true
    rm -rf "$finalizer_workspace"
    return 1
  fi
  cp "$finalizer_raw" "$run_dir/outputs/$(printf '%02d' "$((call_sequence + 1))")-finalizer.raw" || true
  cp "$finalizer_metadata" "$run_dir/metadata/$(printf '%02d' "$((call_sequence + 1))")-finalizer.env" || true
  call_sequence=$((call_sequence + 1))
  rm -rf "$finalizer_workspace"
}

run_finalizer() {
  reason=$1
  if run_finalizer_role; then :; else echo "orchestrate: Finalizer scheiterte" >&2; fi
  block_current_task "$reason"
}

# Ein Fresh-Versuch beginnt beim Laufstart: alles, was der Task anfassen darf
# und seither anders ist, wird auf den Snapshot zurueckgesetzt. Die Rolle
# worker-fresh bekommt Kontext ohne Notizen und ohne Vorbericht.
run_fresh_attempt() {
  now="$scratch_dir/fresh-now.manifest"
  agent_repo_manifest "$project_dir" "$now" || return 1
  restore_list=()
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    path_in_task_scope "$changed" || continue
    restore_list+=("$changed")
  done <<EOF
$(agent_manifest_changes "$run_start_manifest" "$now")
EOF
  rm -f "$now"
  if [ "${#restore_list[@]}" -gt 0 ]; then
    restore_paths "$run_start_manifest" "${restore_list[@]}" || {
      echo "orchestrate: Ruecksetzen auf den Laufstart scheiterte" >&2
      return 1
    }
  fi
  run_role worker-fresh "$task_id" work
}

switch_to_task() {
  selected=$1
  [ "$selected" = "$task_id" ] && return 0
  task_is_ready "$selected" || { echo "orchestrate: Manager wählte nicht bereiten Task $selected" >&2; return 1; }
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress || return 1
  "$status_gate" --project-dir "$project_dir" set-status "$selected" in_progress todo || return 1
  task_id=$selected
  task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || return 1
  run_state_set task_id "$task_id"
}

plan_is_placeholder() {
  # Der Plan gilt als Platzhalter, solange der Abschnitt "Aktuelle Strategie"
  # leer ist oder noch den Starttext der Vorlage traegt.
  strategy=$(awk '$0 == "## Aktuelle Strategie" { inside=1; next } inside && /^## / { exit } inside { print }' "$project_dir/docs/state/plan.md")
  [ -n "$(printf '%s' "$strategy" | tr -d '[:space:]')" ] || return 0
  printf '%s\n' "$strategy" | grep -q 'Noch keine Strategie festgelegt'
}

managed_loop() {
  if plan_is_placeholder; then
    run_role manager-plan '' plan || return 1
  fi
  if [ ! -f "$run_dir/brainstorm.done" ]; then
    run_role worker-brainstorm "$task_id" brainstorm || return 1
    : > "$run_dir/brainstorm.done"
  fi

  no_progress=0
  iteration=$(run_state_get iteration)
  while [ "$iteration" -le "$max_iterations" ]; do
    run_state_set iteration "$iteration" || return 1
    run_role manager-manage '' plan || return 1
    decision=$last_raw
    action=$(manager_value action "$decision")
    selected=$(manager_value task_id "$decision")
    reason=$(manager_value reason_code "$decision")
    case "$action" in
      request_human)
        run_state_set phase paused || return 1
        run_outcome=paused
        echo "orchestrate: menschliche Entscheidung erforderlich ($reason)"
        return 0 ;;
      blocked)
        run_finalizer "$reason"
        return 1 ;;
      done)
        [ "$(ledger_scalar "$task_file" last_verification)" = green ] && ledger_verification_is_green "$verification_dir" "$task_id" "$project_dir" "$task_file" || {
          echo "orchestrate: Manager meldete done ohne grünen Prüfbeleg" >&2
          run_state_set phase failed || true
          return 1
        }
        finish_success
        return ;;
      dispatch) ;;
      *) echo "orchestrate: ungültige Manageraktion" >&2; return 1 ;;
    esac

    switch_to_task "$selected" || { run_state_set phase failed || true; return 1; }
    worker_kind=$(manager_value worker_kind "$decision")
    case "$worker_kind" in normal|fresh) ;; *) echo "orchestrate: unbekannte Worker-Art" >&2; run_state_set phase paused; return 1 ;; esac
    # Der letzte erlaubte Versuch laeuft immer fresh: eine Runde ohne die
    # Vorgeschichte, die bis hierher nicht getragen hat.
    attempts=$(ledger_scalar "$task_file" attempts) || return 1
    attempt_limit=$(task_max_attempts) || return 1
    if [ "$worker_kind" = fresh ] || [ "$((attempts + 1))" -ge "$attempt_limit" ]; then
      run_fresh_attempt || return 1
    else
      run_role worker-task "$task_id" work || return 1
    fi
    worker_result=$(output_value RESULT "$last_raw")
    [ "$worker_result" != blocked ] || { run_finalizer WORKER_BLOCKED; return 1; }
    if verify_candidate; then finish_success; return; fi
    record_failure || { run_finalizer ATTEMPT_LIMIT; return 1; }

    fingerprint=$(progress_fingerprint "$decision") || return 1
    previous=$(run_state_get last_progress_fingerprint)
    if [ "$fingerprint" = "$previous" ]; then no_progress=$((no_progress + 1)); else no_progress=0; fi
    run_state_set last_progress_fingerprint "$fingerprint" || return 1
    if [ "$no_progress" -ge "$max_no_progress" ]; then run_finalizer NO_PROGRESS; return 1; fi
    iteration=$((iteration + 1))
  done
  run_finalizer ITERATION_LIMIT
  return 1
}

# Ein Lauf endet nie mit einem Task in `in_progress`: was der Orchestrator
# angefangen hat, faellt beim Abbruch auf `todo` zurueck. Nur so ist der
# naechste Aufruf ein sauberer Neustart statt einer Wiederaufnahme.
release_active_task() {
  [ -n "${task_file:-}" ] || return 0
  [ "$(ledger_scalar "$task_file" status 2>/dev/null || true)" = in_progress ] || return 0
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress >/dev/null 2>&1 \
    || echo "orchestrate: Task $task_id konnte nicht auf todo zurueckgesetzt werden" >&2
}

cleanup() {
  exit_status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$run_state" ] && [ -f "$run_state" ]; then
    phase=$(run_state_get phase 2>/dev/null || true)
    case "$phase" in finished|paused) ;; *) run_state_set phase failed >/dev/null 2>&1 || true ;; esac
    if [ -z "$run_outcome" ]; then
      if [ "$exit_status" -eq 130 ]; then
        run_outcome=cancelled
      else
        case "$(ledger_scalar "$task_file" status 2>/dev/null || true)" in
          done) run_outcome=success ;;
          review) run_outcome=review ;;
          blocked) run_outcome=blocked ;;
          *) run_outcome=failed ;;
        esac
      fi
    fi
    run_state_set outcome "$run_outcome" >/dev/null 2>&1 || true
    append_run_metric "$run_outcome" || true
  fi
  [ "$run_active" = false ] || release_active_task
  [ -z "$scratch_dir" ] || rm -rf "$scratch_dir"
  [ "$lock_held" = false ] || agent_release_lock "$lock_dir"
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# Ein --dry-run zeigt nur, was ein echter Lauf taete: keine Sperre, kein
# Laufordner, keine Datei aendert sich.
case "$selection" in
  task) task_id=$requested_task ;;
  next) task_id=$(select_next_task); [ -n "$task_id" ] || { echo "orchestrate: kein bereiter Task" >&2; exit 1; } ;;
esac
case "$task_id" in ''|*[!0-9]*) echo "orchestrate: ungültige Task-ID" >&2; exit 1 ;; esac

if [ "$dry_run" = true ]; then
  task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
  mode=$(agent_route_mode "$task_file" "$manual_mode" "$max_task_attempts") || exit 1
  human_gate=$(ledger_scalar "$task_file" human_review) || exit 1
  [ "$(ledger_scalar "$task_file" class)" != open ] || human_gate=true
  printf 'DRY_RUN=true\nTASK_ID=%s\nMODE=%s\nHUMAN_GATE=%s\nMAX_GLOBAL_ITERATIONS=%s\nMAX_TASK_ATTEMPTS=%s\nMAX_NO_PROGRESS=%s\n' \
    "$task_id" "$mode" "$human_gate" "$max_iterations" "$max_task_attempts" "$max_no_progress"
  case "$mode" in
    single) echo 'PLANNED_CALLS=worker-task,verify' ;;
    verified) echo 'PLANNED_CALLS=worker-task,verify,worker-task-if-red,verify-if-fixed,manager-if-still-red' ;;
    managed) echo 'PLANNED_CALLS=manager-plan-if-needed,worker-brainstorm-once,manager-manage,worker-task-or-fresh,verify,repeat-bounded' ;;
    *) echo 'PLANNED_CALLS=none' ;;
  esac
  exit 0
fi

mkdir -p "$project_dir/.agent-runs" || exit 1
agent_acquire_lock "$lock_dir" || exit 1
lock_held=true

# Wer die Sperre haelt, ist der einzige Lauf. Ein Task, der trotzdem noch
# `in_progress` traegt, stammt aus einem abgebrochenen Lauf und faellt hier
# sichtbar auf `todo` zurueck.
while IFS= read -r stale_file; do
  [ -n "$stale_file" ] || continue
  [ "$(ledger_scalar "$stale_file" status 2>/dev/null || true)" = in_progress ] || continue
  stale_id=$(ledger_scalar "$stale_file" id) || continue
  echo "orchestrate: abgebrochener Lauf gefunden; Task $stale_id wird auf todo zurueckgesetzt" >&2
  "$status_gate" --project-dir "$project_dir" set-status "$stale_id" todo in_progress >/dev/null || exit 1
done <<EOF
$(ledger_task_files "$tasks_dir")
EOF

task_is_ready "$task_id" || { echo "orchestrate: Task $task_id ist nicht bereit" >&2; exit 1; }
task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
attempts_at_start=$(ledger_scalar "$task_file" attempts) || exit 1
[ "$attempts_at_start" -lt "$max_task_attempts" ] || { echo "orchestrate: hartes Versuchslimit für Task $task_id ist erreicht" >&2; exit 1; }
run_attempt=$((attempts_at_start + 1))
mode=$(agent_route_mode "$task_file" "$manual_mode" "$max_task_attempts") || exit 1
# Ein offener Task und ein ausdruecklich verlangtes Review enden nie
# unbesehen auf done.
human_gate=$(ledger_scalar "$task_file" human_review) || exit 1
[ "$(ledger_scalar "$task_file" class)" != open ] || human_gate=true
[ "$mode" != blocked ] || { echo "orchestrate: Router blockiert Task $task_id vor dem Start" >&2; exit 1; }

# Ohne Commit gibt es keinen Stand, gegen den «schmutzig» etwas bedeuten
# koennte. Das Ledger zaehlt nicht mit: der Orchestrator schreibt es selbst.
if git -C "$project_dir" rev-parse --verify -q HEAD >/dev/null 2>&1 &&
   [ -n "$(git -C "$project_dir" status --porcelain -- \
     ':(exclude)docs/tasks' ':(exclude)docs/state' ':(exclude)docs/verification' 2>/dev/null)" ]; then
  if [ "$allow_dirty" = false ]; then
    echo "orchestrate: Arbeitsverzeichnis ist nicht sauber; wiederhole bewusst mit --allow-dirty" >&2
    exit 1
  fi
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")"
run_dir="$project_dir/.agent-runs/$run_id"
mkdir "$run_dir" || exit 1
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-scratch.XXXXXX") || exit 1
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"$status_gate" --project-dir "$project_dir" set-status "$task_id" in_progress todo >/dev/null || exit 1
run_active=true
run_state="$run_dir/run.env"
create_run_state || exit 1
# Der Snapshot des Laufstarts liegt ausserhalb des Arbeitsbaums: ein Agent
# duerfte ihn sonst passend zu seinen Aenderungen umschreiben.
run_start_manifest="$scratch_dir/run-start.manifest"
agent_repo_manifest "$project_dir" "$run_start_manifest" || exit 1

case "$mode" in
  single)
    run_role worker-task "$task_id" work || exit 1
    [ "$(output_value RESULT "$last_raw")" != blocked ] || { block_current_task WORKER_BLOCKED; exit 1; }
    if verify_candidate; then finish_success; else finish_single_red; fi ;;
  verified)
    run_role worker-task "$task_id" work || exit 1
    [ "$(output_value RESULT "$last_raw")" != blocked ] || { block_current_task WORKER_BLOCKED; exit 1; }
    if verify_candidate; then finish_success; exit 0; fi
    record_failure || { run_finalizer ATTEMPT_LIMIT; exit 1; }
    run_role worker-task "$task_id" work || exit 1
    [ "$(output_value RESULT "$last_raw")" != blocked ] || { block_current_task WORKER_BLOCKED; exit 1; }
    if verify_candidate; then finish_success; exit 0; fi
    record_failure || { run_finalizer ATTEMPT_LIMIT; exit 1; }
    # Zwei rote Versuche heben den Rang: der Router liest die neuen attempts.
    mode=$(agent_route_mode "$task_file" "$manual_mode" "$max_task_attempts") || exit 1
    run_state_set mode "$mode" || exit 1
    if [ "$mode" = managed ]; then managed_loop; else run_finalizer ATTEMPT_LIMIT; exit 1; fi ;;
  managed) managed_loop ;;
  *) echo "orchestrate: Modus $mode wird nicht ausgeführt" >&2; run_state_set phase paused || true; exit 1 ;;
esac
