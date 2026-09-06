#!/usr/bin/env bash
# Deterministischer Orchestrator: eine Versuchsschleife mit Eskalation.
#
# Ein Aufruf bearbeitet genau einen Task. Pro Runde laeuft im Modus `managed`
# zuerst der Manager, dann in jedem Modus der Worker und danach das
# deterministische Prueftor. Eine rote Pruefung zaehlt einen Versuch und hebt
# den Modus um genau eine Stufe (single -> verified -> managed -> blocked).
# Gruen, `blocked`, `ask_human`, das Versuchslimit, ein ausbleibender Fortschritt
# oder MAX_GLOBAL_ITERATIONS beenden den Lauf; jedes Ende hinterlaesst einen
# Laufbeleg in docs/state/handoff.md.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/agent/common.sh"
. "$script_dir/agent/ledger.sh"
. "$script_dir/agent/route.sh"
. "$script_dir/agent/rolecall.sh"

project_dir=$(agent_project_root "$script_dir") || exit 1
selection=''; requested_task=''; manual_mode=''; scratch_dir=''; run_state=''
run_outcome=''; last_result=''; call_sequence=0
dry_run=false; allow_dirty=false; lock_held=false; run_active=false

usage() {
  echo "Verwendung: $0 (--task ID | --next | --dry-run) [--mode MODUS] [--allow-dirty] [--project-dir PFAD]"
  echo "  --dry-run zeigt nur Route, Limits und geplante Rollen; er schreibt nichts."
}
bad_usage() { usage >&2; exit 2; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) [ "$#" -ge 2 ] || bad_usage; [ -z "$selection" ] || bad_usage; selection=task; requested_task=$2; shift 2 ;;
    --next) [ -z "$selection" ] || bad_usage; selection=next; shift ;;
    --dry-run) dry_run=true; shift ;;
    --mode) [ "$#" -ge 2 ] || bad_usage; manual_mode=$2; shift 2 ;;
    --allow-dirty) allow_dirty=true; shift ;;
    --project-dir) [ "$#" -ge 2 ] || bad_usage; project_dir=$2; shift 2 ;;
    *) echo "orchestrate: unbekannte Option $1" >&2; bad_usage ;;
  esac
done
[ -n "$selection" ] || { [ "$dry_run" = true ] && selection=next || bad_usage; }
case "$manual_mode" in ''|single|verified|managed) ;; *) echo "orchestrate: unbekannter Modus '$manual_mode'" >&2; exit 1 ;; esac

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "orchestrate: Projektpfad fehlt" >&2; exit 1; }
validator="$script_dir/validate-ledger.sh"; config_reader="$script_dir/agent/config.sh"
status_gate="$script_dir/agent/status.sh"; verification_gateway="$script_dir/verify-task.sh"
context_builder="$script_dir/agent/context.sh"; policy="$script_dir/agent/policy.sh"
runner_adapter="$script_dir/agent/runner.sh"; runner=${ORCHESTRATOR_RUNNER:-$runner_adapter}
tasks_dir="$project_dir/docs/tasks"; verification_dir="$project_dir/docs/verification"
notes_file="$project_dir/docs/state/notes.md"; handoff_file="$project_dir/docs/state/handoff.md"
lock_dir="$project_dir/.agent-runs/.orchestrator-lock"

[ -x "$runner" ] || { echo "orchestrate: Runner ist nicht ausführbar: $runner" >&2; exit 1; }
"$config_reader" --check "$project_dir/.agent/config.env" || exit 1
"$validator" --project-dir "$project_dir" >/dev/null || exit 1
config_value() { "$config_reader" --get "$1" "$project_dir/.agent/config.env"; }
max_iterations=$(config_value MAX_GLOBAL_ITERATIONS) || exit 1
max_task_attempts=$(config_value MAX_TASK_ATTEMPTS) || exit 1
max_no_progress=$(config_value MAX_NO_PROGRESS) || exit 1
verify_timeout=$(config_value VERIFY_TIMEOUT_SECONDS) || exit 1
max_infra_retries=$(config_value MAX_INFRA_RETRIES) || exit 1
retry_backoff=$(config_value RETRY_BACKOFF_SECONDS) || exit 1
finalizer_mode=$(config_value FINALIZER) || exit 1

