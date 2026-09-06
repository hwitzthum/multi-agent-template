#!/usr/bin/env bash
# Validiert Task-Graph, Ledger-Dateien und Status-/Pruefbeziehungen.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
. "$script_dir/agent/ledger.sh"

only_task=''
current_run_override=''
case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [--project-dir PFAD] [--task-file DATEI] [--current-run-file DATEI]"
    echo "Validiert Task-Graph, Ledger-Schema und Status-/Prüfbeziehungen."
    exit 0 ;;
esac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir=$2; shift 2 ;;
    --task-file) only_task=$2; shift 2 ;;
    --current-run-file) current_run_override=$2; shift 2 ;;
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
: > "$ids_file"
: > "$graph_file"

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
  for file in goal.md plan.md notes.md current-run.md; do
    [ -f "$state_dir/$file" ] || problem "Ledger-Datei docs/state/$file fehlt"
  done
  [ -f "$verification_dir/latest.md" ] || problem "docs/verification/latest.md fehlt"
  [ -d "$verification_dir/history" ] || problem "docs/verification/history fehlt"
  [ -d "$state_dir/notes-archive" ] || problem "docs/state/notes-archive fehlt"
  metrics_file="$state_dir/metrics.csv"
  metrics_header='run_id,task_id,class,mode,model,prompt_version,manager_calls,worker_calls,verifier_runs,rounds,attempts,tokens_in,tokens_out,cost_estimate,duration_seconds,verification,human_review,outcome,date'
  if [ ! -f "$metrics_file" ]; then
    problem "docs/state/metrics.csv fehlt"
  elif [ "$(sed -n '1p' "$metrics_file")" != "$metrics_header" ]; then
    problem "metrics.csv hat ein unbekanntes Schema"
  elif ! awk -F, '
    function fail() { bad=1 }
    NR == 1 { next }
    NF != 19 { fail(); next }
    $1 !~ /^[0-9]{8}T[0-9]{6}Z-T[0-9]{3}$/ { fail() }
    $2 !~ /^[0-9]+$/ { fail() }
    $3 !~ /^(mechanical|patterned|open)$/ { fail() }
    $4 !~ /^(single|verified|managed)$/ { fail() }
    $7 !~ /^[0-9]+$/ || $8 !~ /^[0-9]+$/ || $9 !~ /^[0-9]+$/ || $10 !~ /^[0-9]+$/ || $11 !~ /^[0-9]+$/ { fail() }
    $12 !~ /^([0-9]+)?$/ || $13 !~ /^([0-9]+)?$/ || $14 !~ /^([0-9]+([.][0-9]+)?)?$/ || $15 !~ /^([0-9]+)?$/ { fail() }
    $16 !~ /^$/ && $16 !~ /^(green|red)$/ { fail() }
    $17 !~ /^(not_required|required|pending|approved)$/ { fail() }
    $18 !~ /^(success|review|blocked|no_progress|infrastructure_error|verification_error|cancelled)$/ { fail() }
    $19 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ { fail() }
    seen_run[$1]++ { fail() }
    END { exit bad ? 1 : 0 }
  ' "$metrics_file"; then
    problem "metrics.csv enthaelt ungueltige oder doppelte Laufzeilen"
  fi

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

  run_file="${current_run_override:-$state_dir/current-run.md}"
  if [ -f "$run_file" ]; then
    ledger_validate_frontmatter_shape "$run_file" >/dev/null 2>&1 || problem "current-run.md: unzulaessiges Frontmatter"
    while IFS= read -r key; do
      case "$key" in
        run_id|task_id|mode|phase|iteration|attempt|last_progress_fingerprint|started_at|route_rule_version|route_reason_code|route_human_gate|route_signals) ;;
        *) problem "current-run.md: unbekanntes Feld '$key'" ;;
      esac
    done <<EOF
