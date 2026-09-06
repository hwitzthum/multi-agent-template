#!/usr/bin/env bash
# Der Runner ist die einzige Anbietergrenze: fester Aufrufvertrag, feste
# Metadaten, und eine Anbieterantwort wird deterministisch übersetzt.
#
# Die Umgebungsprüfung `runner.sh --check` (verlangt eine echte Agenten-CLI)
# gehört nicht in die Suite; sie wird mit scripts/doctor.sh nachgezogen.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

runner="$project_dir/scripts/agent/runner.sh"
output_tool="$project_dir/scripts/agent/output.sh"

begin_suite runner-contract
fixture_workspace

expect_success "Runner-Vertrag" "$runner" --contract
expect_success "Runner veröffentlicht Fünf-Argument-Vertrag" sh -c "'$runner' --contract | grep -q metadata-output"
expect_failure "Runner weist unbekannte Rolle vor jedem Modellaufruf ab" "$runner" run_agent unknown "$tmp_root/prompt.md" "$project_dir" "$tmp_root/raw.md" "$tmp_root/meta.env"

printf '%s\n' 'model=fake' 'started_at=x' 'finished_at=y' 'exit_status=0' 'tokens_total=0' 'abort_reason=none' 'output_status=ok' > "$tmp_root/valid-metadata"
expect_success "Runner akzeptiert vollständige Metadaten" "$runner" validate_metadata "$tmp_root/valid-metadata"
printf '%s\n' 'model=fake' > "$tmp_root/bad-metadata"
expect_failure "Runner lehnt unvollständige Metadaten ab" "$runner" validate_metadata "$tmp_root/bad-metadata"

# Uebertragung der claude-JSON-Antwort (--output-format json --json-schema) ins Zeilenformat.
cat > "$tmp_root/claude-worker.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"num_turns":4,"total_cost_usd":0.0416537,
 "usage":{"input_tokens":9,"cache_creation_input_tokens":19547,"cache_read_input_tokens":17957,"output_tokens":151},
 "modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":9,"outputTokens":151}},
 "result":"```text\nRESULT=implemented\n```",
 "structured_output":{"RESULT":"implemented","CHANGED_PATHS":"src/app.txt","TESTS_RUN":"./scripts/verify.sh","NOTES_ADDED":"-"}}
EOF
expect_success "Runner rendert strukturierte Worker-Antwort" "$runner" render_result worker-task "$tmp_root/claude-worker.json" "$tmp_root/worker.raw" "$tmp_root/worker.values"
expect_success "gerenderte Worker-Antwort besteht den Output-Validator" "$output_tool" validate worker-task "$tmp_root/worker.raw"
assert_eq "Rohantwort folgt der Vertragsreihenfolge" 'RESULT=implemented' "$(sed -n '1p' "$tmp_root/worker.raw")"
assert_file_has "Tokens werden aus der Antwort uebernommen" "$tmp_root/worker.values" 'tokens_in=37513'
assert_file_has "Ausgabetokens werden uebernommen" "$tmp_root/worker.values" 'tokens_out=151'
assert_file_has "Kosten werden aus der Antwort uebernommen" "$tmp_root/worker.values" 'cost_estimate=0.041654'
assert_file_has "Modell wird aus der Antwort uebernommen" "$tmp_root/worker.values" 'model=claude-haiku-4-5-20251001'

cat > "$tmp_root/claude-manage.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"structured_output":{"action":"dispatch","task_id":"017","worker_kind":"normal","reason_code":"NEXT_HIGHEST_VALUE"}}
EOF
expect_success "Runner rendert Manager-Entscheidung als Frontmatter" "$runner" render_result manager-manage "$tmp_root/claude-manage.json" "$tmp_root/manage.raw" "$tmp_root/manage.values"
expect_success "gerenderte Manager-Entscheidung besteht den Output-Validator" "$output_tool" validate manager-manage "$tmp_root/manage.raw"

cat > "$tmp_root/claude-error.json" <<'EOF'
{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":60,"result":"abgebrochen"}
EOF
expect_success "Runner rendert Fehlerantwort ohne Schema-Objekt" "$runner" render_result worker-task "$tmp_root/claude-error.json" "$tmp_root/error.raw" "$tmp_root/error.values"
assert_file_has "Fehlerantwort wird als Fehler gekennzeichnet" "$tmp_root/error.values" 'is_error=true'
assert_file_has "Fehlerantwort nennt den Abbruchgrund" "$tmp_root/error.values" 'subtype=error_max_turns'
[ ! -s "$tmp_root/error.raw" ] && ok || bad "Fehlerantwort erzeugt keinen Rollenoutput"

printf '%s\n' 'kein json' > "$tmp_root/claude-garbage.json"
expect_failure "Runner weist Nicht-JSON ab" "$runner" render_result worker-task "$tmp_root/claude-garbage.json" "$tmp_root/garbage.raw" "$tmp_root/garbage.values"

finish_suite
