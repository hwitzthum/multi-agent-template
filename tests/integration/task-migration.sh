#!/usr/bin/env bash
# Die Migration ergänzt fehlende Schemafelder, ohne Bestehendes zu verlieren.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

migrator="$project_dir/scripts/migrate-tasks.sh"
validator="$project_dir/scripts/validate-ledger.sh"

begin_suite task-migration
fixture_workspace

new_project_fixture
old="$fixture/docs/tasks/007.md"
{
  echo '---'
  echo 'id: 007'
  echo 'title: "Alter Task"'
  echo 'depends_on: []'
  echo 'features: [F-007]'
  echo 'status: todo'
  echo 'acceptance: ["./scripts/verify.sh"]'
  echo 'custom_field: bleibt'
  echo '---'
  echo '# Kontext'
  echo 'Alt.'
  echo '# Umfang'
  echo '- Migrieren.'
  echo '# Nicht Teil dieser Aufgabe'
  echo '- Sonstiges.'
  echo '# Akzeptanzkriterien (über die acceptance-Befehle hinaus)'
  echo '- Gültig.'
} > "$old"
before_id=$(ledger_scalar "$old" id)
before_deps=$(ledger_list "$old" depends_on)
expect_success "Migration des alten Schemas" "$migrator" --project-dir "$fixture"
[ "$(ledger_scalar "$old" id)" = "$before_id" ] && [ "$(ledger_list "$old" depends_on)" = "$before_deps" ] \
  && grep -Fqx 'custom_field: bleibt' "$old" && grep -Fqx 'orchestration: auto' "$old" \
  && ok || bad "Migration erhaelt ID, Abhaengigkeiten und unbekannte Felder"
expect_success "migrierter Task ist gueltig" "$validator" --project-dir "$fixture"

finish_suite
