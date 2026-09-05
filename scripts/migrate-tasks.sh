#!/usr/bin/env bash
# Erweitert Tasks des alten Schemas additiv. Unbekannte Felder bleiben erhalten.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
if [ "${1:-}" = --project-dir ]; then project_dir=$2; shift 2; fi
[ "$#" -eq 0 ] || { echo "Verwendung: $0 [--project-dir PFAD]" >&2; exit 2; }
. "$script_dir/agent/ledger.sh"

tasks_dir="$project_dir/docs/tasks"
validator="$project_dir/scripts/validate-ledger.sh"
[ -x "$validator" ] || validator="$script_dir/validate-ledger.sh"
config="$project_dir/.agent/config.env"
[ -f "$config" ] || config="$script_dir/../.agent/config.env"
config_reader="$project_dir/scripts/agent/config.sh"
[ -x "$config_reader" ] || config_reader="$script_dir/agent/config.sh"
max_attempts=$($config_reader --get MAX_TASK_ATTEMPTS "$config") || exit 1
migrated=0

has_key() {
  file=$1
  key=$2
  ledger_frontmatter_keys "$file" | grep -Fxq "$key"
}

files=$(ledger_task_files "$tasks_dir")
while IFS= read -r file; do
  [ -n "$file" ] || continue
  ledger_has_frontmatter "$file" || { echo "Migration abgebrochen: ungueltiges Frontmatter in $file" >&2; exit 1; }
  dir=$(dirname -- "$file")
  base=$(basename -- "$file")
  tmp=$(mktemp "$dir/.${base}.migration.XXXXXX") || exit 1
  additions=''
  has_key "$file" class || additions="${additions}class: patterned\n"
  has_key "$file" orchestration || additions="${additions}orchestration: auto\n"
  has_key "$file" fresh_perspective || additions="${additions}fresh_perspective: auto\n"
  has_key "$file" attempts || additions="${additions}attempts: 0\n"
  has_key "$file" max_attempts || additions="${additions}max_attempts: $max_attempts\n"
  has_key "$file" last_verification || additions="${additions}last_verification: never\n"
  has_key "$file" human_review || additions="${additions}human_review: false\n"
  has_key "$file" blocked_reason || additions="${additions}blocked_reason: \"\"\n"

  if [ -z "$additions" ]; then rm -f "$tmp"; continue; fi
  if ! awk -v additions="$additions" '
    NR == 1 { print; next }
    !closed && $0 == "---" { printf "%s", additions; closed=1; print; next }
    { print }
    END { if (!closed) exit 1 }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    echo "Migration abgebrochen: $file blieb unveraendert" >&2
    exit 1
  fi
  if ! "$validator" --project-dir "$project_dir" --task-file "$tmp" >/dev/null; then
    rm -f "$tmp"
    echo "Migration abgebrochen: Ergebnis fuer $file ist nicht gueltig; Original blieb erhalten" >&2
    exit 1
  fi
  agent_copy_mode "$file" "$tmp" || { rm -f "$tmp"; exit 1; }
  mv -f "$tmp" "$file"
  migrated=$((migrated + 1))
done <<EOF
$files
EOF

echo "migrate-tasks: GREEN ($migrated Dateien migriert)"
