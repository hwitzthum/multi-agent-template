#!/usr/bin/env bash
# Deterministischer Testadapter; startet niemals ein Modell.
#
# Vertrag wie scripts/agent/runner.sh: run_agent ROLE KONTEXT WORKDIR ERGEBNIS
# METADATEN. Das Ergebnis ist eine JSON-Datei; die Antworten liegen als
# .agent-runs/fake/responses/<rolle>-<nummer>.json bereit.
set -uo pipefail

[ "${1:-}" = run_agent ] && [ "$#" -eq 6 ] || { echo "fake-runner: run_agent erwartet fünf Argumente" >&2; exit 2; }
role=$2
context=$3
workdir=$4
result=$5
metadata=$6
[ -f "$context" ] || exit 1
state_dir=${ORCHESTRATOR_FAKE_STATE_DIR:-${ORCHESTRATOR_PROJECT_DIR:-$workdir}/.agent-runs/fake}
mkdir -p "$state_dir" "$(dirname -- "$result")" "$(dirname -- "$metadata")"
counter="$state_dir/$role.count"
count=0
[ ! -f "$counter" ] || count=$(sed -n '1p' "$counter")
count=$((count + 1))
printf '%s\n' "$count" > "$counter"
response="$state_dir/responses/$role-$count.json"
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
  write-worse) printf '%s\n' worse > "$workdir/src/app.txt" ;;
  # Haelt den Aufruf lange genug offen, damit ein Test den Orchestrator
  # mitten im Lauf abbrechen kann.
  hang) sleep 2; printf '%s\n' good > "$workdir/src/app.txt" ;;
  require-initial-write-good)
    [ "$(sed -n '1p' "$workdir/src/app.txt")" = initial ] \
      || { echo "fake-runner: Fresh-Versuch startet nicht vom Laufstart" >&2; exit 1; }
    printf '%s\n' good > "$workdir/src/app.txt" ;;
  write-outside)
    printf '%s\n' good > "$workdir/src/app.txt"
    printf '%s\n' 'ausserhalb des Umfangs' > "$workdir/src/other.txt" ;;
  append-bad) printf '%s\n' bad >> "$workdir/src/app.txt" ;;
  forbidden) printf '%s\n' '# unerlaubte Worker-Aenderung' >> "$workdir/docs/state/plan.md" ;;
  # Ein Manager darf Tasks anlegen, aber nur mit `todo`/`0` und ohne Grund.
  new-task)
    {
      echo '---'; echo 'id: 018'; echo 'title: "Vom Manager angelegt"'
      echo 'depends_on: []'; echo 'status: todo'; echo 'class: mechanical'
      echo 'orchestration: auto'; echo 'touches: [src/app.txt]'; echo 'risk_flags: []'
      echo 'attempts: 0'; echo 'human_review: false'; echo 'acceptance: ["./scripts/verify.sh"]'
      echo 'blocked_reason: ""'; echo '---'
      echo '# Kontext'; echo 'Nachgeschobene Aufgabe.'
      echo '# Umfang'; echo '- `src/app.txt` bearbeiten.'
      echo '# Nicht Teil dieser Aufgabe'; echo '- Steuerungsdateien ändern.'
      echo '# Akzeptanzkriterien'; echo '- Die Datei enthält `good`.'
    } > "$workdir/docs/tasks/018.md" ;;
  # Ein Manager, der die Versuchszaehlung selbst hochsetzt, muss auffallen.
  tamper-attempts)
    sed 's/^attempts: 0$/attempts: 2/' "$workdir/docs/tasks/017.md" > "$workdir/docs/tasks/.017.tmp" \
      && mv "$workdir/docs/tasks/.017.tmp" "$workdir/docs/tasks/017.md" ;;
  empty) : > "$result" ;;
  truncated) forced_output_status=truncated ;;
  timeout)
    : > "$result"
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
  if [ -f "$response" ]; then cp "$response" "$result"; else echo "fake-runner: Antwort fehlt: $response" >&2; exit 1; fi
fi
output_status=ok
[ -s "$result" ] || output_status=empty
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
