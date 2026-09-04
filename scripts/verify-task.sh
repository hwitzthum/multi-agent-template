#!/usr/bin/env bash
# Taskbezogenes Verification Gateway. Fuehrt Befehle ausschliesslich als
# validierte Argument-Arrays aus und bindet Gruen an Kandidat + Verifierstand.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/agent/common.sh"
. "$script_dir/agent/ledger.sh"

project_dir=$(agent_project_root "$script_dir") || exit 1
task_id=''
run_id=''
attempt=''
timeout_seconds=''

usage() {
  echo "Verwendung: $0 [--project-dir PFAD] [--run-id ID] [--attempt N] [--timeout SEKUNDEN] TASK-ID" >&2
  exit 2
}

case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [--project-dir PFAD] [--run-id ID] [--attempt N] [--timeout SEKUNDEN] TASK-ID"
    echo "Prüft einen Task stufenweise und bindet das Ergebnis an Kandidat und Verifierstand."
    exit 0 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || usage; run_id=$2; shift 2 ;;
    --attempt) [ "$#" -ge 2 ] || usage; attempt=$2; shift 2 ;;
    --timeout) [ "$#" -ge 2 ] || usage; timeout_seconds=$2; shift 2 ;;
    --*) usage ;;
    *) [ -z "$task_id" ] || usage; task_id=$1; shift ;;
  esac
done

case "$task_id" in ''|*[!0-9]*) usage ;; esac
project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "verify-task: Projektpfad fehlt" >&2; exit 1; }
task_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$task_id") || exit 1

if [ -z "$timeout_seconds" ]; then
  if [ -x "$project_dir/scripts/agent/config.sh" ]; then
    timeout_seconds=$("$project_dir/scripts/agent/config.sh" --get VERIFY_TIMEOUT_SECONDS "$project_dir/.agent/config.env" 2>/dev/null || true)
  else
    timeout_seconds=$("$script_dir/agent/config.sh" --get VERIFY_TIMEOUT_SECONDS "$project_dir/.agent/config.env" 2>/dev/null || true)
  fi
fi
timeout_seconds=${timeout_seconds:-90}
case "$timeout_seconds" in ''|*[!0-9]*|0) echo "verify-task: ungueltiges Timeout" >&2; exit 2 ;; esac

if [ -z "$attempt" ]; then
  recorded_attempts=$(ledger_scalar "$task_file" attempts) || exit 1
  attempt=$((recorded_attempts + 1))
fi
case "$attempt" in ''|*[!0-9]*|0) echo "verify-task: ungueltiger Versuch" >&2; exit 2 ;; esac

if [ -z "$run_id" ]; then run_id="$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")"; fi
case "$run_id" in
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-T[0-9][0-9][0-9]) ;;
  *) echo "verify-task: ungueltige Run-ID" >&2; exit 2 ;;
esac

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run_dir="$project_dir/.agent-runs/$run_id/verify"
log_file="$run_dir/attempt-$attempt.log"
verification_dir="$project_dir/docs/verification"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/verify-task.XXXXXX") || exit 1
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir -p "$run_dir" "$verification_dir/history" || exit 1
: > "$log_file"
status_file="$work_dir/stages"
: > "$status_file"
failures_file="$work_dir/failures"
: > "$failures_file"
commands_dir="$work_dir/commands"
mkdir -p "$commands_dir"

overall=green
failure_kind=none
first_failure='Kein Fehler.'

record_failure() {
  kind=$1
  message=$2
  overall=red
  if [ "$first_failure" = 'Kein Fehler.' ]; then first_failure=$message; fi
  printf '%s\n' "- $message" >> "$failures_file"
  if [ "$kind" = verifier ] || [ "$failure_kind" = none ]; then failure_kind=$kind; fi
}

record_stage() {
  printf '%s|%s\n' "$1" "$2" >> "$status_file"
}

step() {
  stage=$1
  label=$2
  shift 2
  {
    echo
    echo "=== $stage: $label ==="
    printf 'command:'
    printf ' %q' "$@"
    echo
  } >> "$log_file"
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
    124) STEP_RESULT=TIMEOUT; record_failure verifier "$stage: Zeitlimit in $label ueberschritten" ;;
    126|127) STEP_RESULT=MISSING; record_failure verifier "$stage: Befehl fuer $label fehlt oder ist nicht ausfuehrbar" ;;
    *) STEP_RESULT=RED; record_failure product "$stage: $label ist fehlgeschlagen (Exit $step_rc)" ;;
  esac
}

