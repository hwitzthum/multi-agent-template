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
metrics_started=false
run_outcome=''

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
case "$manual_mode" in ''|single|verified|managed|managed-fresh) ;; *) echo "orchestrate: unbekannter Modus '$manual_mode'" >&2; exit 1 ;; esac

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "orchestrate: Projektpfad fehlt" >&2; exit 1; }
validator="$script_dir/validate-ledger.sh"
config_reader="$script_dir/agent/config.sh"
router="$script_dir/route-task.sh"
status_gate="$script_dir/agent/status.sh"
verification_gateway="$script_dir/verify-task.sh"
context_builder="$script_dir/agent/context.sh"
output_tool="$script_dir/agent/output.sh"
runner_adapter="$script_dir/agent/runner.sh"
candidate_tool="$script_dir/agent/candidates.sh"
metrics_tool="$script_dir/agent/metrics.sh"
runner=${ORCHESTRATOR_RUNNER:-$runner_adapter}
current_run="$project_dir/docs/state/current-run.md"
tasks_dir="$project_dir/docs/tasks"
verification_dir="$project_dir/docs/verification"
notes_file="$project_dir/docs/state/notes.md"
lock_dir="$project_dir/.agent-runs/.orchestrator-lock"

[ -x "$runner" ] || { echo "orchestrate: Runner ist nicht ausführbar: $runner" >&2; exit 1; }
"$config_reader" --check "$project_dir/.agent/config.env" || exit 1
"$metrics_tool" ensure-schema "$project_dir" || exit 1
"$validator" --project-dir "$project_dir" >/dev/null || exit 1
max_iterations=$("$config_reader" --get MAX_GLOBAL_ITERATIONS "$project_dir/.agent/config.env") || exit 1
max_task_attempts=$("$config_reader" --get MAX_TASK_ATTEMPTS "$project_dir/.agent/config.env") || exit 1
max_no_progress=$("$config_reader" --get MAX_NO_PROGRESS "$project_dir/.agent/config.env") || exit 1
verify_timeout=$("$config_reader" --get VERIFY_TIMEOUT_SECONDS "$project_dir/.agent/config.env") || exit 1
max_infra_retries=$("$config_reader" --get MAX_INFRA_RETRIES "$project_dir/.agent/config.env") || exit 1
retry_backoff=$("$config_reader" --get RETRY_BACKOFF_SECONDS "$project_dir/.agent/config.env") || exit 1

product_fingerprint() {
  destination=$1
  manifest=$(mktemp "${TMPDIR:-/tmp}/agent-base-manifest.XXXXXX") || return 1
  agent_product_manifest "$project_dir" "$manifest" || { rm -f "$manifest"; return 1; }
  shasum -a 256 "$manifest" | awk '{print $1}' > "$destination"
  rm -f "$manifest"
}

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
    "$router" --project-dir "$project_dir" --execution --mode "$manual_mode" "$task_id"
  else
    "$router" --project-dir "$project_dir" --execution "$task_id"
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
  if [ "$role" = reviewer ]; then
    context_args+=(
      --candidate-a-diff "$reviewer_a_diff" --candidate-b-diff "$reviewer_b_diff"
      --candidate-a-report "$reviewer_a_report" --candidate-b-report "$reviewer_b_report"
    )
  fi
  context=$("$context_builder" "${context_args[@]}") || return 1
  agent_repo_manifest "$project_dir" "$before" || return 1
  task_control_snapshot "$controls_before" || return 1
  "$runner" run_agent "$role" "$context" "$project_dir" "$raw" "$metadata"
  runner_status=$?
  "$runner_adapter" validate_metadata "$metadata" >/dev/null 2>&1 || { run_outcome=infrastructure_error; echo "orchestrate: ungültige Runner-Metadaten für $role" >&2; return 1; }
  [ "$runner_status" -eq 0 ] || { run_outcome=infrastructure_error; echo "orchestrate: Agentenaufruf $role scheiterte (Exit $runner_status)" >&2; return 1; }
  [ "$(awk -F= '$1 == "output_status" { print $2; exit }' "$metadata")" = ok ] || { run_outcome=infrastructure_error; echo "orchestrate: Agentenausgabe $role ist leer, abgeschnitten oder fehlerhaft" >&2; return 1; }
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
  mkdir -p "$run_dir/outputs" || return 1
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
  route_human_gate=$(ledger_scalar "$current_run" route_human_gate 2>/dev/null || echo false)
  if [ "$human_review" = true ] || [ "$route_human_gate" = true ]; then target=review; else target=done; fi
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" "$target" in_progress || return 1
  if [ "$target" = review ]; then run_outcome=review; else run_outcome=success; fi
  update_run_field phase finished || return 1
  run_active=false
  checkpoint_product || return 1
  echo "orchestrate: Task $task_id ist $target"
}

