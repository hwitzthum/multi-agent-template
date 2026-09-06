#!/usr/bin/env bash
# Die zwei Zeilen des Sitzungsstarts: Pruefstand und offene Arbeit.
# Der Pruefstand traegt die Fehlerart mit — ohne sie sagt ein rotes Ergebnis
# nicht, ob das Produkt oder der Pruefweg defekt ist.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

summary="$project_dir/scripts/state-summary.sh"
line() { CLAUDE_PROJECT_DIR="$fixture" "$summary" | sed -n "$1p"; }

begin_suite state-summary
fixture_workspace

new_project_fixture
assert_eq "ohne Pruefung meldet der Kurzstand NEVER" 'verify: NEVER' "$(line 1)"
# Ohne Tasks meldet next-tasks.sh einen Hinweissatz statt READY-Zeilen. Wer
# Zeilen zaehlt statt READY-Zeilen, liest ihn als bereite Aufgabe.
assert_eq "ein leeres Ledger hat keine offene Arbeit" \
  'ready: 0 | review: 0 | blocked: 0' "$(line 2)"

new_project_fixture
make_task --id 001 --status in_progress
make_report --id 001 --result green
assert_eq "gruener Beleg wird als GREEN gemeldet" 'verify: GREEN' "$(line 1)"

new_project_fixture
make_task --id 001 --status in_progress
make_report --id 001 --result red --failure-kind product
assert_eq "ein Produktfehler nennt seine Art" 'verify: RED (product)' "$(line 1)"

new_project_fixture
make_task --id 001 --status in_progress
make_report --id 001 --result red --failure-kind verifier
assert_eq "ein defekter Pruefweg nennt seine Art" 'verify: RED (verifier)' "$(line 1)"

# Gezaehlt wird nur, was jetzt dran ist: 002 haengt an einem offenen 001 und
# darf in `ready` nicht auftauchen.
new_project_fixture
make_task --id 001 --status todo
make_task --id 002 --status todo --depends 001
make_task --id 003 --status review
make_task --id 004 --status blocked --blocked-reason ASK_HUMAN
assert_eq "die offene Arbeit wird nach Zustand gezaehlt" \
  'ready: 1 | review: 1 | blocked: 1' "$(line 2)"

finish_suite
