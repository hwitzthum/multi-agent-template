#!/usr/bin/env bash
# Eine Folge von zwei Tasks: der zweite wird frei, sobald der erste done ist,
# und das Ledger bleibt gültig, obwohl das Produkt sich weiterentwickelt.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-sequence
fixture_workspace

new_app_fixture
make_task --id 018 --title 'Zweite App-Datei' --features F-018 --class mechanical \
  --depends 017 --touches src/app.txt --context 'Folgeaufgabe.' \
  --scope '`src/app.txt` erneut bearbeiten.' --not-scope 'Steuerungsdateien ändern.' \
  --criteria 'Die Datei enthält `good`.'
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_response worker-task 2 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-good
fake_action worker-task 2 write-good
expect_success "Erster Task einer Folge wird done" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
printf '%s\n' 'unabhaengige Aenderung' > "$fixture/src/other.txt"
expect_success "Ledger bleibt gueltig, obwohl das Produkt sich nach done weiterentwickelt" "$validator" --project-dir "$fixture"
expect_success "Folgetask wird trotz erledigtem Vorgaenger frei" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --next
assert_eq "Erster Task bleibt done" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Zweiter Task wird done" done "$(ledger_scalar "$fixture/docs/tasks/018.md" status)"
expect_success "Ledger ist nach zwei Laeufen gueltig" "$validator" --project-dir "$fixture"

finish_suite