validate_task_candidate() { "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null; }

task_is_ready() {
  candidate_file=$(ledger_task_path_by_id "$tasks_dir" "$1") || return 1
  [ "$(ledger_scalar "$candidate_file" status)" = todo ] || return 1
  [ "$(ledger_scalar "$candidate_file" attempts)" -lt "$max_task_attempts" ] || return 1
  while IFS= read -r dependency; do
    [ -n "$dependency" ] || continue
    dependency_file=$(ledger_task_path_by_id "$tasks_dir" "$dependency") || return 1
    [ "$(ledger_scalar "$dependency_file" status)" = done ] || return 1
  done <<EOF
$(ledger_list "$candidate_file" depends_on)
EOF
}

# --- Laufzustand ------------------------------------------------------------
# Unversioniert und nie gelesen, um einen Lauf fortzusetzen: er fuehrt Phase,
# Runde und Fortschritt innerhalb eines Aufrufs und bleibt als Beleg zurueck.
run_phase=plan; run_iteration=1; run_attempt=1; run_fingerprint=none

write_run_state() {
  [ -n "$run_state" ] || return 0
  {
    echo "run_id=$run_id"; echo "task_id=$task_id"; echo "mode=$mode"
    echo "phase=$run_phase"; echo "iteration=$run_iteration"; echo "attempt=$run_attempt"
    echo "last_progress_fingerprint=$run_fingerprint"; echo "started_at=$started_at"
    echo "human_gate=$human_gate"; echo "outcome=$run_outcome"
  } > "$run_state"
}

set_phase() { run_phase=$1; write_run_state; }

# Eine Zeile pro Lauf, append-only, unversioniert.
append_run_metric() {
  metrics_file="$project_dir/.agent-runs/metrics.csv"
  [ -f "$metrics_file" ] || printf '%s\n' 'run_id,task_id,mode,attempt,outcome,started_at,finished_at' > "$metrics_file"
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$run_id" "$task_id" "$mode" "$run_attempt" "$1" \
    "$started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$metrics_file"
}

result_value() {
  jq -r --arg key "$1" '.[$key] // ""' "$last_result" 2>/dev/null
}

# --- Pruefung und Fehlerbuchhaltung -----------------------------------------
verify_candidate() {
  set_phase verify
  call_sequence=$((call_sequence + 1))
  mkdir -p "$run_dir/outputs" || return 1
  verify_log="$run_dir/outputs/$(printf '%02d' "$call_sequence")-verify.log"
  attempt_value=$(($(ledger_scalar "$task_file" attempts) + 1))
  verification_result=green
  "$verification_gateway" --project-dir "$project_dir" --run-id "$run_id" --attempt "$attempt_value" \
    --timeout "$verify_timeout" "$task_id" > "$verify_log" 2>&1 || verification_result=red
  [ "$verification_result" = green ]
}

record_failure() {
  attempts=$(ledger_scalar "$task_file" attempts) || return 1
  [ "$attempts" -lt "$max_task_attempts" ] || return 1
  ledger_atomic_replace_scalar "$task_file" attempts "$((attempts + 1))" validate_task_candidate || return 1
  run_attempt=$((attempts + 2))
  ledger_append_note "$notes_file" "$task_id" 'Fehlgeschlagene Verifikation' \
    "Task $task_id: Verifikation rot; siehe docs/verification/$task_id.md." \
    "\`docs/verification/$task_id.md\`" || return 1
}

# Der Fingerprint beschreibt eine Runde: Produkt, Task-Status, Prueferstand,
# Ergebnis und Notizen. Zwei gleiche Fingerprints heissen: nichts bewegt sich.
progress_fingerprint() {
  agent_product_manifest "$project_dir" "$run_dir/.progress-product" || return 1
  {
    cat "$run_dir/.progress-product"
    while IFS= read -r file; do
      [ -n "$file" ] && printf '%s|%s\n' "$(ledger_scalar "$file" id)" "$(ledger_scalar "$file" status)"
    done <<EOF
$(ledger_task_files "$tasks_dir")
EOF
    shasum -a 256 "$project_dir/scripts/verify.sh"
    printf 'verification=%s\n' "${verification_result:-none}"
    awk '/^## N-[0-9]+[[:space:]]/ { print $2 }' "$notes_file"
  } | shasum -a 256 | awk '{print $1}'
}

# --- Laufenden --------------------------------------------------------------
finish_success() {
  human_review=$(ledger_scalar "$task_file" human_review) || return 1
  if [ "$human_review" = true ] || [ "$human_gate" = true ]; then target=review; else target=done; fi
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" "$target" in_progress || return 1
  [ "$target" = review ] && run_outcome=review || run_outcome=success
  set_phase finished
  run_active=false; echo "orchestrate: Task $task_id ist $target"
}

# Ein Modelltext wird nie roh in eine Ledger-Datei geschrieben: Zeilenumbrueche
# werden zu Leerzeichen, Steuerzeichen fallen weg, die Laenge ist begrenzt.
safe_text() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '\000-\010\013\014\016-\037' | cut -c1-400
}

