#!/usr/bin/env bash
# Sichere Lese- und Schreibprimitive fuer das Markdown-Ledger.
# Diese Datei wird von anderen Skripten eingebunden. Markdown wird niemals als
# Shellcode ausgewertet; insbesondere werden weder source noch eval verwendet.
set -uo pipefail

. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ledger_error() {
  echo "ledger: $1" >&2
  return 1
}

ledger_known_scalar() {
  case "$1" in
    id|title|status|class|orchestration|attempts|max_attempts|last_verification|human_review|blocked_reason|run_id|task_id|attempt|result|candidate_fingerprint|verifier_version|failure_kind) return 0 ;;
    *) return 1 ;;
  esac
}

ledger_known_list() {
  case "$1" in
    depends_on|features|acceptance|touches|risk_flags) return 0 ;;
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

ledger_task_files() {
  tasks_dir=$1
  find "$tasks_dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort
}

# Der Dateiname ist die Task-ID; der Validator erzwingt das. Damit ist der
# Lookup ein Dateitest statt eines Durchlaufs durch alle Tasks.
ledger_task_path_by_id() {
  tasks_dir=$1
  wanted=$2
  case "$wanted" in ''|*[!0-9]*) ledger_error "Task-ID muss aus Ziffern bestehen: $wanted"; return 1 ;; esac
  [ -f "$tasks_dir/$wanted.md" ] || { ledger_error "Task $wanted wurde nicht gefunden"; return 1; }
  printf '%s\n' "$tasks_dir/$wanted.md"
}

ledger_candidate_fingerprint() {
  project_dir=$1
  task_file=$2
  [ -d "$project_dir" ] && [ -f "$task_file" ] || return 1
  project_dir=$(CDPATH= cd -- "$project_dir" && pwd -P) || return 1
  case "$task_file" in
    /*) ;;
    *) task_file="$project_dir/$task_file" ;;
  esac
  task_file=$(CDPATH= cd -- "$(dirname -- "$task_file")" && printf '%s/%s\n' "$PWD" "$(basename -- "$task_file")") || return 1
  fingerprint_task_id=$(ledger_scalar "$task_file" id 2>/dev/null) || return 1
  manifest=$(mktemp "${TMPDIR:-/tmp}/agent-candidate.XXXXXX") || return 1
  agent_manifest_build "$project_dir" "$manifest" agent_manifest_include_candidate || { rm -f "$manifest"; return 1; }
  (
    cat "$manifest"
    awk '
      BEGIN { front=0 }
      NR == 1 && $0 == "---" { front=1; print; next }
      front && $0 == "---" { front=0; print; next }
      front && /^(status|attempts|last_verification|blocked_reason):/ {
        key=$0; sub(/:.*/, "", key); print key ": <mutable>"; next
      }
      { print }
    ' "$task_file" | shasum -a 256 | awk -v name="docs/tasks/$fingerprint_task_id.md" '{ print $1 "  " name }'
  ) | shasum -a 256 | awk '{print $1}'
  fingerprint_status=$?
  rm -f "$manifest"
  return "$fingerprint_status"
}

ledger_verifier_fingerprint() {
  project_dir=$1
  [ -d "$project_dir" ] || return 1
  project_dir=$(CDPATH= cd -- "$project_dir" && pwd -P) || return 1
  library_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P) || return 1
  if [ -f "$project_dir/scripts/verify-task.sh" ]; then implementation_root=$project_dir; else implementation_root=$library_root; fi
  {
    for relative in scripts/verify-task.sh scripts/validate-ledger.sh scripts/agent/ledger.sh scripts/agent/status.sh scripts/agent/common.sh; do
      [ -f "$implementation_root/$relative" ] && printf '%s\n' "$implementation_root/$relative"
    done
    [ -f "$project_dir/scripts/verify.sh" ] && printf '%s\n' "$project_dir/scripts/verify.sh"
    [ -f "$project_dir/.agent/config.env" ] && printf '%s\n' "$project_dir/.agent/config.env"
    [ -f "$project_dir/.agent/verification-allowlist" ] && printf '%s\n' "$project_dir/.agent/verification-allowlist"
    [ -f "$project_dir/.agent/verification-runners" ] && printf '%s\n' "$project_dir/.agent/verification-runners"
    true
  } | LC_ALL=C sort -u | while IFS= read -r file; do
    case "$file" in
      "$implementation_root"/*) label="implementation/${file#"$implementation_root"/}" ;;
      "$project_dir"/*) label="project/${file#"$project_dir"/}" ;;
      *) label=$(basename -- "$file") ;;
    esac
    printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "$label"
  done | shasum -a 256 | awk '{print $1}'
}

ledger_verification_is_green() {
  verification_dir=$1
  wanted=$2
  [ -d "$verification_dir" ] || return 1
  project_dir=${3:-}
  task_file=${4:-}
  strict=false
  if [ -n "$project_dir" ] && [ -n "$task_file" ]; then strict=true; fi
  if [ "$strict" = true ]; then
    reports=$(printf '%s\n' "$verification_dir/latest.md"; find "$verification_dir/history" -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort -r)
    current_candidate=$(ledger_candidate_fingerprint "$project_dir" "$task_file") || return 1
    current_verifier=$(ledger_verifier_fingerprint "$project_dir") || return 1
  else
    reports=$(find "$verification_dir" -type f -name '*.md' -print 2>/dev/null)
  fi
  while IFS= read -r report; do
    [ -n "$report" ] || continue
    report_task=$(ledger_scalar "$report" task_id 2>/dev/null) || continue
    [ "$report_task" = "$wanted" ] || continue
    report_result=$(ledger_scalar "$report" result 2>/dev/null) || { [ "$strict" = true ] && return 1; continue; }
    [ "$report_result" = green ] || { [ "$strict" = true ] && return 1; continue; }
    if [ "$strict" = true ]; then
      report_candidate=$(ledger_scalar "$report" candidate_fingerprint 2>/dev/null) || return 1
      report_verifier=$(ledger_scalar "$report" verifier_version 2>/dev/null) || return 1
      [ "$report_candidate" = "$current_candidate" ] || return 1
      [ "$report_verifier" = "$current_verifier" ] || return 1
    fi
    return 0
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
  agent_copy_mode "$file" "$tmp" || { rm -f "$tmp"; trap - HUP INT TERM; return 1; }
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
