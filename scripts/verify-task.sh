#!/usr/bin/env bash
# Taskbezogenes Pruef-Gateway. Ein Ablauf: acceptance-Befehle pruefen, als
# validierte Argument-Arrays ausfuehren, Bericht schreiben. Gruen ist an
# Kandidat und Verifierstand gebunden.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/agent/common.sh"
. "$script_dir/agent/ledger.sh"

project_dir=$(agent_project_root "$script_dir") || exit 1
task_id=''; run_id=''; attempt=''; timeout_seconds=''

usage() {
  echo "Verwendung: $0 [--project-dir PFAD] [--run-id ID] [--attempt N] [--timeout SEKUNDEN] TASK-ID"
  echo "Führt die acceptance-Befehle eines Tasks aus und bindet das Ergebnis an Kandidat und Verifierstand."
}
bad_usage() { usage >&2; exit 2; }

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || bad_usage; project_dir=$2; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || bad_usage; run_id=$2; shift 2 ;;
    --attempt) [ "$#" -ge 2 ] || bad_usage; attempt=$2; shift 2 ;;
    --timeout) [ "$#" -ge 2 ] || bad_usage; timeout_seconds=$2; shift 2 ;;
    --*) bad_usage ;;
    *) [ -z "$task_id" ] || bad_usage; task_id=$1; shift ;;
  esac
done

case "$task_id" in ''|*[!0-9]*) bad_usage ;; esac
project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "verify-task: Projektpfad fehlt" >&2; exit 1; }
task_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$task_id") || exit 1

if [ -z "$timeout_seconds" ]; then
  config_reader="$script_dir/agent/config.sh"
  [ -x "$project_dir/scripts/agent/config.sh" ] && config_reader="$project_dir/scripts/agent/config.sh"
  timeout_seconds=$("$config_reader" --get VERIFY_TIMEOUT_SECONDS "$project_dir/.agent/config.env" 2>/dev/null || true)
fi
timeout_seconds=${timeout_seconds:-90}
case "$timeout_seconds" in ''|*[!0-9]*|0) echo "verify-task: ungueltiges Timeout" >&2; exit 2 ;; esac

if [ -z "$attempt" ]; then attempt=$(ledger_scalar "$task_file" attempts) || exit 1; attempt=$((attempt + 1)); fi
case "$attempt" in ''|*[!0-9]*|0) echo "verify-task: ungueltiger Versuch" >&2; exit 2 ;; esac

if [ -z "$run_id" ]; then run_id="$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")"; fi
case "$run_id" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-T[0-9][0-9][0-9]) ;; *) echo "verify-task: ungueltige Run-ID" >&2; exit 2 ;; esac

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
log_relative=".agent-runs/$run_id/verify/attempt-$attempt.log"
log_file="$project_dir/$log_relative"
verification_dir="$project_dir/docs/verification"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/verify-task.XXXXXX") || exit 1
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir -p "$(dirname -- "$log_file")" "$verification_dir" || exit 1
results_file="$work_dir/results"
failures_file="$work_dir/failures"
: > "$log_file"; : > "$results_file"; : > "$failures_file"

overall=green; failure_kind=none; first_failure='Kein Fehler.'

# Ohne eigene `.agent/verification-allowlist` gelten diese generischen Praefixe.
default_allowlist='./scripts/verify.sh
npm
pytest
go
cargo
make'

record_failure() {
  overall=red
  [ "$first_failure" != 'Kein Fehler.' ] || first_failure=$2
  printf '%s\n' "- $2" >> "$failures_file"
  if [ "$1" = verifier ] || [ "$failure_kind" = none ]; then failure_kind=$1; fi
}

# Fuehrt genau ein Argument-Array aus und trennt Produkt- von Verifierfehlern.
step() {
  label=$1
  shift
  { echo; echo "=== $label ==="; printf 'command:'; printf ' %q' "$@"; echo; } >> "$log_file"
  executable=$1
  if case "$executable" in /*) [ -x "$executable" ] ;; */*) [ -x "$project_dir/$executable" ] ;; *) command -v "$executable" >/dev/null 2>&1 ;; esac; then
    (cd "$project_dir" && agent_run_with_timeout "$timeout_seconds" "$@") >> "$log_file" 2>&1
    step_rc=$?
  else
    echo "Befehl fehlt: $executable" >> "$log_file"
    step_rc=127
  fi
  case "$step_rc" in
    0) STEP_RESULT=GREEN ;;
    124) STEP_RESULT=TIMEOUT; record_failure verifier "$label: Zeitlimit ueberschritten" ;;
    126|127) STEP_RESULT=MISSING; record_failure verifier "$label: Befehl fehlt oder ist nicht ausfuehrbar" ;;
    *) STEP_RESULT=RED; record_failure product "$label ist fehlgeschlagen (Exit $step_rc)" ;;
  esac
}

