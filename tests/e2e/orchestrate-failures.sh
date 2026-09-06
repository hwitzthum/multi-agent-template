#!/usr/bin/env bash
# Jede Störung — Ergebnis ohne Schema, Pfadverletzung, Timeout, leere oder
# abgeschnittene Antwort, ausgeschöpftes Versuchslimit — stoppt kontrolliert
# und lässt ein gültiges Ledger zurück.
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
fake_response worker 1 result implemented
expect_failure "Unvollständiges Rollenergebnis stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Unvollständiges Ergebnis lässt keinen Task in_progress" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Unvollständiges Ergebnis markiert Lauf failed" failed "$(fixture_run_state phase)"
expect_success "Ledger bleibt nach unvollständigem Ergebnis gültig" "$validator" --project-dir "$fixture"

new_app_fixture
fake_response worker 1 result erledigt summary '-' tests_run '-' notes '-'
expect_failure "Wert ausserhalb des Schemas stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
expect_success "Ledger bleibt nach Schemaverstoss gültig" "$validator" --project-dir "$fixture"

new_app_fixture --class open
fake_response manager 1 action weitermachen task_id 017 reason X question ''
expect_failure "Ungültige Managerentscheidung stoppt vor dem Worker" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
[ ! -f "$fixture/.agent-runs/fake/worker.count" ] && ok || bad "Ungültiger Manager startet keinen Worker"
assert_eq "Ungültiger Manager lässt Lauf failed" failed "$(fixture_run_state phase)"

new_app_fixture
fake_worker_result 1
fake_action worker 1 forbidden
expect_failure "Worker darf Steuerungspfad nicht ändern" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Pfadverletzung markiert Lauf failed" failed "$(fixture_run_state phase)"

new_app_fixture
fake_worker_result 1
fake_worker_result 2
fake_action worker 1 timeout
fake_action worker 2 write-good
expect_success "Providerfehler erhält einen begrenzten Infrastruktur-Retry" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Infrastruktur-Retry startet genau einen zweiten Aufruf" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
assert_eq "Infrastruktur-Retry verbraucht keinen Task-Fehlversuch" 0 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"

# Der Retry gilt für jede Rolle, nicht nur für den Worker.
new_app_fixture --class open
fake_manager_result 1
fake_manager_result 2
fake_worker_result 1
fake_action manager 1 timeout
fake_action worker 1 write-good
expect_success "Auch der Manager erhält den Infrastruktur-Retry" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Manager-Retry startet genau einen zweiten Aufruf" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/manager.count")"

new_app_fixture
fake_worker_result 1
fake_worker_result 2
fake_action worker 1 timeout
fake_action worker 2 timeout
expect_failure "Erschöpfter Infrastruktur-Retry stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Erschöpfter Retry markiert Lauf failed" failed "$(fixture_run_state phase)"

new_app_fixture
fake_worker_result 1
fake_action worker 1 empty
expect_failure "Leere Antwort wird nicht ausgewertet" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Leere Antwort gilt nicht als Providerfehler" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"

new_app_fixture
fake_worker_result 1
fake_action worker 1 truncated
expect_failure "Abgeschnittene Antwort wird nicht ausgewertet" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Abgeschnittene Antwort markiert Lauf failed" failed "$(fixture_run_state phase)"
assert_eq "Abgeschnittene Antwort gilt nicht als Providerfehler" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"

new_app_fixture --attempts 3
expect_failure "Globales Versuchslimit bleibt trotz höherem Taskwert hart" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Versuchslimit startet keinen Worker" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

finish_suite
