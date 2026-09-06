#!/usr/bin/env bash
# Die statischen Grenzen in .agent/config.env werden geprüft, nicht ausgeführt.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

config="$project_dir/scripts/agent/config.sh"

begin_suite config-limits
fixture_workspace

new_project_fixture
expect_success "Standardkonfiguration" "$config" --check
expect_success "Konfigurationswert lesen" "$config" --get MAX_TASK_ATTEMPTS

new_project_fixture
fixture_config UNKNOWN_KEY 1
expect_failure "unbekannter Schlüssel" "$config" --check "$fixture/.agent/config.env"

new_project_fixture
fixture_config MAX_TASK_ATTEMPTS -1
expect_failure "negatives Limit" "$config" --check "$fixture/.agent/config.env"

new_project_fixture
fixture_config MAX_NO_PROGRESS '1;touch_x'
expect_failure "Shellsyntax" "$config" --check "$fixture/.agent/config.env"

# FINALIZER ist ein Schalter, keine Zahl: der Finalizer kostet einen zusätzlichen
# Modellaufruf und ist deshalb ausdrücklich abwählbar.
new_project_fixture
expect_output "Finalizer ist im Auslieferungsstand aus" off "$config" --get FINALIZER "$fixture/.agent/config.env"
fixture_config FINALIZER llm
expect_success "FINALIZER=llm ist gültig" "$config" --check "$fixture/.agent/config.env"
fixture_config FINALIZER 1
expect_failure "FINALIZER nimmt keine Zahl" "$config" --check "$fixture/.agent/config.env"

new_project_fixture
awk '$1 != "FINALIZER=off"' "$fixture/.agent/config.env" > "$fixture/.agent/config.tmp"
mv "$fixture/.agent/config.tmp" "$fixture/.agent/config.env"
expect_failure "fehlender Pflichtschlüssel FINALIZER" "$config" --check "$fixture/.agent/config.env"

# AGENT_RUNNER wählt die Anbietergrenze und ist deshalb eine Aufzählung, keine
# freie Zeichenkette: ein Tippfehler soll die Konfiguration rot machen, nicht
# erst den Lauf.
new_project_fixture
expect_output "Auslieferungsstand läuft mit claude" claude "$config" --get AGENT_RUNNER "$fixture/.agent/config.env"
fixture_config AGENT_RUNNER codex
expect_success "AGENT_RUNNER=codex ist gültig" "$config" --check "$fixture/.agent/config.env"
fixture_config AGENT_RUNNER gemini
expect_failure "AGENT_RUNNER kennt nur claude und codex" "$config" --check "$fixture/.agent/config.env"

# AGENT_MODEL ist eine Zeichenkette, aber keine Shell-Eingabe: Modellnamen
# tragen Punkte, Doppelpunkte und Bindestriche, sonst nichts.
new_project_fixture
expect_output "Modellwahl liegt im Auslieferungsstand beim CLI" default "$config" --get AGENT_MODEL "$fixture/.agent/config.env"
fixture_config AGENT_MODEL claude-haiku-4-5-20251001
expect_success "AGENT_MODEL nimmt einen Modellnamen" "$config" --check "$fixture/.agent/config.env"
fixture_config AGENT_MODEL 'modell;touch_x'
expect_failure "AGENT_MODEL nimmt keine Shellsyntax" "$config" --check "$fixture/.agent/config.env"

# Die Grenzen eines Modellaufrufs stehen in der Konfiguration, nicht in der
# Umgebung: ein Lauf soll ohne gesetzte Variablen reproduzierbar sein.
new_project_fixture
expect_success "Zeitlimit eines Modellaufrufs ist konfiguriert" "$config" --get AGENT_TIMEOUT_SECONDS "$fixture/.agent/config.env"
expect_success "Rundenlimit eines Modellaufrufs ist konfiguriert" "$config" --get AGENT_MAX_TURNS "$fixture/.agent/config.env"
fixture_config AGENT_MAX_TURNS 0
expect_failure "AGENT_MAX_TURNS nimmt keine Null" "$config" --check "$fixture/.agent/config.env"

finish_suite
