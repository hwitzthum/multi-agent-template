#!/usr/bin/env bash
# Zwei Kandidaten entstehen isoliert vom selben Commit; nur ein grüner,
# geprüfter Kandidat darf den Hauptstand verändern.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

orchestrator="$project_dir/scripts/orchestrate.sh"
validator="$project_dir/scripts/validate-ledger.sh"
runner="$tests_dir/fake-runner.sh"

begin_suite candidate-tournament
fixture_workspace

new_candidate_fixture
direct_run="$fixture/.agent-runs/direct"
mkdir -p "$direct_run"
expect_success "Kandidaten starten isoliert vom gleichen Commit" "$fixture/scripts/agent/candidates.sh" init --project-dir "$fixture" --run-dir "$direct_run"
assert_eq "Fresh-Worktree enthält keine historische Note" '# Notizen' "$(sed -n '1p' "$direct_run/candidates/candidate-b/worktree/docs/state/notes.md")"
assert_eq "Fresh-Notes sind vollständig bereinigt" 1 "$(wc -l < "$direct_run/candidates/candidate-b/worktree/docs/state/notes.md" | tr -d ' ')"
fresh_context=$("$fixture/scripts/agent/context.sh" build --project-dir "$direct_run/candidates/candidate-b/worktree" --role worker-fresh --run-id 20260904T120000Z-T017 --task-id 017 --include src/app.txt)
assert_file_lacks "Fresh-Kontext enthält keine historische Note" "$fresh_context" HISTORICAL_SECRET_MUST_NOT_REACH_FRESH
printf '%s\n' good > "$direct_run/candidates/candidate-a/worktree/src/app.txt"
expect_success "Kandidatenpatch wird lokal erfasst" "$fixture/scripts/agent/candidates.sh" capture --project-dir "$fixture" --run-dir "$direct_run" --candidate candidate-a --task-id 017
assert_eq "Kandidat verändert Hauptstand vor Review nicht" initial "$(sed -n '1p' "$fixture/src/app.txt")"
expect_success "Unveränderter Hauptstand besteht den Fingerprint-Vergleich" "$fixture/scripts/agent/candidates.sh" check-main --project-dir "$fixture" --run-dir "$direct_run"
expect_success "Temporäre Worktrees sind kontrolliert entfernbar" "$fixture/scripts/agent/candidates.sh" cleanup --project-dir "$fixture" --run-dir "$direct_run"

new_candidate_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_action worker-task 1 write-bad
fake_action worker-fresh 1 require-no-git-write-good
expect_success "Nur der grüne Fresh-Kandidat wird übernommen" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Grüner Kandidat verdrängt roten" good "$(sed -n '1p' "$fixture/src/app.txt")"
assert_eq "Erneute Hauptprüfung führt offene Aufgabe ins Review" review "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
decision=$(find "$fixture/.agent-runs" -path '*/candidates/decision.env' -print | LC_ALL=C sort | tail -n 1)
assert_file_has "Entscheidung protokolliert Fresh-Gewinner" "$decision" 'selected=candidate-b'
assert_file_has "Übernahme verlangt Reverify" "$decision" 'requires_reverify=true'
[ ! -f "$fixture/.agent-runs/fake/reviewer.count" ] && ok || bad "Ein eindeutiger grüner Kandidat startete unnötig den Reviewer"

new_candidate_fixture
fake_response worker-task 2 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_action worker-task 1 timeout
fake_action worker-task 2 write-good
fake_action worker-fresh 1 write-bad
expect_success "Providerfehler erhält genau begrenzten Infrastruktur-Retry" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Infrastruktur-Retry startet zweiten Normal-Worker-Aufruf" 2 "$(sed -n '1p' "$fixture/.agent-runs/fake/worker-task.count")"
assert_eq "Infrastruktur-Retry verbraucht keinen Task-Fehlversuch" 0 "$(ledger_scalar "$fixture/docs/tasks/017.md" attempts)"

