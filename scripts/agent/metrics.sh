#!/usr/bin/env bash
# Lokale, idempotente Laufmetriken ohne externe Telemetrie.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/common.sh"
. "$script_dir/ledger.sh"

METRICS_HEADER='run_id,task_id,class,mode,model,prompt_version,manager_calls,worker_calls,verifier_runs,rounds,attempts,tokens_in,tokens_out,cost_estimate,duration_seconds,verification,human_review,outcome,date'

metrics_fail() { echo "metrics: $1" >&2; return 1; }

metrics_value() {
  file=$1 key=$2
  awk -F= -v wanted="$key" '$1 == wanted { if (seen++) exit 2; print substr($0,length(wanted)+2) } END { if (!seen) exit 1 }' "$file"
}

metrics_safe_value() {
  value=$1 label=$2
  case "$value" in *','*|*$'\n'*|*$'\r'*) metrics_fail "$label darf kein Komma oder Zeilenende enthalten"; return 1 ;; esac
}

metrics_ensure_schema() {
  project_dir=$1
  file="$project_dir/docs/state/metrics.csv"
  mkdir -p "$(dirname -- "$file")" || return 1
  if [ ! -e "$file" ]; then
    tmp=$(mktemp "$(dirname -- "$file")/.metrics.csv.tmp.XXXXXX") || return 1
    printf '%s\n' "$METRICS_HEADER" > "$tmp"
    agent_atomic_write "$file" "$tmp"
    rm -f "$tmp"
    return
  fi
  [ -f "$file" ] && [ ! -L "$file" ] || { metrics_fail 'metrics.csv muss eine regulaere Datei sein'; return 1; }
  header=$(sed -n '1p' "$file")
  [ "$header" = "$METRICS_HEADER" ] && return 0
  # Eine aeltere Datei ohne Laufzeilen (nur Kopfzeile) wird verlustfrei auf das
  # aktuelle Schema umgestellt; mit Laufzeilen bleibt sie unangetastet.
  if [ "$(wc -l < "$file" | tr -d ' ')" -eq 1 ]; then
    tmp=$(mktemp "$(dirname -- "$file")/.metrics.csv.tmp.XXXXXX") || return 1
    printf '%s\n' "$METRICS_HEADER" > "$tmp"
    agent_atomic_write "$file" "$tmp"
    rm -f "$tmp"
    return
  fi
  metrics_fail 'metrics.csv hat ein unbekanntes oder nicht leer migrierbares Schema'
  return 1
}

metrics_set_value() {
  file=$1 key=$2 value=$3
  metrics_safe_value "$value" "$key" || return 1
  tmp=$(mktemp "$(dirname -- "$file")/.run-metadata.tmp.XXXXXX") || return 1
  awk -F= -v wanted="$key" -v replacement="$value" '
    $1 == wanted { if (seen++) exit 2; print wanted "=" replacement; next }
    { print }
    END { if (!seen) print wanted "=" replacement }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  agent_atomic_write "$file" "$tmp"
  rm -f "$tmp"
}

metrics_write_start() {
  project_dir=$1 run_dir=$2 run_id=$3 task_id=$4 mode=$5 started_at=$6 attempt=$7 base_fingerprint=$8
  task_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$task_id") || return 1
  task_class=$(ledger_scalar "$task_file" class) || return 1
  human_review=$(ledger_scalar "$task_file" human_review) || return 1
  prompt_version=$("$script_dir/config.sh" --get PROMPT_VERSION "$project_dir/.agent/config.env") || return 1
  for pair in "$run_id:run_id" "$task_id:task_id" "$mode:mode" "$started_at:started_at" "$attempt:attempts" "$base_fingerprint:base_fingerprint" "$task_class:class" "$human_review:human_review" "$prompt_version:prompt_version"; do
    metrics_safe_value "${pair%:*}" "${pair#*:}" || return 1
  done
  mkdir -p "$run_dir/metadata" || return 1
  destination="$run_dir/metadata/run.env"
  [ ! -e "$destination" ] || { metrics_fail "Laufmetadaten existieren bereits: $run_id"; return 1; }
  tmp=$(mktemp "$run_dir/metadata/.run.env.tmp.XXXXXX") || return 1
  {
    echo "run_id=$run_id"
    echo "task_id=$task_id"
    echo "class=$task_class"
    echo "mode=$mode"
    echo 'recommended_mode='
    echo 'route_reason_code=none'
    echo 'route_rule_version=1'
    echo 'rollout_stage='
    echo "prompt_version=$prompt_version"
    echo "attempts=$attempt"
    echo "human_review=$human_review"
    echo "base_fingerprint=$base_fingerprint"
    echo "started_at=$started_at"
    echo 'finished_at='
    echo 'outcome='
    echo 'finalized=false'
    echo 'dry_run=false'
  } > "$tmp"
  agent_atomic_write "$destination" "$tmp"
  rm -f "$tmp"
}

