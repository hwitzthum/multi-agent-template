#!/usr/bin/env bash
# Ein Rollenergebnis ist eine JSON-Datei, die gegen ihr Schema geprüft wird:
# genau die Vertragsfelder, jeder Wert eine Zeichenkette, enum und pattern
# eingehalten. Geprüft wird mit `jq -e` — dieselbe Prüfung wie im Lauf.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

runner="$project_dir/scripts/agent/runner.sh"
schemas="$project_dir/scripts/agent/schemas"

begin_suite result-contract
fixture_workspace

check() { printf '%s' "$2" > "$tmp_root/result.json"; "$runner" validate_result "$1" "$tmp_root/result.json"; }

for role in manager worker finalizer; do
  assert_file "Schema existiert: $role" "$schemas/$role.json"
  expect_output "Runner nennt den Schemapfad für $role" "$schemas/$role.json" "$runner" schema_path "$role"
  # Alle Properties sind Pflicht, keine zusaetzlichen erlaubt, und es kommen nur
  # type, enum und pattern vor.
  jq -e '
    .type == "object" and .additionalProperties == false
    and ((.properties | keys) == (.required | sort))
    and all(.properties[]; .type == "string" and ((keys - ["type", "enum", "pattern"]) | length) == 0)
  ' "$schemas/$role.json" >/dev/null && ok || bad "Schema für $role hält den Schemavertrag"
done

expect_failure "unbekannte Rolle hat kein Schema" "$runner" schema_path reviewer

expect_success "gültiges Managerergebnis" check manager \
  '{"action":"dispatch","task_id":"017","reason":"Naechster Schritt","question":""}'
expect_success "ask_human mit Frage und ohne Task" check manager \
  '{"action":"ask_human","task_id":"","reason":"Entscheidung fehlt","question":"good oder alpha?"}'
expect_failure "unbekannte Manageraktion" check manager \
  '{"action":"weitermachen","task_id":"017","reason":"x","question":""}'
expect_failure "nicht-numerische Task-ID" check manager \
  '{"action":"dispatch","task_id":"017a","reason":"x","question":""}'
expect_failure "fehlendes Managerfeld" check manager \
  '{"action":"dispatch","task_id":"017","reason":"x"}'
expect_failure "zusätzliches Managerfeld" check manager \
  '{"action":"dispatch","task_id":"017","reason":"x","question":"","worker_kind":"fresh"}'

expect_success "gültiges Workerergebnis" check worker \
  '{"result":"implemented","summary":"fertig","tests_run":"./scripts/verify.sh","notes":""}'
expect_failure "unbekanntes Workerergebnis" check worker \
  '{"result":"erledigt","summary":"fertig","tests_run":"","notes":""}'
expect_failure "Zahl statt Zeichenkette" check worker \
  '{"result":"implemented","summary":"fertig","tests_run":"","notes":7}'
expect_failure "verschachteltes Objekt statt Zeichenkette" check worker \
  '{"result":"implemented","summary":{"text":"fertig"},"tests_run":"","notes":""}'

expect_success "gültiges Finalizerergebnis" check finalizer \
  '{"open_error":"Prüfung rot","next_decision":"Umfang klären","best_green_ref":""}'
expect_failure "Finalizerergebnis ohne Feld" check finalizer \
  '{"open_error":"Prüfung rot","next_decision":"Umfang klären"}'

expect_failure "kaputtes JSON ist kein Ergebnis" check worker 'kein json'
expect_failure "leere Datei ist kein Ergebnis" check worker ''
expect_failure "Liste statt Objekt" check worker '["implemented"]'

finish_suite
