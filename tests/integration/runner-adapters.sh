#!/usr/bin/env bash
# Zwei Adapter, ein Vertrag: `claude -p` und `codex exec` liefern für dieselbe
# Rolle dasselbe result.json und dieselbe metadata.env. Geprüft wird der ganze
# Weg von run_agent bis zu den Metadaten — mit Stub-CLIs statt Modellaufruf,
# damit auch Fehlerfälle reproduzierbar sind.
#
# Der Codex-Adapter ist nie gegen das echte CLI gelaufen; geprüft ist hier der
# dokumentierte Aufruf und die Auswertung seines Ereignisstroms.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

runner="$project_dir/scripts/agent/runner.sh"

begin_suite runner-adapters
fixture_workspace

# Ein Lauf des Adapters: Rolle, Ausgabename, Antwortdatei, Exitcode des Stubs
# und optional die Nachrichtendatei für codex. Kontext und Ausgaben liegen wie
# im echten Lauf unter .agent-runs/.
run_case() {
  local role=$1 label=$2 response=$3 exit_code=${4:-0} message=${5:-}
  mkdir -p "$fixture/.agent-runs/run" || return 1
  printf '%s\n' 'Kontext für den Stub.' > "$fixture/.agent-runs/run/$label.context.md"
  result="$fixture/.agent-runs/run/$label.json"
  metadata="$fixture/.agent-runs/run/$label.env"
  args_log="$fixture/.agent-runs/run/$label.args"
  PATH="$stub_bin:$PATH" STUB_ARGS="$args_log" STUB_STDOUT="$response" \
    STUB_EXIT="$exit_code" STUB_MESSAGE="$message" \
    "$runner" run_agent "$role" "$fixture/.agent-runs/run/$label.context.md" \
      "$fixture" "$result" "$metadata"
}

meta() { value=$(awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$1"); printf '%s' "$value"; }

# --- Claude-Adapter ---------------------------------------------------------
new_project_fixture
fixture_agent_cli_stubs

cat > "$fixture/claude-ok.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"num_turns":4,"total_cost_usd":0.0416537,
 "usage":{"input_tokens":9,"cache_creation_input_tokens":19547,"cache_read_input_tokens":17957,"output_tokens":151},
 "modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":9,"outputTokens":151}},
 "structured_output":{"result":"implemented","summary":"fertig","tests_run":"./scripts/verify.sh","notes":"-"}}
EOF
expect_success "Claude-Adapter beendet einen Worker-Aufruf" run_case worker claude-ok "$fixture/claude-ok.json"
expect_success "Claude-Metadaten sind gültig" "$runner" validate_metadata "$fixture/.agent-runs/run/claude-ok.env"
assert_eq "Claude meldet output_status=ok" ok "$(meta "$fixture/.agent-runs/run/claude-ok.env" output_status)"
assert_eq "Claude meldet keinen Abbruchgrund" none "$(meta "$fixture/.agent-runs/run/claude-ok.env" abort_reason)"
assert_eq "Claude summiert die Tokens" 37664 "$(meta "$fixture/.agent-runs/run/claude-ok.env" tokens_total)"
assert_eq "Claude übernimmt die Kosten" 0.041654 "$(meta "$fixture/.agent-runs/run/claude-ok.env" cost_estimate)"
assert_eq "Claude übernimmt das Modell" claude-haiku-4-5-20251001 "$(meta "$fixture/.agent-runs/run/claude-ok.env" model)"
expect_success "Claude-Ergebnis besteht das Rollenschema" "$runner" validate_result worker "$fixture/.agent-runs/run/claude-ok.json"

# Rollenabhängige Werkzeuge: der Worker schreibt Code und prüft, Manager und
# Finalizer bekommen kein Werkzeug, das Befehle ausführt.
assert_file_has "Worker bekommt Bash" "$fixture/.agent-runs/run/claude-ok.args" 'Bash'
assert_file_has "Worker läuft restriktiv" "$fixture/.agent-runs/run/claude-ok.args" '--restricted'
assert_file_has "Worker lässt fremde MCP-Server aus" "$fixture/.agent-runs/run/claude-ok.args" '--strict-mcp-config'
assert_file_has "Adapter setzt das Rollenschema" "$fixture/.agent-runs/run/claude-ok.args" '--json-schema'
assert_file_has "Adapter unterdrückt Rückfragen" "$fixture/.agent-runs/run/claude-ok.args" '--permission-prompts'
assert_file_has "Adapter reicht eine eigene Einstellungsdatei" "$fixture/.agent-runs/run/claude-ok.args" '--settings'

