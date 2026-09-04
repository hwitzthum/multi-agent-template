#!/usr/bin/env bash
# Baut kleine, rollenbezogene und unveraenderliche Kontextpakete.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
default_project=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
project_dir=$default_project
role=''
run_id=''
task_id=''
includes=()

usage() {
  echo "Verwendung: $0 build --role ROLLE --run-id ID [--task-id ID] [--include PFAD] [--project-dir PFAD]" >&2
  exit 2
}

[ "${1:-}" = build ] || usage
shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) [ "$#" -ge 2 ] || usage; role=$2; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || usage; run_id=$2; shift 2 ;;
    --task-id) [ "$#" -ge 2 ] || usage; task_id=$2; shift 2 ;;
    --include) [ "$#" -ge 2 ] || usage; includes+=("$2"); shift 2 ;;
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    *) echo "context: unbekannte Option $1" >&2; exit 2 ;;
  esac
done

case "$role" in manager-plan|worker-brainstorm|manager-manage|worker-task|worker-fresh|reviewer|finalizer) ;; *) echo "context: unbekannte Rolle '$role'" >&2; exit 1 ;; esac
case "$run_id" in ''|.*|*[!A-Za-z0-9._-]*) echo "context: ungueltige run-id" >&2; exit 1 ;; esac
case "$task_id" in *[!0-9]*) echo "context: ungueltige Task-ID" >&2; exit 1 ;; esac
case "$role" in worker-brainstorm|worker-task|worker-fresh|reviewer) [ -n "$task_id" ] || { echo "context: Rolle $role benoetigt --task-id" >&2; exit 1; } ;; esac

project_dir=$(CDPATH= cd -- "$project_dir" && pwd -P) || { echo "context: Projektpfad fehlt" >&2; exit 1; }
. "$script_dir/common.sh"
. "$script_dir/ledger.sh"
validator="$default_project/scripts/validate-ledger.sh"
policy="$default_project/scripts/agent/policy.sh"
config_reader="$default_project/scripts/agent/config.sh"
"$validator" --project-dir "$project_dir" >/dev/null || exit 1

template="$project_dir/docs/templates/agents/$role.md"
[ -f "$template" ] || template="$default_project/docs/templates/agents/$role.md"
[ -f "$template" ] || { echo "context: Rollenvertrag fuer $role fehlt" >&2; exit 1; }
prompt_hash=$(agent_sha256_file "$template") || exit 1
context_max=$($config_reader --get CONTEXT_MAX_CHARS "$project_dir/.agent/config.env") || exit 1
notes_max=$($config_reader --get NOTES_MAX_CHARS "$project_dir/.agent/config.env") || exit 1

task_file=''
task_class='-'
if [ -n "$task_id" ]; then
  task_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$task_id") || exit 1
  task_class=$(ledger_scalar "$task_file" class) || exit 1
fi

include_plan=false; include_notes=false; include_verification=false; include_code=false
case "$role" in
  manager-plan) include_plan=true ;;
  worker-brainstorm) include_plan=true; include_notes=true ;;
  manager-manage) include_plan=true; include_notes=true; include_verification=true ;;
  worker-task) include_plan=true; include_notes=true; include_verification=true; include_code=true ;;
  worker-fresh) include_verification=true; include_code=true ;;
  reviewer) include_verification=true; include_code=true ;;
  finalizer) include_plan=true; include_notes=true; include_verification=true ;;
esac

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-context.XXXXXX") || exit 1
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
role_contract="$work_dir/role"
output_contract="$work_dir/output"
goal_raw="$work_dir/goal.raw"; goal_section="$work_dir/goal"
task_raw="$work_dir/task.raw"; task_section="$work_dir/task"
plan_raw="$work_dir/plan.raw"; plan_section="$work_dir/plan"
notes_raw="$work_dir/notes.raw"; notes_section="$work_dir/notes"
verification_raw="$work_dir/verification.raw"; verification_section="$work_dir/verification"
code_raw="$work_dir/code.raw"; code_section="$work_dir/code"
final_work="$work_dir/context"

awk '$0 == "# Strukturiertes Ergebnis" { exit } { print }' "$template" | agent_redact > "$role_contract"
awk '$0 == "# Strukturiertes Ergebnis" { copy=1 } copy { print }' "$template" | agent_redact > "$output_contract"
agent_redact < "$project_dir/docs/state/goal.md" > "$goal_raw"

if [ -n "$task_file" ]; then
  agent_redact < "$task_file" > "$task_raw"
  dependencies=$(ledger_list "$task_file" depends_on 2>/dev/null || true)
  if [ -n "$dependencies" ]; then
    {
      echo
      echo '## Direkte Abhängigkeiten'
      while IFS= read -r dependency; do
        [ -n "$dependency" ] || continue
        dependency_file=$(ledger_task_path_by_id "$project_dir/docs/tasks" "$dependency") || continue
        printf -- '- %s | %s | %s\n' "$dependency" "$(ledger_scalar "$dependency_file" title)" "$(ledger_scalar "$dependency_file" status)"
      done <<EOF
$dependencies
EOF
    } | agent_redact >> "$task_raw"
  fi
