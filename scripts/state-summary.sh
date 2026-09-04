#!/usr/bin/env bash
# state-summary.sh — Projektzustand in ≤ 250 Tokens. Läuft automatisch als
# SessionStart-Hook (.claude/settings.json): Die Ausgabe landet direkt im
# Kontext der neuen Sitzung — auch nach /clear und nach jeder Komprimierung.
# PLATZHALTER: Der Initializer ersetzt dieses Skript (Feature-Zähler, READY-Tasks,
# Kopf des handoff.md). Bis dahin: nur Branch + Handoff.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}" || exit 0
echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
echo "features: Initialisierung noch nicht ausgeführt"
echo "--- handoff ---"
[ -f docs/state/handoff.md ] && head -30 docs/state/handoff.md || echo "(kein handoff.md)"
