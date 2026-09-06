#!/usr/bin/env bash
# Ein Lauf erzeugt genau eine Metrikzeile, übernimmt nur gelieferte Verbrauchs-
# werte und lässt sich ohne Doppelzeile erneut finalisieren.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

metrics_tool="$project_dir/scripts/agent/metrics.sh"

begin_suite metrics
fixture_workspace

new_project_fixture --filled-plan
make_task --id 017 --title 'Offene Pilotaufgabe' --features F-017 --class open --touches src/app.txt \
  --context 'Eine kontrollierte Testaufgabe.' --scope '`src/app.txt` bearbeiten.' \
  --not-scope 'Steuerungsdateien ändern.' --criteria 'Die Datei enthält `good`.'

expected_header='run_id,task_id,class,mode,model,prompt_version,manager_calls,worker_calls,verifier_runs,rounds,attempts,tokens_in,tokens_out,cost_estimate,duration_seconds,verification,human_review,outcome,date'
assert_eq "CSV ist auf das Phase-08-Schema migriert" "$expected_header" "$(sed -n '1p' "$fixture/docs/state/metrics.csv")"

base_a=$(printf 'a%.0s' {1..64})

mkdir -p "$fixture/.agent-runs/20260904T100000Z-T017"
"$metrics_tool" start "$fixture" "$fixture/.agent-runs/20260904T100000Z-T017" 20260904T100000Z-T017 017 verified 2026-09-04T10:00:00Z 1 "$base_a" >/dev/null
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

mkdir -p "$fixture/.agent-runs/20260904T100100Z-T017"
"$metrics_tool" start "$fixture" "$fixture/.agent-runs/20260904T100100Z-T017" 20260904T100100Z-T017 017 managed 2026-09-04T10:00:00Z 1 "$base_a" >/dev/null
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

finish_suite