split_command() {
  raw=$1
  case "$raw" in
    *$'\n'*|*$'\r'*|*';'*|*'|'*|*'&'*|*'>'*|*'<'*|*'$'*|*'`'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'*'*|*'?'*|*'\\'*|*'"'*|*"'"*) return 1 ;;
  esac
  COMMAND_WORDS=()
  read -r -a COMMAND_WORDS <<< "$raw"
  [ "${#COMMAND_WORDS[@]}" -gt 0 ] || return 1
  for token in "${COMMAND_WORDS[@]}"; do
    [[ "$token" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]] || return 1
    case "$token" in /*|..|../*|*/../*|*/..) return 1 ;; esac
  done
}

normalize_command() {
  local raw=$1
  local words=()
  local token
  read -r -a words <<< "$raw"
  for token in "${words[@]}"; do printf '%s ' "$token"; done
}

command_allowed() {
  raw=$1
  allowlist="$project_dir/.agent/verification-allowlist"
  if [ -f "$allowlist" ]; then
    normalized=$(normalize_command "$raw")
    while IFS= read -r prefix || [ -n "$prefix" ]; do
      case "$prefix" in ''|'#'*) continue ;; esac
      split_command "$prefix" || return 1
      normalized_prefix=$(normalize_command "$prefix")
      case "$normalized" in "$normalized_prefix"*) return 0 ;; esac
    done < "$allowlist"
    return 1
  fi
  case "${COMMAND_WORDS[0]}" in
    ./scripts/verify.sh) [ "${COMMAND_WORDS[0]}" = "$raw" ] || case "$raw" in './scripts/verify.sh '*) return 0 ;; *) return 1 ;; esac ;;
    npm) [ "${#COMMAND_WORDS[@]}" -ge 2 ] && case "${COMMAND_WORDS[1]}" in test|run) return 0 ;; esac ;;
    pytest|ruff|mypy) return 0 ;;
    python|python3) [ "${#COMMAND_WORDS[@]}" -ge 3 ] && [ "${COMMAND_WORDS[1]}" = -m ] && case "${COMMAND_WORDS[2]}" in pytest|ruff|mypy) return 0 ;; esac ;;
  esac
  [ "${COMMAND_WORDS[0]}" = ./scripts/verify.sh ]
}

resolve_named_runner() {
  runner_name=$1
  runners_file="$project_dir/.agent/verification-runners"
  [ -f "$runners_file" ] || return 1
  found=0
  while IFS='|' read -r name stage command extra || [ -n "$name$stage$command$extra" ]; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -z "$extra" ] || return 1
    [ "$name" = "$runner_name" ] || continue
    [ "$found" -eq 0 ] || return 1
    case "$name" in *[!A-Za-z0-9_.-]*) return 1 ;; esac
    case "$stage" in syntax|unit|integration|lint|build|acceptance) ;; *) return 1 ;; esac
    split_command "$command" || return 1
    RUNNER_STAGE=$stage
    RUNNER_COMMAND=$command
    found=1
  done < "$runners_file"
  [ "$found" -eq 1 ]
}

classify_command() {
  raw=$1
  case "$raw" in
    *integration*) COMMAND_STAGE=integration ;;
    'npm run build'|'npm run build '*) COMMAND_STAGE=build ;;
    pytest|'pytest '*|'python -m pytest'|'python -m pytest '*|'python3 -m pytest'|'python3 -m pytest '*|'npm test'|'npm test '*) COMMAND_STAGE=unit ;;
    ruff|'ruff '*|mypy|'mypy '*|'python -m ruff'|'python -m ruff '*|'python3 -m ruff'|'python3 -m ruff '*|'python -m mypy'|'python -m mypy '*|'python3 -m mypy'|'python3 -m mypy '*) COMMAND_STAGE=lint ;;
    *) COMMAND_STAGE=acceptance ;;
  esac
}

