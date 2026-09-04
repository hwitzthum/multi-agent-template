#!/usr/bin/env bash
# Deterministischer Task-Router. Startet keine Modelle und keinen Agenten.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
manual_mode=''
record=false
escalate_from=''
expected_attempts=''
task_id=''
RULE_VERSION=1

usage() {
  echo "Verwendung: $0 [--project-dir PFAD] [--mode MODUS] [--record] [--escalate-from MODUS --expected-attempts N] TASK-ID" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    --mode) [ "$#" -ge 2 ] || usage; manual_mode=$2; shift 2 ;;
    --record) record=true; shift ;;
    --escalate-from) [ "$#" -ge 2 ] || usage; escalate_from=$2; shift 2 ;;
    --expected-attempts) [ "$#" -ge 2 ] || usage; expected_attempts=$2; shift 2 ;;
    --*) echo "route-task: unbekannte Option $1" >&2; exit 2 ;;
    *) [ -z "$task_id" ] || usage; task_id=$1; shift ;;
  esac
done
[ -n "$task_id" ] || usage
case "$task_id" in *[!0-9]*|'') echo "route-task: ungueltige Task-ID" >&2; exit 1 ;; esac

. "$script_dir/agent/ledger.sh"
validator="$script_dir/validate-ledger.sh"
config_reader="$script_dir/agent/config.sh"
tasks_dir="$project_dir/docs/tasks"
state_dir="$project_dir/docs/state"
config="$project_dir/.agent/config.env"
metrics="$project_dir/docs/state/metrics.csv"

"$validator" --project-dir "$project_dir" >/dev/null || exit 1
task_file=$(ledger_task_path_by_id "$tasks_dir" "$task_id") || exit 1
task_class=$(ledger_scalar "$task_file" class) || exit 1
task_human=$(ledger_scalar "$task_file" human_review) || exit 1
attempts=$(ledger_scalar "$task_file" attempts) || exit 1
max_attempts=$(ledger_scalar "$task_file" max_attempts) || exit 1

valid_mode() {
  case "$1" in single|verified|managed|managed-fresh) return 0 ;; *) return 1 ;; esac
}

mode_rank() {
  case "$1" in single) echo 1 ;; verified) echo 2 ;; managed) echo 3 ;; managed-fresh) echo 4 ;; blocked) echo 5 ;; *) return 1 ;; esac
}

signals=''
add_signal() {
  case ",${signals}," in *",$1,"*) return ;; esac
  if [ -n "$signals" ]; then signals="$signals,$1"; else signals=$1; fi
}

human_gate=$task_human
[ "$task_class" = open ] && human_gate=true

write_attempt() {
  new_value=$1
  validate_attempt_candidate() {
    "$validator" --project-dir "$project_dir" --task-file "$1" >/dev/null
  }
  ledger_atomic_replace_scalar "$task_file" attempts "$new_value" validate_attempt_candidate
}

record_route() {
  selected_mode=$1
  reason_code=$2
  current_run="$state_dir/current-run.md"
  run_task=$(ledger_scalar "$current_run" task_id 2>/dev/null || true)
  run_phase=$(ledger_scalar "$current_run" phase 2>/dev/null || true)
  [ "$run_task" = "$task_id" ] && [ "$run_phase" != finished ] || {
    echo "route-task: --record benoetigt einen aktiven Lauf fuer Task $task_id" >&2
    return 1
  }

  lock="$state_dir/.route-record-lock"
  mkdir "$lock" 2>/dev/null || { echo "route-task: eine andere Routing-Protokollierung laeuft bereits" >&2; return 1; }
  run_tmp=$(mktemp "$state_dir/.current-run.md.route.XXXXXX") || { rmdir "$lock"; return 1; }
  metrics_tmp=''
  cleanup_record() { rm -f "$run_tmp"; [ -z "$metrics_tmp" ] || rm -f "$metrics_tmp"; rmdir "$lock" 2>/dev/null || true; }
  trap cleanup_record EXIT HUP INT TERM

  if ! awk -v version="$RULE_VERSION" -v mode="$selected_mode" -v reason="$reason_code" -v gate="$human_gate" -v route_signals="$signals" '
    BEGIN { front=0; replacements=0 }
    NR == 1 && $0 == "---" { front=1; print; next }
    front && $0 == "---" { front=0; print; next }
    front && /^route_rule_version:/ { print "route_rule_version: \"" version "\""; replacements++; next }
    front && /^mode:/ { print "mode: " mode; replacements++; next }
    front && /^route_reason_code:/ { print "route_reason_code: " reason; replacements++; next }
    front && /^route_human_gate:/ { print "route_human_gate: " gate; replacements++; next }
    front && /^route_signals:/ { print "route_signals: [" route_signals "]"; replacements++; next }
    { print }
    END { if (replacements != 5) exit 1 }
  ' "$current_run" > "$run_tmp"; then
    echo "route-task: Routingfelder in current-run.md fehlen oder sind doppelt" >&2
    return 1
  fi
  "$validator" --project-dir "$project_dir" --current-run-file "$run_tmp" >/dev/null || return 1
  ledger_copy_mode "$current_run" "$run_tmp" || return 1

  expected_header='task_id,class,model,rounds,tokens_total,outcome,date,mode,reason_code,human_gate,rule_version,signals'
  [ "$(sed -n '1p' "$metrics")" = "$expected_header" ] || { echo "route-task: metrics.csv hat ein unbekanntes Schema" >&2; return 1; }
  metrics_tmp=$(mktemp "$state_dir/.metrics.csv.route.XXXXXX") || return 1
  cp "$metrics" "$metrics_tmp" || { rm -f "$metrics_tmp"; return 1; }
  metric_signals=$(printf '%s' "$signals" | tr ',' '+')
  printf '%s,%s,none,0,0,routed,%s,%s,%s,%s,%s,%s\n' "$task_id" "$task_class" "$(date -u +%Y-%m-%d)" "$selected_mode" "$reason_code" "$human_gate" "$RULE_VERSION" "$metric_signals" >> "$metrics_tmp"
  ledger_copy_mode "$metrics" "$metrics_tmp" || { rm -f "$metrics_tmp"; return 1; }

  mv -f "$metrics_tmp" "$metrics" || return 1
  metrics_tmp=''
  mv -f "$run_tmp" "$current_run" || return 1
  trap - EXIT HUP INT TERM
  rmdir "$lock" 2>/dev/null || true
}

