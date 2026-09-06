#!/usr/bin/env bash
# Managed: Manager-Runden mit Brainstorm, Human-Gate im Review und ein
# No-Progress-Guard, der identische Runden beendet.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-managed
fixture_workspace

new_app_fixture --class open
fake_response worker-brainstorm 1 'NOTES_ADDED=-' 'RISKS=-' 'TEST_IDEAS=verify.sh'
fake_response manager-manage 1 '---' 'action: dispatch' 'task_id: 017' 'worker_kind: normal' 'reason_code: NEXT_HIGHEST_VALUE' '---'
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-good
expect_success "Managed-Modus führt Manager-Worker-Runde aus" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Managed startet einen Worker pro Runde" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "Managed ruft Brainstorm genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-brainstorm.count")"
assert_eq "Managed hält offenen grünen Task im Review" review "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
[ ! -f "$fixture/.agent-runs/fake/manager-plan.count" ] && ok || bad "Ausgefuellter Plan startet keinen Manager-Plan"

new_app_fixture --class open
fixture_copy docs/state/plan.md
fake_response manager-plan 1 'PLAN_UPDATED=no' 'TASKS_CREATED=-' 'OPEN_RISK=-'
fake_response worker-brainstorm 1 'NOTES_ADDED=-' 'RISKS=-' 'TEST_IDEAS=verify.sh'
fake_response manager-manage 1 '---' 'action: dispatch' 'task_id: 017' 'worker_kind: normal' 'reason_code: NEXT_HIGHEST_VALUE' '---'
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-good
expect_success "Platzhalter-Plan startet Manager-Plan vor dem Loop" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Manager-Plan laeuft bei Platzhalter genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/manager-plan.count")"

new_app_fixture --class open
fake_response worker-brainstorm 1 'NOTES_ADDED=-' 'RISKS=-' 'TEST_IDEAS=verify.sh'
fake_response manager-manage 1 '---' 'action: dispatch' 'task_id: 017' 'worker_kind: normal' 'reason_code: NEXT_HIGHEST_VALUE' '---'
fake_response manager-manage 2 '---' 'action: dispatch' 'task_id: 017' 'worker_kind: normal' 'reason_code: NEXT_HIGHEST_VALUE' '---'
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_response worker-task 2 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_response finalizer 1 'OUTCOME=blocked' 'BEST_GREEN_REF=-' 'OPEN_ERROR=Unveränderter Kandidat' 'HUMAN_DECISION=Prüfung erforderlich'
fake_action worker-task 1 write-bad
fake_action worker-task 2 write-bad
expect_failure "No-Progress-Guard beendet identische Runden" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "No-Progress startet höchstens zwei identische Worker" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "No-Progress blockiert Task sicher" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "No-Progress ruft Finalizer auf" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/finalizer.count")"

finish_suite
