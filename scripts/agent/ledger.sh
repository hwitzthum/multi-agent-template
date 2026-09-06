#!/usr/bin/env bash
# Sichere Lese- und Schreibprimitive fuer das Markdown-Ledger.
# Diese Datei wird von anderen Skripten eingebunden. Markdown wird niemals als
# Shellcode ausgewertet; insbesondere werden weder source noch eval verwendet.
set -uo pipefail

. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Trennzeichen der Parserausgabe. Als Variable, damit `read` ohne Umweg damit
# arbeiten kann.
ledger_tab=$'\t'
ledger_newline=$'\n'

ledger_error() {
  echo "ledger: $1" >&2
  return 1
}

# ledger_parse DATEI [FELD]
#
# Liest eine Ledger-Datei in genau einem awk-Durchlauf. Ohne FELD steht je Wert
# eine Zeile "<schluessel><TAB><wert>" auf der Standardausgabe; mit FELD nur die
# Werte dieses Feldes, ohne Schluessel und ohne Tabulator.
#
# Ein skalares Feld liefert genau eine Zeile. Ein Listenfeld liefert eine Zeile
# je Eintrag, eine leere Liste genau eine Zeile mit leerem Wert. Ueberschriften
# der Ebene 1 im Rumpf erscheinen unter dem Schluessel `#`; als Feldname ist er
# ausgeschlossen, weil Schluessel mit einem Buchstaben beginnen muessen.
#
# Rueckgabe: 0 bei gueltigem Frontmatter, 1 bei fehlendem oder unzulaessigem
# Frontmatter (mit Meldung auf der Standardfehlerausgabe), 4 wenn FELD gesetzt
# ist und die Datei dieses Feld nicht kennt.
ledger_parse() {
  file=$1
  want=${2:-}
  [ -f "$file" ] || { ledger_error "Datei fehlt oder ist keine Datei: $file"; return 1; }
  awk -v want="$want" -v label="$file" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    # Entfernt aeussere Anfuehrungszeichen; ohne sie gilt ein freistehendes
    # "#" als Kommentarbeginn. Der Inhalt bleibt in jedem Fall reiner Text.
    function unquote(value, first) {
      value = trim(value)
      first = substr(value, 1, 1)
      if (length(value) >= 2 && (first == "\"" || first == "\047") && substr(value, length(value), 1) == first) {
        return substr(value, 2, length(value) - 2)
      }
      sub(/[[:space:]]#.*$/, "", value)
      return trim(value)
    }
    function fail(message) {
      print "ledger: " label ": " message > "/dev/stderr"
      bad = 1
    }
    function emit(key, value) {
      if (want == "") { print key "\t" value; return }
      if (key != want) return
      found = 1
      print value
    }
    # Ein Listenfeld ohne Eintraege bleibt sichtbar: es liefert einen leeren Wert.
    function close_list() {
      if (open_list != "" && open_items == 0) emit(open_list, "")
      open_list = ""
      open_items = 0
    }
    BEGIN { state = 0; bad = 0; found = 0; open_list = ""; open_items = 0 }
    NR == 1 {
      if ($0 != "---") { fail("Frontmatter fehlt"); exit 1 }
      state = 1
      next
    }
    state == 1 && $0 == "---" { close_list(); state = 2; next }
    state == 1 {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) next
      if ($0 ~ /^[[:space:]]+-[[:space:]]/) {
        if (open_list == "") { fail("Listeneintrag ohne Listenfeld"); next }
        item = $0
        sub(/^[[:space:]]+-[[:space:]]+/, "", item)
        item = unquote(item)
        if (item != "") { emit(open_list, item); open_items++ }
        next
      }
      if ($0 !~ /^[A-Za-z_][A-Za-z0-9_-]*:/) { fail("unbekannte Frontmatter-Form: " $0); next }
      close_list()
      key = $0
      sub(/:.*/, "", key)
      if (key in seen) { fail("doppeltes Frontmatter-Feld: " key); next }
      seen[key] = 1
      value = trim(substr($0, length(key) + 2))
      if (value ~ /[{}]/ || value ~ /^[>|&*!]/) { fail("nicht unterstuetzte YAML-Form bei " key); next }
      if (value == "") { open_list = key; open_items = 0; next }
      if (substr(value, 1, 1) == "[") {
        closing = index(value, "]")
        if (closing == 0) { fail("unvollstaendige Liste bei " key); next }
        rest = trim(substr(value, closing + 1))
        if (rest != "" && substr(rest, 1, 1) != "#") { fail("Text nach der Liste bei " key); next }
        count = split(substr(value, 2, closing - 2), parts, ",")
        emitted = 0
        for (i = 1; i <= count; i++) {
          item = unquote(parts[i])
          if (item != "") { emit(key, item); emitted++ }
        }
        if (emitted == 0) emit(key, "")
        next
      }
      emit(key, unquote(value))
      next
    }
    state == 2 && /^# / { emit("#", $0) }
    END {
      if (state != 2) { print "ledger: " label ": Frontmatter fehlt oder ist unvollstaendig" > "/dev/stderr"; exit 1 }
      if (bad) exit 1
      if (want != "" && !found) exit 4
    }
  ' "$file"
}

ledger_scalar() {
  file=$1
  key=$2
  value=$(ledger_parse "$file" "$key") || { ledger_error "Feld $key fehlt oder ist unlesbar in $file"; return 1; }
  case "$value" in
    *"$ledger_newline"*) ledger_error "Feld $key traegt mehrere Werte in $file"; return 1 ;;
  esac
  printf '%s\n' "$value"
}