cat > "$fixture/claude-manager.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,
 "structured_output":{"action":"dispatch","task_id":"017","reason":"NEXT","question":""}}
EOF
expect_success "Claude-Adapter beendet einen Manager-Aufruf" run_case manager claude-manager "$fixture/claude-manager.json"
assert_file_has "Manager läuft restriktiv" "$fixture/.agent-runs/run/claude-manager.args" '--restricted'
assert_file_lacks "Manager bekommt kein Bash" "$fixture/.agent-runs/run/claude-manager.args" 'Bash'

# Die Einstellungsdatei des Laufs ist die Sicherheitshülle des Adapters; die
# Einstellungen der interaktiven Sitzung gelten hier nicht.
settings="$fixture/.agent-runs/run/claude-ok.json.settings.json"
assert_file "Adapter schreibt seine Einstellungsdatei" "$settings"
expect_success "Einstellungsdatei ist gültiges JSON" jq -e . "$settings"
expect_output "Einstellungsdatei trägt den bash-guard als PreToolUse-Hook" Bash \
  jq -r '.hooks.PreToolUse[0].matcher' "$settings"
expect_success "Einstellungsdatei nennt den bash-guard" \
  sh -c "jq -r '.hooks.PreToolUse[0].hooks[0].command' '$settings' | grep -q 'bash-guard.sh$'"
expect_success "Einstellungsdatei trägt eine Deny-Liste" \
  sh -c "jq -e '.permissions.deny | length > 0' '$settings' >/dev/null"
# Die Ausschlussliste ist eine Sicherheitszusage: `--restricted` haelt die
# CLAUDE.md des Projekts zwar heraus, aber der Worker laeuft ohne dieses Flag.
# Deshalb wird hier nicht nur geprueft, DASS die Liste gefuellt ist, sondern
# WAS darin steht.
fixture_real=$(CDPATH= cd -- "$fixture" && pwd -P) || fixture_real=$fixture
expect_success "Einstellungsdatei schließt die persönliche CLAUDE.md aus" \
  sh -c "jq -r '.claudeMdExcludes[]' '$settings' | grep -Fxq '$HOME/.claude/CLAUDE.md'"
expect_success "Einstellungsdatei schließt die CLAUDE.md des Projekts aus" \
  sh -c "jq -r '.claudeMdExcludes[]' '$settings' | grep -Fxq '$fixture_real/CLAUDE.md'"
expect_success "Einstellungsdatei schließt CLAUDE.md aus Unterordnern aus" \
  sh -c "jq -r '.claudeMdExcludes[]' '$settings' | grep -Fxq '$fixture_real/**/CLAUDE.md'"

# Fehlerantwort ohne Ergebnisobjekt: technischer Abbruch, kein Rollenergebnis.
cat > "$fixture/claude-error.json" <<'EOF'
{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":60,"result":"abgebrochen"}
EOF
expect_failure "Claude-Fehlerantwort lässt run_agent scheitern" run_case worker claude-error "$fixture/claude-error.json"
expect_success "Metadaten der Fehlerantwort sind gültig" "$runner" validate_metadata "$fixture/.agent-runs/run/claude-error.env"
assert_eq "Fehlerantwort meldet output_status=error" error "$(meta "$fixture/.agent-runs/run/claude-error.env" output_status)"
assert_eq "Fehlerantwort nennt den Abbruchgrund" error_max_turns "$(meta "$fixture/.agent-runs/run/claude-error.env" abort_reason)"

# Kein JSON: die Antwort ist unbrauchbar, das muss in den Metadaten stehen.
printf '%s\n' 'kein json' > "$fixture/claude-garbage.txt"
expect_failure "unlesbare Antwort lässt run_agent scheitern" run_case worker claude-garbage "$fixture/claude-garbage.txt"
expect_success "Metadaten der unlesbaren Antwort sind gültig" "$runner" validate_metadata "$fixture/.agent-runs/run/claude-garbage.env"
assert_eq "unlesbare Antwort meldet output_status=error" error "$(meta "$fixture/.agent-runs/run/claude-garbage.env" output_status)"
assert_eq "unlesbare Antwort nennt invalid_json" invalid_json "$(meta "$fixture/.agent-runs/run/claude-garbage.env" abort_reason)"

# --- Codex-Adapter ----------------------------------------------------------
new_project_fixture
fixture_agent_cli_stubs
fixture_config AGENT_RUNNER codex

cat > "$fixture/codex-ok.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"t-1"}
{"type":"turn.started","model":"gpt-5.6-sol"}
{"type":"item.completed","item":{"type":"agent_message"}}
{"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":140}}
EOF
cat > "$fixture/codex-message.json" <<'EOF'
{"result":"implemented","summary":"fertig","tests_run":"./scripts/verify.sh","notes":"-"}
EOF
expect_success "Codex-Adapter beendet einen Worker-Aufruf" \
  run_case worker codex-ok "$fixture/codex-ok.jsonl" 0 "$fixture/codex-message.json"