# Ein blockierter Lauf endet mit einem Grund im Task. Der Finalizer ist ein
# zusaetzlicher Modellaufruf und laeuft nur, wenn FINALIZER=llm es erlaubt.
block_current_task() {
  safe_reason=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_.:-' | cut -c1-120)
  [ -n "$safe_reason" ] || safe_reason=ORCHESTRATION_BLOCKED
  # Eine offene Frage ist keine Sackgasse: sie braucht keine Erzaehlung, nur
  # eine Antwort. Der Finalizer laeuft deshalb nur bei echten Blockaden.
  [ "$finalizer_mode" != llm ] || [ "$safe_reason" = ASK_HUMAN ] \
    || run_role finalizer "$task_id" finalize || echo "orchestrate: Finalizer scheiterte" >&2
  ledger_atomic_replace_scalar "$task_file" blocked_reason "$safe_reason" validate_task_candidate || return 1
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" blocked in_progress || return 1
  case "$safe_reason" in
    NO_PROGRESS) run_outcome=no_progress ;; ASK_HUMAN) run_outcome=ask_human ;;
    *VERIFY_ERROR*) run_outcome=verification_error ;; *) run_outcome=blocked ;;
  esac
  set_phase finished
  run_active=false
  echo "orchestrate: Task $task_id blockiert ($safe_reason)" >&2
}

# Die Frage des Managers steht im Task, nicht in einer zweiten Datei. Der Mensch
# antwortet dort und oeffnet die Aufgabe mit `./scripts/task.sh reopen` wieder.
ask_human() {
  question=$(safe_text "$1")
  [ -n "$question" ] || question='Der Manager hat keine Frage formuliert.'
  temp=$(mktemp "$tasks_dir/.task.tmp.XXXXXX") || return 1
  awk '$0 == "# Offene Frage" { exit } { print }' "$task_file" > "$temp" || { rm -f "$temp"; return 1; }
  printf '# Offene Frage\n- %s\n- Antwort hier eintragen, danach `./scripts/task.sh reopen %s`.\n' \
    "$question" "$task_id" >> "$temp"
  validate_task_candidate "$temp" || { rm -f "$temp"; echo "orchestrate: Frage macht den Task ungültig" >&2; return 1; }
  agent_atomic_write "$task_file" "$temp" || { rm -f "$temp"; return 1; }
  rm -f "$temp"
  block_current_task ASK_HUMAN
}

