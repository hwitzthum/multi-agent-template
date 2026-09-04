#!/usr/bin/env bash
# Sichere Lese- und Schreibprimitive fuer das Markdown-Ledger.
# Diese Datei wird von anderen Skripten eingebunden. Markdown wird niemals als
# Shellcode ausgewertet; insbesondere werden weder source noch eval verwendet.
set -uo pipefail

ledger_error() {
  echo "ledger: $1" >&2
  return 1
}

ledger_known_scalar() {
  case "$1" in
    id|title|status|class|orchestration|fresh_perspective|attempts|max_attempts|last_verification|human_review|blocked_reason|run_id|task_id|mode|phase|iteration|attempt|last_progress_fingerprint|started_at|result|finished_at|date|source|confidence|evidence|finding) return 0 ;;
    *) return 1 ;;
  esac
}

ledger_known_list() {
  case "$1" in
    depends_on|features|acceptance|tasks) return 0 ;;
    *) return 1 ;;
  esac
}

ledger_has_frontmatter() {
  file=$1
  [ -f "$file" ] || return 1
  awk '
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && $0 == "---" { found=1; exit }
    END { if (!found) exit 1 }
  ' "$file"
}

ledger_frontmatter() {
  file=$1
  ledger_has_frontmatter "$file" || { ledger_error "Frontmatter fehlt oder ist unvollstaendig: $file"; return 1; }
  awk 'NR == 1 { next } $0 == "---" { exit } { print }' "$file"
}

ledger_unquote() {
  value=$1
  value=$(printf '%s\n' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$value" in
    \"*\") value=${value#\"}; value=${value%\"} ;;
    \'*\') value=${value#\'}; value=${value%\'} ;;
    *) value=$(printf '%s\n' "$value" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
  esac
  printf '%s\n' "$value"
}

ledger_scalar() {
  file=$1
  key=$2
  ledger_known_scalar "$key" || { ledger_error "unbekanntes Einzelfeld: $key"; return 2; }
  raw=$(ledger_frontmatter "$file" | awk -v wanted="$key" '
    index($0, wanted ":") == 1 {
      if (found) exit 3
      found=1
      print substr($0, length(wanted) + 2)
    }
    END { if (!found) exit 4 }
  ') || { ledger_error "Feld $key fehlt oder ist doppelt in $file"; return 1; }
  ledger_unquote "$raw"
}

ledger_list() {
  file=$1
  key=$2
  ledger_known_list "$key" || { ledger_error "unbekanntes Listenfeld: $key"; return 2; }
  ledger_frontmatter "$file" | awk -v wanted="$key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function emit(value) {
      value=trim(value)
      if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
        value=substr(value, 2, length(value)-2)
      }
      if (value != "") print value
    }
    BEGIN { state=0; found=0 }
    index($0, wanted ":") == 1 {
      if (found) exit 3
      found=1
      value=trim(substr($0, length(wanted) + 2))
      if (value == "") { state=1; next }
      if (value !~ /^\[.*\]$/) exit 4
      value=substr(value, 2, length(value)-2)
      count=split(value, parts, ",")
      for (i=1; i<=count; i++) emit(parts[i])
      state=2
      next
    }
    state == 1 && $0 ~ /^[[:space:]]+-[[:space:]]+/ {
      value=$0
      sub(/^[[:space:]]+-[[:space:]]+/, "", value)
      emit(value)
      next
    }
    state == 1 { state=2 }
    END { if (!found) exit 5 }
  '
}

ledger_frontmatter_keys() {
  file=$1
  ledger_frontmatter "$file" | awk '
    /^[A-Za-z_][A-Za-z0-9_-]*:/ {
      key=$0
      sub(/:.*/, "", key)
      print key
    }
  '
}

ledger_validate_frontmatter_shape() {
  file=$1
  ledger_has_frontmatter "$file" || return 1
  ledger_frontmatter "$file" | awk '
    function fail(message) { print message > "/dev/stderr"; bad=1 }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    /^[A-Za-z_][A-Za-z0-9_-]*:/ {
      key=$0
      sub(/:.*/, "", key)
      if (seen[key]++) fail("doppeltes Frontmatter-Feld: " key)
      value=substr($0, length(key)+2)
      sub(/^[[:space:]]*/, "", value)
      list_open=(value == "")
      if (value ~ /[{}]|^[>|&*!]/) fail("nicht unterstuetzte YAML-Form bei " key)
      next
    }
    /^[[:space:]]+-[[:space:]]+/ {
      if (!list_open) fail("Listeneintrag ohne Listenfeld")
      next
    }
    { fail("unbekannte Frontmatter-Form: " $0) }
    END { exit bad ? 1 : 0 }
  '
}

