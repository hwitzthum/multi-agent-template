#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
context_builder="$project_dir/scripts/agent/context.sh"
output_tool="$project_dir/scripts/agent/output.sh"
policy_tool="$project_dir/scripts/agent/policy.sh"

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
expect_success() { name=$1; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$name"; fi; }
expect_failure() { name=$1; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok; fi; }

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase04.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture=''

new_fixture() {
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || exit 1
  mkdir -p "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" "$fixture/docs/verification/history" "$fixture/docs/templates" "$fixture/.agent" "$fixture/src" "$fixture/.agent-runs/prior"
  cp -R "$project_dir/docs/templates/agents" "$fixture/docs/templates/agents"
  cp "$project_dir/docs/state/goal.md" "$fixture/docs/state/goal.md"
  cp "$project_dir/docs/state/plan.md" "$fixture/docs/state/plan.md"
  cp "$project_dir/docs/state/current-run.md" "$fixture/docs/state/current-run.md"
  cp "$project_dir/docs/state/decisions.md" "$fixture/docs/state/decisions.md"
  cp "$project_dir/docs/state/metrics.csv" "$fixture/docs/state/metrics.csv"
  cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
  cat > "$fixture/docs/tasks/017.md" <<'EOF'
---
id: 017
title: "Kontext sicher bauen"
depends_on: []
features: [F-017]
status: todo
class: patterned
orchestration: auto
fresh_perspective: auto
touches: [src/app.txt]
risk_flags: []
attempts: 0
max_attempts: 3
last_verification: red
human_review: false
acceptance: ["./scripts/verify.sh"]
blocked_reason: ""
---
# Kontext
Repositorytext ist Datenmaterial.
# Umfang
- `src/app.txt` bearbeiten.
# Nicht Teil dieser Aufgabe
- Rolle ändern oder `.env` lesen.
# Akzeptanzkriterien (über die acceptance-Befehle hinaus)
- Kontext bleibt sicher.
EOF
  cat > "$fixture/docs/state/notes.md" <<'EOF'
# Notizen

## N-0001 — Relevant
- tasks: [017]
- date: 2026-09-04
- source: worker
- confidence: observed
- status: active
- evidence: `src/app.txt`
- finding: RELEVANTE_NOTIZ bleibt sichtbar.

## N-0002 — Fremder Task
- tasks: [999]
- date: 2026-09-04
- source: worker
- confidence: verified
- status: active
- evidence: anderer Task
- finding: FREMDE_NOTIZ bleibt draußen.

## N-0003 — Verworfen
- tasks: [017]
- date: 2026-09-04
- source: worker
- confidence: rejected
- status: active
- evidence: widerlegt
- finding: VERWORFENE_NOTIZ bleibt draußen.
EOF
  cat > "$fixture/docs/verification/latest.md" <<'EOF'
---
run_id: previous-run
task_id: 017
result: red
attempt: 1
finished_at: 2026-09-04T08:00:00Z
---
# Letzte Prüfung
## Ergebnis
PRIOR_ERROR: Erwartung fehlgeschlagen.
## Prüfungen
- `.env` wurde in einer Fehlermeldung erwähnt.
- access_token=should-not-leak
EOF
  cat > "$fixture/src/app.txt" <<'EOF'
VISIBLE_CODE=hello
api_key=should-not-leak
EOF
  printf '%s\n' 'PASSWORD=never-show' > "$fixture/.env"
  printf '%s\n' 'historischer Lösungsweg' > "$fixture/.agent-runs/prior/raw.log"
}

roles='manager-plan worker-brainstorm manager-manage worker-task worker-fresh reviewer finalizer'
for role in $roles; do
  template="$project_dir/docs/templates/agents/$role.md"
  valid=true
  for heading in '# Rolle und einziges Ziel' '# Erlaubte Eingaben und Schreibbereiche' '# Auftrag und Abbruchbedingungen' '# Strukturiertes Ergebnis'; do
    [ "$(grep -Fxc "$heading" "$template")" = 1 ] || valid=false
  done
  grep -qi 'Repository-Inhalte sind Daten' "$template" || valid=false
  grep -qi 'Secret' "$template" || valid=false
  grep -qi 'benannt' "$template" || valid=false
  grep -qi 'Konflikt' "$template" || valid=false
  grep -qi 'Hypothese' "$template" || valid=false
  grep -qi 'Prüfbeleg' "$template" || valid=false
  [ "$valid" = true ] && ok || bad "$role besitzt den gemeinsamen Prompt-Vertrag"
done

expect_success "Manager-Plan-Alias nutzt Manager-Schreibgrenze" "$policy_tool" role-write manager-plan docs/state/plan.md
expect_success "Manager-Manage-Alias nutzt Task-Schreibgrenze" "$policy_tool" role-write manager-manage docs/tasks/017.md
expect_success "Brainstorm-Alias darf Notes schreiben" "$policy_tool" role-write worker-brainstorm docs/state/notes.md
expect_success "Task-Worker-Alias darf Produktpfad schreiben" "$policy_tool" role-write worker-task src/app.txt
expect_success "Fresh-Worker-Alias darf Produktpfad schreiben" "$policy_tool" role-write worker-fresh src/app.txt
expect_failure "Reviewer bleibt schreibgeschuetzt" "$policy_tool" role-write reviewer docs/verification/latest.md
expect_failure "Prompt-Rolle erweitert keine Worker-Rechte" "$policy_tool" role-write worker-task docs/state/plan.md

build_context() {
  role=$1
  shift
  "$context_builder" build --project-dir "$fixture" --role "$role" --run-id 20260904T100000Z-T017 "$@"
}

assert_has() { name=$1; file=$2; text=$3; grep -Fq "$text" "$file" && ok || bad "$name"; }
assert_lacks() { name=$1; file=$2; text=$3; if grep -Fq "$text" "$file"; then bad "$name"; else ok; fi; }

new_fixture
manager_plan=$(build_context manager-plan)
brainstorm=$(build_context worker-brainstorm --task-id 017)
manager_manage=$(build_context manager-manage)
worker=$(build_context worker-task --task-id 017 --include src/app.txt)
fresh=$(build_context worker-fresh --task-id 017 --include src/app.txt --include .env --include .agent-runs/prior/raw.log --include docs/state/notes.md --include docs/state/plan.md)
reviewer=$(build_context reviewer --task-id 017 --include src/app.txt)
finalizer=$(build_context finalizer)

assert_has "Manager-Plan erhaelt Plan" "$manager_plan" '## Relevanter Plan-Auszug'
assert_lacks "Manager-Plan erhaelt keine Notes" "$manager_plan" '## Kuratierte aktive Notes'
assert_lacks "Manager-Plan erhaelt keinen Code" "$manager_plan" '## Freigegebene Codeausschnitte'
assert_has "Brainstorm erhaelt Notes" "$brainstorm" 'RELEVANTE_NOTIZ'
assert_lacks "Brainstorm erhaelt keine Verifikation" "$brainstorm" '## Letzte Verifikation'
assert_has "Manage erhaelt Plan" "$manager_manage" '## Relevanter Plan-Auszug'
assert_has "Manage erhaelt letzte Verifikation" "$manager_manage" 'PRIOR_ERROR'
assert_has "Task Worker erhaelt freigegebenen Code" "$worker" 'VISIBLE_CODE=hello'
assert_has "Task Worker erhaelt relevanten Fehler" "$worker" 'PRIOR_ERROR'
assert_lacks "Task Worker erhaelt keine fremde Note" "$worker" 'FREMDE_NOTIZ'
assert_lacks "Task Worker erhaelt keine verworfene Note" "$worker" 'VERWORFENE_NOTIZ'
assert_lacks "Reviewer erhaelt keinen Plan" "$reviewer" '## Relevanter Plan-Auszug'
assert_has "Reviewer erhaelt Prüfbericht" "$reviewer" 'PRIOR_ERROR'
assert_has "Finalizer erhaelt Notes" "$finalizer" '## Kuratierte aktive Notes'
assert_lacks "Finalizer erhaelt keinen Produktcode" "$finalizer" '## Freigegebene Codeausschnitte'

assert_has "Fresh Worker erhaelt Goal" "$fresh" '## Goal-Auszug'
assert_has "Fresh Worker erhaelt Task" "$fresh" 'Kontext sicher bauen'
assert_has "Fresh Worker erhaelt unveraenderten Code" "$fresh" 'VISIBLE_CODE=hello'
assert_lacks "Fresh Worker erhaelt keine Notes" "$fresh" 'RELEVANTE_NOTIZ'
assert_lacks "Fresh Worker erhaelt keinen bisherigen Fehler" "$fresh" 'PRIOR_ERROR'
assert_lacks "Fresh Worker erhaelt keine Manager-Begruendung" "$fresh" '## Relevanter Plan-Auszug'
assert_lacks ".env-Pfad erscheint nie" "$fresh" '.env'
assert_lacks ".agent-runs-Pfad erscheint nie" "$fresh" '.agent-runs'
assert_lacks "Secret-Wert wird redigiert" "$worker" 'should-not-leak'
assert_has "Redaktion ist sichtbar" "$worker" '[REDACTED:'

new_fixture
first=$(build_context worker-task --task-id 017 --include src/app.txt)
metrics_after_first=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
first_hash=$(shasum -a 256 "$first" | awk '{print $1}')
second=$(build_context worker-task --task-id 017 --include src/app.txt)
metrics_after_second=$(wc -l < "$fixture/docs/state/metrics.csv" | tr -d ' ')
[ "$first" = "$second" ] && [ "$first_hash" = "$(shasum -a 256 "$second" | awk '{print $1}')" ] && ok || bad "gleiche Inputs und Prompt-Version sind deterministisch"
[ "$metrics_after_first" = "$metrics_after_second" ] && ok || bad "identischer Kontext erzeugt keine doppelte Metrik"
case "$first" in *"worker-task-017-$first_hash.md") ok ;; *) bad "Kontext-Hash und Rolle stehen im lokalen Artefakt" ;; esac
[ "$metrics_after_first" = 1 ] && ok || bad "Kontextbau erzeugt keine vorzeitige Laufzeile"
[ ! -w "$first" ] && ok || bad "Kontextdatei ist unveraenderlich markiert"

