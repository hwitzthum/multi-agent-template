#!/usr/bin/env bash
# Jede Rolle sieht genau ihren Ausschnitt, Secrets werden redigiert, und
# gleiche Eingaben ergeben denselben Kontext.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

builder="$project_dir/scripts/agent/context.sh"
run_id=20260904T100000Z-T017

begin_suite context-build
fixture_workspace

new_populated_fixture
manager_plan=$("$builder" build --project-dir "$fixture" --role manager-plan --run-id "$run_id")
brainstorm=$("$builder" build --project-dir "$fixture" --role worker-brainstorm --run-id "$run_id" --task-id 017)
manager_manage=$("$builder" build --project-dir "$fixture" --role manager-manage --run-id "$run_id")
worker=$("$builder" build --project-dir "$fixture" --role worker-task --run-id "$run_id" --task-id 017 --include src/app.txt)
fresh=$("$builder" build --project-dir "$fixture" --role worker-fresh --run-id "$run_id" --task-id 017 --include src/app.txt --include .env --include .agent-runs/prior/raw.log --include docs/state/notes.md --include docs/state/plan.md)
finalizer=$("$builder" build --project-dir "$fixture" --role finalizer --run-id "$run_id")

assert_file_has "Manager-Plan erhaelt Plan" "$manager_plan" '## Relevanter Plan-Auszug'
assert_file_lacks "Manager-Plan erhaelt keine Notes" "$manager_plan" '## Kuratierte aktive Notes'
assert_file_lacks "Manager-Plan erhaelt keinen Code" "$manager_plan" '## Freigegebene Codeausschnitte'
assert_file_has "Brainstorm erhaelt Notes" "$brainstorm" 'RELEVANTE_NOTIZ'
assert_file_lacks "Brainstorm erhaelt keine Verifikation" "$brainstorm" '## Letzte Verifikation'
assert_file_has "Manage erhaelt Plan" "$manager_manage" '## Relevanter Plan-Auszug'
assert_file_has "Manage erhaelt letzte Verifikation" "$manager_manage" 'PRIOR_ERROR'
assert_file_has "Task Worker erhaelt freigegebenen Code" "$worker" 'VISIBLE_CODE=hello'
assert_file_has "Task Worker erhaelt relevanten Fehler" "$worker" 'PRIOR_ERROR'
assert_file_lacks "Task Worker erhaelt keine fremde Note" "$worker" 'FREMDE_NOTIZ'
assert_file_lacks "Task Worker erhaelt keine verworfene Note" "$worker" 'VERWORFENE_NOTIZ'
assert_file_has "Finalizer erhaelt Notes" "$finalizer" '## Kuratierte aktive Notes'
assert_file_lacks "Finalizer erhaelt keinen Produktcode" "$finalizer" '## Freigegebene Codeausschnitte'

assert_file_has "Fresh Worker erhaelt Goal" "$fresh" '## Goal-Auszug'
assert_file_has "Fresh Worker erhaelt Task" "$fresh" 'Kontext sicher bauen'
assert_file_has "Fresh Worker erhaelt unveraenderten Code" "$fresh" 'VISIBLE_CODE=hello'
assert_file_lacks "Fresh Worker erhaelt keine Notes" "$fresh" 'RELEVANTE_NOTIZ'
assert_file_lacks "Fresh Worker erhaelt keinen bisherigen Fehler" "$fresh" 'PRIOR_ERROR'
assert_file_lacks "Fresh Worker erhaelt keine Manager-Begruendung" "$fresh" '## Relevanter Plan-Auszug'
assert_file_lacks ".env-Pfad erscheint nie" "$fresh" '.env'
assert_file_lacks ".agent-runs-Pfad erscheint nie" "$fresh" '.agent-runs'
assert_file_lacks "Secret-Wert wird redigiert" "$worker" 'should-not-leak'
assert_file_has "Redaktion ist sichtbar" "$worker" '[REDACTED:'

new_populated_fixture
first=$("$builder" build --project-dir "$fixture" --role worker-task --run-id "$run_id" --task-id 017 --include src/app.txt)
first_hash=$(shasum -a 256 "$first" | awk '{print $1}')
second=$("$builder" build --project-dir "$fixture" --role worker-task --run-id "$run_id" --task-id 017 --include src/app.txt)
[ "$first" = "$second" ] && [ "$first_hash" = "$(shasum -a 256 "$second" | awk '{print $1}')" ] \
  && ok || bad "gleiche Inputs und Prompt-Version sind deterministisch"
case "$first" in *"worker-task-017-$first_hash.md") ok ;; *) bad "Kontext-Hash und Rolle stehen im lokalen Artefakt" ;; esac
[ ! -e "$fixture/.agent-runs/metrics.csv" ] && ok || bad "Kontextbau erzeugt keine vorzeitige Laufzeile"
[ ! -w "$first" ] && ok || bad "Kontextdatei ist unveraenderlich markiert"

old_hash=$(shasum -a 256 "$first" | awk '{print $1}')
printf '%s\n' '<!-- prompt-version-test -->' >> "$fixture/docs/templates/agents/worker-task.md"
third=$("$builder" build --project-dir "$fixture" --role worker-task --run-id "$run_id" --task-id 017 --include src/app.txt)
[ "$third" != "$first" ] && [ "$(shasum -a 256 "$first" | awk '{print $1}')" = "$old_hash" ] \
  && ok || bad "neue Prompt-Version erzeugt neuen Kontext und bewahrt alten"

new_populated_fixture
fixture_config CONTEXT_MAX_CHARS 6000
fixture_config NOTES_MAX_CHARS 500
for index in $(seq 1 180); do printf 'Sehr langer Goal-Absatz %s mit kontrolliertem Inhalt.\n\n' "$index" >> "$fixture/docs/state/goal.md"; done
for index in $(seq 1 160); do printf 'Sehr langer Task-Absatz %s.\n\n' "$index" >> "$fixture/docs/tasks/017.md"; done
for index in $(seq 10 24); do
  printf '\n## N-00%s — Lange Notiz\n- tasks: [017]\n- date: 2026-09-04\n- source: worker\n- confidence: observed\n- status: active\n- evidence: test\n- finding: Ausführlicher relevanter Befund Nummer %s.\n' "$index" "$index" >> "$fixture/docs/state/notes.md"
done
limited=$("$builder" build --project-dir "$fixture" --role worker-task --run-id "$run_id" --task-id 017 --include src/app.txt)
[ "$(wc -c < "$limited" | tr -d ' ')" -le 6000 ] && ok || bad "Gesamtbudget wird eingehalten"
assert_file_has "Abschnittskuerzung ist sichtbar markiert" "$limited" '[GEKUERZT:'
assert_file_has "Task-Frontmatter bleibt als Block erhalten" "$limited" '---'
notes_excerpt=$(awk '$0 == "## Kuratierte aktive Notes" { take=1; next } take && $0 == "## Letzte Verifikation" { exit } take { print }' "$limited")
case "$notes_excerpt" in *'[GEKUERZT:'*) ok ;; *) bad "Notes-Budget wird einzeln markiert" ;; esac

finish_suite