else
  {
    echo '# Task-Inventar'
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      printf -- '- %s | %s | %s | %s\n' "$(ledger_scalar "$file" id)" "$(ledger_scalar "$file" title)" "$(ledger_scalar "$file" status)" "$(ledger_scalar "$file" class)"
    done <<EOF
$(ledger_task_files "$project_dir/docs/tasks")
EOF
  } | agent_redact > "$task_raw"
fi

: > "$plan_raw"
if [ "$include_plan" = true ]; then
  {
    sed -n '1,220p' "$project_dir/docs/state/plan.md"
    echo
    echo '### Relevante Entscheidungen'
    sed -n '1,240p' "$project_dir/docs/state/decisions.md"
  } | agent_redact > "$plan_raw"
fi

: > "$notes_raw"
if [ "$include_notes" = true ]; then
  active_notes="$work_dir/active-notes"
  ledger_active_notes "$project_dir/docs/state/notes.md" > "$active_notes"
  if [ -n "$task_id" ]; then
    awk -v wanted="$task_id" '
      BEGIN { RS=""; ORS="\n\n" }
      {
        tasks=""
        count=split($0, lines, "\n")
        for (i=1; i<=count; i++) if (lines[i] ~ /^- tasks:[[:space:]]*\[/) tasks=lines[i]
        sub(/^.*\[/, "", tasks); sub(/\].*$/, "", tasks)
        item_count=split(tasks, items, ",")
        for (i=1; i<=item_count; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
          if (items[i] == wanted) { print; break }
        }
      }
    ' "$active_notes" | agent_redact > "$notes_raw"
  else
    agent_redact < "$active_notes" > "$notes_raw"
  fi
fi

: > "$verification_raw"
if [ "$include_verification" = true ]; then
  if [ "$role" = worker-fresh ]; then
    printf '%s\n' 'Frühere Prüfberichte und Fehler sind für die unabhängige Perspektive ausgeschlossen. Verwende ausschließlich die acceptance-Befehle des Tasks.' > "$verification_raw"
  else
    latest="$project_dir/docs/verification/latest.md"
    report_task=$(ledger_scalar "$latest" task_id 2>/dev/null || true)
    report_result=$(ledger_scalar "$latest" result 2>/dev/null || true)
    take_report=false
    if [ -z "$task_id" ] || [ "$report_task" = "$task_id" ]; then
      case "$role" in worker-task) [ "$report_result" = red ] && take_report=true ;; *) take_report=true ;; esac
    fi
    if [ "$take_report" = true ]; then agent_redact < "$latest" > "$verification_raw"
    else printf '%s\n' 'Kein relevanter aktueller Prüfbericht.' > "$verification_raw"; fi
  fi
fi