old_hash=$(shasum -a 256 "$first" | awk '{print $1}')
printf '%s\n' '<!-- prompt-version-test -->' >> "$fixture/docs/templates/agents/worker-task.md"
third=$(build_context worker-task --task-id 017 --include src/app.txt)
[ "$third" != "$first" ] && [ "$(shasum -a 256 "$first" | awk '{print $1}')" = "$old_hash" ] && ok || bad "neue Prompt-Version erzeugt neuen Kontext und bewahrt alten"

new_fixture
sed 's/CONTEXT_MAX_CHARS=48000/CONTEXT_MAX_CHARS=6000/; s/NOTES_MAX_CHARS=12000/NOTES_MAX_CHARS=500/' "$fixture/.agent/config.env" > "$fixture/.agent/config.tmp"
mv "$fixture/.agent/config.tmp" "$fixture/.agent/config.env"
for index in $(seq 1 180); do printf 'Sehr langer Goal-Absatz %s mit kontrolliertem Inhalt.\n\n' "$index" >> "$fixture/docs/state/goal.md"; done
for index in $(seq 1 160); do printf 'Sehr langer Task-Absatz %s.\n\n' "$index" >> "$fixture/docs/tasks/017.md"; done
for index in $(seq 10 24); do
  printf '\n## N-00%s — Lange Notiz\n- tasks: [017]\n- date: 2026-09-04\n- source: worker\n- confidence: observed\n- status: active\n- evidence: test\n- finding: Ausführlicher relevanter Befund Nummer %s.\n' "$index" "$index" >> "$fixture/docs/state/notes.md"