command_count=0
add_command() {
  requested=$1
  command_count=$((command_count + 1))
  error=''
  case "$requested" in
    runner:*)
      if resolve_named_runner "${requested#runner:}"; then
        command=$RUNNER_COMMAND
        stage=$RUNNER_STAGE
      else
        command=$requested
        stage=acceptance
        error='unbekannter oder ungueltiger benannter Runner'
      fi ;;
    *)
      command=$requested
      classify_command "$command"
      stage=$COMMAND_STAGE
      if ! split_command "$command"; then
        error='Shell-Metazeichen oder ungueltige Argumente'
      elif ! command_allowed "$command"; then
        error='Befehlspraefix ist nicht erlaubt'
      fi ;;
  esac
  printf '%s\n' "$stage" > "$commands_dir/$command_count.stage"
  printf '%s\n' "$command" > "$commands_dir/$command_count.command"
  printf '%s\n' "$error" > "$commands_dir/$command_count.error"
}

has_global_verify=false
while IFS= read -r acceptance; do
  [ -n "$acceptance" ] || continue
  [ "$acceptance" = ./scripts/verify.sh ] && has_global_verify=true
  add_command "$acceptance"
done <<EOF
$(ledger_list "$task_file" acceptance 2>/dev/null || true)
EOF
if [ "$has_global_verify" != true ]; then add_command ./scripts/verify.sh; fi

run_planned_stage() {
  wanted_stage=$1
  any=${2:-false}
  stage_result=${3:-GREEN}
  index=1
  while [ "$index" -le "$command_count" ]; do
    stage=$(sed -n '1p' "$commands_dir/$index.stage")
    if [ "$stage" = "$wanted_stage" ]; then
      any=true
      command=$(sed -n '1p' "$commands_dir/$index.command")
      error=$(sed -n '1p' "$commands_dir/$index.error")
      if [ -n "$error" ]; then
        echo "=== $wanted_stage: acceptance-$index ===" >> "$log_file"
        echo "ABGEWIESEN: $error" >> "$log_file"
        record_failure product "$wanted_stage: acceptance-$index wurde sicher abgewiesen ($error)"
        STEP_RESULT=REJECTED
      else
        split_command "$command" || { record_failure verifier "$wanted_stage: interner Parserfehler"; STEP_RESULT=RED; }
        if [ "$STEP_RESULT" != RED ] 2>/dev/null; then step "$wanted_stage" "acceptance-$index" "${COMMAND_WORDS[@]}"; fi
      fi
      case "$STEP_RESULT" in GREEN) ;; TIMEOUT) [ "$stage_result" = GREEN ] && stage_result=TIMEOUT ;; MISSING) [ "$stage_result" = GREEN ] && stage_result=MISSING ;; REJECTED) [ "$stage_result" = GREEN ] && stage_result=REJECTED ;; *) stage_result=RED ;; esac
      STEP_RESULT=''
    fi
    index=$((index + 1))
  done
  if [ "$any" = true ]; then record_stage "$wanted_stage" "$stage_result"; else record_stage "$wanted_stage" SKIPPED; fi
}

