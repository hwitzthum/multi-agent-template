#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
. "$project_dir/scripts/agent/ledger.sh"

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
expect_success() { name=$1; shift; if command_output=$("$@" 2>&1); then ok; else echo "$command_output" >&2; bad "$name"; fi; }
expect_failure() { name=$1; shift; if command_output=$("$@" 2>&1); then echo "$command_output" >&2; bad "$name"; else ok; fi; }
assert_eq() { name=$1; expected=$2; actual=$3; [ "$expected" = "$actual" ] && ok || bad "$name (erwartet '$expected', erhalten '$actual')"; }
assert_file_has() { name=$1; file=$2; wanted=$3; grep -Fq -- "$wanted" "$file" && ok || bad "$name"; }

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase06.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture=''

new_fixture() {
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || exit 1
  mkdir -p "$fixture/.agent" "$fixture/scripts/agent" "$fixture/docs/tasks" \
    "$fixture/docs/state/notes-archive" "$fixture/docs/verification/history" "$fixture/src"
  cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
  cp "$project_dir/scripts/verify-task.sh" "$fixture/scripts/verify-task.sh"
  cp "$project_dir/scripts/validate-ledger.sh" "$fixture/scripts/validate-ledger.sh"
  cp "$project_dir/scripts/agent/common.sh" "$fixture/scripts/agent/common.sh"
  cp "$project_dir/scripts/agent/ledger.sh" "$fixture/scripts/agent/ledger.sh"
  cp "$project_dir/scripts/agent/status.sh" "$fixture/scripts/agent/status.sh"
  cp "$project_dir/scripts/agent/config.sh" "$fixture/scripts/agent/config.sh"
  chmod +x "$fixture/scripts/verify-task.sh" "$fixture/scripts/validate-ledger.sh" "$fixture/scripts/agent/status.sh" "$fixture/scripts/agent/config.sh"
  cp "$project_dir/docs/state/goal.md" "$fixture/docs/state/goal.md"
  cp "$project_dir/docs/state/plan.md" "$fixture/docs/state/plan.md"
  cp "$project_dir/docs/state/metrics.csv" "$fixture/docs/state/metrics.csv"
  cat > "$fixture/docs/state/notes.md" <<'EOF'
# Notizen
EOF
  cat > "$fixture/docs/state/current-run.md" <<'EOF'
---
run_id: 20260904T120000Z-T017
task_id: 017
mode: verified
phase: verify
iteration: 1
attempt: 1
last_progress_fingerprint: none
started_at: 2026-09-04T12:00:00Z
route_rule_version: "1"
route_reason_code: EXPLICIT_OVERRIDE
route_human_gate: false
route_signals: [CLI_OVERRIDE]
---
EOF
  cat > "$fixture/docs/verification/latest.md" <<'EOF'
---
run_id: none
task_id: none
result: never
attempt: 0
finished_at: never
---
# Letzte Prüfung
EOF
  cat > "$fixture/docs/tasks/017.md" <<'EOF'
---
id: 017
title: "Kandidat verifizieren"
depends_on: []
features: [F-017]
status: in_progress
class: patterned
orchestration: verified
fresh_perspective: auto
touches: [src/app.txt]
risk_flags: []
attempts: 0
max_attempts: 3
last_verification: never
human_review: false
acceptance: ["./scripts/verify.sh"]
blocked_reason: ""
---
# Kontext
Ein deterministischer Testkandidat.
# Umfang
- `src/app.txt` prüfen.
# Nicht Teil dieser Aufgabe
- Andere Produktdateien ändern.
# Akzeptanzkriterien (über die acceptance-Befehle hinaus)
- Die Datei enthält exakt `good`.
EOF
  printf '%s\n' good > "$fixture/src/app.txt"
  cat > "$fixture/scripts/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(sed -n '1p' "$root/src/app.txt")" = good ]; then echo 'verify: GREEN'; exit 0; fi