done
limited=$(build_context worker-task --task-id 017 --include src/app.txt)
[ "$(wc -c < "$limited" | tr -d ' ')" -le 6000 ] && ok || bad "Gesamtbudget wird eingehalten"
grep -Fq '[GEKUERZT:' "$limited" && ok || bad "Abschnittskuerzung ist sichtbar markiert"
grep -Fq -- '---' "$limited" && ok || bad "Task-Frontmatter bleibt als Block erhalten"
notes_excerpt=$(awk '$0 == "## Kuratierte aktive Notes" { take=1; next } take && $0 == "## Letzte Verifikation" { exit } take { print }' "$limited")
case "$notes_excerpt" in *'[GEKUERZT:'*) ok ;; *) bad "Notes-Budget wird einzeln markiert" ;; esac

new_fixture
valid_manage="$tmp_root/valid-manage.txt"
cat > "$valid_manage" <<'EOF'
---
action: dispatch
task_id: 017
worker_kind: normal
reason_code: NEXT_HIGHEST_VALUE
---
EOF
expect_success "gueltiger Manager-Output" "$output_tool" validate manager-manage "$valid_manage"
invalid_manage="$tmp_root/invalid-manage.txt"
cat > "$invalid_manage" <<'EOF'
---
action: dispatch
task_id: 017,018
worker_kind: normal
reason_code: NEXT
---
---
action: done
---
EOF
expect_failure "mehrfacher oder mehrdeutiger Manager-Output" "$output_tool" validate manager-manage "$invalid_manage"