metrics_record_route() {
  run_dir=$1 actual=$2 recommended=$3 reason=$4 rule_version=$5 rollout_stage=$6 human_gate=$7
  file="$run_dir/metadata/run.env"
  if [ ! -f "$file" ]; then
    mkdir -p "$run_dir/metadata" || return 1
    tmp=$(mktemp "$run_dir/metadata/.route.env.tmp.XXXXXX") || return 1
    printf 'mode=%s\nrecommended_mode=%s\nroute_reason_code=%s\nroute_rule_version=%s\nrollout_stage=%s\nhuman_review=%s\n' "$actual" "$recommended" "$reason" "$rule_version" "$rollout_stage" "$human_gate" > "$tmp"
    agent_atomic_write "$run_dir/metadata/route.env" "$tmp"
    rm -f "$tmp"
    return
  fi
  metrics_set_value "$file" mode "$actual" || return 1
  metrics_set_value "$file" recommended_mode "$recommended" || return 1
  metrics_set_value "$file" route_reason_code "$reason" || return 1
  metrics_set_value "$file" route_rule_version "$rule_version" || return 1
  metrics_set_value "$file" rollout_stage "$rollout_stage" || return 1
  [ "$human_gate" != true ] || metrics_set_value "$file" human_review true
}

metrics_append_unique() (
  project_dir=$1 run_id=$2 task_id=$3 line=$4
  file="$project_dir/docs/state/metrics.csv"
  lock="$project_dir/docs/state/.metrics-write-lock"
  mkdir "$lock" 2>/dev/null || { metrics_fail 'metrics.csv wird bereits geschrieben'; return 1; }
  tmp=$(mktemp "$project_dir/docs/state/.metrics.csv.tmp.XXXXXX") || { rmdir "$lock"; return 1; }
  cleanup_metrics() { rm -f "$tmp"; rmdir "$lock" 2>/dev/null || true; }
  trap cleanup_metrics EXIT HUP INT TERM
  [ "$(sed -n '1p' "$file")" = "$METRICS_HEADER" ] || { metrics_fail 'metrics.csv hat ein unbekanntes Schema'; return 1; }
  existing=$(awk -F, -v run="$run_id" -v task="$task_id" '$1 == run || ($1 == run && $2 == task) { print; exit }' "$file")
  if [ -n "$existing" ]; then
    [ "$existing" = "$line" ] && return 0
    metrics_fail "Run-ID $run_id wurde bereits mit anderen Werten finalisiert"
    return 1
  fi
  cp "$file" "$tmp" || return 1
  printf '%s\n' "$line" >> "$tmp" || return 1
  agent_copy_mode "$file" "$tmp" || return 1
  mv -f "$tmp" "$file" || return 1
  trap - EXIT HUP INT TERM
  rmdir "$lock" 2>/dev/null || true
)

