#!/usr/bin/env bash
# Archiviert erledigte oder verworfene Notizen erst oberhalb der Groessenquote.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
max_chars=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir=$2; shift 2 ;;
    --max-chars) max_chars=$2; shift 2 ;;
    *) echo "Verwendung: $0 [--project-dir PFAD] [--max-chars N]" >&2; exit 2 ;;
  esac
done
. "$script_dir/agent/ledger.sh"

notes="$project_dir/docs/state/notes.md"
archive_dir="$project_dir/docs/state/notes-archive"
[ -f "$notes" ] || { echo "archive-notes: notes.md fehlt" >&2; exit 1; }
mkdir -p "$archive_dir"
if [ -z "$max_chars" ]; then
  config="$project_dir/.agent/config.env"
  [ -f "$config" ] || config="$script_dir/../.agent/config.env"
  config_reader="$project_dir/scripts/agent/config.sh"
  [ -x "$config_reader" ] || config_reader="$script_dir/agent/config.sh"
  max_chars=$($config_reader --get NOTES_MAX_CHARS "$config") || exit 1
fi
case "$max_chars" in ''|*[!0-9]*|0) echo "archive-notes: ungueltige Groessenquote" >&2; exit 1 ;; esac

size=$(wc -c < "$notes" | tr -d ' ')
if [ "$size" -le "$max_chars" ]; then
  echo "archive-notes: keine Archivierung noetig ($size/$max_chars Zeichen)"
  exit 0
fi

notes_dir=$(dirname -- "$notes")
notes_tmp=$(mktemp "$notes_dir/.notes.md.tmp.XXXXXX") || exit 1
archive_tmp=$(mktemp "$archive_dir/.archive.tmp.XXXXXX") || { rm -f "$notes_tmp"; exit 1; }
trap 'rm -f "$notes_tmp" "$archive_tmp"' EXIT HUP INT TERM

split_notes() {
  mode=$1
  awk -v mode="$mode" '
    function eligible() { return confidence == "rejected" || status == "resolved" }
    function flush() {
      if (block == "") return
      if ((mode == "archive" && eligible()) || (mode == "keep" && !eligible())) printf "%s", block
      block=""; confidence=""; status=""
    }
    /^## N-[0-9]+[[:space:]]/ { flush(); block=$0 ORS; next }
    block == "" { if (mode == "keep") print; next }
    {
      block=block $0 ORS
      if ($0 ~ /^- confidence:[[:space:]]*/) { confidence=$0; sub(/^.*:[[:space:]]*/, "", confidence) }
      if ($0 ~ /^- status:[[:space:]]*/) { status=$0; sub(/^.*:[[:space:]]*/, "", status) }
    }
    END { flush() }
  ' "$notes"
}

split_notes keep > "$notes_tmp"
{
  echo "# Notizarchiv"
  echo
  echo "Archiviert: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  split_notes archive
} > "$archive_tmp"

if ! grep -q '^## N-' "$archive_tmp"; then
  echo "archive-notes: Quote ueberschritten, aber keine erledigte oder verworfene Notiz archivierbar"
  exit 0
fi
grep -Fqx '# Notizen' "$notes_tmp" || { echo "archive-notes: neuer Notizstand waere ungueltig" >&2; exit 1; }
agent_copy_mode "$notes" "$notes_tmp" || exit 1
archive_file="$archive_dir/$(date -u +%Y%m%dT%H%M%SZ)-notes.md"
mv -f "$archive_tmp" "$archive_file"
mv -f "$notes_tmp" "$notes"
trap - EXIT HUP INT TERM
echo "archive-notes: GREEN ($(basename "$archive_file"))"