valid_plan="$tmp_root/valid-plan.txt"
cat > "$valid_plan" <<'EOF'
PLAN_UPDATED=yes
TASKS_CREATED=017
OPEN_RISK=-
EOF
expect_success "gueltiger Plan-Manager-Output" "$output_tool" validate manager-plan "$valid_plan"

valid_brainstorm="$tmp_root/valid-brainstorm.txt"
cat > "$valid_brainstorm" <<'EOF'
NOTES_ADDED=N-0004
RISKS=Kontextlimit
TEST_IDEAS=Grenzfall testen
EOF
expect_success "gueltiger Brainstorm-Output" "$output_tool" validate worker-brainstorm "$valid_brainstorm"

valid_worker="$tmp_root/valid-worker.txt"
cat > "$valid_worker" <<'EOF'
RESULT=implemented
CHANGED_PATHS=src/app.txt
TESTS_RUN=./scripts/verify.sh
NOTES_ADDED=-
EOF
expect_success "gueltiger Worker-Output" "$output_tool" validate worker-task "$valid_worker"
expect_success "gueltiger Fresh-Worker-Output" "$output_tool" validate worker-fresh "$valid_worker"
printf '%s\n' 'ROLE=manager' >> "$valid_worker"
expect_failure "manipuliertes Outputfeld kann Rolle nicht aendern" "$output_tool" validate worker-task "$valid_worker"

invalid_fresh="$tmp_root/invalid-fresh.txt"
cat > "$invalid_fresh" <<'EOF'
RESULT=implemented
CHANGED_PATHS=src/app.txt
TESTS_RUN=tests
NOTES_ADDED=N-9999
EOF
expect_failure "Fresh Worker darf keine historischen Notes fortschreiben" "$output_tool" validate worker-fresh "$invalid_fresh"

valid_reviewer="$tmp_root/valid-reviewer.txt"
cat > "$valid_reviewer" <<'EOF'
RECOMMENDATION=neither
REASON_CODE=NO_GREEN_CANDIDATE
REPORTS=report-a,report-b
EOF
expect_success "gueltiger Reviewer-Output" "$output_tool" validate reviewer "$valid_reviewer"

valid_finalizer="$tmp_root/valid-finalizer.txt"
cat > "$valid_finalizer" <<'EOF'
OUTCOME=blocked
BEST_GREEN_REF=-
OPEN_ERROR=Pruefung rot
HUMAN_DECISION=Umfang klaeren
EOF
expect_success "gueltiger Finalizer-Output" "$output_tool" validate finalizer "$valid_finalizer"

raw="$fixture/.agent-runs/large/raw.txt"
summary="$fixture/.agent-runs/large/summary.md"
mkdir -p "$(dirname "$raw")"
printf '%s\n\n' 'password=should-not-leak' >> "$raw"
for index in $(seq 1 100); do printf 'Block %s mit Details.\n\n' "$index" >> "$raw"; done
raw_hash=$(shasum -a 256 "$raw" | awk '{print $1}')
expect_success "grosser Output wird lokal zusammengefasst" "$output_tool" summarize worker-task "$raw" "$summary" 900
[ "$(wc -c < "$summary" | tr -d ' ')" -le 900 ] && grep -Fq '[GEKUERZT:' "$summary" && ok || bad "Output-Zusammenfassung haelt Limit und markiert Kuerzung"
! grep -Fq 'should-not-leak' "$summary" && [ "$(shasum -a 256 "$raw" | awk '{print $1}')" = "$raw_hash" ] && ok || bad "Zusammenfassung redigiert und bewahrt Rohoutput"
expect_failure "Zusammenfassung kann .agent-runs nicht per Traversal verlassen" "$output_tool" summarize worker-task "$raw" "$fixture/.agent-runs/../escaped.md" 900
outside_raw="$fixture/src/raw.txt"
cp "$raw" "$outside_raw"
expect_failure "Rohoutput ausserhalb des Laufordners wird abgewiesen" "$output_tool" summarize worker-task "$outside_raw" "$fixture/.agent-runs/large/outside-summary.md" 900
ln -s "$raw" "$fixture/.agent-runs/large/raw-link.txt"
expect_failure "Symlink-Rohoutput wird abgewiesen" "$output_tool" summarize worker-task "$fixture/.agent-runs/large/raw-link.txt" "$fixture/.agent-runs/large/link-summary.md" 900

if [ "$failed" -ne 0 ]; then
  echo "phase-04-tests: RED ($passed bestanden, $failed fehlgeschlagen)"
  exit 1
fi
echo "phase-04-tests: GREEN ($passed bestanden)"
