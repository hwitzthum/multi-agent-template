#!/usr/bin/env bash
# Einziger maschineller Schreibweg fuer Task-Statusuebergaenge.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
. "$script_dir/ledger.sh"
validator="$project_dir/scripts/validate-ledger.sh"

if [ "${1:-}" = --project-dir ]; then
  project_dir=$2
  validator="$project_dir/scripts/validate-ledger.sh"
  if [ ! -x "$validator" ]; then validator="$script_dir/../validate-ledger.sh"; fi
  shift 2
fi

usage() {
  echo "Verwendung: $0 [--project-dir PFAD] set-status TASK-ID NEU ERWARTET" >&2
  exit 2
}

[ "${1:-}" = set-status ] && [ "$#" -eq 4 ] || usage
task_id=$2
new_status=$3
expected_status=$4
tasks_dir="$project_dir/docs/tasks"
verification_dir="$project_dir/docs/verification"

case "$task_id" in ''|*[!0-9]*) echo "status-gate: ungueltige Task-ID" >&2; exit 1 ;; esac
case "$new_status" in todo|in_progress|review|done|blocked) ;; *) echo "status-gate: unbekannter Zielstatus '$new_status'" >&2; exit 1 ;; esac

lock_dir="$tasks_dir/.status-lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "status-gate: ein anderer Statuswechsel laeuft bereits" >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT HUP INT TERM

task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
actual_status=$(ledger_scalar "$task_file" status) || exit 1
[ "$actual_status" = "$expected_status" ] || {
  echo "status-gate: Task $task_id ist '$actual_status', erwartet war '$expected_status' (veralteter Schreibversuch)" >&2
  exit 1
}

transition="$actual_status:$new_status"
case "$transition" in
  todo:in_progress|in_progress:todo|in_progress:review|in_progress:done|in_progress:blocked|review:done|review:todo|review:blocked) ;;
  *) echo "status-gate: Uebergang $actual_status -> $new_status ist nicht erlaubt" >&2; exit 1 ;;
esac

if [ "$new_status" = done ]; then
  last_verification=$(ledger_scalar "$task_file" last_verification) || exit 1
  [ "$last_verification" = green ] || {
    echo "status-gate: done benoetigt last_verification: green" >&2
    exit 1
  }
  ledger_verification_is_green "$verification_dir" "$task_id" || {
    echo "status-gate: done benoetigt einen passenden gruenen Pruefbericht" >&2
    exit 1
  }
  human_review=$(ledger_scalar "$task_file" human_review) || exit 1
  if [ "$actual_status" = in_progress ] && [ "$human_review" = true ]; then
    echo "status-gate: Task $task_id benoetigt zuerst den Status review" >&2
    exit 1
  fi
fi

validate_candidate() {
  "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null
}

ledger_atomic_replace_scalar "$task_file" status "$new_status" validate_candidate || exit 1
echo "status-gate: Task $task_id $actual_status -> $new_status"
