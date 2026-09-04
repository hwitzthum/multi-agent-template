#!/usr/bin/env bash
# Deterministischer Orchestrator fuer Single-, Verified- und Managed-Laeufe.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/agent/common.sh"
. "$script_dir/agent/ledger.sh"

project_dir=$(agent_project_root "$script_dir") || exit 1
selection=''
requested_task=''
manual_mode=''
resume=false
dry_run=false
allow_dirty=false
lock_held=false
run_active=false
call_sequence=0

usage() {
  echo "Verwendung: $0 (--task ID | --next | --resume | --dry-run) [--mode MODUS] [--allow-dirty] [--project-dir PFAD]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) [ "$#" -ge 2 ] || usage; [ -z "$selection" ] || usage; selection=task; requested_task=$2; shift 2 ;;
    --next) [ -z "$selection" ] || usage; selection=next; shift ;;
    --resume) [ -z "$selection" ] || usage; selection=resume; resume=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    --mode) [ "$#" -ge 2 ] || usage; manual_mode=$2; shift 2 ;;
    --allow-dirty) allow_dirty=true; shift ;;
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    *) echo "orchestrate: unbekannte Option $1" >&2; usage ;;
  esac
done
[ -n "$selection" ] || { [ "$dry_run" = true ] && selection=next || usage; }
[ "$selection" != resume ] || { [ "$dry_run" = false ] && [ -z "$manual_mode" ] || usage; }
case "$manual_mode" in ''|single|verified|managed) ;; managed-fresh) echo "orchestrate: managed-fresh folgt erst in Phase 07" >&2; exit 1 ;; *) echo "orchestrate: unbekannter Modus '$manual_mode'" >&2; exit 1 ;; esac

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "orchestrate: Projektpfad fehlt" >&2; exit 1; }
validator="$script_dir/validate-ledger.sh"
config_reader="$script_dir/agent/config.sh"
router="$script_dir/route-task.sh"
status_gate="$script_dir/agent/status.sh"
verification_gateway="$script_dir/verify-task.sh"
context_builder="$script_dir/agent/context.sh"
output_tool="$script_dir/agent/output.sh"
runner_adapter="$script_dir/agent/runner.sh"
runner=${ORCHESTRATOR_RUNNER:-$runner_adapter}
current_run="$project_dir/docs/state/current-run.md"
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

route_task() {
  if [ -n "$manual_mode" ]; then
    "$router" --project-dir "$project_dir" --mode "$manual_mode" "$task_id"
  else
    "$router" --project-dir "$project_dir" "$task_id"
  fi
}

route_value() {
  key=$1
  file=$2
  awk -F= -v wanted="$key" '$1 == wanted { if (found++) exit 2; print substr($0,length(wanted)+2) } END { if (!found) exit 1 }' "$file"
}

validate_run_candidate() {
  "$validator" --project-dir "$project_dir" --current-run-file "$1" >/dev/null
}

update_run_field() {
  ledger_atomic_replace_scalar "$current_run" "$1" "$2" validate_run_candidate
}

create_active_run() {
  temporary=$(mktemp "${TMPDIR:-/tmp}/current-run.XXXXXX") || return 1
  trap 'rm -f "$temporary"' RETURN
  cat > "$temporary" <<EOF
---
run_id: $run_id
task_id: $task_id
mode: auto
phase: plan
iteration: 1
attempt: ${run_attempt:-1}
last_progress_fingerprint: none
started_at: $started_at
route_rule_version: "1"
route_reason_code: none
route_human_gate: false
route_signals: []
---
EOF
  validate_run_candidate "$temporary" || return 1
  agent_atomic_write "$current_run" "$temporary" || return 1
  rm -f "$temporary"
  trap - RETURN
}

checkpoint_product() {
  checkpoint_manifest="$run_dir/checkpoint.manifest"
  checkpoint_temp="$run_dir/.checkpoint.manifest.tmp"
  agent_repo_manifest "$project_dir" "$checkpoint_temp" || return 1
  mv -f "$checkpoint_temp" "$checkpoint_manifest"
  shasum -a 256 "$checkpoint_manifest" | awk '{print $1}' > "$run_dir/checkpoint.sha256"
  if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$project_dir" rev-parse HEAD > "$run_dir/checkpoint.git-head" 2>/dev/null || echo unborn > "$run_dir/checkpoint.git-head"
  else
    echo none > "$run_dir/checkpoint.git-head"
  fi
}

