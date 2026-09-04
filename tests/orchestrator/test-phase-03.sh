#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
router="$project_dir/scripts/route-task.sh"
validator="$project_dir/scripts/validate-ledger.sh"
status_gate="$project_dir/scripts/agent/status.sh"
. "$project_dir/scripts/agent/ledger.sh"

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
expect_success() { name=$1; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$name"; fi; }
expect_failure() { name=$1; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok; fi; }
expect_output() {
  name=$1; expected=$2; shift 2
  actual=$("$@" 2>/dev/null) || { bad "$name"; return; }
  [ "$actual" = "$expected" ] && ok || { bad "$name"; echo "  erwartet: $expected" >&2; echo "  erhalten: $actual" >&2; }
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase03.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture=''

new_fixture() {
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || exit 1
  mkdir -p "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" "$fixture/docs/verification/history" "$fixture/.agent"
  cp "$project_dir/docs/state/goal.md" "$fixture/docs/state/goal.md"
  cp "$project_dir/docs/state/plan.md" "$fixture/docs/state/plan.md"
  cp "$project_dir/docs/state/notes.md" "$fixture/docs/state/notes.md"
  cp "$project_dir/docs/state/current-run.md" "$fixture/docs/state/current-run.md"
  cp "$project_dir/docs/state/metrics.csv" "$fixture/docs/state/metrics.csv"
  cp "$project_dir/docs/verification/latest.md" "$fixture/docs/verification/latest.md"
  cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
}

make_task() {
  id=$1; class=$2; orchestration=${3:-auto}; human=${4:-false}; fresh=${5:-auto}; touches=${6:-}; flags=${7:-}; attempts=${8:-0}; max_attempts=${9:-3}; status=${10:-todo}; scope=${11:-Lokale Änderung.}
  file="$fixture/docs/tasks/$id.md"
  {
    echo '---'
    echo "id: $id"
    echo "title: \"Task $id\""
    echo 'depends_on: []'
    echo 'features: [F-001]'
    echo "status: $status"
    echo "class: $class"
    echo "orchestration: $orchestration"
    echo "fresh_perspective: $fresh"
    echo "touches: [$touches]"
    echo "risk_flags: [$flags]"
    echo "attempts: $attempts"
    echo "max_attempts: $max_attempts"
    echo 'last_verification: never'
    echo "human_review: $human"
    echo 'acceptance: ["./scripts/verify.sh"]'
    echo 'blocked_reason: ""'
    echo '---'
    echo '# Kontext'
    echo 'Routingtest.'
    echo '# Umfang'
    echo "- $scope"
    echo '# Nicht Teil dieser Aufgabe'
    echo '- Andere Bereiche.'
    echo '# Akzeptanzkriterien (über die acceptance-Befehle hinaus)'
    echo '- Entscheidung ist deterministisch.'
  } > "$file"
}

make_active_run() {
  id=$1
  {
    echo '---'
    echo "run_id: 20260904T091500Z-T$id"
    echo "task_id: $id"
    echo 'mode: managed'
    echo 'phase: work'
    echo 'iteration: 1'
    echo 'attempt: 1'
    echo 'last_progress_fingerprint: none'
    echo 'started_at: 2026-09-04T09:15:00Z'
    echo 'route_rule_version: "1"'
    echo 'route_reason_code: none'
    echo 'route_human_gate: false'
    echo 'route_signals: []'
    echo '---'
  } > "$fixture/docs/state/current-run.md"
}

make_green_report() {
  id=$1
  candidate_fingerprint=$(ledger_candidate_fingerprint "$fixture" "$fixture/docs/tasks/$id.md")
  verifier_version=$(ledger_verifier_fingerprint "$fixture")
  {
    echo '---'
    echo 'run_id: test-run'
    echo "task_id: $id"
    echo 'result: green'
    echo 'attempt: 1'
    echo 'finished_at: 2026-09-04T09:15:00Z'
    echo "candidate_fingerprint: $candidate_fingerprint"
    echo "verifier_version: $verifier_version"
    echo '---'
    echo '# Letzte Prüfung'
    echo '## Ergebnis'
    echo 'green'
    echo '## Prüfungen'
    echo '- Test.'
  } > "$fixture/docs/verification/latest.md"
}

mechanical='MODE=single
REASON_CODE=MECHANICAL_LOCAL
HUMAN_GATE=false'
patterned='MODE=verified
REASON_CODE=PATTERNED_LOCAL
HUMAN_GATE=false'
open='MODE=managed
REASON_CODE=OPEN_DECISION
HUMAN_GATE=true'

new_fixture
make_task 001 mechanical
expect_output "mechanical wird single" "$mechanical" "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 patterned
expect_output "patterned wird verified" "$patterned" "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 open
expect_output "open wird managed mit Human Gate" "$open" "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 open
expect_output "Einmallauf kann open nicht auf single senken" "$open" "$router" --project-dir "$fixture" --mode single 001

new_fixture
make_task 001 patterned single
expect_output "Task-Vorgabe darf patterned herabstufen" 'MODE=single
REASON_CODE=EXPLICIT_OVERRIDE
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 patterned
expect_output "Einmallauf-Vorgabe wird respektiert" 'MODE=single
REASON_CODE=EXPLICIT_OVERRIDE
HUMAN_GATE=false' "$router" --project-dir "$fixture" --mode single 001

new_fixture
make_task 001 mechanical single false auto '' high-risk-domain
expect_output "explizites single umgeht Hochrisiko nicht" 'MODE=managed
REASON_CODE=HIGH_RISK_DOMAIN
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto false auto 'frontend, api'
expect_output "mehrere Komponenten werden managed" 'MODE=managed
REASON_CODE=CROSS_COMPONENT
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto false auto 'frontend'
expect_output "ein lokaler Bereich bleibt single" "$mechanical" "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 patterned auto false auto '' '' 0 3 todo 'Authentifizierung und Berechtigungen ändern.'
expect_output "Auth-Umfang wird mindestens managed" 'MODE=managed
REASON_CODE=HIGH_RISK_DOMAIN
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto false required
expect_output "Fresh-Vorgabe wird managed-fresh" 'MODE=managed-fresh
REASON_CODE=FRESH_REQUIRED
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 patterned auto false auto '' repeated-failure
expect_output "wiederholter Fehler wird managed-fresh" 'MODE=managed-fresh
REASON_CODE=REPEATED_FAILURE
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 patterned auto false auto '' conflicting-ledger
expect_output "widerspruechliches Ledger wird managed-fresh" 'MODE=managed-fresh
REASON_CODE=CONFLICTING_LEDGER
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto false auto '' '' 2
expect_output "mehrere Fehlversuche werden managed" 'MODE=managed
REASON_CODE=FAILED_ATTEMPTS
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto false auto '' '' 3 3
expect_output "ausgeschoepftes Versuchslimit blockiert" 'MODE=blocked
REASON_CODE=ATTEMPT_LIMIT
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto true
expect_output "Human Review bleibt als Gate sichtbar" 'MODE=single
REASON_CODE=MECHANICAL_LOCAL
HUMAN_GATE=true' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical auto true auto '' '' 0 3 review
sed 's/last_verification: never/last_verification: green/' "$fixture/docs/tasks/001.md" > "$fixture/docs/tasks/001.tmp"
mv "$fixture/docs/tasks/001.tmp" "$fixture/docs/tasks/001.md"
make_green_report 001
expect_failure "Review kann nicht automatisch auf done" "$status_gate" --project-dir "$fixture" set-status 001 done review
expect_success "ausdrueckliche menschliche Freigabe erlaubt done" "$status_gate" --project-dir "$fixture" --human-approved set-status 001 done review

new_fixture
make_task 001 mechanical
first=$($router --project-dir "$fixture" 001)
second=$($router --project-dir "$fixture" 001)
[ "$first" = "$second" ] && ok || bad "identische Eingaben liefern identische Entscheidung"
[ "$(printf '%s\n' "$first" | wc -l | tr -d ' ')" = 3 ] && ok || bad "Router-Ausgabe hat exakt drei Zeilen"

new_fixture
make_task 001 mechanical
sed 's/ROUTER_ENABLED=true/ROUTER_ENABLED=false/' "$fixture/.agent/config.env" > "$fixture/.agent/config.tmp"
mv "$fixture/.agent/config.tmp" "$fixture/.agent/config.env"
expect_output "Router kann deaktiviert werden" 'MODE=verified
REASON_CODE=ROUTER_DISABLED
HUMAN_GATE=false' "$router" --project-dir "$fixture" 001

new_fixture
make_task 001 mechanical
expect_failure "unbekannter manueller Modus" "$router" --project-dir "$fixture" --mode turbo 001

new_fixture
make_task 001 mechanical auto false auto '' unknown-risk
expect_failure "unbekanntes Risikosignal" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 mechanical auto false auto '' '' 0 3 in_progress
make_active_run 001
expect_output "Fehler eskaliert genau eine Stufe" 'MODE=verified
REASON_CODE=ESCALATED_AFTER_FAILURE
HUMAN_GATE=false' "$router" --project-dir "$fixture" --escalate-from single --expected-attempts 0 001
grep -Fqx 'attempts: 1' "$fixture/docs/tasks/001.md" && ok || bad "Eskalation zaehlt genau einen Versuch"
expect_failure "veraltete Eskalation wird abgewiesen" "$router" --project-dir "$fixture" --escalate-from single --expected-attempts 0 001
grep -Fqx 'attempts: 1' "$fixture/docs/tasks/001.md" && ok || bad "veraltete Eskalation zaehlt nicht erneut"

new_fixture
make_task 001 patterned auto false auto '' '' 2 3 in_progress
make_active_run 001
expect_output "Versuchslimit endet blocked" 'MODE=blocked
REASON_CODE=ATTEMPT_LIMIT
HUMAN_GATE=false' "$router" --project-dir "$fixture" --escalate-from managed-fresh --expected-attempts 2 001

new_fixture
make_task 001 patterned auto false auto '' '' 0 3 in_progress
make_active_run 001
expect_output "Routing kann atomar protokolliert werden" "$patterned" "$router" --project-dir "$fixture" --record 001
grep -Fqx 'mode: verified' "$fixture/docs/state/current-run.md" && grep -Fqx 'route_reason_code: PATTERNED_LOCAL' "$fixture/docs/state/current-run.md" && ok || bad "current-run enthaelt Routingentscheidung"
[ "$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')" = 1 ] && grep -Fqx 'recommended_mode=verified' "$fixture/.agent-runs/20260904T091500Z-T001/metadata/route.env" && ok || bad "Routing bleibt lokal und erzeugt keine vorzeitige Laufzeile"
expect_success "protokollierter Lauf bleibt gueltig" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 patterned auto false auto '' '' 0 3 in_progress
make_active_run 001
sed 's/route_reason_code: none/route_reason_code: UNKNOWN_REASON/' "$fixture/docs/state/current-run.md" > "$fixture/docs/state/current-run.tmp"
mv "$fixture/docs/state/current-run.tmp" "$fixture/docs/state/current-run.md"
expect_failure "unbekannter Reason-Code wird abgewiesen" "$validator" --project-dir "$fixture"

if [ "$failed" -ne 0 ]; then
  echo "phase-03-tests: RED ($passed bestanden, $failed fehlgeschlagen)"
  exit 1
fi
echo "phase-03-tests: GREEN ($passed bestanden)"