: > "$code_raw"
if [ "$include_code" = true ]; then
  removed=false
  for candidate in "${includes[@]}"; do
    case "$candidate" in
      *$'\n'*|*$'\r'*|.agent/*|.claude/*|plans/*|docs/state/*|docs/tasks/*|docs/verification/*|docs/templates/*|scripts/agent/*)
        removed=true
        continue ;;
    esac
    if ! "$policy" context-path "$candidate" >/dev/null 2>&1; then removed=true; continue; fi
    absolute="$project_dir/$candidate"
    if [ ! -f "$absolute" ] || [ -L "$absolute" ]; then removed=true; continue; fi
    candidate_dir=$(dirname -- "$absolute")
    resolved_dir=$(CDPATH= cd -- "$candidate_dir" 2>/dev/null && pwd -P) || { removed=true; continue; }
    case "$resolved_dir/" in "$project_dir/"*) ;; *) removed=true; continue ;; esac
    {
      printf '### %s\n\n' "$candidate"
      agent_redact < "$absolute"
      echo
    } >> "$code_raw"
  done
  [ "$removed" = false ] || printf '%s\n' '[AUSGESCHLOSSENER PFAD ENTFERNT]' >> "$code_raw"
fi

agent_truncate_blocks "$goal_raw" 8000 Goal > "$goal_section"
agent_truncate_blocks "$task_raw" 12000 Task > "$task_section"
agent_truncate_blocks "$plan_raw" 8000 Plan > "$plan_section"
agent_truncate_blocks "$notes_raw" "$notes_max" Notes > "$notes_section"
agent_truncate_blocks "$verification_raw" 8000 Verification > "$verification_section"

render_context() {
  destination=$1
  code_file=$2
  {
    echo '<!-- context-schema: 1 -->'
    echo "<!-- role: $role -->"
    echo "<!-- prompt-sha256: $prompt_hash -->"
    echo
    echo '## Rollenvertrag'
    echo
    cat "$role_contract"
    echo
    echo '## Goal-Auszug'
    echo
    cat "$goal_section"
    echo
    echo '## Aktueller Task'
    echo
    cat "$task_section"
    if [ "$include_plan" = true ]; then echo; echo '## Relevanter Plan-Auszug'; echo; cat "$plan_section"; fi
    if [ "$include_notes" = true ]; then echo; echo '## Kuratierte aktive Notes'; echo; cat "$notes_section"; fi
    if [ "$include_verification" = true ]; then echo; echo '## Letzte Verifikation'; echo; cat "$verification_section"; fi
    if [ "$include_code" = true ]; then
      echo; echo '## Freigegebene Codeausschnitte oder Dateiliste'; echo
      if [ -s "$code_file" ]; then cat "$code_file"; else echo '(keine freigegebenen Dateien)'; fi
    fi
    echo
    echo '## Ausgabeformat'
    echo
    cat "$output_contract"
  } > "$destination"
}

: > "$code_section"
render_context "$final_work" "$code_section"
round=0
while [ "$(wc -c < "$final_work" | tr -d ' ')" -gt "$context_max" ]; do
  round=$((round + 1))
  [ "$round" -le 12 ] || { echo "context: Rollenvertrag passt nicht in CONTEXT_MAX_CHARS" >&2; exit 1; }
  largest=''; largest_size=0
  for entry in "$notes_raw:$notes_section:Notes" "$plan_raw:$plan_section:Plan" "$verification_raw:$verification_section:Verification" "$goal_raw:$goal_section:Goal" "$task_raw:$task_section:Task"; do
    raw=${entry%%:*}; rest=${entry#*:}; section=${rest%%:*}; label=${entry##*:}
    size=$(wc -c < "$section" | tr -d ' ')
    if [ "$size" -gt "$largest_size" ]; then largest=$entry; largest_size=$size; fi
  done
  [ "$largest_size" -gt 160 ] || { echo "context: statischer Rollenvertrag ueberschreitet das Gesamtlimit" >&2; exit 1; }
  overflow=$(($(wc -c < "$final_work" | tr -d ' ') - context_max))
  new_limit=$((largest_size - overflow - 80))
  [ "$new_limit" -ge 160 ] || new_limit=160
  raw=${largest%%:*}; rest=${largest#*:}; section=${rest%%:*}; label=${largest##*:}
  agent_truncate_blocks "$raw" "$new_limit" "$label" > "$section"
  render_context "$final_work" "$code_section"
done

if [ "$include_code" = true ] && [ -s "$code_raw" ]; then
  base_size=$(wc -c < "$final_work" | tr -d ' ')
  code_budget=$((context_max - base_size))
  [ "$code_budget" -gt 0 ] && agent_truncate_blocks "$code_raw" "$code_budget" Code > "$code_section"
  render_context "$final_work" "$code_section"
fi
final_size=$(wc -c < "$final_work" | tr -d ' ')
[ "$final_size" -le "$context_max" ] || { echo "context: Gesamtlimit wurde ueberschritten" >&2; exit 1; }

context_hash=$(agent_sha256_file "$final_work") || exit 1
context_dir="$project_dir/.agent-runs/$run_id/contexts"
mkdir -p "$context_dir" || exit 1
task_label=${task_id:-inventory}
destination="$context_dir/${role}-${task_label}-${context_hash}.md"
if [ -f "$destination" ]; then
  cmp -s "$final_work" "$destination" || { echo "context: Hashkollision bei bestehendem Kontext" >&2; exit 1; }
  printf '%s\n' "$destination"
  exit 0
fi

lock="$context_dir/.${context_hash}.lock"
mkdir "$lock" 2>/dev/null || { echo "context: identischer Kontext wird bereits erstellt" >&2; exit 1; }
context_tmp=$(mktemp "$context_dir/.context.tmp.XXXXXX") || { rmdir "$lock"; exit 1; }
cp "$final_work" "$context_tmp" || { rm -f "$context_tmp"; rmdir "$lock"; exit 1; }
chmod 444 "$context_tmp" || { rm -f "$context_tmp"; rmdir "$lock"; exit 1; }
mv -f "$context_tmp" "$destination" || { rm -f "$context_tmp"; rmdir "$lock"; exit 1; }
rmdir "$lock" 2>/dev/null || true

metrics="$project_dir/docs/state/metrics.csv"
expected_header='task_id,class,model,rounds,tokens_total,outcome,date,mode,reason_code,human_gate,rule_version,signals,run_id,prompt_hash,context_hash,role'
[ "$(sed -n '1p' "$metrics")" = "$expected_header" ] || { echo "context: metrics.csv hat ein unbekanntes Schema" >&2; exit 1; }
run_file="$project_dir/docs/state/current-run.md"
run_mode=$(ledger_scalar "$run_file" mode 2>/dev/null || printf auto)
run_reason=$(ledger_scalar "$run_file" route_reason_code 2>/dev/null || printf none)
run_gate=$(ledger_scalar "$run_file" route_human_gate 2>/dev/null || printf false)
rule_version=$(ledger_scalar "$run_file" route_rule_version 2>/dev/null || printf 1)
metric_task=${task_id:--}
metric_line="$metric_task,$task_class,none,0,0,context-built,$(date -u +%Y-%m-%d),$run_mode,$run_reason,$run_gate,$rule_version,CONTEXT_BUILT,$run_id,$prompt_hash,$context_hash,$role"
agent_atomic_append_line "$metrics" "$metric_line" || exit 1
printf '%s\n' "$destination"
