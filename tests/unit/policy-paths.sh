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

expect_success "Manager-Plan-Alias nutzt Manager-Schreibgrenze" "$policy" role-write manager-plan docs/state/plan.md
expect_success "Manager-Manage-Alias nutzt Task-Schreibgrenze" "$policy" role-write manager-manage docs/tasks/017.md
expect_success "Brainstorm-Alias darf Notes schreiben" "$policy" role-write worker-brainstorm docs/state/notes.md
expect_success "Task-Worker-Alias darf Produktpfad schreiben" "$policy" role-write worker-task src/app.txt
expect_success "Fresh-Worker-Alias darf Produktpfad schreiben" "$policy" role-write worker-fresh src/app.txt
expect_failure "unbekannte Rolle darf nirgends schreiben" "$policy" role-write pruefer docs/verification/latest.md
expect_failure "Prompt-Rolle erweitert keine Worker-Rechte" "$policy" role-write worker-task docs/state/plan.md

finish_suite