ledger_markdown_has_section() {
  file=$1
  heading=$2
  grep -Fqx "$heading" "$file"
}

ledger_copy_mode() {
  source_file=$1
  target_file=$2
  mode=$(stat -f '%Lp' "$source_file" 2>/dev/null || stat -c '%a' "$source_file" 2>/dev/null) || return 0
  chmod "$mode" "$target_file"
}

ledger_task_files() {
  tasks_dir=$1
  find "$tasks_dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort
}

ledger_task_path_by_id() {
  tasks_dir=$1
  wanted=$2
  found=''
  while IFS= read -r candidate; do
    candidate_id=$(ledger_scalar "$candidate" id 2>/dev/null) || continue
    if [ "$candidate_id" = "$wanted" ]; then
      [ -z "$found" ] || { ledger_error "Task-ID $wanted ist nicht eindeutig"; return 1; }
      found=$candidate
    fi
  done <<EOF
$(ledger_task_files "$tasks_dir")
EOF
  [ -n "$found" ] || { ledger_error "Task $wanted wurde nicht gefunden"; return 1; }
  printf '%s\n' "$found"
}

ledger_verification_is_green() {
  verification_dir=$1
  wanted=$2
  [ -d "$verification_dir" ] || return 1
  reports=$(find "$verification_dir" -type f -name '*.md' -print 2>/dev/null)
  while IFS= read -r report; do
    [ -n "$report" ] || continue
    report_task=$(ledger_scalar "$report" task_id 2>/dev/null) || continue
    report_result=$(ledger_scalar "$report" result 2>/dev/null) || continue
    if [ "$report_task" = "$wanted" ] && [ "$report_result" = green ]; then
      return 0
    fi
  done <<EOF
$reports
EOF
  return 1
}

ledger_active_notes() {
  file=$1
  awk '
    function flush() {
      if (block == "") return
      if (confidence != "rejected" && status == "active") printf "%s", block
      block=""; confidence=""; status=""
    }
    /^## N-[0-9]+[[:space:]]/ { flush(); block=$0 ORS; next }
    block != "" {
      block=block $0 ORS
      if ($0 ~ /^- confidence:[[:space:]]*/) { confidence=$0; sub(/^.*:[[:space:]]*/, "", confidence) }
      if ($0 ~ /^- status:[[:space:]]*/) { status=$0; sub(/^.*:[[:space:]]*/, "", status) }
    }
    END { flush() }
  ' "$file"
}

ledger_atomic_replace_scalar() {
  file=$1
  key=$2
  value=$3
  shift 3
  dir=$(dirname -- "$file")
  base=$(basename -- "$file")
  tmp=$(mktemp "$dir/.${base}.tmp.XXXXXX") || return 1
  trap 'rm -f "$tmp"' HUP INT TERM
  if ! awk -v wanted="$key" -v replacement="$value" '
    BEGIN { count=0; front=0 }
    NR == 1 && $0 == "---" { front=1; print; next }
    front && $0 == "---" { front=0; print; next }
    front && index($0, wanted ":") == 1 {
      print wanted ": " replacement
      count++
      next
    }
    { print }
    END { if (count != 1) exit 1 }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    trap - HUP INT TERM
    ledger_error "Feld $key konnte nicht eindeutig ersetzt werden"
    return 1
  fi
  if [ "$#" -gt 0 ] && ! "$@" "$tmp"; then
    rm -f "$tmp"
    trap - HUP INT TERM
    ledger_error "Aenderung an $file wurde vor dem Ersetzen abgewiesen"
    return 1
  fi
  ledger_copy_mode "$file" "$tmp" || { rm -f "$tmp"; trap - HUP INT TERM; return 1; }
  mv -f "$tmp" "$file"
  trap - HUP INT TERM
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    scalar) [ "$#" -eq 3 ] || exit 2; ledger_scalar "$2" "$3" ;;
    list) [ "$#" -eq 3 ] || exit 2; ledger_list "$2" "$3" ;;
    active-notes) [ "$#" -eq 2 ] || exit 2; ledger_active_notes "$2" ;;
    *) echo "Verwendung: $0 scalar DATEI FELD | list DATEI FELD | active-notes DATEI" >&2; exit 2 ;;
  esac
fi
