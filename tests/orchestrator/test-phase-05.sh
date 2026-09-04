#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$script_dir/fake-runner.sh"
. "$project_dir/scripts/agent/ledger.sh"

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
expect_success() { name=$1; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$name"; fi; }
expect_failure() { name=$1; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok; fi; }
assert_eq() { name=$1; expected=$2; actual=$3; [ "$expected" = "$actual" ] && ok || bad "$name (erwartet '$expected', erhalten '$actual')"; }
assert_file_has() { name=$1; file=$2; wanted=$3; grep -Fq "$wanted" "$file" && ok || bad "$name"; }

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase05.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture=''

new_fixture() {
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || exit 1
  mkdir -p "$fixture/.agent" "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" "$fixture/docs/verification/history" "$fixture/docs/templates" "$fixture/src" "$fixture/.agent-runs/fake/responses" "$fixture/.agent-runs/fake/actions" "$fixture/scripts"
  cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
  cp -R "$project_dir/docs/templates/agents" "$fixture/docs/templates/agents"
  cp "$project_dir/docs/state/goal.md" "$fixture/docs/state/goal.md"
  cp "$project_dir/docs/state/plan.md" "$fixture/docs/state/plan.md"
  cp "$project_dir/docs/state/decisions.md" "$fixture/docs/state/decisions.md"
  cp "$project_dir/docs/state/current-run.md" "$fixture/docs/state/current-run.md"
  cp "$project_dir/docs/state/metrics.csv" "$fixture/docs/state/metrics.csv"
  cp "$project_dir/docs/verification/latest.md" "$fixture/docs/verification/latest.md"
  cat > "$fixture/docs/state/notes.md" <<'EOF'
# Notizen
EOF
  cat > "$fixture/docs/tasks/017.md" <<'EOF'
---
id: 017
title: "App-Datei implementieren"
depends_on: []
features: [F-017]
status: todo
class: mechanical
orchestration: auto
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
Eine kleine Testdatei.
# Umfang
- `src/app.txt` bearbeiten.
# Nicht Teil dieser Aufgabe
- Steuerungsdateien ändern.
# Akzeptanzkriterien (über die acceptance-Befehle hinaus)
- Die Datei enthält exakt `good`.
EOF
  printf '%s\n' initial > "$fixture/src/app.txt"
  cat > "$fixture/scripts/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(sed -n '1p' "$root/src/app.txt")" = good ]; then echo 'verify: GREEN'; exit 0; fi
echo 'verify: RED' >&2
exit 1
EOF
  chmod +x "$fixture/scripts/verify.sh"
}

worker_response() {
  number=$1
  cat > "$fixture/.agent-runs/fake/responses/worker-task-$number.out" <<'EOF'
RESULT=implemented
CHANGED_PATHS=src/app.txt
TESTS_RUN=-
NOTES_ADDED=-
EOF
}

manager_response() {
  number=$1
  cat > "$fixture/.agent-runs/fake/responses/manager-manage-$number.out" <<'EOF'
---
action: dispatch
task_id: 017
worker_kind: normal
reason_code: NEXT_HIGHEST_VALUE
---
EOF
}

brainstorm_response() {
  cat > "$fixture/.agent-runs/fake/responses/worker-brainstorm-1.out" <<'EOF'
NOTES_ADDED=-
RISKS=-
TEST_IDEAS=verify.sh
EOF
}

finalizer_response() {
  cat > "$fixture/.agent-runs/fake/responses/finalizer-1.out" <<'EOF'
OUTCOME=blocked
BEST_GREEN_REF=-
OPEN_ERROR=Unveränderter Kandidat
HUMAN_DECISION=Prüfung erforderlich
EOF
}

expect_success "Runner veröffentlicht Fünf-Argument-Vertrag" sh -c "'$project_dir/scripts/agent/runner.sh' --contract | grep -q metadata-output"
valid_metadata="$tmp_root/valid-metadata"
printf '%s\n' 'model=fake' 'started_at=x' 'finished_at=y' 'exit_status=0' 'tokens_total=0' 'abort_reason=none' 'output_status=ok' > "$valid_metadata"
expect_success "Runner akzeptiert vollständige Metadaten" "$project_dir/scripts/agent/runner.sh" validate_metadata "$valid_metadata"
printf '%s\n' 'model=fake' > "$tmp_root/bad-metadata"
expect_failure "Runner lehnt unvollständige Metadaten ab" "$project_dir/scripts/agent/runner.sh" validate_metadata "$tmp_root/bad-metadata"

new_fixture
before=$(find "$fixture" -type f ! -path '*/.agent-runs/*' -exec shasum -a 256 {} \; | shasum -a 256 | awk '{print $1}')
dry_output=$(ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 --dry-run)
after=$(find "$fixture" -type f ! -path '*/.agent-runs/*' -exec shasum -a 256 {} \; | shasum -a 256 | awk '{print $1}')
assert_eq "Dry Run verändert keine produktive oder versionierte Datei" "$before" "$after"
case "$dry_output" in *'MODE=single'*'PLANNED_CALLS=worker-task,verify'*) ok ;; *) bad "Dry Run zeigt Route und Aufrufe" ;; esac

new_fixture
worker_response 1
echo write-good > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_success "Single-Modus schließt grünen Task ab" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Single setzt Status done" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Single setzt Lauf finished" finished "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"
assert_eq "Single startet genau einen Worker" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_file_has "Single erzeugt grünen Prüfbericht" "$fixture/docs/verification/latest.md" 'result: green'

