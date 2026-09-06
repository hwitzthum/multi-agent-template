#!/usr/bin/env bash
# Eskalation zählt genau einen Versuch, ist gegen veraltete Aufrufe geschützt
# und lässt sich atomar im Laufstand protokollieren.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

router="$project_dir/scripts/route-task.sh"
validator="$project_dir/scripts/validate-ledger.sh"

patterned='MODE=verified
REASON_CODE=PATTERNED_LOCAL
HUMAN_GATE=false'

begin_suite router-escalation
fixture_workspace

new_project_fixture
make_task --id 001 --class mechanical --status in_progress
make_active_run --id 001
expect_output "Fehler eskaliert genau eine Stufe" 'MODE=verified
REASON_CODE=ESCALATED_AFTER_FAILURE
HUMAN_GATE=false' "$router" --project-dir "$fixture" --escalate-from single --expected-attempts 0 001
assert_file_has "Eskalation zaehlt genau einen Versuch" "$fixture/docs/tasks/001.md" 'attempts: 1'
expect_failure "veraltete Eskalation wird abgewiesen" "$router" --project-dir "$fixture" --escalate-from single --expected-attempts 0 001
assert_file_has "veraltete Eskalation zaehlt nicht erneut" "$fixture/docs/tasks/001.md" 'attempts: 1'

new_project_fixture
make_task --id 001 --class patterned --status in_progress --attempts 2
make_active_run --id 001
expect_output "Versuchslimit endet blocked" 'MODE=blocked
REASON_CODE=ATTEMPT_LIMIT
HUMAN_GATE=false' "$router" --project-dir "$fixture" --escalate-from managed-fresh --expected-attempts 2 001

new_project_fixture
make_task --id 001 --class patterned --status in_progress
make_active_run --id 001
expect_output "Routing kann atomar protokolliert werden" "$patterned" "$router" --project-dir "$fixture" --record 001
grep -Fqx 'mode: verified' "$fixture/docs/state/current-run.md" \
  && grep -Fqx 'route_reason_code: PATTERNED_LOCAL' "$fixture/docs/state/current-run.md" \
  && ok || bad "current-run enthaelt Routingentscheidung"
[ "$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')" = 1 ] \
  && grep -Fqx 'mode=verified' "$fixture/.agent-runs/20260904T091500Z-T001/metadata/route.env" \
  && ok || bad "Routing bleibt lokal und erzeugt keine vorzeitige Laufzeile"
expect_success "protokollierter Lauf bleibt gueltig" "$validator" --project-dir "$fixture"

finish_suite
