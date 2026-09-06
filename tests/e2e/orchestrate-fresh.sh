#!/usr/bin/env bash
# Der letzte erlaubte Versuch in `managed` läuft fresh: die `touches`-Pfade
# stehen wieder auf dem Laufstart, und der Kontext trägt keine Vorgeschichte.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
runner="$tests_dir/fake-runner.sh"

dispatch='---
action: dispatch
task_id: 017
worker_kind: normal
reason_code: NEXT_HIGHEST_VALUE
---'

begin_suite orchestrate-fresh
fixture_workspace

new_fresh_fixture
fake_response worker-brainstorm 1 'NOTES_ADDED=-' 'RISKS=-' 'TEST_IDEAS=verify.sh'
for round in 1 2 3; do
  printf '%s\n' "$dispatch" > "$fixture/.agent-runs/fake/responses/manager-manage-$round.out"
done
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_response worker-task 2 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-bad
fake_action worker-task 2 write-worse
fake_action worker-fresh 1 require-initial-write-good
expect_success "Letzter Versuch läuft fresh und wird grün" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Fresh-Versuch läuft genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-fresh.count")"
assert_eq "Zwei rote Runden vor dem Fresh-Versuch" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "Grüner offener Task endet im Review" review "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
fresh_context=$(find "$fixture/.agent-runs" -path '*/contexts/worker-fresh-*' -print | LC_ALL=C sort | tail -n 1)
assert_file_lacks "Fresh-Kontext enthält keine historische Note" "$fresh_context" HISTORICAL_SECRET_MUST_NOT_REACH_FRESH
assert_file_lacks "Fresh-Kontext enthält keinen Vorbericht" "$fresh_context" '## Relevanter Plan-Auszug'
expect_success "Ledger bleibt nach dem Fresh-Versuch gültig" "$validator" --project-dir "$fixture"

new_fresh_fixture
fake_response worker-brainstorm 1 'NOTES_ADDED=-' 'RISKS=-' 'TEST_IDEAS=verify.sh'
printf '%s\n' '---
action: dispatch
task_id: 017
worker_kind: fresh
reason_code: STUCK_ON_HISTORY
---' > "$fixture/.agent-runs/fake/responses/manager-manage-1.out"
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-fresh 1 require-initial-write-good
expect_success "Manager kann den Fresh-Versuch selbst verlangen" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
[ ! -f "$fixture/.agent-runs/fake/worker-task.count" ] && ok || bad "Verlangter Fresh-Versuch startet keinen Normal-Worker"

new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-outside
expect_failure "Änderung ausserhalb von touches stoppt den Lauf" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Pfad im Umfang wird auf den Stand vor dem Aufruf zurückgesetzt" initial "$(sed -n '1p' "$fixture/src/app.txt")"
[ ! -e "$fixture/src/other.txt" ] && ok || bad "Pfad ausserhalb des Umfangs wird aus dem Arbeitsbaum entfernt"
quarantined=$(find "$fixture/.agent-runs" -path '*/quarantine/src/other.txt' -print | head -n 1)
assert_file "Entfernter Pfad bleibt in der Quarantäne des Laufs" "$quarantined"
assert_eq "Pfadverletzung markiert Lauf failed" failed "$(fixture_run_state phase)"
expect_success "Ledger bleibt nach der Pfadverletzung gültig" "$validator" --project-dir "$fixture"

finish_suite