# Der Laufbeleg ist deterministisch: der Orchestrator schreibt ihn bei jedem
# Ende selbst, unabhaengig davon, ob eine Rolle etwas dazu gesagt hat. Er
# ersetzt den vorhandenen Abschnitt und steht sonst direkt unter dem Titel.
write_run_receipt() {
  [ -f "$handoff_file" ] || return 0
  verifier_state=NEVER
  green_reference=keiner
  case "$(ledger_scalar "$verification_dir/$task_id.md" result 2>/dev/null || true)" in
    green) verifier_state=GREEN; green_reference="\`docs/verification/$task_id.md\`" ;;
    red) verifier_state=RED ;;
  esac
  receipt="$run_dir/receipt.md"
  printf '## Laufbeleg\n\n- Run-ID: `%s`\n- Modus: %s\n- Ergebnis: %s\n- Task: %s (%s)\n%s\n%s\n' \
    "$run_id" "$mode" "${run_outcome:-unbekannt}" "$task_id" \
    "$(ledger_scalar "$task_file" status 2>/dev/null || echo unbekannt)" \
    "- Verifierstatus: $verifier_state — \`docs/verification/$task_id.md\`" \
    "- Letzter grüner Stand: $green_reference" > "$receipt" || return 1
  temp=$(mktemp "$project_dir/docs/state/.handoff.tmp.XXXXXX") || return 1
  awk -v receipt="$receipt" '
    function emit() { while ((getline line < receipt) > 0) print line; close(receipt); done_receipt=1 }
    $0 == "## Laufbeleg" { skip=1; if (!done_receipt) emit(); next }
    skip && /^## / { skip=0 }
    skip { next }
    { print; if (!done_receipt && NR == 1 && $0 ~ /^# /) { print ""; emit() } }
    END { if (!done_receipt) emit() }
  ' "$handoff_file" > "$temp" || { rm -f "$temp"; return 1; }
  agent_atomic_write "$handoff_file" "$temp" || { rm -f "$temp"; return 1; }
  rm -f "$temp"
}

# --- Versuchsschleife -------------------------------------------------------
attempt_loop() {
  no_progress=0
  iteration=1
  while [ "$iteration" -le "$max_iterations" ]; do
    run_iteration=$iteration
    worker_variant=normal
    if [ "$mode" = managed ]; then
      run_role manager "$task_id" plan || return 1
      action=$(result_value action)
      case "$action" in
        done)
          ledger_verification_is_green "$verification_dir" "$task_id" "$project_dir" "$task_file" || {
            echo "orchestrate: Manager meldete done ohne grünen Prüfbeleg" >&2; return 1; }
          finish_success; return 0 ;;
        blocked) block_current_task "MANAGER_$(printf '%s' "$(result_value reason)" | tr -cd 'A-Za-z0-9_')"; return 1 ;;
        ask_human) ask_human "$(result_value question)"; return 1 ;;
        dispatch) ;;
        *) echo "orchestrate: ungültige Manageraktion '$action'" >&2; return 1 ;;
      esac
      chosen=$(result_value task_id)
      [ -z "$chosen" ] || [ "$chosen" = "$task_id" ] || {
        echo "orchestrate: Manager wählte Task $chosen; dieser Lauf bearbeitet $task_id" >&2; return 1; }
    fi

    # Der letzte erlaubte Versuch laeuft immer fresh: eine Runde ohne die
    # Vorgeschichte, die bis hierher nicht getragen hat.
    attempts=$(ledger_scalar "$task_file" attempts) || return 1
    if [ "$mode" = managed ] && [ "$((attempts + 1))" -ge "$max_task_attempts" ]; then worker_variant=fresh; fi
    [ "$worker_variant" != fresh ] || reset_to_run_start || return 1
    run_role worker "$task_id" work "$worker_variant" || return 1
    [ "$(result_value result)" != blocked ] || { block_current_task WORKER_BLOCKED; return 1; }
    if verify_candidate; then finish_success; return 0; fi

    # Ein technischer Fehler des Pruefwegs ist keine Aussage ueber den
    # Kandidaten und verbraucht deshalb keinen Versuch.
    if [ "$(ledger_scalar "$verification_dir/$task_id.md" failure_kind 2>/dev/null || true)" = verifier ]; then
      run_outcome=verification_error
      echo "orchestrate: Prüfweg ist defekt; der Versuch wird nicht gezählt" >&2
      return 1
    fi
    record_failure || { block_current_task ATTEMPT_LIMIT; return 1; }

    fingerprint=$(progress_fingerprint) || return 1
    if [ "$fingerprint" = "$run_fingerprint" ]; then no_progress=$((no_progress + 1)); else no_progress=0; fi
    run_fingerprint=$fingerprint
    [ "$no_progress" -lt "$max_no_progress" ] || { block_current_task NO_PROGRESS; return 1; }

    # Der Router liest die neuen attempts: genau eine Stufe hoeher.
    mode=$(agent_route_mode "$task_file" "$manual_mode" "$max_task_attempts") || return 1
    write_run_state
    [ "$mode" != blocked ] || { block_current_task ATTEMPT_LIMIT; return 1; }
    echo "orchestrate: Versuch rot; Modus ist jetzt $mode"
    iteration=$((iteration + 1))
  done
  block_current_task ITERATION_LIMIT
  return 1
}

