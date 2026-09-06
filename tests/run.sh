#!/usr/bin/env bash
# tests/run.sh — der eine Befehl, der die Suite ausführt.
#
# Stufen (Ordner unter tests/):
#   unit         reine Funktions- und CLI-Prüfungen ohne Zusammenspiel
#   integration  mehrere Skripte zusammen, Fixtures, kein Modellaufruf
#   e2e          ganzer Orchestrator gegen den Fake-Runner (langsam, parallel)
#   lint         Doku- und Hilfetexte gegen den Code
#
# --fast lässt e2e weg; das ist die Stufe für scripts/verify.sh --quick.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1

usage() {
  echo "Verwendung: $0 [--fast] [--jobs N] [unit|integration|e2e|lint ...]"
  echo "Ohne Angabe laufen alle Stufen. --fast lässt e2e weg."
}

tiers=''
fast=false
jobs=${AGENT_TEST_JOBS:-4}
while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --fast) fast=true ;;
    --jobs) [ "$#" -ge 2 ] || { echo "--jobs erwartet eine Zahl" >&2; usage >&2; exit 2; }; jobs=$2; shift ;;
    unit|integration|e2e|lint) tiers="$tiers $1" ;;
    *) echo "unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$jobs" in
  ''|*[!0-9]*|0) echo "--jobs erwartet eine positive Zahl" >&2; exit 2 ;;
esac

if [ -z "$tiers" ]; then
  if [ "$fast" = true ]; then tiers='unit integration lint'; else tiers='unit integration e2e lint'; fi
elif [ "$fast" = true ]; then
  tiers=$(printf '%s\n' $tiers | grep -v '^e2e$' | tr '\n' ' ')
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/agent-suite.XXXXXX") || exit 1
trap 'command rm -r -f -- "$work"' EXIT HUP INT TERM

# Verhindert, dass scripts/verify.sh die Suite aus der Suite heraus erneut startet.
AGENT_TEST_SUITE=1
export AGENT_TEST_SUITE

cat > "$work/one.sh" <<'RUNNER'
#!/usr/bin/env bash
file=$1
work=$2
tier=$(basename -- "$(dirname -- "$file")")
name=$(basename -- "$file" .sh)
"$file" > "$work/$tier--$name.log" 2>&1
printf '%s\n' "$?" > "$work/$tier--$name.status"
RUNNER
chmod +x "$work/one.sh"

total_assertions=0
total_files=0
failed_files=0

report_tier() {
  local tier=$1 file name status log count noise
  for file in "$script_dir/$tier"/*.sh; do
    [ -f "$file" ] || continue
    name=$(basename -- "$file" .sh)
    log="$work/$tier--$name.log"
    status=$(sed -n '1p' "$work/$tier--$name.status" 2>/dev/null)
    [ -n "$status" ] || status=1
    # Eine Datei, die GRUEN meldet und dabei Spuren eines gebrochenen Skripts
    # ins Log schreibt, ist nicht gruen. Genau so blieb der Aufruf einer nie
    # definierten Fixture-Funktion unbemerkt: das Log wird nur bei Rot
    # gedruckt, und am Ergebnis aenderte er nichts.
    noise=''
    if [ "$status" -eq 0 ]; then
      noise=$(grep -nE 'command not found|unbound variable|syntax error' "$log" 2>/dev/null | head -n 3)
      [ -z "$noise" ] || status=1
    fi
    total_files=$((total_files + 1))
    count=$(sed -n 's/.*(\([0-9][0-9]*\) bestanden.*/\1/p' "$log" 2>/dev/null | tail -n 1)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    total_assertions=$((total_assertions + count))
    if [ "$status" -eq 0 ]; then
      printf '  %-12s %-28s GREEN (%s)\n' "$tier" "$name" "$count"
    else
      failed_files=$((failed_files + 1))
      printf '  %-12s %-28s RED\n' "$tier" "$name"
      [ -z "$noise" ] || echo "      (rot wegen Fehlerspuren im Log, obwohl die Datei GRÜN meldete)" >&2
      sed 's/^/      /' "$log" >&2
    fi
  done
}

for tier in $tiers; do
  files=$(find "$script_dir/$tier" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort)
  [ -n "$files" ] || continue
  if [ "$tier" = e2e ]; then
    printf '%s\n' "$files" | xargs -P "$jobs" -n 1 -I TESTFILE "$work/one.sh" TESTFILE "$work"
  else
    printf '%s\n' "$files" | while IFS= read -r file; do "$work/one.sh" "$file" "$work"; done
  fi
  report_tier "$tier"
done

if [ "$total_files" -eq 0 ]; then
  echo "tests: RED (keine Testdatei gefunden)" >&2
  exit 1
fi
if [ "$failed_files" -ne 0 ]; then
  echo "tests: RED ($failed_files von $total_files Dateien fehlgeschlagen, $total_assertions Zusicherungen bestanden)" >&2
  exit 1
fi
echo "tests: GREEN ($total_assertions Zusicherungen in $total_files Dateien)"
