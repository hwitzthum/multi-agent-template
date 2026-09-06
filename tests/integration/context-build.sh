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
manager=$("$builder" build --project-dir "$fixture" --role manager --run-id "$run_id" --task-id 017)
worker=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include src/app.txt)
fresh=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --fresh \
  --include src/app.txt --include .env --include .agent-runs/prior/raw.log --include docs/state/notes.md)
finalizer=$("$builder" build --project-dir "$fixture" --role finalizer --run-id "$run_id" --task-id 017)

# Der Headless-Rahmen steht im Kontext, damit ihn jeder Runner weiterreicht.
for context in "$manager" "$worker" "$fresh" "$finalizer"; do
  assert_file_has "Kontext trägt den Headless-Rahmen" "$context" '## Headless-Rahmen'
done
assert_file_has "Der Rahmen nennt die Rolle" "$manager" 'als Rolle «manager»'
assert_file_has "Der Rahmen verlangt strukturiertes JSON" "$worker" 'strukturiertes JSON-Objekt'

assert_file_has "Manager erhält Plan und Entscheidungen" "$manager" '## Relevanter Plan-Auszug'
assert_file_has "Manager erhält das Task-Inventar" "$manager" '### Task-Inventar'
assert_file_has "Manager erhält den letzten Prüfbericht" "$manager" 'PRIOR_ERROR'
assert_file_lacks "Manager erhält keine Dateiliste" "$manager" '## Dateien im Umfang'

assert_file_has "Worker erhält die Dateiliste statt der Inhalte" "$worker" '## Dateien im Umfang'
assert_file_has "Die Dateiliste nennt den freigegebenen Pfad" "$worker" '- `src/app.txt`'
assert_file_lacks "Worker erhält keinen Dateiinhalt" "$worker" 'VISIBLE_CODE=hello'
assert_file_has "Worker erhält den relevanten Fehler" "$worker" 'PRIOR_ERROR'
assert_file_has "Worker erhält die relevante Note" "$worker" 'RELEVANTE_NOTIZ'
assert_file_lacks "Worker erhält keine fremde Note" "$worker" 'FREMDE_NOTIZ'
assert_file_lacks "Worker erhält keine verworfene Note" "$worker" 'VERWORFENE_NOTIZ'
assert_file_lacks "Worker erhält keinen Plan" "$worker" '## Relevanter Plan-Auszug'

assert_file_has "Fresh Worker erhält Goal" "$fresh" '## Goal-Auszug'
assert_file_has "Fresh Worker erhält den Task" "$fresh" 'Kontext sicher bauen'
assert_file_has "Fresh Worker wird als zweiter Anlauf benannt" "$fresh" 'Unabhängiger zweiter Anlauf'
assert_file_lacks "Fresh Worker erhält keine Notes" "$fresh" 'RELEVANTE_NOTIZ'
assert_file_lacks "Fresh Worker erhält keinen bisherigen Fehler" "$fresh" 'PRIOR_ERROR'
assert_file_lacks "Fresh Worker erhält keinen Plan" "$fresh" '## Relevanter Plan-Auszug'
assert_file_has "Ausgeschlossene Pfade werden sichtbar entfernt" "$fresh" '[AUSGESCHLOSSENER PFAD ENTFERNT]'
assert_file_lacks ".env-Pfad erscheint nie" "$fresh" '.env'
assert_file_lacks ".agent-runs-Pfad erscheint nie" "$fresh" '.agent-runs'

assert_file_has "Finalizer erhält Notes" "$finalizer" '## Kuratierte aktive Notes'
assert_file_lacks "Finalizer erhält keine Dateiliste" "$finalizer" '## Dateien im Umfang'
assert_file_lacks "Secret-Wert wird redigiert" "$manager" 'should-not-leak'
assert_file_has "Redaktion ist sichtbar" "$manager" '[REDACTED:'

expect_failure "Worker ohne Task ist kein Kontext" "$builder" build --project-dir "$fixture" --role worker --run-id "$run_id"
expect_failure "Fresh gilt nur für den Worker" "$builder" build --project-dir "$fixture" --role manager --run-id "$run_id" --fresh
expect_failure "abgelöste Rolle wird abgewiesen" "$builder" build --project-dir "$fixture" --role worker-task --run-id "$run_id" --task-id 017

# Der Rollenvertrag gehört zu den Daten des Projekts: fehlt er, ist das ein
# Befund und kein stiller Griff zur Fassung des Kits.
new_populated_fixture
rm -f "$fixture/docs/prompts/worker.md"
expect_failure "fehlender Rollenvertrag stoppt den Kontextbau" "$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017

