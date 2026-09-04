#!/usr/bin/env bash
# commit-gate.sh — PreToolUse-Hook (matcher: Bash). Das Hook-Schema von Claude
# Code filtert nur nach Werkzeugnamen, nicht nach Befehl — deshalb prüft dieses
# Skript selbst, ob ein `git commit` ansteht, und ist sonst still.
# Bei `git commit`: verify.sh --quick. Exit 2 = Commit wird blockiert
# (Hook-Vertrag von Claude Code); Exit 0 = frei.
# Hooks laufen im AKTUELLEN Verzeichnis, und ein `cd` des Agenten ändert es.
# Deshalb zuerst in die Projektwurzel wechseln — sonst fände `git commit`
# aus einem Unterordner verify.sh nicht, und das Gate liefe ins Leere.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}" || { echo "commit-gate: Projektwurzel nicht gefunden" >&2; exit 2; }

# Befehl aus dem Hook-JSON auf stdin lesen (kein jq — nicht überall vorhanden).
cmd=""
[ -t 0 ] || cmd=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' | head -n 1)
cmd=${cmd%%'","'*}   # alles ab dem nächsten JSON-Feld abschneiden
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

out=$(./scripts/verify.sh --quick 2>&1)
if [ $? -ne 0 ]; then
  echo "Commit blockiert — verify.sh --quick ist RED:" >&2
  echo "$out" | tail -n 20 >&2
  exit 2
fi
exit 0
