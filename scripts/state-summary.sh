#!/usr/bin/env bash
# Bewusst nur drei kompakte Zeilen; geeignet fuer den SessionStart-Kontext.
set -uo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
project_dir=${CLAUDE_PROJECT_DIR:-$(dirname -- "$script_dir")}
case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0"
    echo "Erklärt Lauf, letzten Prüfstand und offene Arbeit in genau drei Zeilen."
    exit 0 ;;
  '') ;;
  *) echo "Verwendung: $0" >&2; exit 2 ;;
esac
cd "$project_dir" || exit 0
. "$script_dir/agent/ledger.sh"

run_id=$(ledger_scalar docs/state/current-run.md run_id 2>/dev/null || echo none)
task_id=$(ledger_scalar docs/state/current-run.md task_id 2>/dev/null || echo none)
mode=$(ledger_scalar docs/state/current-run.md mode 2>/dev/null || echo auto)
iteration=$(ledger_scalar docs/state/current-run.md iteration 2>/dev/null || echo 0)
attempt=$(ledger_scalar docs/state/current-run.md attempt 2>/dev/null || echo 0)
max_iterations=$("$script_dir/agent/config.sh" --get MAX_GLOBAL_ITERATIONS .agent/config.env 2>/dev/null || echo '?')
max_attempts=$("$script_dir/agent/config.sh" --get MAX_TASK_ATTEMPTS .agent/config.env 2>/dev/null || echo '?')
if [ "$run_id" = none ]; then
  echo 'run: none'
else
  printf 'run: T%03d %s iter %s/%s attempt %s/%s\n' "$((10#$task_id))" "$mode" "$iteration" "$max_iterations" "$attempt" "$max_attempts"
fi

verify_result=$(ledger_scalar docs/verification/latest.md result 2>/dev/null || echo never)
failure_kind=$(ledger_scalar docs/verification/latest.md failure_kind 2>/dev/null || true)
verify_upper=$(printf '%s' "$verify_result" | tr '[:lower:]' '[:upper:]')
if [ -n "$failure_kind" ] && [ "$failure_kind" != none ]; then echo "verify: $verify_upper ($failure_kind)"; else echo "verify: $verify_upper"; fi

ready=$("$script_dir/next-tasks.sh" --project-dir "$project_dir" 2>/dev/null | awk -F: '$1 == "READY" { count++ } END { print count+0 }')
review=0 blocked=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  status=$(ledger_scalar "$file" status 2>/dev/null || true)
  [ "$status" != review ] || review=$((review + 1))
  [ "$status" != blocked ] || blocked=$((blocked + 1))
done <<EOF
$(ledger_task_files docs/tasks)
EOF
echo "ready: $ready | review: $review | blocked: $blocked"
