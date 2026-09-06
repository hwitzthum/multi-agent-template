#!/usr/bin/env bash
# Jede Störung — ungültige Ausgabe, Pfadverletzung, Timeout, abgeschnittene
# Antwort, ausgeschöpftes Versuchslimit — stoppt kontrolliert und lässt ein
# gültiges Ledger zurück.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-failures
fixture_workspace

new_app_fixture
fake_response worker-task 1 'RESULT=implemented'
expect_failure "Ungültiger Rollenoutput stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Ungültiger Output lässt Task in_progress" in_progress "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Ungültiger Output markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"
expect_success "Ledger bleibt nach ungültigem Output gültig" "$validator" --project-dir "$fixture"

new_app_fixture --class open
fake_response worker-brainstorm 1 'NOTES_ADDED=-' 'RISKS=-' 'TEST_IDEAS=verify.sh'
fake_response manager-manage 1 'not yaml'
expect_failure "Ungültige Managerentscheidung stoppt vor Worker" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
[ ! -f "$fixture/.agent-runs/fake/worker-task.count" ] && ok || bad "Ungültiger Manager startet keinen Worker"
assert_eq "Ungültiger Manager lässt Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 forbidden
expect_failure "Worker darf Steuerungspfad nicht ändern" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Pfadverletzung markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 timeout
expect_failure "Timeout stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Timeout markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 truncated
expect_failure "Abgeschnittene Antwort wird nicht ausgewertet" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Abgeschnittene Antwort markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_app_fixture --attempts 3 --max-attempts 9
expect_failure "Globales Versuchslimit bleibt trotz höherem Taskwert hart" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Versuchslimit startet keinen Worker" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

finish_suite