new_candidate_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response reviewer 1 'RECOMMENDATION=candidate-b' 'REASON_CODE=BOTH_GREEN_SIMPLER_CHANGE' 'REPORTS=candidate-a,candidate-b'
fake_action worker-task 1 write-alpha
fake_action worker-fresh 1 write-beta
expect_success "Zwei grüne Kandidaten werden durch Reviewer entschieden" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Reviewer-Auswahl wird übernommen" beta "$(sed -n '1p' "$fixture/src/app.txt")"
assert_eq "Reviewer läuft genau einmal" 1 "$(sed -n '1p' "$fixture/.agent-runs/fake/reviewer.count")"

new_candidate_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response finalizer 1 'OUTCOME=blocked' 'BEST_GREEN_REF=-' 'OPEN_ERROR=Kein sicher übernehmbarer Kandidat' 'HUMAN_DECISION=Kandidaten prüfen'
fake_action worker-task 1 write-bad
fake_action worker-fresh 1 write-bad
fake_action finalizer 1 write-good
expect_failure "Zwei rote Kandidaten erzwingen neither und Finalizer" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Beide rot blockiert statt Auswahl" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Finalizer kann Produktcode nicht verändern" initial "$(sed -n '1p' "$fixture/src/app.txt")"
decision=$(find "$fixture/.agent-runs" -path '*/candidates/decision.env' -print | LC_ALL=C sort | tail -n 1)
assert_file_has "Neither wird dokumentiert" "$decision" 'selected=neither'
expect_success "Ledger bleibt nach Both-red gültig" "$validator" --project-dir "$fixture"

new_candidate_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response finalizer 1 'OUTCOME=blocked' 'BEST_GREEN_REF=-' 'OPEN_ERROR=Kein sicher übernehmbarer Kandidat' 'HUMAN_DECISION=Kandidaten prüfen'
fake_action worker-task 1 empty
expect_failure "Leere Kandidatenausgabe stoppt vor Übernahme" env ORCHESTRATOR_RUNNER="$runner" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Leere Ausgabe verändert Produkt nicht" initial "$(sed -n '1p' "$fixture/src/app.txt")"
assert_eq "Leere Ausgabe erzeugt nie done" blocked "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
expect_success "Ledger bleibt nach leerer Ausgabe gültig" "$validator" --project-dir "$fixture"

new_candidate_fixture
fake_response worker-task 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response worker-fresh 1 'RESULT=implemented' 'CHANGED_PATHS=src/app.txt' 'TESTS_RUN=./scripts/verify.sh' 'NOTES_ADDED=-'
fake_response reviewer 1 'RECOMMENDATION=candidate-b' 'REASON_CODE=BOTH_GREEN_SIMPLER_CHANGE' 'REPORTS=candidate-a,candidate-b'
fake_response finalizer 1 'OUTCOME=blocked' 'BEST_GREEN_REF=-' 'OPEN_ERROR=Kein sicher übernehmbarer Kandidat' 'HUMAN_DECISION=Kandidaten prüfen'
fake_action worker-task 1 write-good
fake_action worker-fresh 1 write-good-external
expect_failure "Externe Hauptänderung pausiert sichere Übernahme" env ORCHESTRATOR_RUNNER="$runner" ORCHESTRATOR_PROJECT_DIR="$fixture" "$orchestrator" --project-dir "$fixture" --task 017
assert_eq "Externe Änderung lässt Task offen" in_progress "$(ledger_scalar "$fixture/docs/tasks/017.md" status)"
assert_eq "Externe Änderung pausiert Lauf" paused "$(ledger_scalar "$fixture/docs/state/current-run.md" phase)"
assert_eq "Externe Änderung wird nicht überschrieben" external "$(sed -n '1p' "$fixture/src/app.txt")"
expect_success "Ledger bleibt nach externer Änderung gültig" "$validator" --project-dir "$fixture"

finish_suite
