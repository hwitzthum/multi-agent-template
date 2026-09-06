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
before=$(find "$fixture" -type f ! -path '*/.agent-runs/*' ! -path '*/.git/*' -exec shasum -a 256 {} \; | shasum -a 256 | awk '{print $1}')
dry_output=$(ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 --dry-run)
after=$(find "$fixture" -type f ! -path '*/.agent-runs/*' ! -path '*/.git/*' -exec shasum -a 256 {} \; | shasum -a 256 | awk '{print $1}')
assert_eq "Dry Run verändert keine produktive oder versionierte Datei" "$before" "$after"
case "$dry_output" in *'MODE=single'*'PLANNED_CALLS=worker,verify'*) ok ;; *) bad "Dry Run zeigt Route und Aufrufe" ;; esac
case "$dry_output" in *'FINALIZER=off'*) ok ;; *) bad "Dry Run nennt den Finalizer-Schalter" ;; esac

new_app_fixture
fake_worker_result 1
fake_action worker 1 write-good
expect_success "Single-Modus schließt grünen Task ab" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Single setzt Status done" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Single setzt Lauf finished" finished "$(fixture_run_state phase)"
assert_eq "Single startet genau einen Worker" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
[ ! -f "$fixture/.agent-runs/fake/manager.count" ] && ok || bad "Single startet keinen Manager"
assert_file_has "Single erzeugt grünen Prüfbericht" "$fixture/docs/verification/latest.md" 'result: green'
assert_file_has "Grüner Lauf hinterlässt einen Laufbeleg" "$fixture/docs/state/handoff.md" '- Ergebnis: success'
assert_file_has "Laufbeleg nennt den Verifierstatus" "$fixture/docs/state/handoff.md" '- Verifierstatus: GREEN'

# Mit genau einem erlaubten Versuch gibt es nach Rot keine zweite Stufe mehr.
new_app_fixture
fixture_config MAX_TASK_ATTEMPTS 1
fake_worker_result 1
fake_action worker 1 write-bad
expect_failure "Worker-Behauptung überstimmt rote Prüfung nicht" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Ausgeschöpftes Versuchslimit blockiert den Task" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Blockade nennt das Versuchslimit" ATTEMPT_LIMIT "$(ledger_scalar "$fixture/docs/tasks/017.md" blocked_reason)"
assert_eq "Rote Prüfung steht im Task-Beleg" red "$(ledger_scalar "$fixture/docs/verification/017.md" result)"
assert_eq "Single startet genau einen Worker" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
assert_file_has "Roter Lauf hinterlässt einen Laufbeleg" "$fixture/docs/state/handoff.md" '- Verifierstatus: RED'

finish_suite
