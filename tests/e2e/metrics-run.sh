#!/usr/bin/env bash
# Ein Dry Run erfindet kein Outcome, und ein abgebrochener Lauf hinterlässt
# genau eine Metrikzeile.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite metrics-run
fixture_workspace

new_project_fixture --filled-plan
make_task --id 017 --title 'Offene Pilotaufgabe' --features F-017 --class open --touches src/app.txt \
  --context 'Eine kontrollierte Testaufgabe.' --scope '`src/app.txt` bearbeiten.' \
  --not-scope 'Steuerungsdateien ändern.' --criteria 'Die Datei enthält `good`.'

before_lines=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
dry_output=$("$orchestrator" --project-dir "$fixture" --task 017 --dry-run)
after_lines=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
assert_eq "Dry-Run erzeugt keine Outcome-Zeile" "$before_lines" "$after_lines"
dry_metadata=${dry_output#*METADATA=}; dry_metadata=${dry_metadata%%$'\n'*}
assert_file_has "Dry-Run ist lokal ausdrücklich markiert" "$fixture/$dry_metadata" 'dry_run=true'
assert_file_has "Dry-Run besitzt kein erfundenes Outcome" "$fixture/$dry_metadata" 'outcome='

make_task --id 018 --title 'Offene Pilotaufgabe' --features F-017 --class mechanical --touches src/app.txt \
  --context 'Eine kontrollierte Testaufgabe.' --scope '`src/app.txt` bearbeiten.' \
  --not-scope 'Steuerungsdateien ändern.' --criteria 'Die Datei enthält `good`.'
fake_response worker-task 1 'RESULT=implemented'
expect_failure "Abgebrochener Lauf wird kontrolliert erfasst" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 018 --mode single
aborted_run=$(awk -F, 'NR > 1 && $18 == "blocked" {run=$1} END {print run}' "$fixture/docs/state/metrics.csv")
[ -n "$aborted_run" ] && [ "$(awk -F, -v run="$aborted_run" '$1 == run {count++} END {print count+0}' "$fixture/docs/state/metrics.csv")" -eq 1 ] \
  && ok || bad "Abgebrochener Lauf besitzt genau ein Outcome"

finish_suite
