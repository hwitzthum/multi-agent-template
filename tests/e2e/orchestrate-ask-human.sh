#!/usr/bin/env bash
# `ask_human`: die Frage steht im Task, die Aufgabe ist blockiert, kein Versuch
# ist verbraucht — und nach der Antwort sieht der Manager sie im Kontext.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
task_command="$project_dir/scripts/task.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-ask-human
fixture_workspace

new_app_fixture --class open
fake_manager_result 1 ask_human '' 'Soll die Datei good oder alpha enthalten?'
expect_failure "Offene Frage beendet den Lauf" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Offene Frage blockiert den Task" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Offene Frage nennt sich als Grund" ASK_HUMAN "$(ledger_scalar "$fixture/docs/tasks/017.md" blocked_reason)"
assert_eq "Offene Frage verbraucht keinen Versuch" 0 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
assert_eq "Offene Frage startet keinen Worker" '' "$(sed -n '1p' "$fixture/.agent-runs/fake/worker.count" 2>/dev/null)"
assert_file_has "Die Frage steht im Task" "$fixture/docs/tasks/017.md" '# Offene Frage'
assert_file_has "Die Frage steht wörtlich im Task" "$fixture/docs/tasks/017.md" 'Soll die Datei good oder alpha enthalten?'
assert_file_has "Der Task nennt den Weg zurück" "$fixture/docs/tasks/017.md" './scripts/task.sh reopen 017'
assert_eq "Der Laufbeleg hält die Frage fest" ask_human "$(fixture_run_state outcome)"
assert_file_has "Handoff nennt die offene Frage" "$fixture/docs/state/handoff.md" '- Ergebnis: ask_human'
expect_success "Ledger bleibt nach der Frage gültig" "$validator" --project-dir "$fixture"

# Der Mensch antwortet im Task und öffnet ihn wieder; der Manager sieht beides.
printf -- '- Antwort: good.\n' >> "$fixture/docs/tasks/017.md"
expect_success "Wiedereröffnen ist ein menschlicher Schritt" "$task_command" --project-dir "$fixture" reopen 017
assert_eq "Wiedereröffneter Task ist todo" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Wiedereröffneter Task trägt keinen Grund mehr" '' "$(ledger_scalar "$fixture/docs/tasks/017.md" blocked_reason)"
fake_manager_result 2
fake_worker_result 1
fake_action worker 1 write-good
expect_success "Nach der Antwort läuft der Task durch" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 --allow-dirty
manager_context=$(find "$fixture/.agent-runs" -path '*/contexts/manager-*' -print | LC_ALL=C sort | tail -n 1)
assert_file_has "Der Manager sieht die Antwort im Task" "$manager_context" 'Antwort: good.'

finish_suite
