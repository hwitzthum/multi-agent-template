#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
metrics_tool="$project_dir/scripts/agent/metrics.sh"
metrics_report="$project_dir/scripts/agent-metrics.sh"
router="$project_dir/scripts/route-task.sh"
orchestrator="$project_dir/scripts/orchestrate.sh"
runner="$script_dir/fake-runner.sh"

passed=0 failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
expect_success() { name=$1; shift; if command_output=$("$@" 2>&1); then ok; else echo "$command_output" >&2; bad "$name"; fi; }
expect_failure() { name=$1; shift; if command_output=$("$@" 2>&1); then echo "$command_output" >&2; bad "$name"; else ok; fi; }
assert_eq() { name=$1 expected=$2 actual=$3; [ "$expected" = "$actual" ] && ok || bad "$name (erwartet '$expected', erhalten '$actual')"; }
assert_has() { name=$1 file=$2 value=$3; grep -Fq -- "$value" "$file" && ok || bad "$name"; }

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase08.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture="$tmp_root/project"
mkdir -p "$fixture/.agent" "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" \
  "$fixture/docs/verification/history" "$fixture/docs/templates" "$fixture/src" \
  "$fixture/.agent-runs/fake/responses" "$fixture/.agent-runs/fake/actions" "$fixture/scripts"
cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
cp -R "$project_dir/docs/templates/agents" "$fixture/docs/templates/agents"
for file in goal.md plan.md notes.md decisions.md handoff.md current-run.md metrics.csv; do cp "$project_dir/docs/state/$file" "$fixture/docs/state/$file"; done
cp "$project_dir/docs/verification/latest.md" "$fixture/docs/verification/latest.md"
: > "$fixture/docs/state/notes-archive/.gitkeep"
: > "$fixture/docs/verification/history/.gitkeep"
printf '%s\n' initial > "$fixture/src/app.txt"
cat > "$fixture/docs/tasks/017.md" <<'EOF'
---
id: 017
title: "Offene Pilotaufgabe"
depends_on: []
features: [F-017]
status: todo
class: open
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
Eine kontrollierte Testaufgabe.
# Umfang
- `src/app.txt` bearbeiten.
# Nicht Teil dieser Aufgabe
- Steuerungsdateien ändern.
# Akzeptanzkriterien (über die acceptance-Befehle hinaus)
- Die Datei enthält `good`.
EOF
cat > "$fixture/scripts/verify.sh" <<'EOF'
#!/usr/bin/env bash
[ "$(sed -n '1p' "$(dirname "$0")/../src/app.txt")" = good ]
EOF
chmod +x "$fixture/scripts/verify.sh"

expected_header='run_id,task_id,class,mode,model,prompt_version,manager_calls,worker_calls,verifier_runs,rounds,attempts,tokens_in,tokens_out,cost_estimate,duration_seconds,verification,human_review,outcome,date'
assert_eq "CSV ist auf das Phase-08-Schema migriert" "$expected_header" "$(sed -n '1p' "$fixture/docs/state/metrics.csv")"

route_output=$("$router" --project-dir "$fixture" 017)
case "$route_output" in *'MODE=managed'*'REASON_CODE=OPEN_DECISION'*) ok ;; *) bad "Router entscheidet fuer open direkt auf managed" ;; esac

