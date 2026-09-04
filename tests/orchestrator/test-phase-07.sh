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
expect_success() { name=$1; shift; if command_output=$("$@" 2>&1); then ok; else echo "$command_output" >&2; bad "$name"; fi; }
expect_failure() { name=$1; shift; if command_output=$("$@" 2>&1); then echo "$command_output" >&2; bad "$name"; else ok; fi; }
assert_eq() { name=$1; expected=$2; actual=$3; [ "$expected" = "$actual" ] && ok || bad "$name (erwartet '$expected', erhalten '$actual')"; }
assert_file_has() { name=$1; file=$2; wanted=$3; grep -Fq -- "$wanted" "$file" && ok || bad "$name"; }

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase07.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture=''

new_fixture() {
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || exit 1
  mkdir -p "$fixture/.agent" "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" \
    "$fixture/docs/verification/history" "$fixture/docs/templates" "$fixture/scripts/agent" "$fixture/src"
  : > "$fixture/docs/state/notes-archive/.gitkeep"
  : > "$fixture/docs/verification/history/.gitkeep"
  cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
  cp -R "$project_dir/docs/templates/agents" "$fixture/docs/templates/agents"
  for file in goal.md plan.md decisions.md handoff.md metrics.csv; do cp "$project_dir/docs/state/$file" "$fixture/docs/state/$file"; done
  cat > "$fixture/docs/state/notes.md" <<'EOF'
# Notizen

## N-0001 — Historische Hypothese
- tasks: [017]
- date: 2026-09-04
- source: test
- confidence: hypothesis
- status: active
- evidence: `secret-history`
- finding: HISTORICAL_SECRET_MUST_NOT_REACH_FRESH
EOF
  cat > "$fixture/docs/state/current-run.md" <<'EOF'
---
run_id: none
task_id: none
mode: auto
phase: finished
iteration: 0
attempt: 0
last_progress_fingerprint: none
started_at: never
route_rule_version: "1"
route_reason_code: none
route_human_gate: false
route_signals: []
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
title: "Zwei Kandidaten vergleichen"
depends_on: []
features: [F-017]
status: todo
class: open
orchestration: managed-fresh
fresh_perspective: required
touches: [src/app.txt]
risk_flags: [high-risk-domain]
attempts: 0
max_attempts: 3
last_verification: never
human_review: false
acceptance: ["./scripts/verify.sh"]
blocked_reason: ""
---
# Kontext
Ein isolierter Kandidatenvergleich.
# Umfang
- `src/app.txt` bearbeiten.
# Nicht Teil dieser Aufgabe
- Steuerungsdateien ändern.
# Akzeptanzkriterien (über die acceptance-Befehle hinaus)
- Erlaubt sind `good`, `alpha` oder `beta`.
EOF
  printf '%s\n' initial > "$fixture/src/app.txt"
  cat > "$fixture/scripts/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(sed -n '1p' "$root/src/app.txt")" in good|alpha|beta) echo 'verify: GREEN'; exit 0 ;; esac
echo 'verify: RED' >&2
exit 1
EOF
  chmod +x "$fixture/scripts/verify.sh"
  for file in common.sh config.sh context.sh ledger.sh output.sh policy.sh runner.sh status.sh candidates.sh; do cp "$project_dir/scripts/agent/$file" "$fixture/scripts/agent/$file"; done
  for file in validate-ledger.sh verify-task.sh; do cp "$project_dir/scripts/$file" "$fixture/scripts/$file"; done
  chmod +x "$fixture/scripts/"*.sh "$fixture/scripts/agent/"*.sh
  printf '%s\n' '.agent-runs/' > "$fixture/.gitignore"
  git -C "$fixture" init -q
  git -C "$fixture" add .
  git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid commit -qm base
  mkdir -p "$fixture/.agent-runs/fake/responses" "$fixture/.agent-runs/fake/actions"
  ORCHESTRATOR_FAKE_STATE_DIR="$fixture/.agent-runs/fake"
  export ORCHESTRATOR_FAKE_STATE_DIR
}

