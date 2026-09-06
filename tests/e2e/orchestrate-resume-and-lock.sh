#!/usr/bin/env bash
# Wiederaufnahme setzt einen abgebrochenen Lauf fort, weist aber eine fremde
# Dateiänderung ab; eine zweite Orchestrierung wird ausgesperrt.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-resume-and-lock
fixture_workspace

new_app_fixture
fake_response worker-task 1 'RESULT=implemented'
expect_failure "Ungültiger Output bereitet Resume-Test vor" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
fake_response worker-task 2 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 2 write-good
expect_success "Resume setzt Lauf ohne Artefaktüberschreiben fort" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --resume
assert_eq "Resume schließt Task ab" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

new_app_fixture
fake_response worker-task 1 'RESULT=implemented'
expect_failure "Fehlerlauf für Fremdänderung wird erzeugt" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
printf '%s\n' fremd > "$fixture/src/app.txt"
expect_failure "Resume weist fremde Dateiänderung ab" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --resume

new_app_fixture
mkdir "$fixture/.agent-runs/.orchestrator-lock"
expect_failure "Atomare Sperre verhindert zweiten Orchestrator" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Sperrkonflikt verändert Task nicht" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

finish_suite
