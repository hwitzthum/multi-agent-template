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
    --project-dir) [ "$#" -ge 2 ] || { echo "validate-ledger: --project-dir braucht einen Pfad" >&2; exit 2; }; project_dir=$2; shift 2 ;;
    --task-file) [ "$#" -ge 2 ] || { echo "validate-ledger: --task-file braucht eine Datei" >&2; exit 2; }; only_task=$2; shift 2 ;;
    *) echo "validate-ledger: unbekannte Option $1" >&2; exit 2 ;;
  esac
done

tasks_dir="$project_dir/docs/tasks"
state_dir="$project_dir/docs/state"
verification_dir="$project_dir/docs/verification"
errors=0
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/ledger-validation.XXXXXX") || exit 1
trap 'rm -r -f -- "$work_dir"' EXIT HUP INT TERM
ids_file="$work_dir/ids"
graph_file="$work_dir/graph"
active_file="$work_dir/active"
: > "$ids_file"
: > "$graph_file"
: > "$active_file"

# Das Schema in zwei Zeilen: acht Einzelfelder und vier Listen. Dazu kommen die
# vier Pflichtabschnitte im Rumpf.
task_scalar_fields='id title status class orchestration attempts human_review blocked_reason'
task_list_fields='depends_on touches risk_flags acceptance'
task_sections='# Kontext|# Umfang|# Nicht Teil dieser Aufgabe|# Akzeptanzkriterien'

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

# Ein Einzelfeld traegt genau einen Wert. Eine zweite Zeile aus dem Parser
# bedeutet, dass es als Liste geschrieben wurde.
scalar_once() {
  case "$seen_scalars" in
    *"|$1|"*) problem "$label: Feld '$1' traegt mehrere Werte"; return 1 ;;
  esac
  seen_scalars="$seen_scalars$1|"
}

validate_task() {
  file=$1
  # Zweites Argument: der Name, unter dem der Task im Ledger liegt. Leer bei
  # einer Kandidatendatei, die noch unter einem Temporaernamen geprueft wird.
  expected_name=${2:-}
  label=${file##*/}
  id=''; title=''; status=''; class=''; orchestration=''; attempts=''
  human_review=''; blocked_reason=''; deps=''; flags=''
  seen_scalars='|'; seen_lists='|'; sections=$ledger_newline

  # Ein awk-Durchlauf liefert Frontmatter und Rumpfueberschriften zusammen.
  parsed=$(ledger_parse "$file") || { problem "$label: Frontmatter fehlt oder ist unzulaessig"; return 0; }
  while IFS="$ledger_tab" read -r key value; do
    case "$key" in
      '#') sections="$sections$value$ledger_newline" ;;
      id) scalar_once id && id=$value ;;
      title) scalar_once title && title=$value ;;
      status) scalar_once status && status=$value ;;
      class) scalar_once class && class=$value ;;
      orchestration) scalar_once orchestration && orchestration=$value ;;
      attempts) scalar_once attempts && attempts=$value ;;
      human_review) scalar_once human_review && human_review=$value ;;
      blocked_reason) scalar_once blocked_reason && blocked_reason=$value ;;
      depends_on) seen_lists="${seen_lists}depends_on|"; [ -z "$value" ] || deps="$deps $value" ;;
      touches) seen_lists="${seen_lists}touches|" ;;
      risk_flags) seen_lists="${seen_lists}risk_flags|"; [ -z "$value" ] || flags="$flags $value" ;;
      acceptance) seen_lists="${seen_lists}acceptance|" ;;
      *) problem "$label: unbekanntes Frontmatter-Feld '$key'" ;;
    esac
  done <<EOF
