#!/usr/bin/env bash
# Die Umgebungsprüfung vor dem ersten Lauf. Sie ersetzt das mit F0 gestrichene
# `runner.sh --check` und muss vor allem eines können: einen kaputten Runner
# als Befund melden, statt selbst abzustürzen.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

doctor="$project_dir/scripts/doctor.sh"

begin_suite doctor
fixture_workspace

expect_contains "doctor --help" 'Verwendung:' "$doctor" --help
expect_failure "doctor weist unbekannte Optionen ab" "$doctor" --was-auch-immer

# --- Ein einsatzbereites Projekt --------------------------------------------
new_project_fixture
fixture_agent_cli_stubs
fixture_git_init
expect_success "doctor ist grün, wenn der gewählte Runner antwortet" \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
expect_contains "doctor nennt den gewählten Runner" 'AGENT_RUNNER=claude' \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
expect_contains "doctor meldet den sauberen Arbeitsbaum" 'Arbeitsbaum sauber' \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"

fixture_config AGENT_RUNNER codex
expect_success "doctor ist grün, wenn codex antwortet" \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
expect_contains "doctor prüft nur den gewählten Runner" 'codex einsatzbereit' \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"

# Ein schmutziger Arbeitsbaum ist ein Hinweis, kein Befund: er blockiert nur
# den Lauf ohne --allow-dirty, nicht die Einsatzbereitschaft.
printf '%s\n' geaendert > "$fixture/src/app.txt"
expect_success "schmutziger Arbeitsbaum ist kein Befund" \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
expect_contains "schmutziger Arbeitsbaum wird benannt" 'schmutzig' \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"

# --- Defekte Codex-Installation ---------------------------------------------
# Genau der beobachtete Fall: `codex` liegt im Pfad, bricht aber schon bei
# --version ab. Das ist ein Befund mit Text, kein Absturz der Prüfung.
new_project_fixture
fixture_agent_cli_stubs
fixture_config AGENT_RUNNER codex
fixture_git_init
cat > "$stub_bin/codex" <<'BROKEN'
#!/usr/bin/env bash
echo 'Error: spawn /opt/homebrew/lib/node_modules/@openai/codex/vendor/codex ENOENT' >&2
exit 1
BROKEN
chmod +x "$stub_bin/codex"
expect_failure "defekte Codex-Installation ist ein Befund" \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
output=$(env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture" 2>&1)
case "$output" in *'BEFUND   codex ist installiert, antwortet aber nicht auf --version'*) ok ;;
  *) bad "doctor benennt die defekte Codex-Installation"; printf '%s\n' "$output" >&2 ;; esac
case "$output" in *ENOENT*) ok ;;
  *) bad "doctor gibt die Fehlermeldung des CLI weiter"; printf '%s\n' "$output" >&2 ;; esac
case "$output" in *'OK       bash gefunden'*) ok ;;
  *) bad "doctor prüft nach dem Befund weiter"; printf '%s\n' "$output" >&2 ;; esac

# --- Fehlender Runner --------------------------------------------------------
# Ein Pfad mit allen Werkzeugen, aber ohne claude und ohne codex: ohne CLI
# läuft kein Lauf, und das muss doctor sagen statt still grün zu bleiben.
new_project_fixture
fixture_git_init
no_cli_bin="$fixture/.agent-runs/no-agent-cli"
mkdir -p "$no_cli_bin"
for tool in bash sh env dirname basename git jq perl grep head sed awk cat mktemp; do
  tool_path=$(command -v "$tool" 2>/dev/null) || continue
  case "$tool_path" in /*) ln -sf "$tool_path" "$no_cli_bin/$tool" ;; esac
done
expect_failure "fehlendes Runner-CLI ist ein Befund" \
  env PATH="$no_cli_bin" "$doctor" --project-dir "$fixture"
expect_contains "doctor sagt, welches CLI fehlt" 'claude wurde nicht gefunden' \
  sh -c "PATH='$no_cli_bin' '$doctor' --project-dir '$fixture' 2>&1 || true"

# --- Kaputte Konfiguration ---------------------------------------------------
new_project_fixture
fixture_agent_cli_stubs
fixture_git_init
printf 'UNBEKANNT=1\n' >> "$fixture/.agent/config.env"
expect_failure "ungültige Konfiguration ist ein Befund" \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
expect_contains "doctor benennt die ungültige Konfiguration" 'Konfiguration ist ungültig' \
  sh -c "PATH='$stub_bin:$PATH' '$doctor' --project-dir '$fixture' 2>&1 || true"

# --- Repository ohne Basiscommit ---------------------------------------------
# Manifeste und der Fresh-Versuch brauchen einen versionierten Stand.
new_project_fixture
fixture_agent_cli_stubs
expect_failure "Repository ohne Basiscommit ist ein Befund" \
  env PATH="$stub_bin:$PATH" "$doctor" --project-dir "$fixture"
expect_contains "doctor benennt den fehlenden Basiscommit" 'ohne Basiscommit' \
  sh -c "PATH='$stub_bin:$PATH' '$doctor' --project-dir '$fixture' 2>&1 || true"

finish_suite