before_lines=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
dry_output=$("$orchestrator" --project-dir "$fixture" --task 017 --dry-run)
after_lines=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
assert_eq "Dry-Run erzeugt keine Outcome-Zeile" "$before_lines" "$after_lines"
dry_metadata=${dry_output#*METADATA=}; dry_metadata=${dry_metadata%%$'\n'*}
assert_has "Dry-Run ist lokal ausdrücklich markiert" "$fixture/$dry_metadata" 'dry_run=true'
assert_has "Dry-Run besitzt kein erfundenes Outcome" "$fixture/$dry_metadata" 'outcome='

make_run() {
  run_id=$1 mode=$2 base=$3
  run_dir="$fixture/.agent-runs/$run_id"
  mkdir -p "$run_dir"
  "$metrics_tool" start "$fixture" "$run_dir" "$run_id" 017 "$mode" 2026-09-04T10:00:00Z 1 "$base"
}

base_a=$(printf 'a%.0s' {1..64})
base_b=$(printf 'b%.0s' {1..64})
make_run 20260904T100000Z-T017 verified "$base_a"
cat > "$fixture/docs/verification/latest.md" <<'EOF'
---
run_id: 20260904T100000Z-T017
task_id: 017
attempt: 1
result: green
failure_kind: none
---
EOF
cat > "$fixture/.agent-runs/20260904T100000Z-T017/metadata/01-worker-task.env" <<'EOF'
model=fake
started_at=2026-09-04T10:00:00Z
finished_at=2026-09-04T10:00:01Z
exit_status=0
tokens_total=unknown
tokens_in=
tokens_out=
cost_estimate=
abort_reason=none
output_status=ok
EOF
expect_success "Lauf ohne Tokenwerte wird finalisiert" "$metrics_tool" finalize "$fixture" "$fixture/.agent-runs/20260904T100000Z-T017" success
row=$(awk -F, '$1 == "20260904T100000Z-T017" {print; exit}' "$fixture/docs/state/metrics.csv")
assert_eq "Finalisierte Zeile hat 19 Felder" 19 "$(printf '%s\n' "$row" | awk -F, '{print NF}')"
assert_eq "Fehlende Token- und Kostenwerte bleiben leer" ',,' "$(printf '%s\n' "$row" | awk -F, '{print $12 "," $13 "," $14}')"
assert_eq "Outcome ist fachlich benannt" success "$(printf '%s\n' "$row" | awk -F, '{print $18}')"

lines_once=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
expect_success "Wiederholtes Finalisieren ist idempotent" "$metrics_tool" finalize "$fixture" "$fixture/.agent-runs/20260904T100000Z-T017" success
assert_eq "Wiederholtes Finalisieren erzeugt keine Doppelzeile" "$lines_once" "$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')"

conflict="$fixture/.agent-runs/conflict"
mkdir -p "$conflict/metadata"
cp "$fixture/.agent-runs/20260904T100000Z-T017/metadata/run.env" "$conflict/metadata/run.env"
sed 's/,verified,/,managed,/' "$fixture/.agent-runs/20260904T100000Z-T017/metadata/summary.csv" > "$conflict/metadata/summary.csv"
expect_failure "Gleiche Run-ID mit anderen Werten wird erkannt" "$metrics_tool" finalize "$fixture" "$conflict" success

make_run 20260904T100100Z-T017 managed "$base_a"
cat > "$fixture/docs/verification/latest.md" <<'EOF'
---
run_id: 20260904T100100Z-T017
task_id: 017
attempt: 1
result: green
failure_kind: none
---
EOF
cat > "$fixture/.agent-runs/20260904T100100Z-T017/metadata/01-manager-manage.env" <<'EOF'
model=fake
tokens_in=10
tokens_out=4
cost_estimate=0.125
EOF
expect_success "Vorhandene echte Verbrauchswerte werden übernommen" "$metrics_tool" finalize "$fixture" "$fixture/.agent-runs/20260904T100100Z-T017" success
row=$(awk -F, '$1 == "20260904T100100Z-T017" {print; exit}' "$fixture/docs/state/metrics.csv")
assert_eq "Tokens in werden nicht geschätzt" 10 "$(printf '%s\n' "$row" | awk -F, '{print $12}')"
assert_eq "Tokens out werden nicht geschätzt" 4 "$(printf '%s\n' "$row" | awk -F, '{print $13}')"
assert_eq "Kosten werden nur aus gelieferten Werten summiert" 0.125000 "$(printf '%s\n' "$row" | awk -F, '{print $14}')"

summary=$(CLAUDE_PROJECT_DIR="$fixture" "$project_dir/scripts/state-summary.sh")
assert_eq "Kurzsummary hält das Drei-Zeilen-Budget" 3 "$(printf '%s\n' "$summary" | wc -l | tr -d ' ')"
[ "$(printf '%s\n' "$summary" | wc -w | tr -d ' ')" -le 250 ] && ok || bad "Kurzsummary überschreitet 250 Tokens als konservatives Wortbudget"

sed 's/^id: 017$/id: 018/; s/^class: open$/class: mechanical/' "$fixture/docs/tasks/017.md" > "$fixture/docs/tasks/018.md"
printf '%s\n' 'RESULT=implemented' > "$fixture/.agent-runs/fake/responses/worker-task-1.out"
ORCHESTRATOR_FAKE_STATE_DIR="$fixture/.agent-runs/fake"; export ORCHESTRATOR_FAKE_STATE_DIR
expect_failure "Abgebrochener Lauf wird kontrolliert erfasst" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 018 --mode single
aborted_run=$(awk -F, 'NR > 1 && $18 == "blocked" {run=$1} END {print run}' "$fixture/docs/state/metrics.csv")
[ -n "$aborted_run" ] && [ "$(awk -F, -v run="$aborted_run" '$1 == run {count++} END {print count+0}' "$fixture/docs/state/metrics.csv")" -eq 1 ] && ok || bad "Abgebrochener Lauf besitzt genau ein Outcome"

expect_success "Metriktabelle lässt sich lokal erzeugen" "$metrics_report" summary --project-dir "$fixture"

if [ "$failed" -ne 0 ]; then
  echo "phase-08-tests: RED ($failed fehlgeschlagen, $passed bestanden)" >&2
  exit 1
fi
echo "phase-08-tests: GREEN ($passed bestanden)"
