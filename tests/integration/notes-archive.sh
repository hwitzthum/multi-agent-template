#!/usr/bin/env bash
# Oberhalb der Größenquote wandern verworfene Notizen ins Archiv, aktive bleiben.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

archiver="$project_dir/scripts/archive-notes.sh"

begin_suite notes-archive
fixture_workspace

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

expect_success "Notizarchivierung" "$archiver" --project-dir "$fixture" --max-chars 100
grep -q 'N-0001' "$fixture/docs/state/notes.md" && ! grep -q 'N-0002' "$fixture/docs/state/notes.md" \
  && ok || bad "Archivierung behaelt aktive relevante Notiz"
grep -q 'N-0002' "$fixture/docs/state/notes-archive/"*.md && ok || bad "Archivierung verschiebt verworfene Notiz"

finish_suite
