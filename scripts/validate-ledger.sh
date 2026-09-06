#!/usr/bin/env bash
# Validiert Task-Graph, Ledger-Dateien und Status-/Pruefbeziehungen.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
. "$script_dir/agent/ledger.sh"

only_task=''
case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [--project-dir PFAD] [--task-file DATEI]"
    echo "Validiert Task-Graph, Ledger-Schema und Status-/Prüfbeziehungen."
    exit 0 ;;
esac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir=$2; shift 2 ;;
    --task-file) only_task=$2; shift 2 ;;
    *) echo "validate-ledger: unbekannte Option $1" >&2; exit 2 ;;
  esac
done

tasks_dir="$project_dir/docs/tasks"
state_dir="$project_dir/docs/state"
verification_dir="$project_dir/docs/verification"
errors=0
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/ledger-validation.XXXXXX") || exit 1
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
ids_file="$work_dir/ids"
graph_file="$work_dir/graph"
active_file="$work_dir/active"
: > "$ids_file"
: > "$graph_file"
: > "$active_file"

problem() {
  echo "Ledger ungueltig: $1" >&2
  errors=$((errors + 1))
}

one_of() {
  value=$1
  shift
  for allowed in "$@"; do [ "$value" = "$allowed" ] && return 0; done
  return 1
}

required_list() {
  file=$1
  key=$2
  ledger_list "$file" "$key" >/dev/null 2>&1 || { problem "$(basename "$file"): Pflichtliste '$key' fehlt oder ist ungueltig"; return 1; }
}

