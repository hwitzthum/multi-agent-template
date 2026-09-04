#!/usr/bin/env bash
# Einzige Anbietergrenze fuer Agentenaufrufe.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/common.sh"

usage() {
  echo "Verwendung: $0 --contract | --check | run_agent ROLE KONTEXT WORKDIR ROHDATEN METADATEN | validate_metadata DATEI" >&2
  exit 2
}

write_metadata() {
  destination=$1
  model=$2
  started=$3
  finished=$4
  exit_status=$5
  tokens=$6
  abort_reason=$7
  output_status=$8
  directory=$(dirname -- "$destination")
  mkdir -p "$directory" || return 1
  temp=$(mktemp "${TMPDIR:-/tmp}/agent-metadata.XXXXXX") || return 1
  trap 'rm -f "$temp"' EXIT HUP INT TERM
  {
    printf 'model=%s\n' "$model"
    printf 'started_at=%s\n' "$started"
    printf 'finished_at=%s\n' "$finished"
    printf 'exit_status=%s\n' "$exit_status"
    printf 'tokens_total=%s\n' "$tokens"
    printf 'tokens_in=\n'
    printf 'tokens_out=\n'
    printf 'cost_estimate=\n'
    printf 'abort_reason=%s\n' "$abort_reason"
    printf 'output_status=%s\n' "$output_status"
  } > "$temp"
  agent_atomic_write "$destination" "$temp"
}

validate_metadata() {
  file=$1
  [ -f "$file" ] || { echo "runner: Metadaten fehlen" >&2; return 1; }
  awk '
    function fail(message) { print "runner: " message > "/dev/stderr"; bad=1 }
    /^[A-Za-z_]+=/ {
      key=$0; sub(/=.*/, "", key); value=substr($0,length(key)+2)
      if (seen[key]++) fail("doppeltes Metadatenfeld " key)
      if (key !~ /^(model|started_at|finished_at|exit_status|tokens_total|tokens_in|tokens_out|cost_estimate|abort_reason|output_status)$/) fail("unbekanntes Metadatenfeld " key)
      values[key]=value
      next
    }
    { fail("ungueltige Metadatenzeile") }
    END {
      required[1]="model"; required[2]="started_at"; required[3]="finished_at"; required[4]="exit_status"; required[5]="tokens_total"; required[6]="abort_reason"; required[7]="output_status"
      for (i=1;i<=7;i++) if (!(required[i] in seen) || values[required[i]] == "") fail("Pflichtfeld fehlt: " required[i])
      if (values["exit_status"] !~ /^[0-9]+$/) fail("exit_status ist nicht numerisch")
      if (values["tokens_total"] !~ /^([0-9]+|unknown)$/) fail("tokens_total ist ungueltig")
      if (("tokens_in" in seen) && values["tokens_in"] !~ /^([0-9]+|unknown)?$/) fail("tokens_in ist ungueltig")
      if (("tokens_out" in seen) && values["tokens_out"] !~ /^([0-9]+|unknown)?$/) fail("tokens_out ist ungueltig")
      if (("cost_estimate" in seen) && values["cost_estimate"] !~ /^([0-9]+([.][0-9]+)?|unknown)?$/) fail("cost_estimate ist ungueltig")
      if (values["output_status"] !~ /^(ok|truncated|empty|error)$/) fail("output_status ist ungueltig")
      exit bad ? 1 : 0
    }
  ' "$file"
}

run_agent() {
  [ "$#" -eq 5 ] || usage
  role=$1; context=$2; workdir=$3; raw_output=$4; metadata_output=$5
  case "$role" in manager-plan|worker-brainstorm|manager-manage|worker-task|worker-fresh|reviewer|finalizer) ;; *) echo "runner: unbekannte Rolle '$role'" >&2; return 1 ;; esac
  [ -f "$context" ] && [ ! -L "$context" ] || { echo "runner: Kontext fehlt oder ist ein Symlink" >&2; return 1; }
  workdir=$(CDPATH= cd -- "$workdir" 2>/dev/null && pwd -P) || { echo "runner: Arbeitsverzeichnis fehlt" >&2; return 1; }
  context_dir=$(CDPATH= cd -- "$(dirname -- "$context")" 2>/dev/null && pwd -P) || return 1
  case "$context_dir/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: Kontext muss unter .agent-runs liegen" >&2; return 1 ;; esac
  raw_dir=$(dirname -- "$raw_output")
  metadata_dir=$(dirname -- "$metadata_output")
  case "$raw_dir" in /*) ;; *) raw_dir="$workdir/$raw_dir" ;; esac
  case "$metadata_dir" in /*) ;; *) metadata_dir="$workdir/$metadata_dir" ;; esac
  case "$raw_dir/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: Rohoutput muss unter .agent-runs liegen" >&2; return 1 ;; esac
  case "$metadata_dir/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: Metadaten müssen unter .agent-runs liegen" >&2; return 1 ;; esac
  mkdir -p "$raw_dir" "$metadata_dir" || return 1
  raw_dir=$(CDPATH= cd -- "$raw_dir" && pwd -P) || return 1
  metadata_dir=$(CDPATH= cd -- "$metadata_dir" && pwd -P) || return 1
  case "$raw_dir/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: Rohoutput muss unter .agent-runs liegen" >&2; return 1 ;; esac
  case "$metadata_dir/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: Metadaten müssen unter .agent-runs liegen" >&2; return 1 ;; esac
  raw_output="$raw_dir/$(basename -- "$raw_output")"
  metadata_output="$metadata_dir/$(basename -- "$metadata_output")"
  [ ! -e "$raw_output" ] && [ ! -e "$metadata_output" ] || { echo "runner: Ausgabedatei existiert bereits" >&2; return 1; }

  command -v claude >/dev/null 2>&1 || { echo "runner: kein unterstützter Agenten-CLI gefunden" >&2; return 127; }
  timeout_seconds=${AGENT_TIMEOUT_SECONDS:-900}
  case "$timeout_seconds" in ''|*[!0-9]*|0) echo "runner: AGENT_TIMEOUT_SECONDS ist ungueltig" >&2; return 1 ;; esac
  model=${AGENT_MODEL:-default}
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  (
    cd "$workdir" || exit 1
    agent_run_with_timeout "$timeout_seconds" claude -p --permission-mode acceptEdits --output-format text < "$context" > "$raw_output" 2>&1
  )
  status=$?
  finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  output_status=ok
  abort_reason=none
  if [ "$status" -eq 124 ]; then output_status=error; abort_reason=timeout
  elif [ "$status" -ne 0 ]; then output_status=error; abort_reason="exit_$status"
  elif [ ! -s "$raw_output" ]; then output_status=empty; abort_reason=empty_output
  fi
  write_metadata "$metadata_output" "$model" "$started" "$finished" "$status" unknown "$abort_reason" "$output_status" || return 1
  return "$status"
}

case "${1:-}" in
  --contract)
    echo "run_agent <role> <context-file> <workdir> <raw-output> <metadata-output>"
    echo "exit 0 = Modellaufruf technisch beendet; keine fachliche Freigabe" ;;
  --check)
    if command -v claude >/dev/null 2>&1; then echo "runner: Claude Code verfügbar"; else echo "runner: kein unterstützter Agenten-CLI gefunden" >&2; exit 1; fi ;;
  run_agent|invoke_role)
    shift
    run_agent "$@" ;;
  validate_metadata)
    [ "$#" -eq 2 ] || usage
    validate_metadata "$2" ;;
  *) usage ;;
esac
