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
# Zuerst den eigenen Ort merken: das `cd` unten zeigt auf die Daten, die
# Pruefskripte kommen weiter von hier.
gate_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || { echo "commit-gate: eigener Ort nicht auflösbar" >&2; exit 2; }
cd "${CLAUDE_PROJECT_DIR:-$gate_dir/..}" || { echo "commit-gate: Projektwurzel nicht gefunden" >&2; exit 2; }

# Befehl aus dem Hook-JSON auf stdin lesen; derselbe Leser wie im bash-guard.
. "$gate_dir/agent/hook-input.sh" 2>/dev/null || {
  echo "commit-gate: die Hook-Eingabe ist nicht lesbar" >&2; exit 2; }
cmd=$(hook_command_text)
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
# `verify.sh` ist die Pruefung des Projekts und kommt aus dem Projekt; der
# Ledger-Validator gehoert zur Implementierung und kommt von hier.
ledger_out=$("$gate_dir/validate-ledger.sh" --project-dir "$PWD" 2>&1)
if [ $? -ne 0 ]; then
  echo "Commit blockiert — das Datei-Ledger ist inkonsistent:" >&2
  echo "$ledger_out" | tail -n 20 >&2
  exit 2
fi
exit 0