expect_success "Codex-Metadaten sind gültig" "$runner" validate_metadata "$fixture/.agent-runs/run/codex-ok.env"
assert_eq "Codex meldet output_status=ok" ok "$(meta "$fixture/.agent-runs/run/codex-ok.env" output_status)"
assert_eq "Codex summiert die Tokens aus turn.completed" 2140 "$(meta "$fixture/.agent-runs/run/codex-ok.env" tokens_total)"
assert_eq "Codex meldet keine Kosten" unknown "$(meta "$fixture/.agent-runs/run/codex-ok.env" cost_estimate)"
assert_eq "Codex übernimmt das Modell aus dem Strom" gpt-5.6-sol "$(meta "$fixture/.agent-runs/run/codex-ok.env" model)"
expect_success "Codex-Ergebnis besteht dasselbe Rollenschema" "$runner" validate_result worker "$fixture/.agent-runs/run/codex-ok.json"

# Der Aufruf muss die Sandbox mitbringen; ohne sie wäre der Lauf ungeschützt.
assert_file_has "Codex läuft in der Sandbox" "$fixture/.agent-runs/run/codex-ok.args" 'workspace-write'
assert_file_has "Codex bekommt das Rollenschema" "$fixture/.agent-runs/run/codex-ok.args" '--output-schema'
assert_file_has "Codex schreibt das Ergebnisobjekt in eine Datei" "$fixture/.agent-runs/run/codex-ok.args" '--output-last-message'
assert_file_has "Codex hält die Projektdoku aus dem Lauf" "$fixture/.agent-runs/run/codex-ok.args" 'project_doc_max_bytes=0'
assert_file_has "Codex nimmt den Prompt über stdin" "$fixture/.agent-runs/run/codex-ok.args" '-'

# turn.failed ohne Nachrichtendatei: der Lauf endet ohne Rollenergebnis.
cat > "$fixture/codex-failed.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"t-2"}
{"type":"turn.failed","error":{"message":"sandbox denied write"}}
EOF
expect_failure "Codex-turn.failed lässt run_agent scheitern" \
  run_case worker codex-failed "$fixture/codex-failed.jsonl"
expect_success "Metadaten nach turn.failed sind gültig" "$runner" validate_metadata "$fixture/.agent-runs/run/codex-failed.env"
assert_eq "turn.failed meldet output_status=error" error "$(meta "$fixture/.agent-runs/run/codex-failed.env" output_status)"
assert_eq "turn.failed nennt den gemeldeten Grund" sandbox_denied_write "$(meta "$fixture/.agent-runs/run/codex-failed.env" abort_reason)"
[ ! -s "$fixture/.agent-runs/run/codex-failed.json" ] && ok || bad "turn.failed erzeugt kein Rollenergebnis"

# Sauberer Lauf, aber keine Nachrichtendatei: eine leere Antwort ist eine
# Aussage des Modells, keine Infrastrukturstörung. Der Runner meldet sie
# deshalb als `empty` und bricht nicht ab — verwerfen tut sie erst der
# Rollenaufruf, der nur `ok` gelten lässt.
expect_success "fehlende Nachrichtendatei ist kein Adapterfehler" \
  run_case worker codex-empty "$fixture/codex-ok.jsonl"
assert_eq "fehlende Nachrichtendatei meldet output_status=empty" empty "$(meta "$fixture/.agent-runs/run/codex-empty.env" output_status)"
[ ! -s "$fixture/.agent-runs/run/codex-empty.json" ] && ok || bad "leere Antwort erzeugt kein Rollenergebnis"

# --- Unbekannter Adapter ----------------------------------------------------
# config.sh lässt nur claude und codex zu; der Runner verlässt sich nicht darauf.
new_project_fixture
fixture_agent_cli_stubs
printf 'AGENT_RUNNER=gemini\n' >> "$fixture/.agent/config.env"
expect_failure "unbekannter Adapter wird abgewiesen" run_case worker unknown-adapter "$fixture/codex-ok.jsonl"

finish_suite
