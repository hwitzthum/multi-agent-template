#!/usr/bin/env bash
# Der Runner ist die einzige Anbietergrenze: fester Aufrufvertrag, feste
# Metadaten, und die Antwort beider Adapter wird deterministisch in dasselbe
# result.json übersetzt.
#
# Hier stehen nur die reinen Übersetzungsschritte. Den ganzen Weg von run_agent
# bis zur metadata.env prüft tests/integration/runner-adapters.sh, die
# Umgebungsprüfung tests/integration/doctor.sh.
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

# Uebertragung des codex-Ereignisstroms (codex exec --json). Das Ergebnisobjekt
# steht nicht im Strom, sondern in der Datei aus --output-last-message.
cat > "$tmp_root/codex-ok.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"t-1"}
{"type":"turn.started","model":"gpt-5.6-sol"}
{"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":140}}
EOF
cat > "$tmp_root/codex-message.json" <<'EOF'
{"result":"implemented","summary":"fertig","tests_run":"./scripts/verify.sh","notes":"-"}
EOF
expect_success "Runner rendert einen codex-Lauf" "$runner" render_codex_result \
  "$tmp_root/codex-ok.jsonl" "$tmp_root/codex-message.json" "$tmp_root/codex.json" "$tmp_root/codex.values"
expect_success "codex-Ergebnis besteht dasselbe Rollenschema" "$runner" validate_result worker "$tmp_root/codex.json"
expect_output "Das Ergebnisobjekt kommt aus der Nachrichtendatei" implemented jq -r '.result' "$tmp_root/codex.json"
assert_file_has "Tokens kommen aus turn.completed" "$tmp_root/codex.values" 'tokens_in=2000'
assert_file_has "Ausgabetokens kommen aus turn.completed" "$tmp_root/codex.values" 'tokens_out=140'
assert_file_has "codex meldet keine Kosten" "$tmp_root/codex.values" 'cost_estimate=unknown'
assert_file_has "Modell kommt aus dem Ereignisstrom" "$tmp_root/codex.values" 'model=gpt-5.6-sol'

cat > "$tmp_root/codex-failed.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"t-2"}
{"type":"turn.failed","error":{"message":"sandbox denied write"}}
EOF
expect_success "Runner rendert turn.failed ohne Nachrichtendatei" "$runner" render_codex_result \
  "$tmp_root/codex-failed.jsonl" "$tmp_root/fehlt.json" "$tmp_root/codex-failed.json" "$tmp_root/codex-failed.values"
assert_file_has "turn.failed wird als Fehler gekennzeichnet" "$tmp_root/codex-failed.values" 'is_error=true'
assert_file_has "turn.failed nennt den gemeldeten Grund" "$tmp_root/codex-failed.values" 'subtype=sandbox_denied_write'
[ ! -s "$tmp_root/codex-failed.json" ] && ok || bad "turn.failed erzeugt kein Rollenergebnis"

printf '%s\n' 'kein json' > "$tmp_root/codex-garbage.jsonl"
expect_failure "Runner weist einen unlesbaren Ereignisstrom ab" "$runner" render_codex_result \
  "$tmp_root/codex-garbage.jsonl" "$tmp_root/fehlt.json" "$tmp_root/codex-garbage.json" "$tmp_root/codex-garbage.values"

# Die Sicherheitshuelle des Claude-Adapters steht in einer eigenen Datei; die
# Einstellungen der interaktiven Sitzung gelten im Headless-Lauf nicht.
expect_success "Runner schreibt seine Einstellungsdatei" "$runner" runner_settings "$tmp_root/runner-settings.json"
expect_success "Einstellungsdatei ist gültiges JSON" jq -e . "$tmp_root/runner-settings.json"
expect_output "Einstellungsdatei hängt den bash-guard an Bash" Bash jq -r '.hooks.PreToolUse[0].matcher' "$tmp_root/runner-settings.json"
expect_success "Einstellungsdatei trägt eine Deny-Liste" \
  sh -c "jq -e '.permissions.deny | length > 0' '$tmp_root/runner-settings.json' >/dev/null"

finish_suite
