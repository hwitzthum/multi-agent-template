#!/usr/bin/env bash
# Eskalation: jede rote Prüfung hebt den Modus um genau eine Stufe, und der
# letzte erlaubte Versuch läuft fresh.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-escalation
fixture_workspace

# Jede Runde hinterlaesst ein anderes Produkt; der No-Progress-Guard bleibt
# damit still, und geprüft wird allein die Leiter single -> verified -> managed.
new_app_fixture
fake_worker_result 1
fake_worker_result 2
fake_worker_result 3
fake_manager_result 1
fake_action worker 1 write-bad
fake_action worker 2 write-worse
fake_action worker 3 require-initial-write-good
ladder=$(ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 2>&1)
status=$?
assert_eq "Eskalierter Lauf endet grün" 0 "$status"
case "$ladder" in
  *'Modus ist jetzt verified'*'Modus ist jetzt managed'*) ok ;;
  *) bad "Eskalation nimmt genau eine Stufe pro rotem Versuch"; printf '%s\n' "$ladder" >&2 ;;
esac
assert_eq "Zwei rote Runden zählen zwei Versuche" 2 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
assert_eq "Erst die dritte Runde ruft den Manager" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/manager.count")"
assert_eq "Drei Worker-Runden insgesamt" 3 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count")"
assert_eq "Der reparierte Task wird done" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
fresh_context=$(find "$fixture/.agent-runs" -path '*/contexts/worker-fresh-*' -print | LC_ALL=C sort | tail -n 1)
assert_file "Der letzte Versuch läuft als Fresh-Worker" "$fresh_context"
assert_file_has "Laufbeleg nennt den erreichten Modus" "$fixture/docs/state/handoff.md" '- Modus: managed'
expect_success "Ledger bleibt nach der Eskalation gültig" "$validator" --project-dir "$fixture"

# Ohne Fortschritt endet die Leiter früher: zwei identische Runden reichen.
new_app_fixture
fake_worker_result 1
fake_worker_result 2
fake_action worker 1 write-bad
fake_action worker 2 write-bad
expect_failure "Stillstand beendet die Eskalation" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Stillstand blockiert den Task" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Stillstand nennt seinen Grund" NO_PROGRESS "$(ledger_scalar "$fixture/docs/tasks/017.md" blocked_reason)"
assert_eq "Stillstand wird als Ergebnis belegt" no_progress "$(fixture_run_state outcome)"

finish_suite
