#!/usr/bin/env bash
# Die beiden menschlichen Statusuebergaenge: `reopen` oeffnet eine blockierte
# Aufgabe, `approve` gibt eine Aufgabe im Review frei. Ohne Mensch geht keiner
# von beiden.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

task_tool="$project_dir/scripts/task.sh"
status_gate="$project_dir/scripts/agent/status.sh"
validator="$project_dir/scripts/validate-ledger.sh"

begin_suite task-commands
fixture_workspace

# reopen: blocked -> todo, und der Grund verschwindet mit dem Zustand.
new_project_fixture
make_task --id 001 --status blocked
sed 's/^blocked_reason: ""$/blocked_reason: ASK_HUMAN/' "$fixture/docs/tasks/001.md" > "$fixture/docs/tasks/001.new"
mv "$fixture/docs/tasks/001.new" "$fixture/docs/tasks/001.md"
expect_success "blockierte Aufgabe ist gueltig" "$validator" --project-dir "$fixture"
expect_failure "der Orchestrator kann blocked nicht selbst oeffnen" "$status_gate" --project-dir "$fixture" set-status 001 todo blocked
assert_eq "abgewiesenes Oeffnen laesst den Status stehen" blocked "$(ledger_scalar "$fixture/docs/tasks/001.md" status)"
expect_success "reopen oeffnet die Aufgabe" "$task_tool" --project-dir "$fixture" reopen 001
assert_eq "reopen setzt todo" todo "$(ledger_scalar "$fixture/docs/tasks/001.md" status)"
assert_eq "reopen raeumt den Grund weg" '' "$(ledger_scalar "$fixture/docs/tasks/001.md" blocked_reason)"
expect_success "Ledger bleibt nach reopen gueltig" "$validator" --project-dir "$fixture"
expect_failure "reopen auf einer offenen Aufgabe wird abgewiesen" "$task_tool" --project-dir "$fixture" reopen 001

# approve: review -> done, aber nur mit passendem gruenem Bericht.
new_project_fixture
make_task --id 001 --status review --class open
expect_failure "approve ohne gruenen Bericht" "$task_tool" --project-dir "$fixture" approve 001
make_report --id 001 --result green
expect_success "approve gibt die Aufgabe frei" "$task_tool" --project-dir "$fixture" approve 001
assert_eq "approve setzt done" done "$(ledger_scalar "$fixture/docs/tasks/001.md" status)"
expect_success "Ledger bleibt nach approve gueltig" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo
expect_failure "approve greift nur im Review" "$task_tool" --project-dir "$fixture" approve 001

# Der Weg in den Review bleibt automatisch, die Freigabe daraus nicht.
new_project_fixture
make_task --id 001 --status in_progress --human-review true
make_report --id 001 --result green
expect_success "grüner Lauf endet im Review" "$status_gate" --project-dir "$fixture" set-status 001 review in_progress
expect_failure "ohne Freigabe bleibt der Review stehen" "$status_gate" --project-dir "$fixture" set-status 001 done review
expect_success "approve schliesst den Review ab" "$task_tool" --project-dir "$fixture" approve 001
assert_eq "Review endet auf done" done "$(ledger_scalar "$fixture/docs/tasks/001.md" status)"

expect_failure "unbekanntes Kommando" "$task_tool" --project-dir "$fixture" fertig 001
expect_failure "ungueltige Task-ID" "$task_tool" --project-dir "$fixture" reopen eins
expect_contains "task --help nennt beide Kommandos" 'approve' "$task_tool" --help

finish_suite
