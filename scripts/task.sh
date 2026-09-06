#!/usr/bin/env bash
# Die beiden Statusuebergaenge, die nur ein Mensch auslösen darf: eine
# blockierte Aufgabe wieder öffnen und eine Aufgabe im Review freigeben.
# Der Orchestrator ruft dieses Skript nie auf.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1

usage() {
  echo "Verwendung: $0 [--project-dir PFAD] (reopen TASK-ID | approve TASK-ID)"
  echo "  reopen   blockierte Aufgabe auf todo setzen (Antwort steht im Task); Versuche zurück auf 0"
  echo "  approve  Aufgabe im Review freigeben und auf done setzen"
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

while [ "${1:-}" = --project-dir ]; do
  [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  project_dir=$2
  shift 2
done

command=${1:-}
task_id=${2:-}
[ "$#" -eq 2 ] || { usage >&2; exit 2; }
case "$task_id" in ''|*[!0-9]*) echo "task: ungueltige Task-ID" >&2; exit 1 ;; esac

status_gate="$script_dir/agent/status.sh"
validator="$script_dir/validate-ledger.sh"
. "$script_dir/agent/ledger.sh"

validate_task_candidate() {
  "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null
}

case "$command" in
  reopen)
    task_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$task_id") || exit 1
    actual_status=$(ledger_scalar "$task_file" status) || exit 1
    [ "$actual_status" = blocked ] || {
      echo "task: $task_id ist nicht blockiert, sondern '$actual_status'" >&2; exit 1; }
    # Die Versuche fallen vor dem Statuswechsel. Eine wieder offene Aufgabe mit
    # ausgeschoepftem Zaehler waere sonst `todo` und trotzdem unbearbeitbar: der
    # Orchestrator weist sie ab, waehrend next-tasks.sh sie als bereit meldet.
    # Ein `attempts: 0` ist auch im blockierten Zustand gueltig, ein leerer
    # blocked_reason nicht — deshalb diese Reihenfolge.
    ledger_atomic_replace_scalar "$task_file" attempts 0 validate_task_candidate || exit 1
    "$status_gate" --project-dir "$project_dir" --human-approved set-status "$task_id" todo blocked || exit 1
    # Der Grund gehoert zum blockierten Zustand; eine wieder offene Aufgabe
    # traegt ihn nicht weiter.
    ledger_atomic_replace_scalar "$task_file" blocked_reason '""' validate_task_candidate || exit 1
    echo "task: $task_id ist wieder offen (Versuche zurückgesetzt)" ;;
  approve)
    "$status_gate" --project-dir "$project_dir" --human-approved set-status "$task_id" done review || exit 1
    echo "task: $task_id ist freigegeben" ;;
  *) usage >&2; exit 2 ;;
esac