# Die Dateiliste ist genau die Schreibpolicy des Workers: was sie nennt, darf er
# auch ändern. Steuerungspfade, die allein die Kontextpolicy durchliesse, stehen
# deshalb nicht darin — sonst nennte der Kontext einen Pfad, den der
# Manifestvergleich danach als Regelverstoss zurücksetzt.
new_populated_fixture
scoped=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 \
  --include src/app.txt --include CLAUDE.md --include scripts/bash-guard.sh \
  --include scripts/commit-gate.sh --include .gitignore --include scripts/agent)
assert_file_has "Produktpfad bleibt in der Dateiliste" "$scoped" '- `src/app.txt`'
assert_file_lacks "Sitzungsregeln stehen nicht in der Dateiliste" "$scoped" '- `CLAUDE.md`'
assert_file_lacks "Schutz-Hook steht nicht in der Dateiliste" "$scoped" '- `scripts/bash-guard.sh`'
assert_file_lacks "Commit-Gate steht nicht in der Dateiliste" "$scoped" '- `scripts/commit-gate.sh`'
assert_file_lacks "Git-Steuerdatei steht nicht in der Dateiliste" "$scoped" '- `.gitignore`'
assert_file_lacks "Orchestrierungsordner steht nicht in der Dateiliste" "$scoped" '- `scripts/agent`'
assert_file_has "Die Entfernung bleibt sichtbar" "$scoped" '[AUSGESCHLOSSENER PFAD ENTFERNT]'

# Zwei verschiedene Lagen, zwei verschiedene Aussagen: eine vollständig
# gefilterte Liste bleibt eine Grenze, ein Task ohne `touches` ist keine.
filtered=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include CLAUDE.md)
assert_file_has "vollständig gefilterte Liste zeigt die Entfernung" "$filtered" '[AUSGESCHLOSSENER PFAD ENTFERNT]'
assert_file_lacks "gefilterte Liste behauptet keinen offenen Umfang" "$filtered" '(kein touches-Umfang'

make_task --id 018 --title 'Task ohne touches' --class patterned \
  --context 'Kein Umfang gesetzt.' --scope 'Produktnahe Dateien.' \
  --not-scope 'Steuerungsdateien ändern.' --criteria 'Verhalten ist geprüft.'
unbounded=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 018)
assert_file_has "leeres touches wird als unbeschränkt benannt" "$unbounded" '(kein touches-Umfang'
assert_file_lacks "leeres touches nennt keine Entfernung" "$unbounded" '[AUSGESCHLOSSENER PFAD ENTFERNT]'

new_populated_fixture
first=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include src/app.txt)
first_hash=$(shasum -a 256 "$first" | awk '{print $1}')
second=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include src/app.txt)
[ "$first" = "$second" ] && [ "$first_hash" = "$(shasum -a 256 "$second" | awk '{print $1}')" ] \
  && ok || bad "gleiche Inputs und Prompt-Version sind deterministisch"
case "$first" in *"worker-017-$first_hash.md") ok ;; *) bad "Kontext-Hash und Rolle stehen im lokalen Artefakt" ;; esac
[ ! -e "$fixture/.agent-runs/metrics.csv" ] && ok || bad "Kontextbau erzeugt keine vorzeitige Laufzeile"
[ ! -w "$first" ] && ok || bad "Kontextdatei ist unveraenderlich markiert"

old_hash=$(shasum -a 256 "$first" | awk '{print $1}')
printf '%s\n' '<!-- prompt-version-test -->' >> "$fixture/docs/prompts/worker.md"
third=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include src/app.txt)
[ "$third" != "$first" ] && [ "$(shasum -a 256 "$first" | awk '{print $1}')" = "$old_hash" ] \
  && ok || bad "neue Prompt-Version erzeugt neuen Kontext und bewahrt alten"

# Die Budgets sind fest: ein zu kleines Gesamtlimit wird gemeldet, nicht still
# unterschritten.
new_populated_fixture
fixture_config NOTES_MAX_CHARS 500
for index in $(seq 1 180); do printf 'Sehr langer Goal-Absatz %s mit kontrolliertem Inhalt.\n\n' "$index" >> "$fixture/docs/state/goal.md"; done
for index in $(seq 1 160); do printf 'Sehr langer Task-Absatz %s.\n\n' "$index" >> "$fixture/docs/tasks/017.md"; done
limited=$("$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include src/app.txt)
assert_file_has "Abschnittskuerzung ist sichtbar markiert" "$limited" '[GEKUERZT:'
assert_file_has "Task-Frontmatter bleibt als Block erhalten" "$limited" '---'
[ "$(wc -c < "$limited" | tr -d ' ')" -le 48000 ] && ok || bad "Feste Budgets halten das Gesamtlimit"
fixture_config CONTEXT_MAX_CHARS 2000
expect_failure "zu kleines Gesamtlimit wird gemeldet" "$builder" build --project-dir "$fixture" --role worker --run-id "$run_id" --task-id 017 --include src/app.txt

finish_suite
