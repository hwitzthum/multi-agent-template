#!/usr/bin/env bash
# Verified: nach einer roten Prüfung genau eine Reparaturrunde.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-verified
fixture_workspace

new_app_fixture --class patterned
fake_worker_result 1
fake_worker_result 2
fake_action worker 1 write-bad
fake_action worker 2 write-good
expect_success "Verified-Modus repariert genau einmal" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Verified schließt reparierten Task ab" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Verified zählt bestätigten Fehlschlag" 1 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
assert_eq "Verified startet zwei Worker" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
[ ! -f "$fixture/.agent-runs/fake/manager.count" ] && ok || bad "Verified startet keinen Manager"
assert_file_has "Verified übernimmt Fehler kompakt in Notes" "$fixture/docs/state/notes.md" 'Verifikation rot'

# Ein defekter Prüfweg ist keine Aussage über den Kandidaten: kein Versuch,
# keine Eskalation, kein blockierter Task.
new_app_fixture --class patterned
fake_worker_result 1
fake_action worker 1 write-good
chmod -x "$fixture/scripts/verify.sh"
expect_failure "Defekter Prüfweg stoppt den Lauf" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Verifier-Fehler verbraucht keinen Versuch" 0 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
assert_eq "Verifier-Fehler startet keine zweite Runde" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
assert_eq "Verifier-Fehler lässt den Task offen" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Verifier-Fehler wird als solcher belegt" verification_error "$(fixture_run_state outcome)"
assert_file_has "Prüfbericht trennt den technischen Fehler" "$fixture/docs/verification/017.md" 'failure_kind: verifier'

finish_suite