worker_response() {
  role=$1
  number=${2:-1}
  cat > "$fixture/.agent-runs/fake/responses/$role-$number.out" <<'EOF'
RESULT=implemented
CHANGED_PATHS=src/app.txt
TESTS_RUN=./scripts/verify.sh
NOTES_ADDED=-
EOF
}

reviewer_response() {
  choice=$1
  cat > "$fixture/.agent-runs/fake/responses/reviewer-1.out" <<EOF
RECOMMENDATION=$choice
REASON_CODE=BOTH_GREEN_SIMPLER_CHANGE
REPORTS=candidate-a,candidate-b
EOF
}

finalizer_response() {
  cat > "$fixture/.agent-runs/fake/responses/finalizer-1.out" <<'EOF'
OUTCOME=blocked
BEST_GREEN_REF=-
OPEN_ERROR=Kein sicher übernehmbarer Kandidat
HUMAN_DECISION=Kandidaten prüfen
EOF
}

latest_run_file() {
  find "$fixture/.agent-runs" -path '*/candidates/decision.env' -print | LC_ALL=C sort | tail -n 1
}

new_fixture
direct_run="$fixture/.agent-runs/direct"
mkdir -p "$direct_run"
expect_success "Kandidaten starten isoliert vom gleichen Commit" "$fixture/scripts/agent/candidates.sh" init --project-dir "$fixture" --run-dir "$direct_run"
assert_eq "Fresh-Worktree enthält keine historische Note" '# Notizen' "$(sed -n '1p' "$direct_run/candidates/candidate-b/worktree/docs/state/notes.md")"
[ "$(wc -l < "$direct_run/candidates/candidate-b/worktree/docs/state/notes.md" | tr -d ' ')" = 1 ] && ok || bad "Fresh-Notes sind nicht vollständig bereinigt"
fresh_context=$("$fixture/scripts/agent/context.sh" build --project-dir "$direct_run/candidates/candidate-b/worktree" --role worker-fresh --run-id 20260904T120000Z-T017 --task-id 017 --include src/app.txt)
if grep -Fq HISTORICAL_SECRET_MUST_NOT_REACH_FRESH "$fresh_context"; then bad "Fresh-Kontext enthält historische Note"; else ok; fi
printf '%s\n' good > "$direct_run/candidates/candidate-a/worktree/src/app.txt"
expect_success "Kandidatenpatch wird lokal erfasst" "$fixture/scripts/agent/candidates.sh" capture --project-dir "$fixture" --run-dir "$direct_run" --candidate candidate-a --task-id 017
assert_eq "Kandidat verändert Hauptstand vor Review nicht" initial "$(sed -n '1p' "$fixture/src/app.txt")"
expect_success "Unveränderter Hauptstand besteht den Fingerprint-Vergleich" "$fixture/scripts/agent/candidates.sh" check-main --project-dir "$fixture" --run-dir "$direct_run"
expect_success "Temporäre Worktrees sind kontrolliert entfernbar" "$fixture/scripts/agent/candidates.sh" cleanup --project-dir "$fixture" --run-dir "$direct_run"

new_fixture
worker_response worker-task; worker_response worker-fresh
printf '%s\n' write-bad > "$fixture/.agent-runs/fake/actions/worker-task-1"
printf '%s\n' require-no-git-write-good > "$fixture/.agent-runs/fake/actions/worker-fresh-1"
expect_success "Nur der grüne Fresh-Kandidat wird übernommen" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Grüner Kandidat verdrängt roten" good "$(sed -n '1p' "$fixture/src/app.txt")"
assert_eq "Erneute Hauptprüfung führt offene Aufgabe ins Review" review "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
decision=$(latest_run_file)
assert_file_has "Entscheidung protokolliert Fresh-Gewinner" "$decision" 'selected=candidate-b'
assert_file_has "Übernahme verlangt Reverify" "$decision" 'requires_reverify=true'
[ ! -f "$fixture/.agent-runs/fake/reviewer.count" ] && ok || bad "Ein eindeutiger grüner Kandidat startete unnötig den Reviewer"