metrics_reopen() (
  project_dir=$1 run_dir=$2
  run_file="$run_dir/metadata/run.env"
  [ -f "$run_file" ] || { metrics_fail 'Laufmetadaten fehlen'; return 1; }
  [ "$(metrics_value "$run_file" finalized 2>/dev/null || true)" = true ] || return 0
  run_id=$(metrics_value "$run_file" run_id) || return 1
  file="$project_dir/docs/state/metrics.csv"
  lock="$project_dir/docs/state/.metrics-write-lock"
  mkdir "$lock" 2>/dev/null || { metrics_fail 'metrics.csv wird bereits geschrieben'; return 1; }
  tmp=$(mktemp "$project_dir/docs/state/.metrics.csv.tmp.XXXXXX") || { rmdir "$lock"; return 1; }
  cleanup_reopen() { rm -f "$tmp"; rmdir "$lock" 2>/dev/null || true; }
  trap cleanup_reopen EXIT HUP INT TERM
  awk -F, -v run="$run_id" '$1 == run { removed++; next } { print } END { if (removed > 1) exit 1 }' "$file" > "$tmp" || { metrics_fail "finalisierte Zeile fuer $run_id ist nicht eindeutig"; return 1; }
  agent_copy_mode "$file" "$tmp" || return 1
  mv -f "$tmp" "$file" || return 1
  trap - EXIT HUP INT TERM
  rmdir "$lock" 2>/dev/null || true
  rm -f "$run_dir/metadata/summary.csv"
  metrics_set_value "$run_file" finished_at '' || return 1
  metrics_set_value "$run_file" outcome '' || return 1
  metrics_set_value "$run_file" finalized false
)

metrics_sum_field() {
  key=$1; shift
  [ "$#" -gt 0 ] || return 0
  awk -F= -v wanted="$key" '
    $1 == wanted {
      if ($2 == "" || $2 == "unknown" || $2 !~ /^[0-9]+$/) { unknown=1; next }
      total += $2; found=1
    }
    END { if (found && !unknown) print total }
  ' "$@"
}

metrics_sum_decimal_field() {
  key=$1; shift
  [ "$#" -gt 0 ] || return 0
  awk -F= -v wanted="$key" '
    $1 == wanted {
      if ($2 == "" || $2 == "unknown" || $2 !~ /^[0-9]+([.][0-9]+)?$/) { unknown=1; next }
      total += $2; found=1
    }
    END { if (found && !unknown) printf "%.6f", total }
  ' "$@"
}