checkpoint_matches() {
  [ -f "$run_dir/checkpoint.manifest" ] || { echo "orchestrate: Resume-Checkpoint fehlt" >&2; return 1; }
  now="$run_dir/.resume-current.manifest"
  agent_repo_manifest "$project_dir" "$now" || return 1
  if ! cmp -s "$run_dir/checkpoint.manifest" "$now"; then
    rm -f "$now"
    echo "orchestrate: Dateien wurden seit dem letzten vollständigen Schritt verändert; Resume wird abgewiesen" >&2
    return 1
  fi
  rm -f "$now"
  expected_git=$(sed -n '1p' "$run_dir/checkpoint.git-head" 2>/dev/null || true)
  if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
    actual_git=$(git -C "$project_dir" rev-parse HEAD 2>/dev/null || echo unborn)
  else
    actual_git=none
  fi
  [ -n "$expected_git" ] && [ "$expected_git" = "$actual_git" ] || { echo "orchestrate: Git-Stand passt nicht zum Resume-Checkpoint" >&2; return 1; }
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
  update_run_field phase "$phase" || return 1
  call_sequence=$((call_sequence + 1))
  label=$(printf '%02d-%s' "$call_sequence" "$role")
  raw="$run_dir/outputs/$label.raw"
  metadata="$run_dir/metadata/$label.env"
  before="$run_dir/manifests/$label.before"
  after="$run_dir/manifests/$label.after"
  changes="$run_dir/manifests/$label.changed"
  controls_before="$run_dir/manifests/$label.controls-before"
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
  "$runner" run_agent "$role" "$context" "$project_dir" "$raw" "$metadata"
  runner_status=$?
  "$runner_adapter" validate_metadata "$metadata" >/dev/null 2>&1 || { echo "orchestrate: ungültige Runner-Metadaten für $role" >&2; return 1; }
  [ "$runner_status" -eq 0 ] || { echo "orchestrate: Agentenaufruf $role scheiterte (Exit $runner_status)" >&2; return 1; }
  [ "$(awk -F= '$1 == "output_status" { print $2; exit }' "$metadata")" = ok ] || { echo "orchestrate: Agentenausgabe $role ist leer, abgeschnitten oder fehlerhaft" >&2; return 1; }
  "$output_tool" validate "$role" "$raw" >/dev/null || return 1
  agent_repo_manifest "$project_dir" "$after" || return 1
  agent_manifest_changes "$before" "$after" > "$changes"
  check_role_changes "$role" "$changes" || return 1
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
  checkpoint_product || return 1
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
  update_run_field phase verify || return 1
  call_sequence=$((call_sequence + 1))
  verify_log="$run_dir/outputs/$(printf '%02d' "$call_sequence")-verify.log"
  attempt_value=$(ledger_scalar "$task_file" attempts) || return 1
  attempt_value=$((attempt_value + 1))
  if "$verification_gateway" --project-dir "$project_dir" --run-id "$run_id" --attempt "$attempt_value" --timeout "$verify_timeout" "$task_id" > "$verify_log" 2>&1; then
    verification_result=green
  else
    verification_result=red
  fi
  checkpoint_product || return 1
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
  max_attempts=$(ledger_scalar "$task_file" max_attempts) || return 1
  [ "$max_attempts" -le "$max_task_attempts" ] || max_attempts=$max_task_attempts
  [ "$attempts" -lt "$max_attempts" ] || return 1
  new_attempts=$((attempts + 1))
  validate_task_candidate() { "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null; }
  ledger_atomic_replace_scalar "$task_file" attempts "$new_attempts" validate_task_candidate || return 1
  update_run_field attempt "$((new_attempts + 1))" || return 1
  append_failure_note || return 1
}

finish_success() {
  human_review=$(ledger_scalar "$task_file" human_review) || return 1
  if [ "$human_review" = true ]; then target=review; else target=done; fi
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" "$target" in_progress || return 1
  update_run_field phase finished || return 1
  run_active=false
  checkpoint_product || return 1
  echo "orchestrate: Task $task_id ist $target"
}

finish_single_red() {
  record_failure || true
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress || return 1
  update_run_field phase finished || return 1
  run_active=false
  checkpoint_product || return 1
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
  update_run_field phase finished || return 1
  run_active=false
  checkpoint_product || return 1
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

run_finalizer() {
  reason=$1
  if run_role finalizer "$task_id" finalize; then :; else echo "orchestrate: Finalizer scheiterte" >&2; fi
  block_current_task "$reason"
}

switch_to_task() {
  selected=$1
  [ "$selected" = "$task_id" ] && return 0
  task_is_ready "$selected" || { echo "orchestrate: Manager wählte nicht bereiten Task $selected" >&2; return 1; }
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress || return 1
  "$status_gate" --project-dir "$project_dir" set-status "$selected" in_progress todo || return 1
  task_id=$selected
  task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || return 1
  update_run_field task_id "$task_id"
}

managed_loop() {
  case "$mode" in managed-fresh) echo "orchestrate: managed-fresh benötigt Phase 07" >&2; update_run_field phase paused; return 1 ;; esac
  if ! grep -qvE '^(#|[[:space:]]*$|.*Initialisierung.*|.*noch nicht.*|.*Platzhalter.*)$' "$project_dir/docs/state/plan.md"; then
    run_role manager-plan '' plan || return 1
  fi
  if [ ! -f "$run_dir/brainstorm.done" ]; then
    run_role worker-brainstorm "$task_id" brainstorm || return 1
    : > "$run_dir/brainstorm.done"
    checkpoint_product || return 1
  fi

  no_progress=0
  iteration=$(ledger_scalar "$current_run" iteration)
  while [ "$iteration" -le "$max_iterations" ]; do
    update_run_field iteration "$iteration" || return 1
    run_role manager-manage '' plan || return 1
    decision=$last_raw
    action=$(manager_value action "$decision")
    selected=$(manager_value task_id "$decision")
    reason=$(manager_value reason_code "$decision")
    case "$action" in
      request_human)
        update_run_field phase paused || return 1
        checkpoint_product || return 1
        echo "orchestrate: menschliche Entscheidung erforderlich ($reason)"
        return 0 ;;
      blocked)
        run_finalizer "$reason"
        return 1 ;;
      done)
        [ "$(ledger_scalar "$task_file" last_verification)" = green ] && ledger_verification_is_green "$verification_dir" "$task_id" "$project_dir" "$task_file" || {
          echo "orchestrate: Manager meldete done ohne grünen Prüfbeleg" >&2
          update_run_field phase failed || true
          return 1
        }
        finish_success
        return ;;
      dispatch) ;;
      *) echo "orchestrate: ungültige Manageraktion" >&2; return 1 ;;
    esac

    switch_to_task "$selected" || { update_run_field phase failed || true; return 1; }
    worker_kind=$(manager_value worker_kind "$decision")
    [ "$worker_kind" = normal ] || { echo "orchestrate: Fresh Worker folgt erst in Phase 07" >&2; update_run_field phase paused; return 1; }
    run_role worker-task "$task_id" work || return 1
    worker_result=$(output_value RESULT "$last_raw")
    [ "$worker_result" != blocked ] || { run_finalizer WORKER_BLOCKED; return 1; }
    if verify_candidate; then finish_success; return; fi
    record_failure || { run_finalizer ATTEMPT_LIMIT; return 1; }

    fingerprint=$(progress_fingerprint "$decision") || return 1
    previous=$(ledger_scalar "$current_run" last_progress_fingerprint)
    if [ "$fingerprint" = "$previous" ]; then no_progress=$((no_progress + 1)); else no_progress=0; fi
    update_run_field last_progress_fingerprint "$fingerprint" || return 1
    if [ "$no_progress" -ge "$max_no_progress" ]; then run_finalizer NO_PROGRESS; return 1; fi
    iteration=$((iteration + 1))
  done
  run_finalizer ITERATION_LIMIT
  return 1
}