finish_single_red() {
  record_failure || true
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress || return 1
  if [ "$(ledger_scalar "$verification_dir/latest.md" failure_kind 2>/dev/null || true)" = verifier ]; then run_outcome=verification_error; else run_outcome=blocked; fi
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
  case "$safe_reason" in
    NO_PROGRESS) run_outcome=no_progress ;;
    *VERIFY_ERROR*) run_outcome=verification_error ;;
    *) run_outcome=blocked ;;
  esac
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

run_finalizer_role() {
  update_run_field phase finalize || return 1
  finalizer_context=$("$context_builder" build --project-dir "$project_dir" --role finalizer --run-id "$run_id" --task-id "$task_id") || return 1
  finalizer_workspace=$(mktemp -d "${TMPDIR:-/tmp}/agent-finalizer.XXXXXX") || return 1
  mkdir -p "$finalizer_workspace/.agent" "$finalizer_workspace/.agent-runs/$run_id/outputs" "$finalizer_workspace/.agent-runs/$run_id/metadata" || { rm -rf "$finalizer_workspace"; return 1; }
  cp -R "$project_dir/docs" "$finalizer_workspace/docs" || { rm -rf "$finalizer_workspace"; return 1; }
  cp -R "$project_dir/scripts" "$finalizer_workspace/scripts" || { rm -rf "$finalizer_workspace"; return 1; }
  cp "$project_dir/.agent/config.env" "$finalizer_workspace/.agent/config.env" || { rm -rf "$finalizer_workspace"; return 1; }
  finalizer_context_copy="$finalizer_workspace/.agent-runs/$run_id/finalizer.context.md"
  cp "$finalizer_context" "$finalizer_context_copy" || { rm -rf "$finalizer_workspace"; return 1; }
  finalizer_raw="$finalizer_workspace/.agent-runs/$run_id/outputs/finalizer.raw"
  finalizer_metadata="$finalizer_workspace/.agent-runs/$run_id/metadata/finalizer.env"
  before="$finalizer_workspace/.agent-runs/$run_id/before.manifest"
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

pause_with_finalizer() {
  reason=$1
  if run_finalizer_role; then :; else echo "orchestrate: Finalizer scheiterte" >&2; fi
  update_run_field phase paused || return 1
  run_active=false
  echo "orchestrate: Lauf pausiert ($reason)" >&2
}

run_candidate_worker() {
  candidate_name=$1
  candidate_role=$2
  candidate_root="$run_dir/candidates/$candidate_name/worktree"
  [ -d "$candidate_root" ] || { echo "orchestrate: Kandidaten-Worktree fehlt: $candidate_name" >&2; return 1; }
  update_run_field phase work || return 1
  candidate_run_dir="$candidate_root/.agent-runs/$run_id"
  mkdir -p "$candidate_run_dir/outputs" "$candidate_run_dir/metadata" "$candidate_run_dir/manifests" || return 1
  context_args=(build --project-dir "$candidate_root" --role "$candidate_role" --run-id "$run_id" --task-id "$task_id")
  while IFS= read -r include; do [ -n "$include" ] && context_args+=(--include "$include"); done <<EOF
$(ledger_list "$task_file" touches 2>/dev/null || true)
EOF
  candidate_context=$("$context_builder" "${context_args[@]}") || return 1
  candidate_before="$candidate_run_dir/manifests/$candidate_role.before"
  candidate_after="$candidate_run_dir/manifests/$candidate_role.after"
  candidate_changes="$candidate_run_dir/manifests/$candidate_role.changed"
  agent_repo_manifest "$candidate_root" "$candidate_before" || return 1
  fresh_git_link=''
  if [ "$candidate_role" = worker-fresh ]; then
    [ -f "$candidate_root/.git" ] && [ ! -L "$candidate_root/.git" ] || { echo "orchestrate: Fresh-Kandidat besitzt keinen sicheren Git-Verweis" >&2; return 1; }
    fresh_git_link=$(sed -n '1p' "$candidate_root/.git")
    case "$fresh_git_link" in gitdir:\ *) ;; *) echo "orchestrate: Fresh-Kandidat besitzt einen ungueltigen Git-Verweis" >&2; return 1 ;; esac
    rm -f "$candidate_root/.git" || return 1
  fi
  infra_retry=0
  invocation=1
  while :; do
    candidate_raw="$candidate_run_dir/outputs/$candidate_role-$invocation.raw"
    candidate_metadata="$candidate_run_dir/metadata/$candidate_role-$invocation.env"
    "$runner" run_agent "$candidate_role" "$candidate_context" "$candidate_root" "$candidate_raw" "$candidate_metadata"
    candidate_runner_status=$?
    if [ "$candidate_role" = worker-fresh ] && [ ! -f "$candidate_root/.git" ]; then printf '%s\n' "$fresh_git_link" > "$candidate_root/.git"; fi
    if ! "$runner_adapter" validate_metadata "$candidate_metadata" >/dev/null 2>&1; then
      run_outcome=infrastructure_error
      echo "orchestrate: ungueltige Runner-Metadaten fuer $candidate_name" >&2
      return 1
    fi
    cp "$candidate_metadata" "$run_dir/metadata/$candidate_name-$candidate_role-$invocation.env" || return 1
    candidate_output_status=$(awk -F= '$1 == "output_status" { print $2; exit }' "$candidate_metadata")
    if [ "$candidate_runner_status" -eq 0 ] && [ "$candidate_output_status" != error ]; then break; fi
    if [ "$infra_retry" -ge "$max_infra_retries" ]; then
      run_outcome=infrastructure_error
      echo "orchestrate: Infrastruktur-Retry fuer $candidate_name ist erschoepft" >&2
      return 1
    fi
    infra_retry=$((infra_retry + 1))
    sleep "$retry_backoff"
    invocation=$((invocation + 1))
    if [ "$candidate_role" = worker-fresh ]; then rm -f "$candidate_root/.git" || return 1; fi
  done
  if [ "$candidate_role" = worker-fresh ] && [ ! -f "$candidate_root/.git" ]; then printf '%s\n' "$fresh_git_link" > "$candidate_root/.git"; fi
  [ "$candidate_output_status" = ok ] || { echo "orchestrate: Kandidatenausgabe $candidate_name ist $candidate_output_status" >&2; return 1; }
  "$output_tool" validate "$candidate_role" "$candidate_raw" >/dev/null || return 1
  agent_repo_manifest "$candidate_root" "$candidate_after" || return 1
  agent_manifest_changes "$candidate_before" "$candidate_after" > "$candidate_changes"
  check_role_changes "$candidate_role" "$candidate_changes" || return 1
  "$validator" --project-dir "$candidate_root" >/dev/null || return 1
  "$candidate_tool" capture --project-dir "$project_dir" --run-dir "$run_dir" --candidate "$candidate_name" --task-id "$task_id" || return 1
}

