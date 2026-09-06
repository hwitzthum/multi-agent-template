#!/usr/bin/env bash
# Der Router entscheidet allein aus dem Task: Klasse, Vorgabe, Versuche,
# Risiko. Gleiche Eingabe, gleiche Route.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"
. "$project_dir/scripts/agent/route.sh"

max_attempts=3

# route_case <erwarteter modus> <klasse> <orchestration> <cli-modus> <versuche> <flags>
route_case() {
  local expected=$1 class=$2 orchestration=$3 cli=$4 attempts=$5 flags=$6 actual
  new_project_fixture
  make_task --id 001 --class "$class" --orchestration "$orchestration" \
    --attempts "$attempts" --max-attempts "$max_attempts" --risk-flags "$flags"
  actual=$(agent_route_mode "$fixture/docs/tasks/001.md" "$cli" "$max_attempts") || actual='(Fehler)'
  assert_eq "$class/$orchestration/${cli:-–}/$attempts/${flags:-–} wird $expected" "$expected" "$actual"
}

begin_suite router-decisions
fixture_workspace

# Klasse allein.
route_case single    mechanical auto '' 0 ''
route_case verified  patterned  auto '' 0 ''
route_case managed   open       auto '' 0 ''

# Task-Vorgabe ersetzt die Klassenbasis in beide Richtungen.
route_case single    patterned  single   '' 0 ''
route_case managed   mechanical managed  '' 0 ''
route_case single    open       single   '' 0 ''
route_case verified  open       verified '' 0 ''

# Der Einmallauf sticht die Task-Vorgabe.
route_case managed   mechanical single   managed  0 ''
route_case single    open       managed  single   0 ''

# Versuche heben den Rang, senken ihn nie.
route_case verified  mechanical auto '' 1 ''
route_case managed   mechanical auto '' 2 ''
route_case verified  patterned  auto '' 1 ''
route_case managed   patterned  auto '' 2 ''
route_case managed   open       auto '' 1 ''
route_case verified  patterned  single '' 1 ''
route_case managed   open       single '' 2 ''

# Jedes Risiko-Signal hebt das Minimum auf managed.
route_case managed   mechanical auto   '' 0 high-risk
route_case managed   mechanical auto   '' 0 cross-component
route_case managed   mechanical auto   '' 0 repeated-failure
route_case managed   mechanical single '' 0 high-risk
route_case managed   mechanical auto   single 0 repeated-failure
route_case managed   open       auto   '' 2 'high-risk, cross-component'

# Das Versuchslimit sticht alles.
route_case blocked   mechanical auto    '' 3 ''
route_case blocked   open       managed '' 3 high-risk
route_case blocked   patterned  auto    single 3 ''

# Ein niedrigeres max_attempts des Aufrufers gilt ebenfalls.
new_project_fixture
make_task --id 001 --class mechanical --attempts 1 --max-attempts 3
assert_eq "kleineres Aufruferlimit blockiert frueher" blocked \
  "$(agent_route_mode "$fixture/docs/tasks/001.md" '' 1)"

new_project_fixture
make_task --id 001 --class patterned
first=$(agent_route_mode "$fixture/docs/tasks/001.md" '' "$max_attempts")
second=$(agent_route_mode "$fixture/docs/tasks/001.md" '' "$max_attempts")
assert_eq "identische Eingaben liefern identische Entscheidung" "$first" "$second"
assert_eq "Router-Ausgabe ist genau eine Zeile" 1 "$(printf '%s\n' "$first" | wc -l | tr -d ' ')"

expect_failure "unbekannter Modus wird abgewiesen" agent_route_mode "$fixture/docs/tasks/001.md" turbo "$max_attempts"
expect_failure "fehlende Task-Datei wird abgewiesen" agent_route_mode "$fixture/docs/tasks/999.md" '' "$max_attempts"

finish_suite
