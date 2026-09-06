#!/usr/bin/env bash
# Einmallauf: eine Worker-Runde, danach entscheidet allein die Prüfung.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-single
fixture_workspace

new_app_fixture
before=$(find "$fixture" -type f ! -path '*/.agent-runs/*' -exec shasum -a 256 {} \; | shasum -a 256 | awk '{print $1}')
dry_output=$(ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 --dry-run)
after=$(find "$fixture" -type f ! -path '*/.agent-runs/*' -exec shasum -a 256 {} \; | shasum -a 256 | awk '{print $1}')
assert_eq "Dry Run verändert keine produktive oder versionierte Datei" "$before" "$after"
case "$dry_output" in *'MODE=single'*'PLANNED_CALLS=worker-task,verify'*) ok ;; *) bad "Dry Run zeigt Route und Aufrufe" ;; esac

new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-good
expect_success "Single-Modus schließt grünen Task ab" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Single setzt Status done" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Single setzt Lauf finished" finished "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"
assert_eq "Single startet genau einen Worker" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_file_has "Single erzeugt grünen Prüfbericht" "$fixture/docs/verification/latest.md" 'result: green'

new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-bad
expect_failure "Worker-Behauptung überstimmt rote Prüfung nicht" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Roter Single-Task bleibt todo" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Rote Prüfung wird im Task protokolliert" red "$(ledger_scalar "$fixture/docs/tasks/017.md" last_verification)"

finish_suite
