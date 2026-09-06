#!/usr/bin/env bash
# next-tasks.sh — listet todo-Tasks, deren Abhaengigkeiten alle done sind.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [--project-dir PFAD]"
    echo "Zeigt todo-Tasks, deren Abhängigkeiten vollständig done sind."
    echo "LIMIT-Zeilen nennen Tasks, deren Versuchslimit erreicht ist."
    exit 0 ;;
esac
if [ "${1:-}" = --project-dir ]; then
  [ "$#" -ge 2 ] || { echo "Verwendung: $0 [--project-dir PFAD]" >&2; exit 2; }
  project_dir=$2
  shift 2
fi
[ "$#" -eq 0 ] || { echo "Verwendung: $0 [--project-dir PFAD]" >&2; exit 2; }
. "$script_dir/agent/ledger.sh"

tasks_dir="$project_dir/docs/tasks"
files=$(ledger_task_files "$tasks_dir")
[ -n "$files" ] || { echo "keine Tasks (Initialisierung noch nicht ausgeführt)"; exit 0; }
"$script_dir/validate-ledger.sh" --project-dir "$project_dir" >/dev/null || exit 1
max_attempts=$("$script_dir/agent/config.sh" --get MAX_TASK_ATTEMPTS "$project_dir/.agent/config.env") || exit 1

while IFS= read -r file; do
  [ "$(ledger_scalar "$file" status)" = todo ] || continue
  ready=true
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    dep_file=$(ledger_task_path_by_id "$tasks_dir" "$dep") || { ready=false; break; }
    [ "$(ledger_scalar "$dep_file" status)" = done ] || { ready=false; break; }
  done <<EOF
$(ledger_list "$file" depends_on)
EOF
  [ "$ready" = true ] || continue
  id=$(ledger_scalar "$file" id)
  title=$(ledger_scalar "$file" title)
  class=$(ledger_scalar "$file" class)
  # Bereit heisst: der Orchestrator nimmt die Aufgabe auch an. Ein
  # ausgeschoepfter Versuchszaehler schliesst das aus — die Aufgabe bleibt
  # sichtbar, aber unter eigenem Wort.
  if [ "$(ledger_scalar "$file" attempts)" -ge "$max_attempts" ]; then
    printf 'LIMIT: %s | %s | Versuchslimit erreicht\n' "$id" "$title"
    continue
  fi
  printf 'READY: %s | %s | %s\n' "$id" "$title" "$class"
done <<EOF
$files
EOF
