#!/usr/bin/env bash
# Deterministischer Testadapter; startet niemals ein Modell.
set -uo pipefail

[ "${1:-}" = run_agent ] && [ "$#" -eq 6 ] || { echo "fake-runner: run_agent erwartet fünf Argumente" >&2; exit 2; }
role=$2
context=$3
workdir=$4
raw=$5
metadata=$6
[ -f "$context" ] || exit 1
state_root=${ORCHESTRATOR_FAKE_STATE_DIR:-${ORCHESTRATOR_PROJECT_DIR:-$workdir}/.agent-runs/fake}
state_dir=$state_root
mkdir -p "$state_dir" "$(dirname -- "$raw")" "$(dirname -- "$metadata")"
counter="$state_dir/$role.count"
count=0
[ ! -f "$counter" ] || count=$(sed -n '1p' "$counter")
count=$((count + 1))
printf '%s\n' "$count" > "$counter"
response="$state_dir/responses/$role-$count.out"
action_file="$state_dir/actions/$role-$count"
action=none
forced_output_status=''
[ ! -f "$action_file" ] || action=$(sed -n '1p' "$action_file")

case "$action" in
  none) ;;
  write-good) printf '%s\n' good > "$workdir/src/app.txt" ;;
  write-bad) printf '%s\n' bad > "$workdir/src/app.txt" ;;
  write-alpha) printf '%s\n' alpha > "$workdir/src/app.txt" ;;
  write-beta) printf '%s\n' beta > "$workdir/src/app.txt" ;;
  require-no-git-write-good)
    [ ! -e "$workdir/.git" ] || { echo "fake-runner: Fresh-Workspace enthaelt einen Git-Verweis" >&2; exit 1; }
    printf '%s\n' good > "$workdir/src/app.txt" ;;
  write-good-external)
    printf '%s\n' good > "$workdir/src/app.txt"
    [ -n "${ORCHESTRATOR_PROJECT_DIR:-}" ] && printf '%s\n' external > "$ORCHESTRATOR_PROJECT_DIR/src/app.txt" ;;
  append-bad) printf '%s\n' bad >> "$workdir/src/app.txt" ;;
  forbidden) printf '%s\n' '# unerlaubte Worker-Aenderung' >> "$workdir/docs/state/plan.md" ;;
  empty) : > "$raw" ;;
  truncated) forced_output_status=truncated ;;
  timeout)
    : > "$raw"
    {
      echo 'model=fake'
      echo 'started_at=2026-09-04T10:00:00Z'
      echo 'finished_at=2026-09-04T10:00:01Z'
      echo 'exit_status=124'
      echo 'tokens_total=0'
      echo 'abort_reason=timeout'
      echo 'output_status=error'
    } > "$metadata"
    exit 124 ;;
  *) echo "fake-runner: unbekannte Aktion $action" >&2; exit 1 ;;
esac

if [ "$action" != empty ]; then
  if [ -f "$response" ]; then cp "$response" "$raw"; else echo "fake-runner: Antwort fehlt: $response" >&2; exit 1; fi
fi
output_status=ok
[ -s "$raw" ] || output_status=empty
[ -z "$forced_output_status" ] || output_status=$forced_output_status
{
  echo 'model=fake'
  echo 'started_at=2026-09-04T10:00:00Z'
  echo 'finished_at=2026-09-04T10:00:01Z'
  echo 'exit_status=0'
  echo 'tokens_total=0'
  echo 'abort_reason=none'
  echo "output_status=$output_status"
} > "$metadata"