cleanup() {
  exit_status=$?
  trap - EXIT HUP INT TERM
  if [ "$run_active" = true ] && [ -f "$current_run" ]; then
    phase=$(ledger_scalar "$current_run" phase 2>/dev/null || true)
    case "$phase" in finished|paused|failed) ;; *) update_run_field phase failed >/dev/null 2>&1 || true ;; esac
  fi
  [ "$lock_held" = false ] || agent_release_lock "$lock_dir"
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

if [ "$resume" = true ]; then
  phase=$(ledger_scalar "$current_run" phase) || exit 1
  case "$phase" in paused|failed) ;; *) echo "orchestrate: kein fortsetzbarer Lauf vorhanden" >&2; exit 1 ;; esac
  task_id=$(ledger_scalar "$current_run" task_id) || exit 1
  task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
  [ "$(ledger_scalar "$task_file" status)" = in_progress ] || { echo "orchestrate: Resume-Task ist nicht in_progress" >&2; exit 1; }
  run_id=$(ledger_scalar "$current_run" run_id) || exit 1
  mode=$(ledger_scalar "$current_run" mode) || exit 1
  run_dir="$project_dir/.agent-runs/$run_id"
  checkpoint_matches || exit 1
  call_sequence=$(find "$run_dir/outputs" -maxdepth 1 -type f -name '[0-9][0-9]-*' -print 2>/dev/null | sed 's#.*/##; s/-.*//' | LC_ALL=C sort -n | tail -n 1)
  call_sequence=${call_sequence:-0}