# --- Aufraeumen -------------------------------------------------------------
# Ein Lauf endet nie mit einem Task in `in_progress`: was der Orchestrator
# angefangen hat, faellt beim Abbruch auf `todo` zurueck.
release_active_task() {
  [ -n "${task_file:-}" ] || return 0
  [ "$(ledger_scalar "$task_file" status 2>/dev/null || true)" = in_progress ] || return 0
  "$status_gate" --project-dir "$project_dir" set-status "$task_id" todo in_progress >/dev/null 2>&1 \
    || echo "orchestrate: Task $task_id konnte nicht auf todo zurueckgesetzt werden" >&2
}

cleanup() {
  exit_status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$run_state" ] && [ -f "$run_state" ]; then
    case "$run_phase" in finished|paused) ;; *) run_phase=failed ;; esac
    if [ -z "$run_outcome" ]; then
      case "$exit_status:$(ledger_scalar "$task_file" status 2>/dev/null || true)" in
        130:*) run_outcome=cancelled ;; *:done) run_outcome=success ;;
        *:review) run_outcome=review ;; *:blocked) run_outcome=blocked ;;
        *) run_outcome=failed ;;
      esac
    fi
    write_run_state
    [ "$run_active" = false ] || release_active_task
    write_run_receipt || echo "orchestrate: Laufbeleg konnte nicht geschrieben werden" >&2
    append_run_metric "$run_outcome" || true
  fi
  [ -z "$scratch_dir" ] || rm -rf "$scratch_dir"
  [ "$lock_held" = false ] || agent_release_lock "$lock_dir"
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# --- Lauf -------------------------------------------------------------------
case "$selection" in
  task) task_id=$requested_task ;;
  next) task_id=$("$script_dir/next-tasks.sh" --project-dir "$project_dir" | awk -F '[ |]+' '$1 == "READY:" { print $2; exit }')
        [ -n "$task_id" ] || { echo "orchestrate: kein bereiter Task" >&2; exit 1; } ;;
esac
case "$task_id" in ''|*[!0-9]*) echo "orchestrate: ungültige Task-ID" >&2; exit 1 ;; esac

