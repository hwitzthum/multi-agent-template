#!/usr/bin/env bash
# Kompakte lokale Auswertung der versionierten Laufzusammenfassungen.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
command=summary

usage() {
  echo "Verwendung: $0 [summary] [--project-dir PFAD]" >&2
  exit 2
}

case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [summary] [--project-dir PFAD]"
    echo "Fasst finalisierte Läufe nach Klasse und Modus zusammen."
    exit 0 ;;
esac

if [ "${1:-}" = summary ]; then command=$1; shift; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    *) usage ;;
  esac
done

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo 'agent-metrics: Projektpfad fehlt' >&2; exit 1; }
metrics="$project_dir/docs/state/metrics.csv"
"$script_dir/agent/metrics.sh" ensure-schema "$project_dir" || exit 1

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
