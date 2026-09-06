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

begin_suite orchestrate-fresh
fixture_workspace

new_fresh_fixture
for round in 1 2 3; do
  fake_manager_result "$round"
  fake_worker_result "$round"
done
fake_action worker 1 write-bad
fake_action worker 2 write-worse
fake_action worker 3 require-initial-write-good
expect_success "Letzter Versuch läuft fresh und wird grün" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Drei Worker-Runden, davon die letzte fresh" 3 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
assert_eq "Grüner offener Task endet im Review" review "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
fresh_context=$(find "$fixture/.agent-runs" -path '*/contexts/worker-fresh-*' -print | LC_ALL=C sort | tail -n 1)
assert_file "Der Fresh-Kontext ist als solcher benannt" "$fresh_context"
assert_file_has "Fresh-Kontext benennt den zweiten Anlauf" "$fresh_context" 'Unabhängiger zweiter Anlauf'
assert_file_lacks "Fresh-Kontext enthält keine historische Note" "$fresh_context" HISTORICAL_SECRET_MUST_NOT_REACH_FRESH
assert_file_lacks "Fresh-Kontext enthält keinen Vorbericht" "$fresh_context" '## Letzte Verifikation'
expect_success "Ledger bleibt nach dem Fresh-Versuch gültig" "$validator" --project-dir "$fixture"

new_app_fixture
fake_worker_result 1
fake_action worker 1 write-outside
expect_failure "Änderung ausserhalb von touches stoppt den Lauf" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Pfad im Umfang wird auf den Stand vor dem Aufruf zurückgesetzt" initial "$(sed -n '1p' "$fixture/src/app.txt")"
[ ! -e "$fixture/src/other.txt" ] && ok || bad "Pfad ausserhalb des Umfangs wird aus dem Arbeitsbaum entfernt"
quarantined=$(find "$fixture/.agent-runs" -path '*/quarantine/src/other.txt' -print | head -n 1)
assert_file "Entfernter Pfad bleibt in der Quarantäne des Laufs" "$quarantined"
assert_eq "Pfadverletzung markiert Lauf failed" failed "$(fixture_run_state phase)"
expect_success "Ledger bleibt nach der Pfadverletzung gültig" "$validator" --project-dir "$fixture"

finish_suite