echo 'verify: RED'
exit 1
EOF
  chmod +x "$fixture/scripts/verify.sh"
}

set_acceptance() {
  value=$1
  sed "s|^acceptance:.*|acceptance: [$value]|" "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.task.tmp"
  mv "$fixture/docs/tasks/.task.tmp" "$fixture/docs/tasks/017.md"
}

run_verify() {
  "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id 20260904T120000Z-T017 --timeout 3 017
}

run_commit_gate() {
  printf '%s\n' '{"tool_input":{"command":"git commit -m test"}}' | CLAUDE_PROJECT_DIR="$fixture" "$project_dir/scripts/commit-gate.sh"
}

new_fixture
expect_success "grüner Kandidat passiert das Gateway" run_verify
assert_eq "grünes Gateway aktualisiert last_verification" green "$(ledger_scalar "$fixture/docs/tasks/017.md" last_verification)"
assert_file_has "Bericht enthält Kandidatenfingerprint" "$fixture/docs/verification/latest.md" 'candidate_fingerprint:'
assert_file_has "Bericht enthält Verifierversion" "$fixture/docs/verification/latest.md" 'verifier_version:'
assert_file_has "Bericht nennt alle Stufen" "$fixture/docs/verification/latest.md" '- integration: SKIPPED'
assert_file_has "vollständiger Log liegt am dokumentierten Ort" "$fixture/.agent-runs/20260904T120000Z-T017/verify/attempt-1.log" 'acceptance: acceptance-1'
expect_success "passender grüner Fingerprint erlaubt done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress
sed 's/task_id: 017/task_id: 018/' "$fixture/docs/verification/latest.md" > "$fixture/docs/verification/.latest.tmp"
mv "$fixture/docs/verification/.latest.tmp" "$fixture/docs/verification/latest.md"
expect_success "historischer Task-Beleg bleibt nach anderer Latest-Prüfung auffindbar" ledger_verification_is_green "$fixture/docs/verification" 017 "$fixture" "$fixture/docs/tasks/017.md"

new_fixture
expect_success "Kandidat wird zunächst grün" run_verify
printf '%s\n' changed > "$fixture/src/app.txt"
expect_failure "nachträgliche Kandidatenänderung verweigert done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress

new_fixture
expect_success "Verifierstand wird zunächst grün" run_verify
printf '%s\n' '# verifier changed' >> "$fixture/scripts/verify.sh"
expect_failure "nachträgliche Teständerung verweigert done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress

new_fixture
sed 's/human_review: false/human_review: true/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.task.tmp"
mv "$fixture/docs/tasks/.task.tmp" "$fixture/docs/tasks/017.md"
expect_success "Human-Review-Kandidat wird maschinell grün" run_verify
expect_failure "Human Review verhindert direktes done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress
expect_success "grüner Human-Review-Kandidat wechselt in review" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 review in_progress
expect_failure "review braucht ausdrückliche menschliche Freigabe" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done review
expect_success "menschliche Freigabe schließt review ab" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" --human-approved set-status 017 done review

new_fixture
set_acceptance '"./scripts/verify.sh; touch injected"'
expect_failure "Shell-Metazeichen werden abgewiesen" run_verify
[ ! -e "$fixture/injected" ] && ok || bad "abgewiesener Befehl wurde dennoch ausgeführt"
assert_file_has "Bericht dokumentiert sichere Abweisung" "$fixture/docs/verification/latest.md" 'REJECTED'

new_fixture
printf '%s\n' './scripts/verify.sh' > "$fixture/.agent/verification-allowlist"
set_acceptance '"./scripts/verify.sh", "pytest"'
expect_failure "Projekt-Allowlist kann Standardpräfixe verschärfen" run_verify
assert_file_has "verschärfte Allowlist weist Zusatzbefehl aus" "$fixture/docs/verification/latest.md" 'Befehlspraefix ist nicht erlaubt'