if [ -n "$escalate_from" ]; then
  [ -z "$manual_mode" ] || { echo "route-task: --mode und --escalate-from sind nicht kombinierbar" >&2; exit 2; }
  valid_mode "$escalate_from" || { echo "route-task: unbekannter Ausgangsmodus '$escalate_from'" >&2; exit 1; }
  case "$expected_attempts" in ''|*[!0-9]*) echo "route-task: --expected-attempts ist fuer Eskalation erforderlich" >&2; exit 2 ;; esac
  [ "$attempts" = "$expected_attempts" ] || { echo "route-task: veralteter Versuch; Task hat attempts=$attempts statt $expected_attempts" >&2; exit 1; }

  attempt_lock="$tasks_dir/.route-attempt-lock"
  mkdir "$attempt_lock" 2>/dev/null || { echo "route-task: eine andere Eskalation laeuft bereits" >&2; exit 1; }
  cleanup_attempt() { rmdir "$attempt_lock" 2>/dev/null || true; }
  trap cleanup_attempt EXIT HUP INT TERM
  attempts_now=$(ledger_scalar "$task_file" attempts) || exit 1
  [ "$attempts_now" = "$expected_attempts" ] || { echo "route-task: veralteter paralleler Versuch" >&2; exit 1; }
  new_attempts=$((attempts_now + 1))
  write_attempt "$new_attempts" || exit 1
  trap - EXIT HUP INT TERM
  rmdir "$attempt_lock" 2>/dev/null || true

  add_signal FAILURE_RECORDED
  if [ "$new_attempts" -ge "$max_attempts" ]; then
    selected=blocked
    reason=ATTEMPT_LIMIT
    add_signal ATTEMPT_LIMIT
  else
    case "$escalate_from" in
      single) selected=verified ;;
      verified) selected=managed ;;
      managed) selected=managed-fresh ;;
      managed-fresh) selected=blocked ;;
    esac
    if [ "$selected" = blocked ]; then reason=MODE_EXHAUSTED; add_signal MODE_EXHAUSTED
    else reason=ESCALATED_AFTER_FAILURE; fi
  fi
  [ "$record" = false ] || record_route "$selected" "$reason" || exit 1
  printf 'MODE=%s\nREASON_CODE=%s\nHUMAN_GATE=%s\n' "$selected" "$reason" "$human_gate"
  exit 0
fi

[ -z "$expected_attempts" ] || { echo "route-task: --expected-attempts ist nur bei Eskalation erlaubt" >&2; exit 2; }
if [ -n "$manual_mode" ]; then
  valid_mode "$manual_mode" || { echo "route-task: unbekannter Modus '$manual_mode'" >&2; exit 1; }
fi

task_override=$(ledger_scalar "$task_file" orchestration) || exit 1
router_enabled=$($config_reader --get ROUTER_ENABLED "$config") || exit 1
default_mode=$($config_reader --get DEFAULT_MODE "$config") || exit 1

