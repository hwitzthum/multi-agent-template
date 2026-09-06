#!/usr/bin/env bash
# Markdown-Ledger lesen und atomar schreiben — ohne den Inhalt je als Shellcode
# zu behandeln.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

begin_suite ledger-parsing
fixture_workspace

# Ein Durchlauf, eine Ausgabe: "schluessel<TAB>wert" fuer Frontmatter,
# Schluessel "#" fuer die Rumpfueberschriften.
new_project_fixture
parse_file="$fixture/docs/tasks/001.md"
cat > "$parse_file" <<'EOF'
---
id: 001
title: "Wert mit: Doppelpunkt"
depends_on: [002, 003]
status: todo
class: patterned # mechanical | patterned | open
orchestration: auto
touches: [] # leer heisst unbeschraenkt
risk_flags: []
attempts: 0
human_review: false
acceptance:
  - "./scripts/verify.sh"
  - "npm test"
blocked_reason: ""
---

# Kontext
Text.
## Kein Pflichtabschnitt
# Umfang
- etwas
EOF
expect_output "Doppelpunkt im Wert bleibt erhalten" 'Wert mit: Doppelpunkt' ledger_scalar "$parse_file" title
expect_output "Kommentar hinter einem Wert zaehlt nicht zum Wert" patterned ledger_scalar "$parse_file" class
expect_output "Kommentar hinter einer leeren Liste stoert nicht" '' ledger_list "$parse_file" touches
expect_output "Inline-Liste liefert eine Zeile je Eintrag" '002
003' ledger_list "$parse_file" depends_on
expect_output "Blockliste liefert eine Zeile je Eintrag" './scripts/verify.sh
npm test' ledger_list "$parse_file" acceptance
expect_output "leeres Einzelfeld liefert einen leeren Wert" '' ledger_scalar "$parse_file" blocked_reason
expect_output "nur Ueberschriften der Ebene 1 aus dem Rumpf" '# Kontext
# Umfang' ledger_sections "$parse_file"
expect_failure "unbekanntes Feld liefert keinen Wert" ledger_scalar "$parse_file" features
expect_failure "ein Listenfeld ist kein Einzelwert" ledger_scalar "$parse_file" acceptance
assert_eq "ein Durchlauf liefert Frontmatter und Ueberschriften zusammen" 16 \
  "$(ledger_parse "$parse_file" | awk 'END { print NR }')"

new_project_fixture
broken_file="$fixture/docs/tasks/001.md"
printf '%s\n' 'kein Frontmatter' > "$broken_file"
expect_failure "Datei ohne Frontmatter wird abgewiesen" ledger_parse "$broken_file"
printf '%s\n' '---' 'id: 001' 'id: 002' '---' > "$broken_file"
expect_failure "doppeltes Feld wird abgewiesen" ledger_parse "$broken_file"
printf '%s\n' '---' 'id: 001' '  - verirrt' '---' > "$broken_file"
expect_failure "Listeneintrag ohne Listenfeld wird abgewiesen" ledger_parse "$broken_file"
printf '%s\n' '---' 'id: 001' > "$broken_file"
expect_failure "unabgeschlossenes Frontmatter wird abgewiesen" ledger_parse "$broken_file"

new_project_fixture
make_task --id 001
atomic_file="$fixture/docs/tasks/001.md"
expect_failure "atomare Aenderung wird vor Ersetzen abgebrochen" ledger_atomic_replace_scalar "$atomic_file" status in_progress false
assert_eq "Schreibabbruch bewahrt vorherige Datei" todo "$(ledger_scalar "$atomic_file" status)"

new_project_fixture
marker="$fixture/markdown-was-not-executed"
make_task --id 001 --title "\$(touch $marker)"
ledger_scalar "$fixture/docs/tasks/001.md" title >/dev/null
[ ! -e "$marker" ] && ok || bad "Markdown wird nicht als Shellcode ausgefuehrt"

new_project_fixture
{
  echo '# Notizen'
  echo
  printf '%0300d\n' 0
  echo '## N-0001 — Aktiv'
  echo '- tasks: [001]'
  echo '- source: worker'
  echo '- confidence: verified'
  echo '- status: active'
  echo '- evidence: test'
  echo '- finding: behalten'
  echo
  echo '## N-0002 — Verworfen'
  echo '- tasks: [001]'
  echo '- source: worker'
  echo '- confidence: rejected'
  echo '- status: active'
  echo '- evidence: test'
  echo '- finding: archivieren'
} > "$fixture/docs/state/notes.md"
active=$(ledger_active_notes "$fixture/docs/state/notes.md")
case "$active" in *N-0001*) ok ;; *) bad "aktive Notiz wird in Kontext uebernommen" ;; esac
case "$active" in *N-0002*) bad "rejected Notiz wird nicht als aktiver Fakt geliefert" ;; *) ok ;; esac

finish_suite