ledger_list() {
  file=$1
  key=$2
  ledger_parse "$file" "$key" | grep -v '^$'
  # grep liefert 1, wenn die Liste leer ist; das ist kein Fehler.
  [ "${PIPESTATUS[0]}" -eq 0 ]
}

# Die Ueberschriften der Ebene 1 im Rumpf, eine je Zeile.
ledger_sections() {
  ledger_parse "$1" '#'
  case "$?" in 0|4) return 0 ;; *) return 1 ;; esac
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
      front && /^(status|attempts|blocked_reason):/ {
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

# Der Pruefbeleg eines Tasks ist genau eine Datei: docs/verification/<id>.md.
# Ohne Projekt und Task-Datei zaehlt nur das gruene Ergebnis; mit beiden muss
# der Bericht zusaetzlich zum aktuellen Kandidaten- und Verifierstand passen.
ledger_verification_is_green() {
  verification_dir=$1
  wanted=$2
  project_dir=${3:-}
  task_file=${4:-}
  report="$verification_dir/$wanted.md"
  [ -f "$report" ] || return 1
  report_task=''; report_result=''; report_candidate=''; report_verifier=''
  while IFS="$ledger_tab" read -r report_key report_value; do
    case "$report_key" in
      task_id) report_task=$report_value ;;
      result) report_result=$report_value ;;
      candidate_fingerprint) report_candidate=$report_value ;;
      verifier_version) report_verifier=$report_value ;;
    esac
  done <<EOF
$(ledger_parse "$report" 2>/dev/null)
EOF
  [ "$report_task" = "$wanted" ] || return 1
  [ "$report_result" = green ] || return 1
  [ -n "$project_dir" ] && [ -n "$task_file" ] || return 0
  current_candidate=$(ledger_candidate_fingerprint "$project_dir" "$task_file") || return 1
  current_verifier=$(ledger_verifier_fingerprint "$project_dir") || return 1
  [ "$report_candidate" = "$current_candidate" ] || return 1
  [ "$report_verifier" = "$current_verifier" ] || return 1
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

# Ein Schnappschuss der Steuerfelder aller Tasks, eine Zeile je Task:
# "<id>|<status>|<attempts>|<blocked_reason>". Vor und nach einem Rollenaufruf
# gebildet beweist er, dass die Rolle die Steuerung nicht angefasst hat.
ledger_control_snapshot() {
  : > "$2"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    printf '%s|%s|%s|%s\n' "$(ledger_scalar "$file" id)" "$(ledger_scalar "$file" status)" \
      "$(ledger_scalar "$file" attempts)" "$(ledger_scalar "$file" blocked_reason)" >> "$2"
  done <<EOF
$(ledger_task_files "$1")
EOF
}

# Liegt ein Pfad im `touches`-Umfang eines Tasks? Ein Task ohne `touches`
# begrenzt nichts und laesst jeden Pfad zu.
ledger_path_in_touches() {
  ledger_touches=$(ledger_list "$1" touches 2>/dev/null || true)
  [ -n "$ledger_touches" ] || return 0
  while IFS= read -r allowed; do
    [ -n "$allowed" ] || continue
    allowed=${allowed%/}
    case "$2" in "$allowed"|"$allowed"/*) return 0 ;; esac
  done <<EOF
$ledger_touches
EOF
  return 1
}

# Haengt eine Notiz im Schema von notes.md an: ledger_append_note DATEI TASK
# TITEL BEFUND BELEG. Dieselbe Erkenntnis wird nicht zweimal geschrieben.
ledger_append_note() {
  notes=$1
  grep -Fq -- "- finding: $4" "$notes" && return 0
  lock="$(dirname -- "$notes")/.notes-write-lock"
  mkdir "$lock" 2>/dev/null || { ledger_error "Notes werden bereits geschrieben"; return 1; }
  temp=$(mktemp "$(dirname -- "$notes")/.notes.tmp.XXXXXX") || { rmdir "$lock"; return 1; }
  cp "$notes" "$temp" || { rm -f "$temp"; rmdir "$lock"; return 1; }
  next=$(awk '/^## N-[0-9]+[[:space:]]/ { id=$2; sub(/^N-/,"",id); if (id+0>max) max=id+0 } END { printf "%04d", max+1 }' "$notes")
  {
    echo
    echo "## N-$next — $3"
    echo "- tasks: [$2]"
    echo "- date: $(date -u +%Y-%m-%d)"
    echo '- source: orchestrator'
    echo '- confidence: observed'
    echo '- status: active'
    echo "- evidence: $5"
    echo "- finding: $4"
  } >> "$temp"
  agent_atomic_write "$notes" "$temp" || { rm -f "$temp"; rmdir "$lock"; return 1; }
  rm -f "$temp"
  rmdir "$lock" 2>/dev/null || true
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
    parse) [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2; ledger_parse "$2" "${3:-}" ;;
    scalar) [ "$#" -eq 3 ] || exit 2; ledger_scalar "$2" "$3" ;;
    list) [ "$#" -eq 3 ] || exit 2; ledger_list "$2" "$3" ;;
    active-notes) [ "$#" -eq 2 ] || exit 2; ledger_active_notes "$2" ;;
    *) echo "Verwendung: $0 parse DATEI [FELD] | scalar DATEI FELD | list DATEI FELD | active-notes DATEI" >&2; exit 2 ;;
  esac
fi