metrics_duration() {
  started=$1 finished=$2
  perl -MTime::Piece -e '
    eval {
      my ($start, $finish) = map { Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%SZ") } @ARGV;
      my $seconds = $finish - $start;
      print int($seconds) if $seconds >= 0;
    };
  ' "$started" "$finished" 2>/dev/null
}

metrics_finalize() {
  project_dir=$1 run_dir=$2 outcome=$3
  case "$outcome" in success|review|blocked|no_progress|infrastructure_error|verification_error|cancelled) ;; *) metrics_fail "unbekanntes Outcome $outcome"; return 1 ;; esac
  metrics_ensure_schema "$project_dir" || return 1
  run_file="$run_dir/metadata/run.env"
  [ -f "$run_file" ] || { metrics_fail 'Laufmetadaten fehlen'; return 1; }
  summary_file="$run_dir/metadata/summary.csv"
  if [ -f "$summary_file" ]; then
    line=$(sed -n '1p' "$summary_file")
    run_id=$(metrics_value "$run_file" run_id) || return 1
    task_id=$(metrics_value "$run_file" task_id) || return 1
    metrics_append_unique "$project_dir" "$run_id" "$task_id" "$line" || return 1
    metrics_set_value "$run_file" finalized true
    return
  fi

  run_id=$(metrics_value "$run_file" run_id) || return 1
  task_id=$(metrics_value "$run_file" task_id) || return 1
  task_class=$(metrics_value "$run_file" class) || return 1
  mode=$(metrics_value "$run_file" mode) || return 1
  prompt_version=$(metrics_value "$run_file" prompt_version) || return 1
  attempts=$(metrics_value "$run_file" attempts) || return 1
  human_review=$(metrics_value "$run_file" human_review) || return 1
  started_at=$(metrics_value "$run_file" started_at) || return 1
  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  date_value=${finished_at%%T*}

  metadata_files=()
  while IFS= read -r file; do metadata_files+=("$file"); done < <(find "$run_dir/metadata" -maxdepth 1 -type f -name '*.env' ! -name run.env -print | LC_ALL=C sort)
  manager_calls=0 worker_calls=0 model=''
  for file in "${metadata_files[@]}"; do
    base=$(basename -- "$file")
    case "$base" in *manager-plan*|*manager-manage*) manager_calls=$((manager_calls + 1)) ;; esac
    case "$base" in *worker-task*|*worker-fresh*|*worker-brainstorm*) worker_calls=$((worker_calls + 1)) ;; esac
    current_model=$(metrics_value "$file" model 2>/dev/null || true)
    if [ -n "$current_model" ]; then
      if [ -z "$model" ]; then model=$current_model; elif [ "$model" != "$current_model" ]; then model=mixed; fi
    fi
  done
  metrics_safe_value "$model" model || model=''
  tokens_in=$(metrics_sum_field tokens_in "${metadata_files[@]}" 2>/dev/null || true)
  tokens_out=$(metrics_sum_field tokens_out "${metadata_files[@]}" 2>/dev/null || true)
  cost_estimate=$(metrics_sum_decimal_field cost_estimate "${metadata_files[@]}" 2>/dev/null || true)
  verifier_runs=$(find "$run_dir" -type f \( -name '*-verify.log' -o -path '*/candidates/*/report.md' \) -print 2>/dev/null | awk 'END { print NR+0 }')
  rounds=$(find "$run_dir/metadata" -maxdepth 1 -type f -name '*manager-manage*.env' -print 2>/dev/null | awk 'END { print NR+0 }')
  duration=$(metrics_duration "$started_at" "$finished_at")
  current_run="$project_dir/docs/state/current-run.md"
  if [ -f "$current_run" ] && [ "$(ledger_scalar "$current_run" run_id 2>/dev/null || true)" = "$run_id" ]; then
    attempts=$(ledger_scalar "$current_run" attempt 2>/dev/null || printf '%s' "$attempts")
  fi
  verification=''
  latest="$project_dir/docs/verification/latest.md"
  if [ -f "$latest" ] && [ "$(ledger_scalar "$latest" run_id 2>/dev/null || true)" = "$run_id" ]; then
    verification=$(ledger_scalar "$latest" result 2>/dev/null || true)
  elif find "$run_dir/candidates" -type f -name report.md -exec grep -q '^result: red$' {} \; -print -quit 2>/dev/null | grep -q .; then
    verification=red
  fi
  case "$outcome" in
    success|review)
      [ "$verification" = green ] || { metrics_fail "$outcome erfordert einen gruenen maschinellen Pruefbeleg"; return 1; } ;;
  esac
  if [ "$human_review" = true ]; then
    if [ "$outcome" = review ]; then human_review=pending
    elif [ "$outcome" = success ]; then human_review=approved
    else human_review=required
    fi
  else
    human_review=not_required
  fi
  changed_paths="$run_dir/metadata/changed-paths.txt"
  {
    find "$run_dir/manifests" -maxdepth 1 -type f -name '*.changed' -exec cat {} \; 2>/dev/null || true
    find "$run_dir/candidates" -type f -name changed-paths.txt -exec cat {} \; 2>/dev/null || true
  } | sed '/^$/d' | LC_ALL=C sort -u > "$changed_paths"
  changed_files=$(awk 'END {print NR+0}' "$changed_paths")
  if [ -f "$run_dir/rollback.performed" ]; then rollback_performed=true; else rollback_performed=false; fi
  for value_label in "$run_id:run_id" "$task_id:task_id" "$task_class:class" "$mode:mode" "$model:model" "$prompt_version:prompt_version" "$verification:verification" "$human_review:human_review"; do
    metrics_safe_value "${value_label%:*}" "${value_label#*:}" || return 1
  done
  line="$run_id,$task_id,$task_class,$mode,$model,$prompt_version,$manager_calls,$worker_calls,$verifier_runs,$rounds,$attempts,$tokens_in,$tokens_out,$cost_estimate,$duration,$verification,$human_review,$outcome,$date_value"
  metrics_set_value "$run_file" finished_at "$finished_at" || return 1
  metrics_set_value "$run_file" outcome "$outcome" || return 1
  metrics_set_value "$run_file" manager_calls "$manager_calls" || return 1
  metrics_set_value "$run_file" worker_calls "$worker_calls" || return 1
  metrics_set_value "$run_file" verifier_runs "$verifier_runs" || return 1
  metrics_set_value "$run_file" rounds "$rounds" || return 1
  metrics_set_value "$run_file" attempts "$attempts" || return 1
  metrics_set_value "$run_file" tokens_in "$tokens_in" || return 1
  metrics_set_value "$run_file" tokens_out "$tokens_out" || return 1
  metrics_set_value "$run_file" cost_estimate "$cost_estimate" || return 1
  metrics_set_value "$run_file" duration_seconds "$duration" || return 1
  metrics_set_value "$run_file" verification "$verification" || return 1
  metrics_set_value "$run_file" human_review "$human_review" || return 1
  metrics_set_value "$run_file" changed_files "$changed_files" || return 1
  metrics_set_value "$run_file" diff_lines '' || return 1
  metrics_set_value "$run_file" rollback_performed "$rollback_performed" || return 1
  metrics_set_value "$run_file" new_defects '' || return 1
  tmp=$(mktemp "$run_dir/metadata/.summary.csv.tmp.XXXXXX") || return 1
  printf '%s\n' "$line" > "$tmp"
  agent_atomic_write "$summary_file" "$tmp"
  rm -f "$tmp"
  metrics_append_unique "$project_dir" "$run_id" "$task_id" "$line" || return 1
  metrics_set_value "$run_file" finalized true
}

