#!/usr/bin/env bash
# Kompakte lokale Auswertung der versionierten Laufzusammenfassungen.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
command=summary
manifest=''

usage() {
  echo "Verwendung: $0 [summary] [--project-dir PFAD] | compare --manifest DATEI [--project-dir PFAD]" >&2
  exit 2
}

case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [summary] [--project-dir PFAD] | compare --manifest DATEI [--project-dir PFAD]"
    echo "Fasst finalisierte Läufe zusammen oder vergleicht vorbereitete Pilotpaare."
    exit 0 ;;
esac

if [ "${1:-}" = summary ] || [ "${1:-}" = compare ]; then command=$1; shift; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    --manifest) [ "$#" -ge 2 ] || usage; manifest=$2; shift 2 ;;
    *) usage ;;
  esac
done

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo 'agent-metrics: Projektpfad fehlt' >&2; exit 1; }
metrics="$project_dir/docs/state/metrics.csv"
"$script_dir/agent/metrics.sh" ensure-schema "$project_dir" || exit 1

if [ "$command" = summary ]; then
  awk -F, '
    NR == 1 { next }
    {
      key=$3 "|" $4
      runs[key]++
      outcomes[key SUBSEP $18]++
      managers[key]+=$7; workers[key]+=$8; verifiers[key]+=$9
      if ($15 != "") { durations[key]+=$15; duration_known[key]++ }
      if ($12 != "" && $13 != "") { tokens[key]+=$12+$13; token_known[key]++ }
    }
    END {
      print "class mode runs success review blocked no_progress infra_error verify_error cancelled manager worker verifier duration_s tokens"
      for (key in runs) {
        split(key, parts, "|")
        printf "%s %s %d %d %d %d %d %d %d %d %d %d %d ", parts[1], parts[2], runs[key], outcomes[key SUBSEP "success"]+0, outcomes[key SUBSEP "review"]+0, outcomes[key SUBSEP "blocked"]+0, outcomes[key SUBSEP "no_progress"]+0, outcomes[key SUBSEP "infrastructure_error"]+0, outcomes[key SUBSEP "verification_error"]+0, outcomes[key SUBSEP "cancelled"]+0, managers[key], workers[key], verifiers[key]
        if (duration_known[key] == runs[key]) printf "%d ", durations[key]; else printf "- "
        if (token_known[key] == runs[key]) printf "%d\n", tokens[key]; else print "-"
      }
      if (NR == 1) print "(keine finalisierten Laeufe)"
    }
  ' "$metrics"
  exit 0
fi

[ -n "$manifest" ] || usage
case "$manifest" in /*) ;; *) manifest="$project_dir/$manifest" ;; esac
[ -f "$manifest" ] || { echo "agent-metrics: Pilotmanifest fehlt: $manifest" >&2; exit 1; }
[ "$(sed -n '1p' "$manifest")" = 'pair_id,task_id,baseline_run_id,variant_run_id,base_fingerprint' ] || { echo 'agent-metrics: unbekanntes Pilotmanifest-Schema' >&2; exit 1; }

printf '%s\n' 'pair task baseline_mode baseline_outcome variant_mode variant_outcome base'
count=0
while IFS=, read -r pair_id task_id baseline_run variant_run expected_base extra; do
  [ "$pair_id" != pair_id ] || continue
  [ -n "$pair_id" ] || continue
  [ -z "${extra:-}" ] && [ -n "$task_id" ] && [ -n "$baseline_run" ] && [ -n "$variant_run" ] || { echo "agent-metrics: unvollstaendiges Paar $pair_id" >&2; exit 1; }
  baseline_meta="$project_dir/.agent-runs/$baseline_run/metadata/run.env"
  variant_meta="$project_dir/.agent-runs/$variant_run/metadata/run.env"
  [ -f "$baseline_meta" ] && [ -f "$variant_meta" ] || { echo "agent-metrics: lokale Laufmetadaten fuer Paar $pair_id fehlen" >&2; exit 1; }
  baseline_base=$(awk -F= '$1 == "base_fingerprint" {print $2; exit}' "$baseline_meta")
  variant_base=$(awk -F= '$1 == "base_fingerprint" {print $2; exit}' "$variant_meta")
  [ -n "$baseline_base" ] && [ "$baseline_base" = "$variant_base" ] || { echo "agent-metrics: Basis-Fingerprint fuer Paar $pair_id ist verschieden" >&2; exit 1; }
  [ -z "$expected_base" ] || [ "$expected_base" = "$baseline_base" ] || { echo "agent-metrics: dokumentierter Basis-Fingerprint fuer Paar $pair_id stimmt nicht" >&2; exit 1; }
  baseline_row=$(awk -F, -v run="$baseline_run" '$1 == run {print; exit}' "$metrics")
  variant_row=$(awk -F, -v run="$variant_run" '$1 == run {print; exit}' "$metrics")
  [ -n "$baseline_row" ] && [ -n "$variant_row" ] || { echo "agent-metrics: finalisierte CSV-Zeile fuer Paar $pair_id fehlt" >&2; exit 1; }
  baseline_task=$(printf '%s\n' "$baseline_row" | awk -F, '{print $2}')
  variant_task=$(printf '%s\n' "$variant_row" | awk -F, '{print $2}')
  [ "$baseline_task" = "$task_id" ] && [ "$variant_task" = "$task_id" ] || { echo "agent-metrics: Task-ID fuer Paar $pair_id stimmt nicht" >&2; exit 1; }
  printf '%s %s %s %s %s %s same\n' "$pair_id" "$task_id" \
    "$(printf '%s\n' "$baseline_row" | awk -F, '{print $4}')" "$(printf '%s\n' "$baseline_row" | awk -F, '{print $18}')" \
    "$(printf '%s\n' "$variant_row" | awk -F, '{print $4}')" "$(printf '%s\n' "$variant_row" | awk -F, '{print $18}')"
  count=$((count + 1))
done < "$manifest"
[ "$count" -gt 0 ] || echo '(Pilot noch nicht ausgefuehrt)'
