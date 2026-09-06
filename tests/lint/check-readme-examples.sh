#!/usr/bin/env bash
# Beispielausgaben im README gegen die echten Skripte.
#
# Warum es diese Datei gibt: die Beispielbloecke im README waren dreimal
# veraltet — next-tasks.sh, state-summary.sh und der Dry-Run zeigten Formate,
# die es im Code nie gab. check-docs.sh hat das nicht gemerkt, weil es Pfade
# und Hilfetexte prueft, keine Ausgaben. Hier laufen die Skripte deshalb gegen
# ein Fixture, und jede erzeugte Zeile muss woertlich im README stehen.
#
# Aendert ein Skript sein Ausgabeformat, wird dieser Test rot, bevor ein Leser
# auf das falsche Beispiel hereinfaellt. Passt dann beides an: erst das README,
# dann die Erwartung hier.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

readme="$project_dir/README.md"
runner="$tests_dir/fake-runner.sh"
orchestrator="$project_dir/scripts/orchestrate.sh"

begin_suite check-readme-examples
fixture_workspace

# Jede Zeile der echten Ausgabe muss woertlich im README stehen.
assert_output_documented() {
  local name=$1 line
  shift
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    assert_file_has "$name: $line" "$readme" "$line"
  done <<INNER
$("$@" 2>/dev/null)
INNER
}

# --- Fixture A: Task-Liste und Kurzstand ------------------------------------
new_project_fixture --filled-plan
make_task --id 001 --title 'Startseite aufbauen' --class mechanical
make_task --id 004 --title 'Kontaktformular anbinden' --class patterned
make_task --id 005 --title 'Impressum freigeben' --class open --status review
make_report --id 001 --result green

assert_output_documented 'next-tasks.sh' \
  "$project_dir/scripts/next-tasks.sh" --project-dir "$fixture"

assert_output_documented 'state-summary.sh' \
  env CLAUDE_PROJECT_DIR="$fixture" "$project_dir/scripts/state-summary.sh"

assert_output_documented 'orchestrate.sh --next --dry-run' \
  env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --next --dry-run

# --- Fixture B: der Dry-Run einer offenen Aufgabe ---------------------------
new_project_fixture --filled-plan
make_task --id 003 --title 'Preise recherchieren' --class open

assert_output_documented 'orchestrate.sh --task 003 --dry-run' \
  env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 003 --dry-run

finish_suite
