#!/usr/bin/env bash
# Der bewachte Rollenaufruf: alles, was um genau einen Modellaufruf herum
# passieren muss, damit sein Ergebnis verwendbar ist.
#
# Diese Datei wird eingebunden, nicht gestartet. Sie baut den Kontext, ruft den
# Runner (mit begrenztem Infrastruktur-Retry), prueft das Ergebnis gegen das
# Rollenschema, vergleicht ein Manifest vor und nach dem Aufruf, weist
# Schreibzugriffe ausserhalb des Rollen- und Task-Umfangs zurueck und setzt den
# Arbeitsbaum in diesem Fall zurueck. Der Orchestrator behaelt damit nur seinen
# Ablauf: wer wann laeuft und wie ein Lauf endet.
set -uo pipefail

# Die Steuerfelder gehoeren dem Orchestrator: der Manager darf Inhalte schaerfen,
# aber weder Status noch Versuche noch Blockadegrund bewegen. Ein neuer Task
# startet auf `todo` mit null Versuchen und ohne Grund.
check_task_controls() {
  while IFS= read -r protected_line; do
    grep -Fqx "$protected_line" "$2" || { echo "orchestrate: Manager änderte geschützte Task-Steuerfelder" >&2; return 1; }
  done < "$1"
  while IFS= read -r current_line; do
    grep -Fqx "$current_line" "$1" && continue
    case "$current_line" in *'|todo|0|') ;; *) echo "orchestrate: neuer Task trägt unzulässige Steuerwerte: $current_line" >&2; return 1 ;; esac
  done < "$2"
}

# Setzt Pfade auf den Stand eines Manifests zurueck. Was das Manifest nicht
# kennt, ist nach dem Snapshot entstanden und wandert in die Quarantaene.
restore_paths() {
  manifest=$1
  shift
  [ "$#" -gt 0 ] || return 0
  mkdir -p "$run_dir/quarantine" || return 1
  agent_snapshot_restore "$project_dir" "$manifest" "$run_dir/quarantine" "$@"
}

check_role_changes() {
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    "$policy" role-write "$1" "$changed" >/dev/null 2>&1 || {
      echo "orchestrate: Rolle $1 änderte verbotenen Pfad $changed" >&2; return 1; }
    [ "$1" != worker ] || ledger_path_in_touches "$task_file" "$changed" || {
      echo "orchestrate: Pfad $changed liegt außerhalb des Task-Umfangs" >&2; return 1; }
  done < "$2"
}

