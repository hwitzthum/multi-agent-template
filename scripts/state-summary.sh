#!/usr/bin/env bash
# state-summary.sh — Projektzustand in ≤ 250 Tokens. Läuft automatisch als
# SessionStart-Hook (.claude/settings.json): Die Ausgabe landet direkt im
# Kontext der neuen Sitzung — auch nach /clear und nach jeder Komprimierung.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}" || exit 0
. ./scripts/agent/ledger.sh
echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
echo "features: Initialisierung noch nicht ausgeführt"
counts=$(for wanted in todo in_progress review done blocked; do
  count=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ "$(ledger_scalar "$file" status 2>/dev/null || true)" = "$wanted" ] && count=$((count + 1))
  done <<EOF
$(ledger_task_files docs/tasks)
EOF
  printf '%s=%s ' "$wanted" "$count"
done)
echo "tasks: $counts"
echo "ready:"
./scripts/next-tasks.sh 2>/dev/null | sed -n '1,5p'
echo "--- handoff ---"
[ -f docs/state/handoff.md ] && head -30 docs/state/handoff.md || echo "(kein handoff.md)"