# 1. Ledger: gesamtes Schema/Graph plus Task-Scope bei einem Git-Checkout.
step ledger schema "$script_dir/validate-ledger.sh" --project-dir "$project_dir"
ledger_result=$STEP_RESULT
touches=$(ledger_list "$task_file" touches 2>/dev/null || true)
if [ "$ledger_result" = GREEN ] && [ -n "$touches" ] && git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r status_line; do
    [ -n "$status_line" ] || continue
    changed=${status_line#???}
    case "$changed" in *' -> '*) changed=${changed##* -> } ;; esac
    case "$changed" in .agent-runs/*|docs/verification/*|docs/state/*|docs/tasks/*|plans/*) continue ;; esac
    allowed=false
    while IFS= read -r permitted; do
      permitted=${permitted%/}
      case "$changed" in "$permitted"|"$permitted"/*) allowed=true ;; esac
    done <<EOF
$touches
EOF
    if [ "$allowed" != true ]; then
      echo "Nicht erlaubte Aenderung ausserhalb touches: $changed" >> "$log_file"
      record_failure product "ledger: geaenderter Pfad $changed liegt ausserhalb des Task-Umfangs"
      ledger_result=RED
    fi
  done <<EOF
$(git -C "$project_dir" status --porcelain 2>/dev/null)
EOF
fi
record_stage ledger "$ledger_result"
STEP_RESULT=''

# 2. Syntax/Compile: schnelle, stackabhaengige Checks ohne generierten Code.
syntax_any=false
syntax_result=GREEN
shell_files=()
while IFS= read -r file; do [ -n "$file" ] && shell_files+=("$file"); done <<EOF
$(find "$project_dir/scripts" "$project_dir/tests" -type f -name '*.sh' -print 2>/dev/null | LC_ALL=C sort)
EOF
if [ "${#shell_files[@]}" -gt 0 ]; then
  syntax_any=true
  step syntax shell-parse bash -n "${shell_files[@]}"
  [ "$STEP_RESULT" = GREEN ] || syntax_result=$STEP_RESULT
fi
python_files=()
while IFS= read -r file; do [ -n "$file" ] && python_files+=("$file"); done <<EOF
$(find "$project_dir" -type f -name '*.py' ! -path '*/.venv/*' ! -path '*/node_modules/*' ! -path '*/.agent-runs/*' -print 2>/dev/null | LC_ALL=C sort)
EOF
if [ "${#python_files[@]}" -gt 0 ]; then
  syntax_any=true
  step syntax python-compile python3 -m py_compile "${python_files[@]}"
  [ "$STEP_RESULT" = GREEN ] || syntax_result=$STEP_RESULT
fi
STEP_RESULT=''
run_planned_stage syntax "$syntax_any" "$syntax_result"
STEP_RESULT=''

# 3-7. Taskbefehle werden ihrer Stufe zugeordnet und trotz Einzelfehlern alle ausgefuehrt.
run_planned_stage unit
run_planned_stage integration
run_planned_stage lint
run_planned_stage build
run_planned_stage acceptance

# 8. Das Human Gate trifft kein automatisches Urteil.
human_review=$(ledger_scalar "$task_file" human_review 2>/dev/null || echo false)
if [ "$human_review" = true ]; then record_stage human REVIEW_REQUIRED; else record_stage human NOT_REQUIRED; fi

candidate_fingerprint=$(ledger_candidate_fingerprint "$project_dir" "$task_file" 2>/dev/null || true)
verifier_version=$(ledger_verifier_fingerprint "$project_dir" 2>/dev/null || true)
if [ "${#candidate_fingerprint}" -ne 64 ]; then candidate_fingerprint=unavailable; record_failure verifier 'fingerprint: Kandidat konnte nicht bestimmt werden'; fi
if [ "${#verifier_version}" -ne 64 ]; then verifier_version=unavailable; record_failure verifier 'fingerprint: Verifier konnte nicht bestimmt werden'; fi
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
report_temp="$work_dir/report"

write_report() {
  {
    echo '---'
    echo "run_id: $run_id"
    echo "task_id: $task_id"
    echo "attempt: $attempt"
    echo "result: $overall"
    echo "failure_kind: $failure_kind"
    echo "started_at: $started_at"
    echo "finished_at: $finished_at"
    echo "candidate_fingerprint: $candidate_fingerprint"
    echo "verifier_version: $verifier_version"
    echo "log_path: .agent-runs/$run_id/verify/attempt-$attempt.log"
    echo '---'
    echo
    echo '# Verification'
    echo
    echo '## Stufen'
    while IFS='|' read -r stage status; do printf '%s\n' "- $stage: $status"; done < "$status_file"
    echo
    echo '## Erster relevanter Fehler'
    echo
    echo "$first_failure"
    if [ -s "$failures_file" ]; then
      echo
      echo '## Fehlerübersicht'
      echo
      cat "$failures_file"
    fi
    echo
    echo '## Vollständiger Log'
    echo
    echo "\`.agent-runs/$run_id/verify/attempt-$attempt.log\`"
  } > "$report_temp"
  history="$verification_dir/history/$run_id-attempt-$(printf '%06d' "$attempt").md"
  agent_atomic_write "$history" "$report_temp" && agent_atomic_write "$verification_dir/latest.md" "$report_temp"
}

write_report || { echo 'verify: RED'; exit 1; }

validate_task_candidate() {
  "$script_dir/validate-ledger.sh" --project-dir "$project_dir" --task-file "$1" >/dev/null
}
if ! ledger_atomic_replace_scalar "$task_file" last_verification "$overall" validate_task_candidate; then
  record_failure verifier 'status: last_verification konnte nicht atomar aktualisiert werden'
  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  write_report || true
fi

if [ "$overall" = green ]; then echo 'verify: GREEN'; exit 0; fi
echo 'verify: RED'
exit 1
