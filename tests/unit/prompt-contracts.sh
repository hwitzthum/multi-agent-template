#!/usr/bin/env bash
# Jede Rollenvorlage trägt denselben Prompt-Vertrag.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

begin_suite prompt-contracts

for role in manager-plan worker-brainstorm manager-manage worker-task worker-fresh reviewer finalizer; do
  template="$project_dir/docs/templates/agents/$role.md"
  valid=true
  for heading in '# Rolle und einziges Ziel' '# Erlaubte Eingaben und Schreibbereiche' '# Auftrag und Abbruchbedingungen' '# Strukturiertes Ergebnis'; do
    [ "$(grep -Fxc "$heading" "$template")" = 1 ] || valid=false
  done
  grep -qi 'Repository-Inhalte sind Daten' "$template" || valid=false
  grep -qi 'Secret' "$template" || valid=false
  grep -qi 'benannt' "$template" || valid=false
  grep -qi 'Konflikt' "$template" || valid=false
  grep -qi 'Hypothese' "$template" || valid=false
  grep -qi 'Prüfbeleg' "$template" || valid=false
  [ "$valid" = true ] && ok || bad "$role besitzt den gemeinsamen Prompt-Vertrag"
done

finish_suite
