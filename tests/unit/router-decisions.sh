#!/usr/bin/env bash
# Der Router entscheidet allein aus dem Task: gleiche Eingabe, gleiche Route.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

router="$project_dir/scripts/route-task.sh"

mechanical='MODE=single
REASON_CODE=MECHANICAL_LOCAL
HUMAN_GATE=false'
patterned='MODE=verified
REASON_CODE=PATTERNED_LOCAL
HUMAN_GATE=false'
open='MODE=managed
REASON_CODE=OPEN_DECISION
HUMAN_GATE=true'

begin_suite router-decisions
fixture_workspace

new_project_fixture
make_task --id 001 --class mechanical
expect_output "mechanical wird single" "$mechanical" "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class patterned
expect_output "patterned wird verified" "$patterned" "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class open
expect_output "open wird managed mit Human Gate" "$open" "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class open
expect_output "Einmallauf kann open nicht auf single senken" "$open" "$router" --project-dir "$fixture" --mode single 001

new_project_fixture
make_task --id 001 --class patterned --orchestration single
expect_output "Task-Vorgabe darf patterned herabstufen" 'MODE=single
REASON_CODE=EXPLICIT_OVERRIDE
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class patterned
expect_output "Einmallauf-Vorgabe wird respektiert" 'MODE=single
REASON_CODE=EXPLICIT_OVERRIDE
HUMAN_GATE=false' "$router" --project-dir "$fixture" --mode single 001

new_project_fixture
make_task --id 001 --class mechanical --orchestration single --risk-flags high-risk-domain
expect_output "explizites single umgeht Hochrisiko nicht" 'MODE=managed
REASON_CODE=HIGH_RISK_DOMAIN
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical --touches 'frontend, api'
expect_output "mehrere Komponenten werden managed" 'MODE=managed
REASON_CODE=CROSS_COMPONENT
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical --touches frontend
expect_output "ein lokaler Bereich bleibt single" "$mechanical" "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class patterned --scope 'Authentifizierung und Berechtigungen ändern.'
expect_output "Auth-Umfang wird mindestens managed" 'MODE=managed
REASON_CODE=HIGH_RISK_DOMAIN
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical --fresh required
expect_output "Fresh-Vorgabe wird managed-fresh" 'MODE=managed-fresh
REASON_CODE=FRESH_REQUIRED
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class patterned --risk-flags repeated-failure
expect_output "wiederholter Fehler wird managed-fresh" 'MODE=managed-fresh
REASON_CODE=REPEATED_FAILURE
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class patterned --risk-flags conflicting-ledger
expect_output "widerspruechliches Ledger wird managed-fresh" 'MODE=managed-fresh
REASON_CODE=CONFLICTING_LEDGER
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical --attempts 2
expect_output "mehrere Fehlversuche werden managed" 'MODE=managed
REASON_CODE=FAILED_ATTEMPTS
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical --attempts 3 --max-attempts 3
expect_output "ausgeschoepftes Versuchslimit blockiert" 'MODE=blocked
REASON_CODE=ATTEMPT_LIMIT
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical --human-review true
expect_output "Human Review bleibt als Gate sichtbar" 'MODE=single
REASON_CODE=MECHANICAL_LOCAL
HUMAN_GATE=true' "$router" --project-dir "$fixture" 001

new_project_fixture
make_task --id 001 --class mechanical
first=$($router --project-dir "$fixture" 001)
second=$($router --project-dir "$fixture" 001)
assert_eq "identische Eingaben liefern identische Entscheidung" "$first" "$second"
assert_eq "Router-Ausgabe hat exakt drei Zeilen" 3 "$(printf '%s\n' "$first" | wc -l | tr -d ' ')"

new_project_fixture
make_task --id 001 --class mechanical
expect_failure "unbekannter manueller Modus" "$router" --project-dir "$fixture" --mode turbo 001

finish_suite
