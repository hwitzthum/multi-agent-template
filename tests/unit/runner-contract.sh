#!/usr/bin/env bash
# Der Runner ist die einzige Anbietergrenze: fester Aufrufvertrag, feste
# Metadaten, und eine Anbieterantwort wird deterministisch in result.json
# übersetzt.
#
# Die Umgebungsprüfung `runner.sh --check` (verlangt eine echte Agenten-CLI)
# gehört nicht in die Suite; sie wird mit scripts/doctor.sh nachgezogen.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

runner="$project_dir/scripts/agent/runner.sh"

begin_suite runner-contract
fixture_workspace

expect_success "Runner-Vertrag" "$runner" --contract
expect_success "Runner veröffentlicht Fünf-Argument-Vertrag" sh -c "'$runner' --contract | grep -q metadata-output"
expect_contains "Runner nennt die drei Rollen" 'manager | worker | finalizer' "$runner" --contract
expect_failure "Runner weist unbekannte Rolle vor jedem Modellaufruf ab" "$runner" run_agent worker-task "$tmp_root/prompt.md" "$project_dir" "$tmp_root/result.json" "$tmp_root/meta.env"

printf '%s\n' 'model=fake' 'started_at=x' 'finished_at=y' 'exit_status=0' 'tokens_total=0' 'abort_reason=none' 'output_status=ok' > "$tmp_root/valid-metadata"
expect_success "Runner akzeptiert vollständige Metadaten" "$runner" validate_metadata "$tmp_root/valid-metadata"
printf '%s\n' 'model=fake' > "$tmp_root/bad-metadata"
expect_failure "Runner lehnt unvollständige Metadaten ab" "$runner" validate_metadata "$tmp_root/bad-metadata"

# Uebertragung der claude-JSON-Antwort (--output-format json --json-schema).
cat > "$tmp_root/claude-worker.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"num_turns":4,"total_cost_usd":0.0416537,
 "usage":{"input_tokens":9,"cache_creation_input_tokens":19547,"cache_read_input_tokens":17957,"output_tokens":151},
 "modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":9,"outputTokens":151}},
 "result":"```json\n{}\n```",
 "structured_output":{"result":"implemented","summary":"fertig","tests_run":"./scripts/verify.sh","notes":"-"}}
EOF
expect_success "Runner rendert strukturierte Worker-Antwort" "$runner" render_result worker "$tmp_root/claude-worker.json" "$tmp_root/worker.json" "$tmp_root/worker.values"
expect_success "gerendertes Ergebnis besteht die Schemaprüfung" "$runner" validate_result worker "$tmp_root/worker.json"
expect_output "Das Ergebnisobjekt wird unverändert übernommen" implemented jq -r '.result' "$tmp_root/worker.json"
assert_file_has "Tokens werden aus der Antwort uebernommen" "$tmp_root/worker.values" 'tokens_in=37513'
assert_file_has "Ausgabetokens werden uebernommen" "$tmp_root/worker.values" 'tokens_out=151'
assert_file_has "Kosten werden aus der Antwort uebernommen" "$tmp_root/worker.values" 'cost_estimate=0.041654'
assert_file_has "Modell wird aus der Antwort uebernommen" "$tmp_root/worker.values" 'model=claude-haiku-4-5-20251001'

cat > "$tmp_root/claude-manager.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"structured_output":{"action":"dispatch","task_id":"017","reason":"NEXT","question":""}}
EOF
expect_success "Runner rendert Manager-Entscheidung" "$runner" render_result manager "$tmp_root/claude-manager.json" "$tmp_root/manager.json" "$tmp_root/manager.values"
expect_success "gerenderte Manager-Entscheidung besteht die Schemaprüfung" "$runner" validate_result manager "$tmp_root/manager.json"

cat > "$tmp_root/claude-error.json" <<'EOF'
{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":60,"result":"abgebrochen"}
EOF
expect_success "Runner rendert Fehlerantwort ohne Ergebnisobjekt" "$runner" render_result worker "$tmp_root/claude-error.json" "$tmp_root/error.json" "$tmp_root/error.values"
assert_file_has "Fehlerantwort wird als Fehler gekennzeichnet" "$tmp_root/error.values" 'is_error=true'
assert_file_has "Fehlerantwort nennt den Abbruchgrund" "$tmp_root/error.values" 'subtype=error_max_turns'
[ ! -s "$tmp_root/error.json" ] && ok || bad "Fehlerantwort erzeugt kein Rollenergebnis"
expect_failure "leeres Ergebnis besteht die Schemaprüfung nicht" "$runner" validate_result worker "$tmp_root/error.json"

printf '%s\n' 'kein json' > "$tmp_root/claude-garbage.json"
expect_failure "Runner weist Nicht-JSON ab" "$runner" render_result worker "$tmp_root/claude-garbage.json" "$tmp_root/garbage.json" "$tmp_root/garbage.values"

finish_suite