new_fixture
worker_response worker-task 2; worker_response worker-fresh
printf '%s\n' timeout > "$fixture/.agent-runs/fake/actions/worker-task-1"
printf '%s\n' write-good > "$fixture/.agent-runs/fake/actions/worker-task-2"
printf '%s\n' write-bad > "$fixture/.agent-runs/fake/actions/worker-fresh-1"
expect_success "Providerfehler erhält genau begrenzten Infrastruktur-Retry" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Infrastruktur-Retry startet zweiten Normal-Worker-Aufruf" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "Infrastruktur-Retry verbraucht keinen Task-Fehlversuch" 0 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"

new_fixture
worker_response worker-task; worker_response worker-fresh; reviewer_response candidate-b
printf '%s\n' write-alpha > "$fixture/.agent-runs/fake/actions/worker-task-1"
printf '%s\n' write-beta > "$fixture/.agent-runs/fake/actions/worker-fresh-1"
expect_success "Zwei grüne Kandidaten werden durch Reviewer entschieden" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Reviewer-Auswahl wird übernommen" beta "$(sed -n '1p' "$fixture/src/app.txt")"
assert_eq "Reviewer läuft genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/reviewer.count")"

new_fixture
worker_response worker-task; worker_response worker-fresh; finalizer_response
printf '%s\n' write-bad > "$fixture/.agent-runs/fake/actions/worker-task-1"
printf '%s\n' write-bad > "$fixture/.agent-runs/fake/actions/worker-fresh-1"
printf '%s\n' write-good > "$fixture/.agent-runs/fake/actions/finalizer-1"
expect_failure "Zwei rote Kandidaten erzwingen neither und Finalizer" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Beide rot blockiert statt Auswahl" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Finalizer kann Produktcode nicht verändern" initial "$(sed -n '1p' "$fixture/src/app.txt")"
decision=$(latest_run_file)
assert_file_has "Neither wird dokumentiert" "$decision" 'selected=neither'
expect_success "Ledger bleibt nach Both-red gültig" "$project_dir/scripts/validate-ledger.sh" --project-dir "$fixture"

new_fixture
worker_response worker-task; finalizer_response
printf '%s\n' empty > "$fixture/.agent-runs/fake/actions/worker-task-1"
expect_failure "Leere Kandidatenausgabe stoppt vor Übernahme" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Leere Ausgabe verändert Produkt nicht" initial "$(sed -n '1p' "$fixture/src/app.txt")"
assert_eq "Leere Ausgabe erzeugt nie done" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
expect_success "Ledger bleibt nach leerer Ausgabe gültig" "$project_dir/scripts/validate-ledger.sh" --project-dir "$fixture"

new_fixture
worker_response worker-task; worker_response worker-fresh; reviewer_response candidate-b; finalizer_response
printf '%s\n' write-good > "$fixture/.agent-runs/fake/actions/worker-task-1"
printf '%s\n' write-good-external > "$fixture/.agent-runs/fake/actions/worker-fresh-1"
expect_failure "Externe Hauptänderung pausiert sichere Übernahme" env ORCHESTRATOR_RUNNER="$runner" ORCHESTRATOR_PROJECT_DIR="$fixture" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Externe Änderung lässt Task offen" in_progress "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Externe Änderung pausiert Lauf" paused "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"
assert_eq "Externe Änderung wird nicht überschrieben" external "$(sed -n '1p' "$fixture/src/app.txt")"
expect_success "Ledger bleibt nach externer Änderung gültig" "$project_dir/scripts/validate-ledger.sh" --project-dir "$fixture"

if [ "$failed" -ne 0 ]; then
  echo "phase-07-tests: RED ($failed fehlgeschlagen, $passed bestanden)" >&2
  exit 1
fi
echo "phase-07-tests: GREEN ($passed bestanden)"
