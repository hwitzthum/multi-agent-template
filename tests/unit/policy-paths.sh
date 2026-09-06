#!/usr/bin/env bash
# Welche Pfade in einen Kontext dürfen und welche Rolle wohin schreiben darf.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

policy="$project_dir/scripts/agent/policy.sh"

begin_suite policy-paths

expect_success "normaler Kontextpfad" "$policy" context-path src/app.ts
expect_failure ".env ausgeschlossen" "$policy" context-path .env
expect_failure ".env.example ausgeschlossen" "$policy" context-path .env.example
expect_failure "Binärdatei ausgeschlossen" "$policy" context-path docs/guide.docx
expect_failure "Laufdaten ausgeschlossen" "$policy" context-path .agent-runs/run/raw.log
expect_failure "private Schlüssel ausgeschlossen" "$policy" context-path deploy/private.key
expect_failure "PfadTraversal ausgeschlossen" "$policy" context-path ../outside.txt

expect_success "Manager darf Plan schreiben" "$policy" role-write manager docs/state/plan.md
expect_failure "Manager darf keinen Produktcode schreiben" "$policy" role-write manager src/app.ts
expect_success "Worker darf Produktcode schreiben" "$policy" role-write worker src/app.ts
expect_failure "Worker darf Task-Ledger nicht schreiben" "$policy" role-write worker docs/tasks/017.md
expect_failure "Worker darf Schutz-Hook nicht schreiben" "$policy" role-write worker scripts/bash-guard.sh
expect_success "Verifier darf Prüfbericht schreiben" "$policy" role-write verifier docs/verification/latest.md
expect_failure "Verifier darf Produktcode nicht schreiben" "$policy" role-write verifier src/app.ts
expect_success "Status-Gate darf Task schreiben" "$policy" role-write status-gate docs/tasks/017.md
expect_failure "unbekannte Rolle" "$policy" role-write unknown src/app.ts

expect_failure "nur Orchestrator schreibt Laufdaten" "$policy" role-write finalizer .agent-runs/run/run.env
expect_success "Orchestrator darf Laufdaten schreiben" "$policy" role-write orchestrator .agent-runs/run/run.env
expect_failure "Orchestrator schreibt keinen versionierten Laufzustand" "$policy" role-write orchestrator docs/state/current-run.md

expect_success "Manager darf Task-Inhalte schreiben" "$policy" role-write manager docs/tasks/017.md
expect_success "Finalizer darf Handoff schreiben" "$policy" role-write finalizer docs/state/handoff.md
expect_success "Finalizer darf Notes schreiben" "$policy" role-write finalizer docs/state/notes.md
expect_failure "Finalizer darf keinen Plan schreiben" "$policy" role-write finalizer docs/state/plan.md
expect_failure "Worker darf keinen Plan schreiben" "$policy" role-write worker docs/state/plan.md
expect_failure "unbekannte Rolle darf nirgends schreiben" "$policy" role-write pruefer docs/verification/latest.md

# Die abgeloesten Prompt-Rollen sind keine Schreibbereiche mehr.
for legacy in manager-plan manager-manage worker-brainstorm worker-task worker-fresh; do
  expect_failure "abgeloeste Rolle $legacy hat keinen Schreibbereich" "$policy" role-write "$legacy" src/app.txt
done

finish_suite
