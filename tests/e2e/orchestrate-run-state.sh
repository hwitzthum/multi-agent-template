#!/usr/bin/env bash
# Der Laufzustand ist unversioniert: ein Lauf schmutzt den Git-Stand nur mit
# fachlichen Belegen ein, hinterlaesst nie einen Task in `in_progress` und
# uebernimmt den Stand eines abgestuerzten Vorlaufs.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
status_gate="$project_dir/scripts/agent/status.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite orchestrate-run-state
fixture_workspace

# --- Ein gruener Lauf beruehrt ausser dem Produkt nur fachliche Belege -------
new_app_fixture
fixture_git_init
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-good
expect_success "Gruener Lauf schliesst den Task ab" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
unexpected=$(git -C "$fixture" status --porcelain \
  | awk '{ print $2 }' \
  | grep -Ev '^(src/app\.txt|docs/tasks/|docs/verification/|docs/state/handoff\.md$)' || true)
assert_eq "Gruener Lauf aendert nur Task, Pruefbericht und Handoff" '' "$unexpected"
[ ! -e "$fixture/docs/state/current-run.md" ] && ok || bad "Kein versionierter Laufzustand"
[ ! -e "$fixture/docs/state/metrics.csv" ] && ok || bad "Keine versionierte Metrik"
assert_file "Laufzustand liegt im Laufordner" "$(fixture_latest_run_dir)/run.env"
assert_file "Laufmetrik liegt unter .agent-runs" "$fixture/.agent-runs/metrics.csv"
assert_eq "Laufzustand haelt das Ergebnis fest" success "$(fixture_run_state outcome)"
assert_eq "Metrik enthaelt genau eine Laufzeile" 1 \
  "$(awk 'NR > 1 && NF { count++ } END { print count+0 }' "$fixture/.agent-runs/metrics.csv")"

summary=$(CLAUDE_PROJECT_DIR="$fixture" "$project_dir/scripts/state-summary.sh")
assert_eq "Kurzsummary haelt das Zwei-Zeilen-Budget" 2 "$(printf '%s\n' "$summary" | wc -l | tr -d ' ')"
case "$summary" in *'verify: GREEN'*) ok ;; *) bad "Kurzsummary nennt den Pruefstand" ;; esac

# --- Ein Dry Run hat keine Nebenwirkung -------------------------------------
new_app_fixture
fixture_git_init
before=$(find "$fixture" -type f ! -path '*/.git/*' -exec shasum -a 256 {} \; | LC_ALL=C sort | shasum -a 256)
dry_output=$(ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 --dry-run)
after=$(find "$fixture" -type f ! -path '*/.git/*' -exec shasum -a 256 {} \; | LC_ALL=C sort | shasum -a 256)
assert_eq "Dry Run schreibt keine einzige Datei" "$before" "$after"
[ ! -e "$fixture/.agent-runs/metrics.csv" ] && ok || bad "Dry Run erzeugt keine Laufzeile"
[ -z "$(fixture_latest_run_dir)" ] && ok || bad "Dry Run legt keinen Laufordner an"
case "$dry_output" in *'MODE=single'*) ok ;; *) bad "Dry Run zeigt die Route" ;; esac

# --- Ein abgebrochener Lauf laesst keinen Task in_progress zurueck ----------
new_app_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 hang
ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017 >/dev/null 2>&1 &
aborted=$!
tries=0
while [ "$(ledger_scalar "$fixture/docs/tasks/017.md" status 2>/dev/null || true)" != in_progress ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 100 ] || break
  sleep 0.1
done
assert_eq "Lauf setzt den Task zuerst auf in_progress" in_progress "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
kill -TERM "$aborted" 2>/dev/null
wait "$aborted" 2>/dev/null
assert_eq "Abbruch laesst keinen Task in_progress" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Abbruch wird als cancelled belegt" cancelled "$(fixture_run_state outcome)"
[ ! -d "$fixture/.agent-runs/.orchestrator-lock" ] && ok || bad "Abbruch gibt die Sperre frei"

# --- Ein abgestuerzter Vorlauf wird beim Start uebernommen ------------------
new_app_fixture
"$status_gate" --project-dir "$fixture" set-status 017 in_progress todo >/dev/null
mkdir -p "$fixture/.agent-runs/.orchestrator-lock"
sleep 0 & dead_pid=$!; wait "$dead_pid"
printf '%s\n' "$dead_pid" > "$fixture/.agent-runs/.orchestrator-lock/pid"
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=-' 'NOTES_ADDED=-'
fake_action worker-task 1 write-good
expect_success "Verwaiste Sperre und Stale-Task werden uebernommen" \
  env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Uebernommener Task laeuft bis done durch" done "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

# --- Ein zweiter Orchestrator wird abgewiesen -------------------------------
new_app_fixture
mkdir "$fixture/.agent-runs/.orchestrator-lock"
expect_failure "Lebende Sperre weist den zweiten Orchestrator ab" \
  env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Sperrkonflikt veraendert den Task nicht" todo "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"

finish_suite
