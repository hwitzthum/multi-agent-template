#!/usr/bin/env bash
# Der Validator ist das Gedächtnis des Ledgers: er lässt nur einen in sich
# stimmigen Aufgabenstand durch.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

validator="$project_dir/scripts/validate-ledger.sh"
next_tasks="$project_dir/scripts/next-tasks.sh"

begin_suite ledger-validation
fixture_workspace

new_project_fixture
make_task --id 001 --status done --acceptance-style block
make_task --id 002 --status todo --depends 001 --acceptance-style block
make_report --id 001 --result green
expect_success "gueltiger Task-Graph" "$validator" --project-dir "$fixture"
expect_contains "nur abhaengigkeitsfreier todo-Task ist bereit" 'READY: 002 | Task 002 | patterned' "$next_tasks" --project-dir "$fixture"

new_project_fixture
make_task --id 002 --status todo --depends 999
expect_failure "fehlende Abhaengigkeit" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo --depends 002
make_task --id 002 --status todo --depends 001
expect_failure "zyklische Abhaengigkeit" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo
cp "$fixture/docs/tasks/001.md" "$fixture/docs/tasks/duplicate.md"
expect_failure "doppelte Task-ID" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status done
expect_failure "done ohne Pruefbericht" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status done
make_report --id 002 --result green
expect_failure "done ohne passenden Pruefbericht" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status done
make_report --id 001 --result red
expect_failure "done mit rotem Pruefbericht" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo --orchestration impossible
expect_failure "unbekannter Orchestrierungsmodus" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo --attempts spaeter
expect_failure "attempts ist keine Zahl" "$validator" --project-dir "$fixture"

# Eine Task-Datei nach make_task gezielt verbiegen: patch_task <sed-Ausdruck>
patch_task() {
  sed "$1" "$fixture/docs/tasks/001.md" > "$fixture/docs/tasks/001.new" \
    && mv "$fixture/docs/tasks/001.new" "$fixture/docs/tasks/001.md"
}

# Das Schema ist abschliessend: was nicht dazugehoert, faellt auf.
new_project_fixture
make_task --id 001 --status todo
patch_task 's/^attempts: 0$/attempts: 0\'$'\n''max_attempts: 3/'
expect_failure "abgeschafftes Feld max_attempts wird abgewiesen" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo
patch_task '/^touches:/d'
expect_failure "fehlende Pflichtliste touches" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo
patch_task 's/^status: todo$/status: [todo, done]/'
expect_failure "Einzelfeld mit mehreren Werten" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status todo
patch_task 's/^# Akzeptanzkriterien$/# Akzeptanzkriterien (über die acceptance-Befehle hinaus)/'
expect_failure "abgewandelter Pflichtabschnitt zaehlt nicht" "$validator" --project-dir "$fixture"

# Ein Ledger mit 60 Aufgaben muss in unter einer Sekunde geprueft sein; sonst
# wird der Validator zum Bremsklotz jedes Laufs und jeder Statusaenderung.
new_project_fixture
index=1
while [ "$index" -le 60 ]; do
  make_task --id "$(printf '%03d' "$index")"
  index=$((index + 1))
done
started=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
expect_success "60 Tasks sind gueltig" "$validator" --project-dir "$fixture"
elapsed=$(( $(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000') - started ))
if [ "$elapsed" -lt 1000 ]; then ok; else bad "60 Tasks brauchen ${elapsed}ms statt unter 1000ms"; fi

new_project_fixture
make_task --id 001 --status todo
sed '/# Umfang/d' "$fixture/docs/tasks/001.md" > "$fixture/docs/tasks/001.tmp"
mv "$fixture/docs/tasks/001.tmp" "$fixture/docs/tasks/001.md"
expect_failure "fehlender Pflichtabschnitt" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status in_progress
expect_success "ein einzelner laufender Task ist zulaessig" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --status in_progress
make_task --id 002 --status in_progress
expect_failure "zwei gleichzeitig laufende Tasks" "$validator" --project-dir "$fixture"

new_project_fixture
make_task --id 001 --class mechanical --risk-flags unknown-risk
expect_failure "unbekanntes Risikosignal" "$validator" --project-dir "$fixture"

finish_suite