new_fixture
cat > "$fixture/scripts/named-check" <<'EOF'
#!/usr/bin/env bash
echo named-runner-ok
EOF
chmod +x "$fixture/scripts/named-check"
printf '%s\n' 'release|build|./scripts/named-check' > "$fixture/.agent/verification-runners"
set_acceptance '"./scripts/verify.sh", "runner:release"'
expect_success "Projektprofil ergänzt einen benannten Runner" run_verify
assert_file_has "benannter Runner wird seiner Stufe zugeordnet" "$fixture/docs/verification/latest.md" '- build: GREEN'

new_fixture
set_acceptance '"./scripts/verify.sh", "mypy"'
expect_failure "fehlender erlaubter Befehl ergibt Rot" env PATH=/usr/bin:/bin "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id 20260904T120000Z-T017 --timeout 3 017
assert_file_has "fehlender Befehl wird als technischer Fehler getrennt" "$fixture/docs/verification/latest.md" 'failure_kind: verifier'
assert_file_has "fehlender Befehl erhält Stufenstatus" "$fixture/docs/verification/latest.md" '- lint: MISSING'

new_fixture
mkdir -p "$fixture/bin"
cat > "$fixture/bin/pytest" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
chmod +x "$fixture/bin/pytest"
set_acceptance '"./scripts/verify.sh", "pytest"'
expect_failure "Zeitlimit ergibt Rot" env PATH="$fixture/bin:/usr/bin:/bin" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id 20260904T120000Z-T017 --timeout 1 017
assert_file_has "Timeout ist im Bericht sichtbar" "$fixture/docs/verification/latest.md" '- unit: TIMEOUT'

new_fixture
mkdir -p "$fixture/bin"
cat > "$fixture/bin/pytest" <<'EOF'
#!/usr/bin/env bash
echo unit-control-failed
exit 1
EOF
cat > "$fixture/bin/ruff" <<'EOF'
#!/usr/bin/env bash
echo lint-control-failed
exit 1
EOF
chmod +x "$fixture/bin/pytest" "$fixture/bin/ruff"
set_acceptance '"./scripts/verify.sh", "pytest", "ruff"'
expect_failure "negative Kontroll-Fixture muss sicher scheitern" env PATH="$fixture/bin:/usr/bin:/bin" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id 20260904T120000Z-T017 --timeout 3 017
assert_file_has "Unit-Fehler wird berichtet" "$fixture/docs/verification/latest.md" '- unit: RED'
assert_file_has "spätere Lint-Stufe läuft trotz Unit-Fehler" "$fixture/docs/verification/latest.md" '- lint: RED'
assert_file_has "echter Prozessoutput liegt im Voll-Log" "$fixture/.agent-runs/20260904T120000Z-T017/verify/attempt-1.log" 'lint-control-failed'

new_fixture
printf '%s\n' bad > "$fixture/src/app.txt"
expect_failure "falscher Produktkandidat muss sicher scheitern" run_verify
assert_eq "Produktfehler bleibt als red im Task" red "$(ledger_scalar "$fixture/docs/tasks/017.md" last_verification)"
assert_file_has "Produktfehler wird getrennt klassifiziert" "$fixture/docs/verification/latest.md" 'failure_kind: product'

new_fixture
expect_success "Commit-Gate akzeptiert schnelle Prüfung plus gültiges Ledger" run_commit_gate
sed 's/status: in_progress/status: unbekannt/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.task.tmp"
mv "$fixture/docs/tasks/.task.tmp" "$fixture/docs/tasks/017.md"
expect_failure "Commit-Gate blockiert inkonsistentes Ledger" run_commit_gate

new_fixture
printf '%s\n' bad > "$fixture/src/app.txt"
expect_failure "Commit-Gate blockiert rote Schnellprüfung" run_commit_gate

if [ "$failed" -ne 0 ]; then
  echo "phase-06-tests: RED ($failed fehlgeschlagen, $passed bestanden)" >&2
  exit 1
fi
echo "phase-06-tests: GREEN ($passed bestanden)"
