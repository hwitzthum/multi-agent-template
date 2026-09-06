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