metrics_record_dry_run() {
  project_dir=$1 task_id=$2 actual=$3 recommended=$4 reason=$5 rollout_stage=$6 base_fingerprint=$7
  dry_id="dry-$(date -u +%Y%m%dT%H%M%SZ)-T$(printf '%03d' "$((10#$task_id))")-$$"
  run_dir="$project_dir/.agent-runs/$dry_id"
  mkdir -p "$run_dir/metadata" || return 1
  task_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$task_id") || return 1
  tmp=$(mktemp "$run_dir/metadata/.run.env.tmp.XXXXXX") || return 1
  {
    echo "run_id=$dry_id"
    echo "task_id=$task_id"
    echo "class=$(ledger_scalar "$task_file" class)"
    echo "mode=$actual"
    echo "recommended_mode=$recommended"
    echo "route_reason_code=$reason"
    echo 'route_rule_version=1'
    echo "rollout_stage=$rollout_stage"
    echo "base_fingerprint=$base_fingerprint"
    echo "recorded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo 'outcome='
    echo 'dry_run=true'
  } > "$tmp"
  agent_atomic_write "$run_dir/metadata/run.env" "$tmp"
  rm -f "$tmp"
  printf '%s\n' "$run_dir/metadata/run.env"
}

usage() {
  echo 'Verwendung: metrics.sh ensure-schema PROJECT | start PROJECT RUN_DIR RUN_ID TASK MODE START ATTEMPT BASE | route RUN_DIR ACTUAL RECOMMENDED REASON RULE STAGE HUMAN_GATE | finalize PROJECT RUN_DIR OUTCOME | reopen PROJECT RUN_DIR | dry-run PROJECT TASK ACTUAL RECOMMENDED REASON STAGE BASE' >&2
  exit 2
}

case "${1:-}" in
  ensure-schema) [ "$#" -eq 2 ] || usage; metrics_ensure_schema "$2" ;;
  start) [ "$#" -eq 9 ] || usage; metrics_write_start "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" ;;
  route) [ "$#" -eq 8 ] || usage; metrics_record_route "$2" "$3" "$4" "$5" "$6" "$7" "$8" ;;
  finalize) [ "$#" -eq 4 ] || usage; metrics_finalize "$2" "$3" "$4" ;;
  reopen) [ "$#" -eq 3 ] || usage; metrics_reopen "$2" "$3" ;;
  dry-run) [ "$#" -eq 8 ] || usage; metrics_record_dry_run "$2" "$3" "$4" "$5" "$6" "$7" "$8" ;;
  *) usage ;;
esac
