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
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_response worker-task 2 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-bad
fake_action worker-task 2 write-good
expect_success "Verified-Modus repariert genau einmal" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Verified schließt reparierten Task ab" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Verified zählt bestätigten Fehlschlag" 1 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
assert_eq "Verified startet zwei Worker" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_file_has "Verified übernimmt Fehler kompakt in Notes" "$fixture/docs/state/notes.md" 'Verifikation rot'

finish_suite