# Ein --dry-run zeigt nur, was ein echter Lauf taete; er schreibt nichts.
if [ "$dry_run" = true ]; then
  task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
  mode=$(agent_route_mode "$task_file" "$manual_mode" "$max_task_attempts") || exit 1
  human_gate=$(ledger_scalar "$task_file" human_review) || exit 1
  [ "$(ledger_scalar "$task_file" class)" != open ] || human_gate=true
  printf 'DRY_RUN=true\nTASK_ID=%s\nMODE=%s\nHUMAN_GATE=%s\nFINALIZER=%s\nMAX_GLOBAL_ITERATIONS=%s\nMAX_TASK_ATTEMPTS=%s\nMAX_NO_PROGRESS=%s\n' \
    "$task_id" "$mode" "$human_gate" "$finalizer_mode" "$max_iterations" "$max_task_attempts" "$max_no_progress"
  case "$mode" in
    single|verified) echo 'PLANNED_CALLS=worker,verify,eskalation-bei-rot' ;;
    managed) echo 'PLANNED_CALLS=manager,worker-oder-worker-fresh,verify,eskalation-bei-rot' ;;
    *) echo 'PLANNED_CALLS=none' ;;
  esac
  exit 0
fi

mkdir -p "$project_dir/.agent-runs" || exit 1
agent_acquire_lock "$lock_dir" || exit 1
lock_held=true

# Wer die Sperre haelt, ist der einzige Lauf. Ein Task, der trotzdem noch
# `in_progress` traegt, stammt aus einem Abbruch und faellt sichtbar auf `todo`.
while IFS= read -r stale_file; do
  [ -n "$stale_file" ] || continue
  [ "$(ledger_scalar "$stale_file" status 2>/dev/null || true)" = in_progress ] || continue
  stale_id=$(ledger_scalar "$stale_file" id) || continue
  echo "orchestrate: abgebrochener Lauf gefunden; Task $stale_id wird auf todo zurueckgesetzt" >&2
  "$status_gate" --project-dir "$project_dir" set-status "$stale_id" todo in_progress >/dev/null || exit 1
done <<EOF
$(ledger_task_files "$tasks_dir")
EOF

task_is_ready "$task_id" || { echo "orchestrate: Task $task_id ist nicht bereit" >&2; exit 1; }
task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
attempts_at_start=$(ledger_scalar "$task_file" attempts) || exit 1
[ "$attempts_at_start" -lt "$max_task_attempts" ] || { echo "orchestrate: hartes Versuchslimit für Task $task_id ist erreicht" >&2; exit 1; }
mode=$(agent_route_mode "$task_file" "$manual_mode" "$max_task_attempts") || exit 1
[ "$mode" != blocked ] || { echo "orchestrate: Router blockiert Task $task_id vor dem Start" >&2; exit 1; }
# Ein offener Task und ein verlangtes Review enden nie unbesehen auf done.
human_gate=$(ledger_scalar "$task_file" human_review) || exit 1
[ "$(ledger_scalar "$task_file" class)" != open ] || human_gate=true

# Ohne Commit gibt es keinen Stand, gegen den «schmutzig» etwas bedeuten
# koennte. Das Ledger zaehlt nicht mit: der Orchestrator schreibt es selbst.
if git -C "$project_dir" rev-parse --verify -q HEAD >/dev/null 2>&1 &&
   [ -n "$(git -C "$project_dir" status --porcelain -- \
     ':(exclude)docs/tasks' ':(exclude)docs/state' ':(exclude)docs/verification' 2>/dev/null)" ] &&
   [ "$allow_dirty" = false ]; then
  echo "orchestrate: Arbeitsverzeichnis ist nicht sauber; wiederhole bewusst mit --allow-dirty" >&2
  exit 1
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")"
run_dir="$project_dir/.agent-runs/$run_id"
mkdir "$run_dir" || exit 1
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-scratch.XXXXXX") || exit 1
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"$status_gate" --project-dir "$project_dir" set-status "$task_id" in_progress todo >/dev/null || exit 1
run_active=true
run_state="$run_dir/run.env"
run_attempt=$((attempts_at_start + 1))
write_run_state || exit 1
# Der Snapshot des Laufstarts liegt ausserhalb des Arbeitsbaums: ein Agent
# koennte ihn sonst passend zu seinen Aenderungen umschreiben.
run_start_manifest="$scratch_dir/run-start.manifest"
agent_repo_manifest "$project_dir" "$run_start_manifest" || exit 1

attempt_loop