validate_task() {
  file=$1
  # Zweites Argument: der Name, unter dem der Task im Ledger liegt. Leer bei
  # einer Kandidatendatei, die noch unter einem Temporaernamen geprueft wird.
  expected_name=${2:-}
  label=$(basename "$file")
  ledger_validate_frontmatter_shape "$file" >/dev/null 2>&1 || problem "$label: Frontmatter verwendet eine unzulaessige oder doppelte Form"

  id=$(ledger_scalar "$file" id 2>/dev/null) || { problem "$label: Pflichtfeld 'id' fehlt oder ist doppelt"; id=''; }
  title=$(ledger_scalar "$file" title 2>/dev/null) || { problem "$label: Pflichtfeld 'title' fehlt oder ist doppelt"; title=''; }
  status=$(ledger_scalar "$file" status 2>/dev/null) || { problem "$label: Pflichtfeld 'status' fehlt oder ist doppelt"; status=''; }
  class=$(ledger_scalar "$file" class 2>/dev/null) || { problem "$label: Pflichtfeld 'class' fehlt oder ist doppelt"; class=''; }
  orchestration=$(ledger_scalar "$file" orchestration 2>/dev/null) || { problem "$label: Pflichtfeld 'orchestration' fehlt oder ist doppelt"; orchestration=''; }
  attempts=$(ledger_scalar "$file" attempts 2>/dev/null) || { problem "$label: Pflichtfeld 'attempts' fehlt oder ist doppelt"; attempts=''; }
  max_attempts=$(ledger_scalar "$file" max_attempts 2>/dev/null) || { problem "$label: Pflichtfeld 'max_attempts' fehlt oder ist doppelt"; max_attempts=''; }
  verification=$(ledger_scalar "$file" last_verification 2>/dev/null) || { problem "$label: Pflichtfeld 'last_verification' fehlt oder ist doppelt"; verification=''; }
  human_review=$(ledger_scalar "$file" human_review 2>/dev/null) || { problem "$label: Pflichtfeld 'human_review' fehlt oder ist doppelt"; human_review=''; }
  ledger_scalar "$file" blocked_reason >/dev/null 2>&1 || problem "$label: Pflichtfeld 'blocked_reason' fehlt oder ist doppelt"
  required_list "$file" depends_on || true
  required_list "$file" features || true
  required_list "$file" acceptance || true
  if ledger_frontmatter_keys "$file" | grep -Fxq touches; then
    ledger_list "$file" touches >/dev/null 2>&1 || problem "$label: touches muss eine einfache Liste sein"
  fi
  if ledger_frontmatter_keys "$file" | grep -Fxq risk_flags; then
    if flags=$(ledger_list "$file" risk_flags 2>/dev/null); then
      while IFS= read -r flag; do
        [ -n "$flag" ] || continue
        one_of "$flag" high-risk cross-component repeated-failure || problem "$label: unbekanntes risk_flag '$flag'"
      done <<EOF
$flags
EOF
    else
      problem "$label: risk_flags muss eine einfache Liste sein"
    fi
  fi

  case "$id" in ''|*[!0-9]*) problem "$label: id muss nur aus Ziffern bestehen" ;; esac
  # Der Dateiname ist der Schluessel: nur so bleibt der Lookup ein Dateitest.
  [ -z "$id" ] || [ -z "$expected_name" ] || [ "$expected_name" = "$id.md" ] || problem "$expected_name: Dateiname muss $id.md heissen"
  [ -n "$title" ] || problem "$label: title darf nicht leer sein"
  one_of "$status" todo in_progress review done blocked || problem "$label: unbekannter status '$status'"
  one_of "$class" mechanical patterned open || problem "$label: unbekannte class '$class'"
  one_of "$orchestration" auto single verified managed || problem "$label: unbekannte orchestration '$orchestration'"
  one_of "$verification" never green red || problem "$label: unbekannte last_verification '$verification'"
  one_of "$human_review" true false || problem "$label: human_review muss true oder false sein"
  case "$attempts" in ''|*[!0-9]*) problem "$label: attempts muss eine nichtnegative ganze Zahl sein" ;; esac
  case "$max_attempts" in ''|*[!0-9]*|0) problem "$label: max_attempts muss eine positive ganze Zahl sein" ;; esac
  if case "$attempts:$max_attempts" in *[!0-9:]*) false ;; *) true ;; esac; then
    [ "$attempts" -le "$max_attempts" ] || problem "$label: attempts ($attempts) ist groesser als max_attempts ($max_attempts)"
  fi

  for heading in '# Kontext' '# Umfang' '# Nicht Teil dieser Aufgabe' '# Akzeptanzkriterien (über die acceptance-Befehle hinaus)'; do
    ledger_markdown_has_section "$file" "$heading" || problem "$label: Pflichtabschnitt '$heading' fehlt"
  done

  if [ "$status" = blocked ]; then
    reason=$(ledger_scalar "$file" blocked_reason 2>/dev/null || true)
    [ -n "$reason" ] || problem "$label: blocked benoetigt einen blocked_reason"
  fi
  if [ "$status" = done ]; then
    [ "$verification" = green ] || problem "$label: done ist nur mit last_verification: green erlaubt"
    # Der strikte Fingerprint-Vergleich gehoert an den Statusuebergang (status.sh).
    # Nach dem Uebergang aendern spaetere Tasks das Produkt; ein erledigter Task
    # bleibt gueltig, solange ein gruener Bericht fuer ihn existiert.
    ledger_verification_is_green "$verification_dir" "$id" || problem "$label: passender gruener Pruefbericht fehlt"
  fi

  if [ -n "$id" ]; then
    printf '%s\n' "$id" >> "$ids_file"
    [ "$status" != in_progress ] || printf '%s\n' "$id" >> "$active_file"
    deps=$(ledger_list "$file" depends_on 2>/dev/null | tr '\n' ' ' || true)
    printf '%s|%s\n' "$id" "$deps" >> "$graph_file"
  fi
}

validate_task_set() {
  files=$(ledger_task_files "$tasks_dir")
  while IFS= read -r file; do
    [ -n "$file" ] && validate_task "$file" "$(basename "$file")"
  done <<EOF
$files
EOF

  duplicates=$(LC_ALL=C sort "$ids_file" | uniq -d)
  [ -z "$duplicates" ] || problem "Task-IDs sind nicht eindeutig: $(printf '%s' "$duplicates" | tr '\n' ' ')"

  # Ein Orchestrator bearbeitet genau einen Task. Mehr als ein `in_progress`
  # bedeutet einen abgebrochenen Lauf oder einen Schreibfehler von Hand.
  active_count=$(awk 'END { print NR+0 }' "$work_dir/active")
  [ "$active_count" -le 1 ] || problem "mehr als ein Task ist in_progress"

  while IFS='|' read -r id deps; do
    for dep in $deps; do
      case "$dep" in ''|*[!0-9]*) problem "Task $id: ungueltige Abhaengigkeit '$dep'"; continue ;; esac
      [ "$dep" != "$id" ] || { problem "Task $id darf nicht von sich selbst abhaengen"; continue; }
      grep -Fxq "$dep" "$ids_file" || problem "Task $id verweist auf fehlende Abhaengigkeit $dep"
    done
  done < "$graph_file"

  cp "$graph_file" "$work_dir/remaining"
  while [ -s "$work_dir/remaining" ]; do
    removable=''
    while IFS='|' read -r id deps; do
      ready=true
      for dep in $deps; do
        grep -q "^${dep}|" "$work_dir/remaining" && ready=false
      done
      if [ "$ready" = true ]; then removable=$id; break; fi
    done < "$work_dir/remaining"
    if [ -z "$removable" ]; then
      problem "Abhaengigkeitsgraph enthaelt einen Zyklus"
      break
    fi
    awk -F '|' -v remove="$removable" '$1 != remove' "$work_dir/remaining" > "$work_dir/next"
    mv "$work_dir/next" "$work_dir/remaining"
  done
}