$parsed
EOF

  for required in $task_scalar_fields; do
    case "$seen_scalars" in *"|$required|"*) ;; *) problem "$label: Pflichtfeld '$required' fehlt" ;; esac
  done
  for required in $task_list_fields; do
    case "$seen_lists" in *"|$required|"*) ;; *) problem "$label: Pflichtliste '$required' fehlt" ;; esac
  done

  case "$id" in ''|*[!0-9]*) problem "$label: id muss nur aus Ziffern bestehen" ;; esac
  # Der Dateiname ist der Schluessel: nur so bleibt der Lookup ein Dateitest.
  [ -z "$id" ] || [ -z "$expected_name" ] || [ "$expected_name" = "$id.md" ] || problem "$expected_name: Dateiname muss $id.md heissen"
  [ -n "$title" ] || problem "$label: title darf nicht leer sein"
  one_of "$status" todo in_progress review done blocked || problem "$label: unbekannter status '$status'"
  one_of "$class" mechanical patterned open || problem "$label: unbekannte class '$class'"
  one_of "$orchestration" auto single verified managed || problem "$label: unbekannte orchestration '$orchestration'"
  one_of "$human_review" true false || problem "$label: human_review muss true oder false sein"
  case "$attempts" in ''|*[!0-9]*) problem "$label: attempts muss eine nichtnegative ganze Zahl sein" ;; esac
  for flag in $flags; do
    one_of "$flag" high-risk cross-component repeated-failure || problem "$label: unbekanntes risk_flag '$flag'"
  done

  old_ifs=$IFS
  IFS='|'
  for heading in $task_sections; do
    case "$sections" in
      *"$ledger_newline$heading$ledger_newline"*) ;;
      *) problem "$label: Pflichtabschnitt '$heading' fehlt" ;;
    esac
  done
  IFS=$old_ifs

  if [ "$status" = blocked ]; then
    [ -n "$blocked_reason" ] || problem "$label: blocked benoetigt einen blocked_reason"
  fi
  if [ "$status" = done ]; then
    # Der strikte Fingerprint-Vergleich gehoert an den Statusuebergang (status.sh).
    # Nach dem Uebergang aendern spaetere Tasks das Produkt; ein erledigter Task
    # bleibt gueltig, solange ein gruener Bericht fuer ihn existiert.
    ledger_verification_is_green "$verification_dir" "$id" || problem "$label: passender gruener Pruefbericht fehlt"
  fi

  if [ -n "$id" ]; then
    printf '%s\n' "$id" >> "$ids_file"
    [ "$status" != in_progress ] || printf '%s\n' "$id" >> "$active_file"
    printf '%s|%s\n' "$id" "$deps" >> "$graph_file"
  fi
}

validate_task_set() {
  files=$(ledger_task_files "$tasks_dir")
  while IFS= read -r file; do
    [ -n "$file" ] && validate_task "$file" "${file##*/}"
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

  # Zyklensuche als eine Kahn-Sortierung in awk statt als Schleife aus Prozessen.
  cycle=$(awk -F '|' '
    { id[NR]=$1; deps[NR]=$2; open[$1]=1; total=NR }
    END {
      removed=1
      while (removed) {
        removed=0
        for (i=1; i<=total; i++) {
          if (!open[id[i]]) continue
          ready=1
          count=split(deps[i], parts, " ")
          for (j=1; j<=count; j++) if (parts[j] != id[i] && open[parts[j]]) ready=0
          if (ready) { open[id[i]]=0; removed=1 }
        }
      }
      for (i=1; i<=total; i++) if (open[id[i]]) { print "zyklus"; exit }
    }
  ' "$graph_file")
  [ -z "$cycle" ] || problem "Abhaengigkeitsgraph enthaelt einen Zyklus"
}

validate_ledger_files() {
  # `decisions.md` und `handoff.md` sind verbindliche Quellen wie die anderen
  # drei: ohne sie verliert der Manager seine Entscheidungshistorie und der
  # Orchestrator seinen Laufbeleg — beides bisher stillschweigend.
  for file in goal.md plan.md notes.md decisions.md handoff.md; do
    [ -f "$state_dir/$file" ] || problem "Ledger-Datei docs/state/$file fehlt"
  done
  [ -f "$verification_dir/latest.md" ] || problem "docs/verification/latest.md fehlt"
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
