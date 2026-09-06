#!/usr/bin/env bash
# Nur das Status-Gate setzt Status, und nur mit passendem Prüfbeleg.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

status_gate="$project_dir/scripts/agent/status.sh"

begin_suite status-gate
fixture_workspace

new_project_fixture
make_task --id 001 --status in_progress --human-review true
make_report --id 001 --result green
expect_failure "Human Review verhindert direkten done-Uebergang" "$status_gate" --project-dir "$fixture" set-status 001 done in_progress
expect_contains "abgewiesener Human-Review-Wechsel bleibt unveraendert" 'in_progress' ledger_scalar "$fixture/docs/tasks/001.md" status

new_project_fixture
make_task --id 001 --status todo
expect_success "todo nach in_progress" "$status_gate" --project-dir "$fixture" set-status 001 in_progress todo
expect_failure "veralteter Statuswechsel" "$status_gate" --project-dir "$fixture" set-status 001 in_progress todo

# Der Fall oben scheitert schon an der Uebergangstabelle (in_progress:in_progress
# ist kein gueltiger Wechsel) und sagt damit nichts ueber den Erwartungswert.
# Hier ist der Uebergang todo:in_progress zulaessig — abweisen darf ihn allein
# der Abgleich des erwarteten Stands.
new_project_fixture
make_task --id 001 --status todo
expect_failure "falscher Erwartungswert wird abgewiesen" "$status_gate" --project-dir "$fixture" set-status 001 in_progress review
expect_contains "abgewiesener Wechsel laesst den Status unveraendert" 'todo' ledger_scalar "$fixture/docs/tasks/001.md" status

new_project_fixture
make_task --id 001 --status in_progress
make_report --id 001 --result green
expect_success "done mit passendem gruenen Bericht" "$status_gate" --project-dir "$fixture" set-status 001 done in_progress

new_project_fixture
make_task --id 001 --class mechanical --status review --human-review true
make_report --id 001 --result green
expect_failure "Review kann nicht automatisch auf done" "$status_gate" --project-dir "$fixture" set-status 001 done review
expect_success "ausdrueckliche menschliche Freigabe erlaubt done" "$status_gate" --project-dir "$fixture" --human-approved set-status 001 done review

finish_suite
