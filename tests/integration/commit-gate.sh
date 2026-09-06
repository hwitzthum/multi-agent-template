#!/usr/bin/env bash
# Der Commit-Hook ist still bei anderen Befehlen und blockiert einen Commit
# nur bei roter Schnellprüfung oder kaputtem Ledger.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

gate="$project_dir/scripts/commit-gate.sh"

begin_suite commit-gate
fixture_workspace

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id 20260904T120000Z-T017
printf '%s\n' good > "$fixture/src/app.txt"

expect_success "Commit-Gate ignoriert Nicht-Commit" sh -c "printf '%s\n' '{\"tool_input\":{\"command\":\"git status\"}}' | CLAUDE_PROJECT_DIR='$fixture' '$gate'"
expect_success "Commit-Gate akzeptiert grünes Verify" sh -c "printf '%s\n' '{\"tool_input\":{\"command\":\"git commit -m test\"}}' | CLAUDE_PROJECT_DIR='$fixture' '$gate'"
expect_success "Commit-Gate akzeptiert schnelle Prüfung plus gültiges Ledger" sh -c "printf '%s\n' '{\"tool_input\":{\"command\":\"git commit -m test\"}}' | CLAUDE_PROJECT_DIR='$fixture' '$gate'"

sed 's/status: in_progress/status: unbekannt/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.task.tmp"
mv "$fixture/docs/tasks/.task.tmp" "$fixture/docs/tasks/017.md"
expect_failure "Commit-Gate blockiert inkonsistentes Ledger" sh -c "printf '%s\n' '{\"tool_input\":{\"command\":\"git commit -m test\"}}' | CLAUDE_PROJECT_DIR='$fixture' '$gate'"

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id 20260904T120000Z-T017
printf '%s\n' bad > "$fixture/src/app.txt"
expect_failure "Commit-Gate blockiert rote Schnellprüfung" sh -c "printf '%s\n' '{\"tool_input\":{\"command\":\"git commit -m test\"}}' | CLAUDE_PROJECT_DIR='$fixture' '$gate'"

finish_suite