# run_role ROLLE TASK PHASE [fresh]
run_role() {
  role=$1; role_task=$2; variant=${4:-normal}
  set_phase "$3"
  call_sequence=$((call_sequence + 1))
  label=$(printf '%02d-%s' "$call_sequence" "$role")
  [ "$variant" != fresh ] || label="$label-fresh"
  # Das Vorher-Manifest liegt ausserhalb des Arbeitsbaums, solange der Agent
  # laeuft: unter .agent-runs/ koennte er es passend zu seinen Aenderungen
  # umschreiben und so den Abgleich entwerten.
  before="$scratch_dir/$label.before"
  controls_before="$scratch_dir/$label.controls-before"
  changes="$run_dir/manifests/$label.changed"
  mkdir -p "$run_dir/results" "$run_dir/metadata" "$run_dir/manifests" || return 1

  context_args=(build --project-dir "$project_dir" --role "$role" --run-id "$run_id" --task-id "$role_task")
  [ "$variant" != fresh ] || context_args+=(--fresh)
  if [ "$role" = worker ]; then
    while IFS= read -r include; do [ -n "$include" ] && context_args+=(--include "$include"); done <<EOF
$(ledger_list "$task_file" touches 2>/dev/null || true)
EOF
  fi
  context=$("$context_builder" "${context_args[@]}") || return 1
  agent_repo_manifest "$project_dir" "$before" || return 1
  ledger_control_snapshot "$tasks_dir" "$controls_before" || return 1

  # Nur ein Providerfehler wird wiederholt: Exit ungleich null oder
  # output_status=error. Eine leere oder abgeschnittene Antwort ist eine Aussage
  # des Modells und wird nie als Infrastrukturfehler umgedeutet. Ein Retry
  # zaehlt keinen Task-Versuch und bekommt eigene Ausgabedateien.
  infra_retry=0
  attempt_label=$label
  while :; do
    last_result="$run_dir/results/$attempt_label.json"
    metadata="$run_dir/metadata/$attempt_label.env"
    "$runner" run_agent "$role" "$context" "$project_dir" "$last_result" "$metadata"
    runner_status=$?
    "$runner_adapter" validate_metadata "$metadata" >/dev/null 2>&1 || {
      run_outcome=infrastructure_error
      echo "orchestrate: ungültige Runner-Metadaten für $role" >&2; return 1; }
    output_status=$(awk -F= '$1 == "output_status" { print $2; exit }' "$metadata")
    if [ "$runner_status" -eq 0 ] && [ "$output_status" != error ]; then break; fi
    if [ "$infra_retry" -ge "$max_infra_retries" ]; then
      run_outcome=infrastructure_error
      echo "orchestrate: Agentenaufruf $role scheiterte endgültig (Exit $runner_status, Ausgabe $output_status)" >&2
      return 1
    fi
    infra_retry=$((infra_retry + 1))
    attempt_label="$label.retry$infra_retry"
    sleep "$retry_backoff"
  done
  [ "$output_status" = ok ] || {
    run_outcome=infrastructure_error
    echo "orchestrate: Agentenausgabe $role ist leer, abgeschnitten oder fehlerhaft" >&2; return 1; }
  "$runner_adapter" validate_result "$role" "$last_result" || return 1

  agent_repo_manifest "$project_dir" "$run_dir/manifests/$label.after" || return 1
  agent_manifest_changes "$before" "$run_dir/manifests/$label.after" > "$changes"
  mv -f "$before" "$run_dir/manifests/$label.before" || return 1
  mv -f "$controls_before" "$run_dir/manifests/$label.controls-before" || return 1
  # Ein Verstoss gegen Schreibbereich, Task-Umfang, Steuerfelder oder
  # Ledger-Gueltigkeit faellt gleich zurueck: der Arbeitsbaum steht danach
  # wieder auf dem Stand vor dem Aufruf, damit der naechste Lauf nicht auf
  # einer Manipulation aufsetzt.
  violation=false
  check_role_changes "$role" "$changes" || violation=true
  if [ "$role" = manager ] && [ "$violation" = false ]; then
    ledger_control_snapshot "$tasks_dir" "$run_dir/manifests/$label.controls-after" || return 1
    check_task_controls "$run_dir/manifests/$label.controls-before" "$run_dir/manifests/$label.controls-after" || violation=true
  fi
  # Ein Ledger, das nach dem Aufruf nicht mehr gilt, ist derselbe Fall: bliebe
  # es stehen, scheiterte schon der naechste Lauf an seiner Eingangspruefung.
  if [ "$violation" = false ] && ! "$validator" --project-dir "$project_dir" >/dev/null; then
    echo "orchestrate: Rolle $role hinterliess ein ungültiges Ledger" >&2
    violation=true
  fi
  if [ "$violation" = true ]; then
    restore_list=()
    while IFS= read -r changed; do [ -n "$changed" ] && restore_list+=("$changed"); done < "$changes"
    [ "${#restore_list[@]}" -eq 0 ] || restore_paths "$run_dir/manifests/$label.before" "${restore_list[@]}" \
      || echo "orchestrate: Ruecksetzen nach Regelverstoss scheiterte" >&2
    return 1
  fi
}

# Ein Fresh-Versuch beginnt beim Laufstart: alles, was der Task anfassen darf
# und seither anders ist, wird auf den Snapshot zurueckgesetzt.
reset_to_run_start() {
  now="$scratch_dir/fresh-now.manifest"
  agent_repo_manifest "$project_dir" "$now" || return 1
  restore_list=()
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    ledger_path_in_touches "$task_file" "$changed" || continue
    restore_list+=("$changed")
  done <<EOF
$(agent_manifest_changes "$run_start_manifest" "$now")
EOF
  rm -f "$now"
  [ "${#restore_list[@]}" -eq 0 ] || restore_paths "$run_start_manifest" "${restore_list[@]}" || {
    echo "orchestrate: Ruecksetzen auf den Laufstart scheiterte" >&2; return 1; }
}
