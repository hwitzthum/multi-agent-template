#!/usr/bin/env bash
# Bewusst nur zwei kompakte Zeilen; geeignet fuer den SessionStart-Kontext.
# Ein Lauf ist zwischen zwei Aufrufen zustandslos, deshalb steht hier kein
# Laufzustand, sondern nur der Pruefstand und die offene Arbeit.
set -uo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
project_dir=${CLAUDE_PROJECT_DIR:-$(dirname -- "$script_dir")}
case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0"
    echo "Erklärt den letzten Prüfstand und die offene Arbeit in zwei Zeilen."
    exit 0 ;;
  '') ;;
  *) echo "Verwendung: $0" >&2; exit 2 ;;
esac
cd "$project_dir" || exit 0
. "$script_dir/agent/ledger.sh"

verify_result=$(ledger_scalar docs/verification/latest.md result 2>/dev/null || echo never)
failure_kind=$(ledger_scalar docs/verification/latest.md failure_kind 2>/dev/null || true)
verify_upper=$(printf '%s' "$verify_result" | tr '[:lower:]' '[:upper:]')
if [ -n "$failure_kind" ] && [ "$failure_kind" != none ]; then echo "verify: $verify_upper ($failure_kind)"; else echo "verify: $verify_upper"; fi

# Die Fehlerausgabe bleibt draussen, der Exitcode nicht: ein ungueltiges Ledger
# ergaebe sonst dieselbe Zeile wie «nichts zu tun».
ready_lines=$("$script_dir/next-tasks.sh" --project-dir "$project_dir" 2>/dev/null)
ready_status=$?
ready=$(printf '%s\n' "$ready_lines" | awk -F: '$1 == "READY" { count++ } END { print count+0 }')
review=0 blocked=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  status=$(ledger_scalar "$file" status 2>/dev/null || true)
  [ "$status" != review ] || review=$((review + 1))
  [ "$status" != blocked ] || blocked=$((blocked + 1))
done <<EOF
$(ledger_task_files docs/tasks)
EOF
if [ "$ready_status" -ne 0 ]; then
  echo "ledger: UNGÜLTIG (./scripts/validate-ledger.sh zeigt die Fehler) | review: $review | blocked: $blocked"
else
  echo "ready: $ready | review: $review | blocked: $blocked"
fi