$(ledger_frontmatter_keys "$run_file")
EOF
    if awk 'BEGIN { closed=0 } NR == 1 { next } !closed && $0 == "---" { closed=1; next } closed && /[^[:space:]]/ { exit 1 } END { if (!closed) exit 1 }' "$run_file"; then :; else
      problem "current-run.md: ausserhalb des Frontmatters ist kein Inhalt erlaubt"
    fi
    run_id=$(ledger_scalar "$run_file" run_id 2>/dev/null) || { problem "current-run.md: Pflichtfeld run_id fehlt"; run_id=''; }
    task_id=$(ledger_scalar "$run_file" task_id 2>/dev/null) || { problem "current-run.md: Pflichtfeld task_id fehlt"; task_id=''; }
    mode=$(ledger_scalar "$run_file" mode 2>/dev/null) || { problem "current-run.md: Pflichtfeld mode fehlt"; mode=''; }
    phase=$(ledger_scalar "$run_file" phase 2>/dev/null) || { problem "current-run.md: Pflichtfeld phase fehlt"; phase=''; }
    iteration=$(ledger_scalar "$run_file" iteration 2>/dev/null) || { problem "current-run.md: Pflichtfeld iteration fehlt"; iteration=''; }
    attempt=$(ledger_scalar "$run_file" attempt 2>/dev/null) || { problem "current-run.md: Pflichtfeld attempt fehlt"; attempt=''; }
    fingerprint=$(ledger_scalar "$run_file" last_progress_fingerprint 2>/dev/null) || { problem "current-run.md: Pflichtfeld last_progress_fingerprint fehlt"; fingerprint=''; }
    started_at=$(ledger_scalar "$run_file" started_at 2>/dev/null) || { problem "current-run.md: Pflichtfeld started_at fehlt"; started_at=''; }
    route_version=$(ledger_scalar "$run_file" route_rule_version 2>/dev/null) || { problem "current-run.md: Pflichtfeld route_rule_version fehlt"; route_version=''; }
    route_reason=$(ledger_scalar "$run_file" route_reason_code 2>/dev/null) || { problem "current-run.md: Pflichtfeld route_reason_code fehlt"; route_reason=''; }
    route_gate=$(ledger_scalar "$run_file" route_human_gate 2>/dev/null) || { problem "current-run.md: Pflichtfeld route_human_gate fehlt"; route_gate=''; }
    route_signals=$(ledger_list "$run_file" route_signals 2>/dev/null) || { problem "current-run.md: Pflichtliste route_signals fehlt"; route_signals=''; }
    one_of "$mode" auto single verified managed blocked || problem "current-run.md: unbekannter mode '$mode'"
    one_of "$phase" plan brainstorm work verify finalize paused failed finished || problem "current-run.md: unbekannte phase '$phase'"
    case "$iteration:$attempt" in *[!0-9:]*) problem "current-run.md: iteration und attempt muessen nichtnegative ganze Zahlen sein" ;; esac
    case "$run_id" in none|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-T[0-9][0-9][0-9]) ;; *) problem "current-run.md: run_id hat nicht das erwartete Format" ;; esac
    case "$task_id" in none|*[!0-9]*|'') [ "$task_id" = none ] || problem "current-run.md: task_id muss numerisch oder none sein" ;; esac
    if [ "$fingerprint" != none ]; then
      case "$fingerprint" in *[!0-9a-f]*) problem "current-run.md: Fortschrittsfingerprint muss SHA-256 oder none sein" ;; esac
      [ "${#fingerprint}" -eq 64 ] || problem "current-run.md: Fortschrittsfingerprint muss 64 Zeichen lang sein"
    fi
    case "$started_at" in never|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) problem "current-run.md: started_at muss eine UTC-Zeit oder never sein" ;; esac
    case "$route_version" in ''|*[!0-9]*) problem "current-run.md: route_rule_version muss numerisch sein" ;; esac
    one_of "$route_reason" none EXPLICIT_OVERRIDE MECHANICAL_LOCAL PATTERNED_LOCAL OPEN_DECISION CROSS_COMPONENT HIGH_RISK FAILED_ATTEMPTS REPEATED_FAILURE ATTEMPT_LIMIT || problem "current-run.md: unbekannter route_reason_code '$route_reason'"
    one_of "$route_gate" true false || problem "current-run.md: route_human_gate muss true oder false sein"
    while IFS= read -r route_signal; do
      [ -n "$route_signal" ] || continue
      one_of "$route_signal" CLI_OVERRIDE TASK_OVERRIDE OPEN_CLASS MULTIPLE_FAILURES CROSS_COMPONENT HIGH_RISK REPEATED_FAILURE FAILURE_RECORDED ATTEMPT_LIMIT || problem "current-run.md: unbekanntes route_signal '$route_signal'"
    done <<EOF
$route_signals
EOF
    if [ "$route_reason" = none ]; then
      [ -z "$route_signals" ] || problem "current-run.md: ohne Routing duerfen route_signals nicht gesetzt sein"
    else
      [ "$mode" != auto ] || problem "current-run.md: protokolliertes Routing benoetigt einen konkreten mode"
    fi

    active_ids=''
    while IFS= read -r file; do
      [ "$(ledger_scalar "$file" status 2>/dev/null || true)" = in_progress ] || continue
      current_id=$(ledger_scalar "$file" id 2>/dev/null || true)
      active_ids="$active_ids $current_id"
    done <<EOF
$(ledger_task_files "$tasks_dir")
EOF
    active_count=$(printf '%s\n' "$active_ids" | awk '{ print NF }')
    [ "$active_count" -le 1 ] || problem "mehr als ein Task ist in_progress"
    if [ "$phase" = finished ]; then
      [ "$active_count" -eq 0 ] || problem "current-run.md ist finished, aber ein Task ist in_progress"
    else
      [ "$run_id" != none ] || problem "aktiver Lauf benoetigt eine run_id"
      [ "$task_id" != none ] || problem "aktiver Lauf benoetigt eine task_id"
      [ "$iteration" -gt 0 ] 2>/dev/null || problem "aktiver Lauf benoetigt iteration groesser null"
      [ "$attempt" -gt 0 ] 2>/dev/null || problem "aktiver Lauf benoetigt attempt groesser null"
      [ "$active_count" -eq 1 ] || problem "aktiver Lauf benoetigt genau einen in_progress-Task"
      [ "${active_ids# }" = "$task_id" ] || problem "current-run.md task_id passt nicht zum aktiven Task"
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