validate_ledger_files() {
  for file in goal.md plan.md notes.md; do
    [ -f "$state_dir/$file" ] || problem "Ledger-Datei docs/state/$file fehlt"
  done
  [ -f "$verification_dir/latest.md" ] || problem "docs/verification/latest.md fehlt"
  [ -d "$verification_dir/history" ] || problem "docs/verification/history fehlt"
  [ -d "$state_dir/notes-archive" ] || problem "docs/state/notes-archive fehlt"
  [ -f "$state_dir/goal.md" ] && for heading in '# Ziel' '## Ergebnis' '## Muss' '## Nicht Teil' '## Globale Abnahme'; do
    ledger_markdown_has_section "$state_dir/goal.md" "$heading" || problem "goal.md: Pflichtabschnitt '$heading' fehlt"
  done
  [ -f "$state_dir/plan.md" ] && for heading in '# Plan' '## Aktuelle Strategie' '## Meilensteine' '## Offene Risiken' '## Änderungsverlauf'; do
    ledger_markdown_has_section "$state_dir/plan.md" "$heading" || problem "plan.md: Pflichtabschnitt '$heading' fehlt"
  done
  if [ -f "$state_dir/notes.md" ]; then
    ledger_markdown_has_section "$state_dir/notes.md" '# Notizen' || problem "notes.md: Titel fehlt"
    if ! awk '
      function issue(message) { print "notes.md: " message > "/dev/stderr"; bad=1 }
      function finish() {
        if (!in_note) return
        if (!has_tasks) issue(note " hat kein tasks-Feld")
        if (!has_date) issue(note " hat kein date-Feld")
        if (!has_source) issue(note " hat kein source-Feld")
        if (!has_confidence) issue(note " hat kein confidence-Feld")
        if (!has_status) issue(note " hat kein status-Feld")
        if (!has_evidence) issue(note " hat kein evidence-Feld")
        if (!has_finding) issue(note " hat kein finding-Feld")
      }
      /^## N-[0-9]+[[:space:]]/ {
        finish()
        note=$2
        if (seen[note]++) issue("doppelte Notiz-ID " note)
        in_note=1
        has_tasks=has_date=has_source=has_confidence=has_status=has_evidence=has_finding=0
        next
      }
      in_note && /^- tasks:[[:space:]]*\[.*\][[:space:]]*$/ { has_tasks=1; next }
      in_note && /^- date:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*$/ { has_date=1; next }
      in_note && /^- source:[[:space:]]*[^[:space:]].*$/ { has_source=1; next }
      in_note && /^- confidence:[[:space:]]*/ {
        value=$0; sub(/^.*:[[:space:]]*/, "", value)
        if (value !~ /^(hypothesis|observed|verified|rejected)$/) issue(note " hat unbekannten confidence-Wert " value)
        has_confidence=1; next
      }
      in_note && /^- status:[[:space:]]*/ {
        value=$0; sub(/^.*:[[:space:]]*/, "", value)
        if (value !~ /^(active|resolved)$/) issue(note " hat unbekannten status " value)
        has_status=1; next
      }
      in_note && /^- evidence:[[:space:]]*[^[:space:]].*$/ { has_evidence=1; next }
      in_note && /^- finding:[[:space:]]*[^[:space:]].*$/ { has_finding=1; next }
      END { finish(); exit bad ? 1 : 0 }
    ' "$state_dir/notes.md"; then
      problem "notes.md enthaelt unvollstaendige oder unzulaessige Eintraege"
    fi
  fi

}

if [ -n "$only_task" ]; then
  validate_task "$only_task"
else
  [ -d "$tasks_dir" ] || problem "docs/tasks fehlt"
  validate_task_set
  validate_ledger_files
fi

if [ "$errors" -ne 0 ]; then
  echo "validate-ledger: RED ($errors Fehler)" >&2
  exit 1
fi
echo "validate-ledger: GREEN"