# Zerlegt einen Befehl in COMMAND_WORDS; nie als Shelltext ausgewertet.
# Shell-Metazeichen, absolute Pfade und Pfadtraversierung werden abgewiesen.
split_command() {
  case "$1" in
    *$'\n'*|*$'\r'*|*';'*|*'|'*|*'&'*|*'>'*|*'<'*|*'$'*|*'`'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'*'*|*'?'*|*'\\'*|*'"'*|*"'"*) return 1 ;;
  esac
  COMMAND_WORDS=()
  read -r -a COMMAND_WORDS <<< "$1"
  [ "${#COMMAND_WORDS[@]}" -gt 0 ] || return 1
  for token in "${COMMAND_WORDS[@]}"; do
    [[ "$token" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]] || return 1
    case "$token" in /*|..|../*|*/../*|*/..) return 1 ;; esac
  done
}

normalize_command() {
  local words=() token
  read -r -a words <<< "$1"
  for token in "${words[@]}"; do printf '%s ' "$token"; done
}

# Praefixvergleich auf Wortgrenze: `go` erlaubt `go test`, aber nicht `gofmt`.
command_allowed() {
  allowlist="$project_dir/.agent/verification-allowlist"
  if [ -f "$allowlist" ]; then entries=$(cat "$allowlist"); else entries=$default_allowlist; fi
  normalized=$(normalize_command "$1")
  while IFS= read -r prefix || [ -n "$prefix" ]; do
    case "$prefix" in ''|'#'*) continue ;; esac
    split_command "$prefix" || return 1
    normalized_prefix=$(normalize_command "$prefix")
    case "$normalized" in "$normalized_prefix"*) return 0 ;; esac
  done <<EOF
$entries
EOF
  return 1
}

command_count=0
run_command() {
  requested=$1
  command_count=$((command_count + 1))
  label="acceptance-$command_count"
  error=''
  if ! split_command "$requested"; then
    error='Shell-Metazeichen oder ungueltige Argumente'
  elif ! command_allowed "$requested"; then
    error='Befehlspraefix ist nicht erlaubt'
  fi
  if [ -n "$error" ]; then
    { echo; echo "=== $label ==="; echo "ABGEWIESEN: $error"; } >> "$log_file"
    record_failure product "$label wurde sicher abgewiesen ($error)"
    printf '%s|%s\n' "$label" REJECTED >> "$results_file"
    return 0
  fi
  split_command "$requested"
  step "$label" "${COMMAND_WORDS[@]}"
  printf '%s|%s\n' "$label" "$STEP_RESULT" >> "$results_file"
}

# Alle acceptance-Befehle laufen, auch nach einem Fehler; `verify.sh` ist Pflicht.
has_global_verify=false
while IFS= read -r acceptance; do
  [ -n "$acceptance" ] || continue
  if [ "$acceptance" = ./scripts/verify.sh ]; then has_global_verify=true; fi
  run_command "$acceptance"
done <<EOF
$(ledger_list "$task_file" acceptance 2>/dev/null || true)
EOF
if [ "$has_global_verify" != true ]; then run_command ./scripts/verify.sh; fi

candidate_fingerprint=$(ledger_candidate_fingerprint "$project_dir" "$task_file" 2>/dev/null || true)
verifier_version=$(ledger_verifier_fingerprint "$project_dir" 2>/dev/null || true)
if [ "${#candidate_fingerprint}" -ne 64 ]; then candidate_fingerprint=unavailable; record_failure verifier 'fingerprint: Kandidat konnte nicht bestimmt werden'; fi
if [ "${#verifier_version}" -ne 64 ]; then verifier_version=unavailable; record_failure verifier 'fingerprint: Verifier konnte nicht bestimmt werden'; fi
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
report_temp="$work_dir/report"

write_report() {
  {
    printf '%s\n' '---' "run_id: $run_id" "task_id: $task_id" "attempt: $attempt" \
      "result: $overall" "failure_kind: $failure_kind" "started_at: $started_at" \
      "finished_at: $finished_at" "candidate_fingerprint: $candidate_fingerprint" \
      "verifier_version: $verifier_version" "log_path: $log_relative" '---'
    printf '\n# Verification\n\n## Befehle\n'
    while IFS='|' read -r label status; do printf '%s\n' "- $label: $status"; done < "$results_file"
    printf '\n## Erster relevanter Fehler\n\n%s\n' "$first_failure"
    if [ -s "$failures_file" ]; then printf '\n## Fehlerübersicht\n\n'; cat "$failures_file"; fi
    printf '\n## Vollständiger Log\n\n`%s`\n' "$log_relative"
  } > "$report_temp"
  # Der Beleg eines Tasks liegt unter seiner ID; `latest.md` ist seine Kopie.
  agent_atomic_write "$verification_dir/$task_id.md" "$report_temp" \
    && agent_atomic_write "$verification_dir/latest.md" "$report_temp"
}

write_report || { echo 'verify: RED'; exit 1; }

if [ "$overall" = green ]; then echo 'verify: GREEN'; exit 0; fi
echo 'verify: RED'
exit 1
