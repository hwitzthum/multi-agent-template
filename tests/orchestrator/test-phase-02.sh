#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
validator="$project_dir/scripts/validate-ledger.sh"
status_gate="$project_dir/scripts/agent/status.sh"
migrator="$project_dir/scripts/migrate-tasks.sh"
archiver="$project_dir/scripts/archive-notes.sh"
next_tasks="$project_dir/scripts/next-tasks.sh"
. "$project_dir/scripts/agent/ledger.sh"

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
expect_success() { name=$1; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$name"; fi; }
expect_failure() { name=$1; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok; fi; }
expect_contains() {
  name=$1; needle=$2; shift 2
  output=$("$@" 2>/dev/null) || { bad "$name"; return; }
  case "$output" in *"$needle"*) ok ;; *) bad "$name" ;; esac
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-phase02.XXXXXX") || exit 1
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
fixture=''

new_fixture() {
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || exit 1
  mkdir -p "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" "$fixture/docs/verification/history" "$fixture/.agent"
  cp "$project_dir/docs/state/goal.md" "$fixture/docs/state/goal.md"
  cp "$project_dir/docs/state/plan.md" "$fixture/docs/state/plan.md"
  cp "$project_dir/docs/state/notes.md" "$fixture/docs/state/notes.md"
  cp "$project_dir/docs/state/current-run.md" "$fixture/docs/state/current-run.md"
  cp "$project_dir/docs/verification/latest.md" "$fixture/docs/verification/latest.md"
  cp "$project_dir/.agent/config.env" "$fixture/.agent/config.env"
}

make_task() {
  id=$1; status=$2; deps=$3; human=${4:-false}; verification=${5:-never}; class=${6:-patterned}; mode=${7:-auto}; attempts=${8:-0}; max_attempts=${9:-3}
  file="$fixture/docs/tasks/$id.md"
  {
    echo '---'
    echo "id: $id"
    echo "title: \"Task $id\""
    echo "depends_on: [$deps]"
    echo 'features: [F-001]'
    echo "status: $status"
    echo "class: $class"
    echo "orchestration: $mode"
    echo 'fresh_perspective: auto'
    echo "attempts: $attempts"
    echo "max_attempts: $max_attempts"
    echo "last_verification: $verification"
    echo "human_review: $human"
    echo 'acceptance:'
    echo '  - "./scripts/verify.sh"'
    echo 'blocked_reason: ""'
    echo '---'
    echo '# Kontext'
    echo 'Testkontext.'
    echo '# Umfang'
    echo '- Testen.'
    echo '# Nicht Teil dieser Aufgabe'
    echo '- Anderes.'
    echo '# Akzeptanzkriterien (über die acceptance-Befehle hinaus)'
    echo '- Verhalten ist geprüft.'
  } > "$file"
}

make_report() {
  id=$1; result=$2
  {
    echo '---'
    echo 'run_id: test-run'
    echo "task_id: $id"
    echo "result: $result"
    echo 'attempt: 1'
    echo 'finished_at: 2026-09-04T09:15:00Z'
    echo '---'
    echo '# Letzte Prüfung'
    echo '## Ergebnis'
    echo "$result"
    echo '## Prüfungen'
    echo '- Test.'
  } > "$fixture/docs/verification/latest.md"
}

new_fixture
make_task 001 done '' false green
make_task 002 todo '001'
make_report 001 green
expect_success "gueltiger Task-Graph" "$validator" --project-dir "$fixture"
expect_contains "nur abhaengigkeitsfreier todo-Task ist bereit" 'READY: 002 | Task 002 | patterned' "$next_tasks" --project-dir "$fixture"
expect_failure "nur Orchestrator schreibt current-run" "$project_dir/scripts/agent/policy.sh" role-write finalizer docs/state/current-run.md
expect_success "Orchestrator darf current-run schreiben" "$project_dir/scripts/agent/policy.sh" role-write orchestrator docs/state/current-run.md

new_fixture
make_task 002 todo '999'
expect_failure "fehlende Abhaengigkeit" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 todo '002'
make_task 002 todo '001'
expect_failure "zyklische Abhaengigkeit" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 todo ''
make_task 001 todo ''
cp "$fixture/docs/tasks/001.md" "$fixture/docs/tasks/duplicate.md"
expect_failure "doppelte Task-ID" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 done '' false never
expect_failure "done ohne gruenen Pruefstand" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 done '' false green
make_report 002 green
expect_failure "done ohne passenden Pruefbericht" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 in_progress '' true green
make_report 001 green
expect_failure "Human Review verhindert direkten done-Uebergang" "$status_gate" --project-dir "$fixture" set-status 001 done in_progress
expect_contains "abgewiesener Human-Review-Wechsel bleibt unveraendert" 'in_progress' ledger_scalar "$fixture/docs/tasks/001.md" status

