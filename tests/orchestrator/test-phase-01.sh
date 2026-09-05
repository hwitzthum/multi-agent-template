#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
config="$project_dir/scripts/agent/config.sh"
policy="$project_dir/scripts/agent/policy.sh"
runner="$project_dir/scripts/agent/runner.sh"

passed=0
failed=0

ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }

expect_success() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then ok; else bad "$name"; fi
}

expect_failure() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then bad "$name"; else ok; fi
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase01.XXXXXX") || exit 1
trap 'rm -f "$tmp_dir"/*; rmdir "$tmp_dir" 2>/dev/null || true' EXIT HUP INT TERM

expect_success "Standardkonfiguration" "$config" --check
expect_success "Konfigurationswert lesen" "$config" --get MAX_TASK_ATTEMPTS

cp "$project_dir/.agent/config.env" "$tmp_dir/unknown.env"
printf '%s\n' 'UNKNOWN_KEY=1' >> "$tmp_dir/unknown.env"
expect_failure "unbekannter Schlüssel" "$config" --check "$tmp_dir/unknown.env"

sed 's/MAX_TASK_ATTEMPTS=3/MAX_TASK_ATTEMPTS=-1/' "$project_dir/.agent/config.env" > "$tmp_dir/negative.env"
expect_failure "negatives Limit" "$config" --check "$tmp_dir/negative.env"

sed 's/MAX_NO_PROGRESS=1/MAX_NO_PROGRESS=1;touch_x/' "$project_dir/.agent/config.env" > "$tmp_dir/shell.env"
expect_failure "Shellsyntax" "$config" --check "$tmp_dir/shell.env"

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

expect_success "Runner-Vertrag" "$runner" --contract
expect_success "lokaler Agenten-CLI" "$runner" --check
expect_failure "Runner weist unbekannte Rolle vor jedem Modellaufruf ab" "$runner" run_agent unknown "$tmp_dir/prompt.md" "$project_dir" "$tmp_dir/raw.md" "$tmp_dir/meta.env"

expect_success "Bash-Guard lässt Statusprüfung zu" sh -c "printf '%s' '{\"command\":\"git status\"}' | '$project_dir/scripts/bash-guard.sh'"
expect_failure "Bash-Guard blockiert Push" sh -c "printf '%s' '{\"command\":\"git push origin main\"}' | '$project_dir/scripts/bash-guard.sh'"
expect_failure "Bash-Guard blockiert rekursives Löschen" sh -c "printf '%s' '{\"command\":\"rm -rf build\"}' | '$project_dir/scripts/bash-guard.sh'"
expect_success "Commit-Gate ignoriert Nicht-Commit" sh -c "printf '%s' '{\"command\":\"git status\"}' | '$project_dir/scripts/commit-gate.sh'"
expect_success "Commit-Gate akzeptiert grünes Verify" sh -c "printf '%s' '{\"command\":\"git commit -m test\"}' | '$project_dir/scripts/commit-gate.sh'"

if [ "$failed" -ne 0 ]; then
  echo "phase-01-tests: RED ($passed bestanden, $failed fehlgeschlagen)"
  exit 1
fi

echo "phase-01-tests: GREEN ($passed bestanden)"
