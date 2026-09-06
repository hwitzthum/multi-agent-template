#!/usr/bin/env bash
# Managed: der Manager entscheidet pro Runde, darf Tasks schärfen und anlegen,
# aber die Steuerfelder nie bewegen.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-managed
fixture_workspace

new_app_fixture --class open
fake_manager_result 1
fake_worker_result 1
fake_action worker 1 write-good
expect_success "Managed-Modus führt Manager-Worker-Runde aus" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Managed startet einen Worker pro Runde" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
assert_eq "Managed fragt den Manager genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/manager.count")"
assert_eq "Managed hält offenen grünen Task im Review" review "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_file_has "Laufbeleg nennt das Review" "$fixture/docs/state/handoff.md" '- Ergebnis: review'

# Der Manager darf Aufgaben anlegen — aber nur mit `todo` und null Versuchen.
new_app_fixture --class open
fake_manager_result 1
fake_worker_result 1
fake_action manager 1 new-task
fake_action worker 1 write-good
expect_success "Manager darf einen Task nachlegen" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Nachgelegter Task startet auf todo" todo "$(ledger_scalar "$fixture/docs/tasks/018.md" status)"
assert_eq "Nachgelegter Task startet ohne Versuche" 0 "$(ledger_scalar "$fixture/docs/tasks/018.md" attempts)"
expect_success "Ledger bleibt nach dem neuen Task gültig" "$validator" --project-dir "$fixture"

new_app_fixture --class open
fake_manager_result 1
fake_action manager 1 tamper-attempts
expect_failure "Manager kann die Versuchszählung nicht bewegen" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Die geschützte Versuchszählung bleibt stehen" 0 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
[ ! -f "$fixture/.agent-runs/fake/worker.count" ] && ok || bad "Steuerfeldverstoss startet keinen Worker"

new_app_fixture --class open
fake_manager_result 1 done
expect_failure "Manager meldet done ohne grünen Beleg vergeblich" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Unbelegtes done ändert den Status nicht" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

# Der Finalizer ist abwählbar: erst `FINALIZER=llm` erlaubt den Zusatzaufruf.
new_app_fixture --class open
fake_manager_result 1 blocked ''
expect_failure "Manager blockiert den Lauf" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Manager-Blockade blockiert den Task" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
[ ! -f "$fixture/.agent-runs/fake/finalizer.count" ] && ok || bad "FINALIZER=off ruft keinen Finalizer"

new_app_fixture --class open
fixture_config FINALIZER llm
fake_manager_result 1 blocked ''
fake_response finalizer 1 open_error 'Prüfung blieb rot.' next_decision 'Umfang klären.' best_green_ref ''
expect_failure "Manager blockiert den Lauf auch mit Finalizer" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "FINALIZER=llm ruft den Finalizer genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/finalizer.count")"
assert_file_has "Auch der blockierte Lauf hinterlässt einen Laufbeleg" "$fixture/docs/state/handoff.md" '- Ergebnis: blocked'

finish_suite