else
  case "$selection" in
    task) task_id=$requested_task ;;
    next) task_id=$(select_next_task); [ -n "$task_id" ] || { echo "orchestrate: kein bereiter Task" >&2; exit 1; } ;;
  esac
  case "$task_id" in ''|*[!0-9]*) echo "orchestrate: ungültige Task-ID" >&2; exit 1 ;; esac
  task_is_ready "$task_id" || { echo "orchestrate: Task $task_id ist nicht bereit" >&2; exit 1; }
  task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
  attempts_at_start=$(ledger_scalar "$task_file" attempts) || exit 1
  [ "$attempts_at_start" -lt "$max_task_attempts" ] || { echo "orchestrate: hartes Versuchslimit für Task $task_id ist erreicht" >&2; exit 1; }
  run_attempt=$((attempts_at_start + 1))
  route_file=$(mktemp "${TMPDIR:-/tmp}/route.XXXXXX") || exit 1
  route_task > "$route_file" || { rm -f "$route_file"; exit 1; }
  mode=$(route_value MODE "$route_file") || { rm -f "$route_file"; exit 1; }
  reason_code=$(route_value REASON_CODE "$route_file") || { rm -f "$route_file"; exit 1; }
  rm -f "$route_file"
  [ "$mode" != managed-fresh ] || { echo "orchestrate: Route managed-fresh benötigt Phase 07" >&2; exit 1; }

  if [ "$dry_run" = true ]; then
    printf 'DRY_RUN=true\nTASK_ID=%s\nMODE=%s\nREASON_CODE=%s\nMAX_GLOBAL_ITERATIONS=%s\nMAX_TASK_ATTEMPTS=%s\nMAX_NO_PROGRESS=%s\n' \
      "$task_id" "$mode" "$reason_code" "$max_iterations" "$max_task_attempts" "$max_no_progress"
    case "$mode" in
      single) echo 'PLANNED_CALLS=worker-task,verify' ;;
      verified) echo 'PLANNED_CALLS=worker-task,verify,worker-task-if-red,verify-if-fixed,manager-if-still-red' ;;
      managed) echo 'PLANNED_CALLS=manager-plan-if-needed,worker-brainstorm-once,manager-manage,worker-task,verify,repeat-bounded' ;;
    esac
    exit 0
  fi

  [ "$mode" != blocked ] || { echo "orchestrate: Router blockiert Task $task_id vor dem Start" >&2; exit 1; }

  if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1 && [ "$allow_dirty" = false ] && [ -n "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]; then
    echo "orchestrate: Arbeitsverzeichnis ist nicht sauber; wiederhole bewusst mit --allow-dirty" >&2
    exit 1
  fi
  mkdir -p "$project_dir/.agent-runs" || exit 1
  agent_acquire_lock "$lock_dir" || exit 1
  lock_held=true
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")"
  run_dir="$project_dir/.agent-runs/$run_id"
  mkdir "$run_dir" || exit 1
  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" in_progress todo >/dev/null || exit 1
  run_active=true
  create_active_run || exit 1
  if [ -n "$manual_mode" ]; then
    "$router" --project-dir "$project_dir" --mode "$manual_mode" --record "$task_id" >/dev/null || exit 1
  else
    "$router" --project-dir "$project_dir" --record "$task_id" >/dev/null || exit 1
  fi
  mode=$(ledger_scalar "$current_run" mode) || exit 1
  checkpoint_product || exit 1
fi

[ "$dry_run" = false ] || exit 0
mkdir -p "$project_dir/.agent-runs" || exit 1
if [ "$lock_held" = false ]; then agent_acquire_lock "$lock_dir" || exit 1; lock_held=true; fi
run_active=true

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
    attempts=$(ledger_scalar "$task_file" attempts)
    max_attempts=$(ledger_scalar "$task_file" max_attempts)
    [ "$max_attempts" -le "$max_task_attempts" ] || max_attempts=$max_task_attempts
    if [ "$attempts" -lt "$max_attempts" ]; then
      run_role worker-task "$task_id" work || exit 1
      [ "$(output_value RESULT "$last_raw")" != blocked ] || { block_current_task WORKER_BLOCKED; exit 1; }
      if verify_candidate; then finish_success; exit 0; fi
      escalation=$(mktemp "${TMPDIR:-/tmp}/route-escalation.XXXXXX") || exit 1
      "$router" --project-dir "$project_dir" --record --escalate-from verified --expected-attempts "$attempts" "$task_id" > "$escalation" || { rm -f "$escalation"; run_finalizer ATTEMPT_LIMIT; exit 1; }
      mode=$(route_value MODE "$escalation") || { rm -f "$escalation"; exit 1; }
      rm -f "$escalation"
      if [ "$mode" = managed ]; then managed_loop; else run_finalizer ATTEMPT_LIMIT; exit 1; fi
    else
      run_finalizer ATTEMPT_LIMIT
      exit 1
    fi ;;
  managed) managed_loop ;;
  *) echo "orchestrate: Modus $mode wird in Phase 05 nicht ausgeführt" >&2; update_run_field phase paused || true; exit 1 ;;
esac
