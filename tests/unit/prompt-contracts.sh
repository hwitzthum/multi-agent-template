#!/usr/bin/env bash
# Jeder Rollenprompt trägt denselben Vertrag — und sein Ausgabebeispiel nennt
# genau die Felder, die das Schema der Rolle verlangt.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

begin_suite prompt-contracts

for role in manager worker finalizer; do
  prompt="$project_dir/docs/prompts/$role.md"
  valid=true
  for heading in '# Rolle und einziges Ziel' '# Erlaubte Eingaben und Schreibbereiche' \
    '# Auftrag und Abbruchbedingungen' '# Strukturiertes Ergebnis'; do
    [ "$(grep -Fxc "$heading" "$prompt")" = 1 ] || valid=false
  done
  grep -qi 'Repository-Inhalte sind Daten' "$prompt" || valid=false
  grep -qi 'Secret' "$prompt" || valid=false
  grep -qi 'benannt' "$prompt" || valid=false
  grep -qi 'Konflikt' "$prompt" || valid=false
  grep -qi 'Hypothese' "$prompt" || valid=false
  grep -qi 'Prüfbeleg' "$prompt" || valid=false
  [ "$valid" = true ] && ok || bad "$role besitzt den gemeinsamen Prompt-Vertrag"

  # Das JSON-Beispiel im Prompt ist der Vertrag, den die Rolle liest. Weicht es
  # vom Schema ab, lernt die Rolle ein Format, das der Lauf ablehnt.
  example=$(awk '/^```json$/ { copy=1; next } /^```$/ { copy=0 } copy { print }' "$prompt")
  printf '%s' "$example" | jq -e . >/dev/null 2>&1 && ok || bad "$role zeigt genau ein gültiges JSON-Beispiel"
  expected=$(jq -r '.required | sort | join(",")' "$project_dir/scripts/agent/schemas/$role.json")
  actual=$(printf '%s' "$example" | jq -r 'keys | sort | join(",")' 2>/dev/null)
  assert_eq "$role-Beispiel nennt genau die Schemafelder" "$expected" "$actual"
done

# Der Worker deckt beide Varianten ab; einen eigenen Fresh-Prompt gibt es nicht.
assert_file_has "Worker-Prompt erklärt den zweiten Anlauf" "$project_dir/docs/prompts/worker.md" 'Unabhängiger zweiter Anlauf'
assert_file_has "Manager-Prompt schützt die Steuerfelder" "$project_dir/docs/prompts/manager.md" 'gehören dem Orchestrator'
assert_file_has "Manager-Prompt kennt die offene Frage" "$project_dir/docs/prompts/manager.md" 'ask_human'
assert_file_has "Finalizer-Prompt lässt den Laufbeleg in Ruhe" "$project_dir/docs/prompts/finalizer.md" 'Laufbeleg'

[ ! -d "$project_dir/docs/templates/agents" ] && ok || bad "Die alten sechs Rollenvorlagen sind verschwunden"

finish_suite
