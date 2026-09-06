#!/usr/bin/env bash
# Die Suite gegen sich selbst. Zwei Loecher sind hier schon aufgetreten und
# duerfen nicht wiederkommen:
#
#   * eine Zusicherung ohne Befehl bestand still — `$("$@")` ohne Argumente ist
#     eine leere Kommandosubstitution mit Exit 0, und die Zusicherungszahl
#     stieg dabei sogar;
#   * eine Testdatei rief eine nie definierte Fixture-Funktion auf, meldete
#     trotzdem GRUEN und blieb unbemerkt, weil das Log nur bei Rot gedruckt
#     wird.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

begin_suite test-harness

# --- Zusicherungen ohne Befehl ----------------------------------------------
# Der Fehlschlag ist hier der erwartete Ausgang, deshalb laeuft die Zusicherung
# in einer eigenen Shell und nur ihre Zaehler kommen zurueck.
counters() {
  bash -c '
    . "$1/lib.sh"
    shift
    begin_suite probe
    "$@"
    printf "%s/%s" "$suite_passed" "$suite_failed"
  ' _ "$tests_dir" "$@" 2>/dev/null
}

assert_eq "expect_success ohne Befehl besteht nicht" '0/1' "$(counters expect_success leer)"
assert_eq "expect_failure ohne Befehl besteht nicht" '0/1' "$(counters expect_failure leer)"
assert_eq "expect_contains ohne Befehl besteht nicht" '0/1' "$(counters expect_contains leer nadel)"
assert_eq "expect_output ohne Befehl besteht nicht" '0/1' "$(counters expect_output leer erwartet)"
assert_eq "mit Befehl zaehlt dieselbe Zusicherung normal" '1/0' "$(counters expect_success name true)"

# --- Eine gruene Datei mit Fehlerspuren im Log ------------------------------
# Geprueft an einer Wegwerf-Suite aus run.sh, lib.sh und zwei Testdateien: die
# echte Suite soll dabei nicht noch einmal laufen.
harness=$(mktemp -d "${TMPDIR:-/tmp}/harness.XXXXXX") || exit 1
trap 'command rm -r -f -- "$harness"' EXIT HUP INT TERM
mkdir -p "$harness/tests/unit"
cp "$tests_dir/run.sh" "$tests_dir/lib.sh" "$harness/tests/"

cat > "$harness/tests/unit/leise.sh" <<'LEISE'
#!/usr/bin/env bash
set -uo pipefail
tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
begin_suite leise
expect_success "harmlos" true
finish_suite
LEISE
chmod +x "$harness/tests/unit/leise.sh"
expect_success "eine stille Testdatei bleibt gruen" "$harness/tests/run.sh" unit

cat > "$harness/tests/unit/laut.sh" <<'LAUT'
#!/usr/bin/env bash
set -uo pipefail
tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
begin_suite laut
diesen_helfer_gibt_es_nicht
expect_success "meldet sich trotzdem gruen" true
finish_suite
LAUT
chmod +x "$harness/tests/unit/laut.sh"
expect_failure "eine Datei mit Fehlerspuren wird rot, obwohl sie GRUEN meldet" \
  "$harness/tests/run.sh" unit
expect_contains "der Riegel nennt seinen Grund" 'Fehlerspuren im Log' \
  sh -c "'$harness/tests/run.sh' unit 2>&1 || true"

# --- Optionen des Suite-Einstiegs -------------------------------------------
# Eine Option ohne Wert ist ein Bedienfehler mit Meldung, kein Abbruch der
# Shell: `unbound variable` endete ebenso ungleich null und saehe gleich aus.
expect_contains "run.sh meldet --jobs ohne Zahl" 'Verwendung:' \
  sh -c "'$tests_dir/run.sh' --jobs 2>&1 || true"
expect_failure "run.sh weist eine unbekannte Stufe ab" "$tests_dir/run.sh" nichtvorhanden

finish_suite
