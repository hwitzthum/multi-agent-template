#!/usr/bin/env bash
# Einziger maschineller Schreibweg fuer Task-Statusuebergaenge.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
. "$script_dir/ledger.sh"
# `--project-dir` benennt nur die Daten; geprueft wird mit dem Validator neben
# diesem Skript, auch wenn im Zielprojekt eine Kopie liegt.
validator="$script_dir/../validate-ledger.sh"
human_approved=false

usage() {
  echo "Verwendung: $0 [--project-dir PFAD] [--human-approved] set-status TASK-ID NEU ERWARTET" >&2
  exit 2
}

while [ "${1:-}" != set-status ] && [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ "$#" -ge 2 ] || usage
      project_dir=$2
      shift 2 ;;
    --human-approved) human_approved=true; shift ;;
    *) break ;;
  esac
done

[ "${1:-}" = set-status ] && [ "$#" -eq 4 ] || usage
task_id=$2
new_status=$3
expected_status=$4
tasks_dir="$project_dir/docs/tasks"
verification_dir="$project_dir/docs/verification"

case "$task_id" in ''|*[!0-9]*) echo "status-gate: ungueltige Task-ID" >&2; exit 1 ;; esac
case "$new_status" in todo|in_progress|review|done|blocked) ;; *) echo "status-gate: unbekannter Zielstatus '$new_status'" >&2; exit 1 ;; esac

lock_dir="$tasks_dir/.status-lock"
agent_acquire_lock "$lock_dir" "ein anderer Statuswechsel" || exit 1
trap 'agent_release_lock "$lock_dir"' EXIT HUP INT TERM

task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
actual_status=$(ledger_scalar "$task_file" status) || exit 1
[ "$actual_status" = "$expected_status" ] || {
  echo "status-gate: Task $task_id ist '$actual_status', erwartet war '$expected_status' (veralteter Schreibversuch)" >&2
  exit 1
}

transition="$actual_status:$new_status"
case "$transition" in
  todo:in_progress|in_progress:todo|in_progress:review|in_progress:done|in_progress:blocked|review:done|review:todo|review:blocked) ;;
  # Eine blockierte Aufgabe oeffnet nur ein Mensch wieder: der Orchestrator
  # wuerde sonst genau den Lauf wiederholen, der sie blockiert hat.
  blocked:todo)
    [ "$human_approved" = true ] || {
      echo "status-gate: blocked -> todo verlangt eine ausdrueckliche menschliche Freigabe" >&2
      exit 1
    } ;;
  *) echo "status-gate: Uebergang $actual_status -> $new_status ist nicht erlaubt" >&2; exit 1 ;;
esac

if [ "$new_status" = done ] || [ "$new_status" = review ]; then
  ledger_verification_is_green "$verification_dir" "$task_id" "$project_dir" "$task_file" || {
    echo "status-gate: $new_status benoetigt einen passenden gruenen Pruefbericht mit aktuellen Fingerprints" >&2
    report_candidate=$(ledger_scalar "$verification_dir/$task_id.md" candidate_fingerprint 2>/dev/null || echo fehlt)
    report_verifier=$(ledger_scalar "$verification_dir/$task_id.md" verifier_version 2>/dev/null || echo fehlt)
    current_candidate=$(ledger_candidate_fingerprint "$project_dir" "$task_file" 2>/dev/null || echo fehler)
    current_verifier=$(ledger_verifier_fingerprint "$project_dir" 2>/dev/null || echo fehler)
    echo "status-gate: Kandidat Bericht=$report_candidate aktuell=$current_candidate; Verifier Bericht=$report_verifier aktuell=$current_verifier" >&2
    exit 1
  }
fi

if [ "$new_status" = done ]; then
  human_review=$(ledger_scalar "$task_file" human_review) || exit 1
  task_class=$(ledger_scalar "$task_file" class) || exit 1
  if [ "$actual_status" = in_progress ] && { [ "$human_review" = true ] || [ "$task_class" = open ]; }; then
    echo "status-gate: Task $task_id benoetigt zuerst den Status review" >&2
    exit 1
  fi
  if [ "$actual_status" = review ] && { [ "$human_review" = true ] || [ "$task_class" = open ]; } && [ "$human_approved" != true ]; then
    echo "status-gate: Task $task_id benoetigt eine ausdrueckliche menschliche Freigabe" >&2
    exit 1
  fi
fi

validate_candidate() {
  "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null
}

ledger_atomic_replace_scalar "$task_file" status "$new_status" validate_candidate || exit 1
echo "status-gate: Task $task_id $actual_status -> $new_status"