new_fixture
worker_response 1
echo write-bad > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_failure "Worker-Behauptung überstimmt rote Prüfung nicht" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Roter Single-Task bleibt todo" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Rote Prüfung wird im Task protokolliert" red "$(ledger_scalar "$fixture/docs/tasks/017.md" last_verification)"

new_fixture
printf '%s\n' 'RESULT=implemented' > "$fixture/.agent-runs/fake/responses/worker-task-1.out"
expect_failure "Ungültiger Rollenoutput stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Ungültiger Output lässt Task in_progress" in_progress "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Ungültiger Output markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"
expect_success "Ledger bleibt nach ungültigem Output gültig" "$project_dir/scripts/validate-ledger.sh" --project-dir "$fixture"

new_fixture
sed 's/class: mechanical/class: patterned/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.tmp" && mv "$fixture/docs/tasks/.tmp" "$fixture/docs/tasks/017.md"
worker_response 1; worker_response 2
echo write-bad > "$fixture/.agent-runs/fake/actions/worker-task-1"
echo write-good > "$fixture/.agent-runs/fake/actions/worker-task-2"
expect_success "Verified-Modus repariert genau einmal" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Verified schließt reparierten Task ab" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Verified zählt bestätigten Fehlschlag" 1 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"
assert_eq "Verified startet zwei Worker" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_file_has "Verified übernimmt Fehler kompakt in Notes" "$fixture/docs/state/notes.md" 'Verifikation rot'

new_fixture
sed 's/class: mechanical/class: open/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.tmp" && mv "$fixture/docs/tasks/.tmp" "$fixture/docs/tasks/017.md"
brainstorm_response; manager_response 1; worker_response 1
echo write-good > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_success "Managed-Modus führt Manager-Worker-Runde aus" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Managed startet einen Worker pro Runde" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "Managed ruft Brainstorm genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-brainstorm.count")"
assert_eq "Managed schließt grünen Task ab" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

new_fixture
sed 's/class: mechanical/class: open/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.tmp" && mv "$fixture/docs/tasks/.tmp" "$fixture/docs/tasks/017.md"
brainstorm_response
printf '%s\n' 'not yaml' > "$fixture/.agent-runs/fake/responses/manager-manage-1.out"
expect_failure "Ungültige Managerentscheidung stoppt vor Worker" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
[ ! -f "$fixture/.agent-runs/fake/worker-task.count" ] && ok || bad "Ungültiger Manager startet keinen Worker"
assert_eq "Ungültiger Manager lässt Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_fixture
worker_response 1
echo forbidden > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_failure "Worker darf Steuerungspfad nicht ändern" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Pfadverletzung markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_fixture
worker_response 1
echo timeout > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_failure "Timeout stoppt kontrolliert" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Timeout markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_fixture
worker_response 1
echo truncated > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_failure "Abgeschnittene Antwort wird nicht ausgewertet" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Abgeschnittene Antwort markiert Lauf failed" failed "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"

new_fixture
sed 's/max_attempts: 3/max_attempts: 9/; s/attempts: 0/attempts: 3/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.tmp" && mv "$fixture/docs/tasks/.tmp" "$fixture/docs/tasks/017.md"
expect_failure "Globales Versuchslimit bleibt trotz höherem Taskwert hart" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Versuchslimit startet keinen Worker" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

new_fixture
printf '%s\n' 'RESULT=implemented' > "$fixture/.agent-runs/fake/responses/worker-task-1.out"
expect_failure "Ungültiger Output bereitet Resume-Test vor" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
worker_response 2
echo write-good > "$fixture/.agent-runs/fake/actions/worker-task-2"
expect_success "Resume setzt Lauf ohne Artefaktüberschreiben fort" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --resume
assert_eq "Resume schließt Task ab" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

new_fixture
printf '%s\n' 'RESULT=implemented' > "$fixture/.agent-runs/fake/responses/worker-task-1.out"
expect_failure "Fehlerlauf für Fremdänderung wird erzeugt" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
printf '%s\n' fremd > "$fixture/src/app.txt"
expect_failure "Resume weist fremde Dateiänderung ab" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --resume

new_fixture
mkdir "$fixture/.agent-runs/.orchestrator-lock"
expect_failure "Atomare Sperre verhindert zweiten Orchestrator" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Sperrkonflikt verändert Task nicht" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

new_fixture
sed 's/class: mechanical/class: open/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/.tmp" && mv "$fixture/docs/tasks/.tmp" "$fixture/docs/tasks/017.md"
brainstorm_response; manager_response 1; manager_response 2; worker_response 1; worker_response 2; finalizer_response
echo write-bad > "$fixture/.agent-runs/fake/actions/worker-task-1"
echo write-bad > "$fixture/.agent-runs/fake/actions/worker-task-2"
expect_failure "No-Progress-Guard beendet identische Runden" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "No-Progress startet höchstens zwei identische Worker" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "No-Progress blockiert Task sicher" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "No-Progress ruft Finalizer auf" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/finalizer.count")"

if [ "$failed" -ne 0 ]; then
  echo "phase-05-tests: RED ($failed fehlgeschlagen, $passed bestanden)" >&2
  exit 1
fi
echo "phase-05-tests: GREEN ($passed bestanden)"