new_fixture
make_task 001 todo ''
expect_success "todo nach in_progress" "$status_gate" --project-dir "$fixture" set-status 001 in_progress todo
expect_failure "veralteter Statuswechsel" "$status_gate" --project-dir "$fixture" set-status 001 in_progress todo

new_fixture
make_task 001 in_progress '' false green
make_report 001 green
expect_success "done mit passendem gruenen Bericht" "$status_gate" --project-dir "$fixture" set-status 001 done in_progress

new_fixture
make_task 001 todo '' false never patterned impossible
expect_failure "unbekannter Orchestrierungsmodus" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 todo '' false never patterned auto 4 3
expect_failure "Versuchslimit" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 todo ''
sed '/# Umfang/d' "$fixture/docs/tasks/001.md" > "$fixture/docs/tasks/001.tmp"
mv "$fixture/docs/tasks/001.tmp" "$fixture/docs/tasks/001.md"
expect_failure "fehlender Pflichtabschnitt" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 in_progress ''
expect_failure "current-run passt nicht zu aktivem Task" "$validator" --project-dir "$fixture"

new_fixture
old="$fixture/docs/tasks/007.md"
{
  echo '---'
  echo 'id: 007'
  echo 'title: "Alter Task"'
  echo 'depends_on: []'
  echo 'features: [F-007]'
  echo 'status: todo'
  echo 'acceptance: ["./scripts/verify.sh"]'
  echo 'custom_field: bleibt'
  echo '---'
  echo '# Kontext'
  echo 'Alt.'
  echo '# Umfang'
  echo '- Migrieren.'
  echo '# Nicht Teil dieser Aufgabe'
  echo '- Sonstiges.'
  echo '# Akzeptanzkriterien (über die acceptance-Befehle hinaus)'
  echo '- Gültig.'
} > "$old"
before_id=$(ledger_scalar "$old" id)
before_deps=$(ledger_list "$old" depends_on)
expect_success "Migration des alten Schemas" "$migrator" --project-dir "$fixture"
[ "$(ledger_scalar "$old" id)" = "$before_id" ] && [ "$(ledger_list "$old" depends_on)" = "$before_deps" ] && grep -Fqx 'custom_field: bleibt' "$old" && grep -Fqx 'orchestration: auto' "$old" && ok || bad "Migration erhaelt ID, Abhaengigkeiten und unbekannte Felder"
expect_success "migrierter Task ist gueltig" "$validator" --project-dir "$fixture"

new_fixture
make_task 001 todo ''
atomic_file="$fixture/docs/tasks/001.md"
expect_failure "atomare Aenderung wird vor Ersetzen abgebrochen" ledger_atomic_replace_scalar "$atomic_file" status in_progress false
[ "$(ledger_scalar "$atomic_file" status)" = todo ] && ok || bad "Schreibabbruch bewahrt vorherige Datei"

new_fixture
marker="$fixture/markdown-was-not-executed"
make_task 001 todo ''
sed "s|title: .*|title: \"\$(touch $marker)\"|" "$fixture/docs/tasks/001.md" > "$fixture/docs/tasks/safe.md"
ledger_scalar "$fixture/docs/tasks/safe.md" title >/dev/null
[ ! -e "$marker" ] && ok || bad "Markdown wird nicht als Shellcode ausgefuehrt"

new_fixture
{
  echo '# Notizen'
  echo
  printf '%0300d\n' 0
  echo '## N-0001 — Aktiv'
  echo '- tasks: [001]'
  echo '- source: worker'
  echo '- confidence: verified'
  echo '- status: active'
  echo '- evidence: test'
  echo '- finding: behalten'
  echo
  echo '## N-0002 — Verworfen'
  echo '- tasks: [001]'
  echo '- source: worker'
  echo '- confidence: rejected'
  echo '- status: active'
  echo '- evidence: test'
  echo '- finding: archivieren'
} > "$fixture/docs/state/notes.md"
active=$(ledger_active_notes "$fixture/docs/state/notes.md")
case "$active" in *N-0001* ) ok ;; *) bad "aktive Notiz wird in Kontext uebernommen" ;; esac
case "$active" in *N-0002* ) bad "rejected Notiz wird nicht als aktiver Fakt geliefert" ;; *) ok ;; esac
expect_success "Notizarchivierung" "$archiver" --project-dir "$fixture" --max-chars 100
grep -q 'N-0001' "$fixture/docs/state/notes.md" && ! grep -q 'N-0002' "$fixture/docs/state/notes.md" && ok || bad "Archivierung behaelt aktive relevante Notiz"
grep -q 'N-0002' "$fixture/docs/state/notes-archive/"*.md && ok || bad "Archivierung verschiebt verworfene Notiz"

if [ "$failed" -ne 0 ]; then
  echo "phase-02-tests: RED ($passed bestanden, $failed fehlgeschlagen)"
  exit 1
fi
echo "phase-02-tests: GREEN ($passed bestanden)"