if [ -n "$manual_mode" ]; then
  selected=$manual_mode
  reason=EXPLICIT_OVERRIDE
  add_signal CLI_OVERRIDE
elif [ "$task_override" != auto ]; then
  selected=$task_override
  reason=EXPLICIT_OVERRIDE
  add_signal TASK_OVERRIDE
elif [ "$router_enabled" = false ]; then
  if [ "$default_mode" = auto ]; then selected=verified; else selected=$default_mode; fi
  reason=ROUTER_DISABLED
  add_signal ROUTER_DISABLED
else
  case "$task_class" in
    mechanical) selected=single; reason=MECHANICAL_LOCAL ;;
    patterned) selected=verified; reason=PATTERNED_LOCAL ;;
    open) selected=managed; reason=OPEN_DECISION ;;
  esac
fi

scope=$(awk '$0 == "# Umfang" { inside=1; next } inside && /^# / { exit } inside { print }' "$task_file")
touches=$(ledger_list "$task_file" touches 2>/dev/null || true)
risk_flags=$(ledger_list "$task_file" risk_flags 2>/dev/null || true)
combined=$(printf '%s\n%s\n%s\n' "$(ledger_scalar "$task_file" title)" "$scope" "$touches" | tr '[:upper:]' '[:lower:]')
flat=$(printf ' %s ' "$combined" | tr '\n' ' ')

flag_cross=false; flag_high=false; flag_repeat=false; flag_conflict=false
while IFS= read -r flag; do
  case "$flag" in
    cross-component) flag_cross=true ;;
    high-risk-domain) flag_high=true ;;
    repeated-failure) flag_repeat=true ;;
    conflicting-ledger) flag_conflict=true ;;
  esac
done <<EOF
$risk_flags
EOF

case "$flat" in
  *authentication*|*authorization*|*authentifizierung*|*autorisierung*|*oauth*|*'/auth'*|*' auth '*|*berechtigung*|*permission*|*payment*|*zahlung*|*billing*|*datenmigration*|*database\ migration*|*secret*|*deploy*|*security\ hook*|*sicherheitshook*) flag_high=true ;;
esac

component_count=0
case "$flat" in *frontend*|*'/ui'*|*' ui '*) component_count=$((component_count + 1)) ;; esac
case "$flat" in *backend*|*'/api'*|*' api '*) component_count=$((component_count + 1)) ;; esac
case "$flat" in *database*|*datenbank*|*'/db'*|*' db '*) component_count=$((component_count + 1)) ;; esac
case "$flat" in *infrastructure*|*infrastruktur*|*'/infra'*|*' infra '*) component_count=$((component_count + 1)) ;; esac
[ "$component_count" -gt 1 ] && flag_cross=true

hard_rank=0
hard_reason=''
if [ "$task_class" = open ]; then hard_rank=3; hard_reason=OPEN_DECISION; add_signal OPEN_CLASS; fi
if [ "$attempts" -ge 2 ]; then hard_rank=3; hard_reason=FAILED_ATTEMPTS; add_signal MULTIPLE_FAILURES; fi
if [ "$flag_cross" = true ]; then hard_rank=3; hard_reason=CROSS_COMPONENT; add_signal CROSS_COMPONENT; fi
if [ "$flag_high" = true ]; then hard_rank=3; hard_reason=HIGH_RISK_DOMAIN; add_signal HIGH_RISK_DOMAIN; fi
if [ "$flag_conflict" = true ]; then hard_rank=4; hard_reason=CONFLICTING_LEDGER; add_signal CONFLICTING_LEDGER; fi
if [ "$flag_repeat" = true ]; then hard_rank=4; hard_reason=REPEATED_FAILURE; add_signal REPEATED_FAILURE; fi
if [ "$(ledger_scalar "$task_file" fresh_perspective)" = required ]; then hard_rank=4; hard_reason=FRESH_REQUIRED; add_signal FRESH_REQUIRED; fi

selected_rank=$(mode_rank "$selected") || exit 1
if [ "$hard_rank" -gt 0 ]; then
  if [ "$selected_rank" -lt "$hard_rank" ]; then
    case "$hard_rank" in 3) selected=managed ;; 4) selected=managed-fresh ;; esac
  fi
  reason=$hard_reason
fi
if [ "$attempts" -ge "$max_attempts" ]; then
  selected=blocked
  reason=ATTEMPT_LIMIT
  add_signal ATTEMPT_LIMIT
fi

[ "$record" = false ] || record_route "$selected" "$reason" || exit 1
printf 'MODE=%s\nREASON_CODE=%s\nHUMAN_GATE=%s\n' "$selected" "$reason" "$human_gate"