verify_isolated_candidate() {
  candidate_name=$1
  candidate_root="$run_dir/candidates/$candidate_name/worktree"
  candidate_dir="$run_dir/candidates/$candidate_name"
  update_run_field phase verify || return 1
  if "$verification_gateway" --project-dir "$candidate_root" --run-id "$run_id" --attempt 1 --timeout "$verify_timeout" "$task_id" > "$candidate_dir/verify.log" 2>&1; then
    candidate_result=green
  else
    candidate_result=red
  fi
  cp "$candidate_root/docs/verification/latest.md" "$candidate_dir/report.md" || return 1
  report_result=$(ledger_scalar "$candidate_dir/report.md" result 2>/dev/null || true)
  [ "$report_result" = "$candidate_result" ] || { echo "orchestrate: widerspruechlicher Kandidatenbericht" >&2; return 1; }
  printf 'candidate=%s\nresult=%s\nbase_commit=%s\npatch_sha256=%s\n' \
    "$candidate_name" "$candidate_result" "$(sed -n '1p' "$run_dir/candidates/base.commit")" \
    "$(sed -n '1p' "$candidate_dir/patch.sha256")" > "$candidate_dir/result.env"
}

record_candidate_decision() {
  selected_candidate=$1
  decision_reason=$2
  {
    echo "selected=$selected_candidate"
    echo "reason_code=$decision_reason"
    echo "candidate_a_result=$candidate_a_result"
    echo "candidate_b_result=$candidate_b_result"
    echo 'requires_reverify=true'
  } > "$run_dir/candidates/decision.env"
}

managed_fresh_loop() {
  git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1 || { run_finalizer GIT_REQUIRED; return 1; }
  "$candidate_tool" init --project-dir "$project_dir" --run-dir "$run_dir" >/dev/null || { run_finalizer CANDIDATE_INIT_FAILED; return 1; }

  if ! run_candidate_worker candidate-a worker-task; then
    "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true
    run_finalizer CANDIDATE_A_INVALID
    return 1
  fi
  verify_isolated_candidate candidate-a || { "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true; run_finalizer CANDIDATE_A_VERIFY_ERROR; return 1; }
  candidate_a_result=$candidate_result

  if ! run_candidate_worker candidate-b worker-fresh; then
    "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true
    run_finalizer CANDIDATE_B_INVALID
    return 1
  fi
  verify_isolated_candidate candidate-b || { "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true; run_finalizer CANDIDATE_B_VERIFY_ERROR; return 1; }
  candidate_b_result=$candidate_result

  selected_candidate=''
  decision_reason=''
  if [ "$candidate_a_result" = green ] && [ "$candidate_b_result" = red ]; then
    selected_candidate=candidate-a; decision_reason=ONLY_A_GREEN
  elif [ "$candidate_a_result" = red ] && [ "$candidate_b_result" = green ]; then
    selected_candidate=candidate-b; decision_reason=ONLY_B_GREEN
  elif [ "$candidate_a_result" = red ] && [ "$candidate_b_result" = red ]; then
    record_candidate_decision neither BOTH_RED
    "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true
    run_finalizer BOTH_CANDIDATES_RED
    return 1
  else
    reviewer_a_diff="$run_dir/candidates/candidate-a/candidate.patch"
    reviewer_b_diff="$run_dir/candidates/candidate-b/candidate.patch"
    reviewer_a_report="$run_dir/candidates/candidate-a/report.md"
    reviewer_b_report="$run_dir/candidates/candidate-b/report.md"
    if ! run_role reviewer "$task_id" finalize; then
      "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true
      run_finalizer REVIEWER_INVALID
      return 1
    fi
    recommendation=$(output_value RECOMMENDATION "$last_raw")
    decision_reason=$(output_value REASON_CODE "$last_raw")
    case "$recommendation" in
      candidate-a|candidate-b) selected_candidate=$recommendation ;;
      neither) record_candidate_decision neither "$decision_reason"; "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true; run_finalizer REVIEWER_NEITHER; return 1 ;;
      human) record_candidate_decision human "$decision_reason"; "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true; run_finalizer HUMAN_DECISION; return 1 ;;
      *) "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true; run_finalizer REVIEWER_INVALID; return 1 ;;
    esac
  fi

  record_candidate_decision "$selected_candidate" "$decision_reason"
  if ! "$candidate_tool" check-main --project-dir "$project_dir" --run-dir "$run_dir"; then
    pause_with_finalizer EXTERNAL_CHANGE
    return 1
  fi
  "$candidate_tool" apply --project-dir "$project_dir" --run-dir "$run_dir" --candidate "$selected_candidate" || { pause_with_finalizer APPLY_CONFLICT; return 1; }
  if verify_candidate; then
    "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true
    finish_success
    return 0
  fi
  "$candidate_tool" rollback --project-dir "$project_dir" --run-dir "$run_dir" --candidate "$selected_candidate" || {
    pause_with_finalizer ROLLBACK_FAILED
    return 1
  }
  : > "$run_dir/rollback.performed"
  "$candidate_tool" cleanup --project-dir "$project_dir" --run-dir "$run_dir" || true
  record_failure || true
  run_finalizer MAIN_REVERIFY_RED
  return 1
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
    if [ "$worker_kind" = fresh ]; then managed_fresh_loop; return; fi
    [ "$worker_kind" = normal ] || { echo "orchestrate: unbekannte Worker-Art" >&2; update_run_field phase paused; return 1; }
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
  if [ "$metrics_started" = true ] && [ -f "$run_dir/metadata/run.env" ]; then
    phase=$(ledger_scalar "$current_run" phase 2>/dev/null || true)
    if [ "$phase" != paused ]; then
      if [ -z "$run_outcome" ]; then
        if [ "$exit_status" -eq 130 ]; then
          run_outcome=cancelled
        elif find "$run_dir/metadata" -maxdepth 1 -type f -name '*.env' ! -name run.env -exec awk -F= '$1 == "exit_status" && $2 != "0" { bad=1 } END { exit bad ? 0 : 1 }' {} \; -print -quit 2>/dev/null | grep -q .; then
          run_outcome=infrastructure_error
        elif [ "$(ledger_scalar "$verification_dir/latest.md" failure_kind 2>/dev/null || true)" = verifier ] && [ "$(ledger_scalar "$verification_dir/latest.md" run_id 2>/dev/null || true)" = "$run_id" ]; then
          run_outcome=verification_error
        else
          task_status=$(ledger_scalar "$task_file" status 2>/dev/null || true)
          case "$task_status" in done) run_outcome=success ;; review) run_outcome=review ;; *) run_outcome=blocked ;; esac
        fi
      fi
      "$metrics_tool" finalize "$project_dir" "$run_dir" "$run_outcome" >/dev/null || exit_status=1
    fi
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
  "$metrics_tool" reopen "$project_dir" "$run_dir" || exit 1
  metrics_started=true
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
  recommended_mode=$(route_value RECOMMENDED_MODE "$route_file") || { rm -f "$route_file"; exit 1; }
  rollout_stage=$(route_value ROLLOUT_STAGE "$route_file") || { rm -f "$route_file"; exit 1; }
  rm -f "$route_file"
  if [ "$dry_run" = true ]; then
    base_file=$(mktemp "${TMPDIR:-/tmp}/agent-dry-base.XXXXXX") || exit 1
    product_fingerprint "$base_file" || { rm -f "$base_file"; exit 1; }
    base_fingerprint=$(sed -n '1p' "$base_file")
    rm -f "$base_file"
    dry_metadata=$("$metrics_tool" dry-run "$project_dir" "$task_id" "$mode" "$recommended_mode" "$reason_code" "$rollout_stage" "$base_fingerprint") || exit 1
    printf 'DRY_RUN=true\nTASK_ID=%s\nMODE=%s\nRECOMMENDED_MODE=%s\nREASON_CODE=%s\nROLLOUT_STAGE=%s\nMETADATA=%s\nMAX_GLOBAL_ITERATIONS=%s\nMAX_TASK_ATTEMPTS=%s\nMAX_NO_PROGRESS=%s\n' \
      "$task_id" "$mode" "$recommended_mode" "$reason_code" "$rollout_stage" "${dry_metadata#"$project_dir/"}" "$max_iterations" "$max_task_attempts" "$max_no_progress"
    case "$mode" in
      single) echo 'PLANNED_CALLS=worker-task,verify' ;;
      verified) echo 'PLANNED_CALLS=worker-task,verify,worker-task-if-red,verify-if-fixed,manager-if-still-red' ;;
      managed) echo 'PLANNED_CALLS=manager-plan-if-needed,worker-brainstorm-once,manager-manage,worker-task,verify,repeat-bounded' ;;
      managed-fresh) echo 'PLANNED_CALLS=worker-task-isolated,verify-a,worker-fresh-isolated,verify-b,reviewer-if-both-green,apply-selected,reverify-main' ;;
    esac
    exit 0
  fi

  [ "$mode" != blocked ] || { echo "orchestrate: Router blockiert Task $task_id vor dem Start" >&2; exit 1; }

  if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1 && [ -n "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]; then
    if [ "$mode" = managed-fresh ]; then
      echo "orchestrate: managed-fresh benoetigt einen sauberen, eindeutig versionierten Basisstand" >&2
      exit 1
    fi
    if [ "$allow_dirty" = false ]; then
      echo "orchestrate: Arbeitsverzeichnis ist nicht sauber; wiederhole bewusst mit --allow-dirty" >&2
      exit 1
    fi
  fi
  mkdir -p "$project_dir/.agent-runs" || exit 1
  agent_acquire_lock "$lock_dir" || exit 1
  lock_held=true
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")"
  run_dir="$project_dir/.agent-runs/$run_id"
  mkdir "$run_dir" || exit 1
  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  base_file="$run_dir/base-fingerprint"
  product_fingerprint "$base_file" || exit 1
  base_fingerprint=$(sed -n '1p' "$base_file")
  "$metrics_tool" start "$project_dir" "$run_dir" "$run_id" "$task_id" "$mode" "$started_at" "$run_attempt" "$base_fingerprint" || exit 1
  metrics_started=true
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" in_progress todo >/dev/null || exit 1
  run_active=true
  create_active_run || exit 1
  if [ -n "$manual_mode" ]; then
      "$router" --project-dir "$project_dir" --execution --mode "$manual_mode" --record "$task_id" >/dev/null || exit 1
  else
    "$router" --project-dir "$project_dir" --execution --record "$task_id" >/dev/null || exit 1
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
      "$router" --project-dir "$project_dir" --execution --record --escalate-from verified --expected-attempts "$attempts" "$task_id" > "$escalation" || { rm -f "$escalation"; run_finalizer ATTEMPT_LIMIT; exit 1; }
      mode=$(route_value MODE "$escalation") || { rm -f "$escalation"; exit 1; }
      rm -f "$escalation"
      if [ "$mode" = managed ]; then managed_loop; else run_finalizer ATTEMPT_LIMIT; exit 1; fi
    else
      run_finalizer ATTEMPT_LIMIT
      exit 1
    fi ;;
  managed) managed_loop ;;
  managed-fresh) managed_fresh_loop ;;
  *) echo "orchestrate: Modus $mode wird nicht ausgeführt" >&2; update_run_field phase paused || true; exit 1 ;;
esac
