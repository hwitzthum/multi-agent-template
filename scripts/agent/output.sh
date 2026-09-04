#!/usr/bin/env bash
# Validiert strukturierte Rollenoutputs und kuerzt grosse Rohantworten lokal.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/common.sh"

known_role() {
  case "$1" in manager-plan|worker-brainstorm|manager-manage|worker-task|worker-fresh|reviewer|finalizer) return 0 ;; *) return 1 ;; esac
}

fail() { echo "role-output: $1" >&2; return 1; }

validate_lines() {
  role=$1
  file=$2
  awk -v role="$role" '
    function reject(message) { print "role-output: " message > "/dev/stderr"; bad=1 }
    /^[[:space:]]*$/ { next }
    {
      if ($0 !~ /^[A-Z_]+=/) { reject("unerlaubte Zeile: " $0); next }
      key=$0; sub(/=.*/, "", key)
      value=substr($0, length(key)+2)
      if (seen[key]++) reject("doppeltes Feld " key)
      allowed=0
      if (role == "manager-plan" && key ~ /^(PLAN_UPDATED|TASKS_CREATED|OPEN_RISK)$/) allowed=1
      if (role == "worker-brainstorm" && key ~ /^(NOTES_ADDED|RISKS|TEST_IDEAS)$/) allowed=1
      if ((role == "worker-task" || role == "worker-fresh") && key ~ /^(RESULT|CHANGED_PATHS|TESTS_RUN|NOTES_ADDED)$/) allowed=1
      if (role == "reviewer" && key ~ /^(RECOMMENDATION|REASON_CODE|REPORTS)$/) allowed=1
      if (role == "finalizer" && key ~ /^(OUTCOME|BEST_GREEN_REF|OPEN_ERROR|HUMAN_DECISION)$/) allowed=1
      if (!allowed) reject("unbekanntes Feld " key)
      values[key]=value
    }
    END {
      if (role == "manager-plan") {
        if (!("PLAN_UPDATED" in seen) || !("TASKS_CREATED" in seen) || !("OPEN_RISK" in seen)) reject("Manager-Plan-Ausgabe ist unvollstaendig")
        if (values["PLAN_UPDATED"] !~ /^(yes|no)$/) reject("PLAN_UPDATED muss yes oder no sein")
      }
      if (role == "worker-brainstorm") {
        if (!("NOTES_ADDED" in seen) || !("RISKS" in seen) || !("TEST_IDEAS" in seen)) reject("Brainstorm-Ausgabe ist unvollstaendig")
      }
      if (role == "worker-task" || role == "worker-fresh") {
        if (!("RESULT" in seen) || !("CHANGED_PATHS" in seen) || !("TESTS_RUN" in seen) || !("NOTES_ADDED" in seen)) reject("Worker-Ausgabe ist unvollstaendig")
        if (values["RESULT"] !~ /^(implemented|partial|blocked)$/) reject("unbekanntes Worker-RESULT")
        if (role == "worker-fresh" && values["NOTES_ADDED"] != "-") reject("Fresh Worker darf keine historischen Notes fortschreiben")
      }
      if (role == "reviewer") {
        if (!("RECOMMENDATION" in seen) || !("REASON_CODE" in seen) || !("REPORTS" in seen)) reject("Reviewer-Ausgabe ist unvollstaendig")
        if (values["RECOMMENDATION"] !~ /^(candidate-a|candidate-b|neither|human)$/) reject("unbekannte Reviewer-Empfehlung")
      }
      if (role == "finalizer") {
        if (!("OUTCOME" in seen) || !("BEST_GREEN_REF" in seen) || !("OPEN_ERROR" in seen) || !("HUMAN_DECISION" in seen)) reject("Finalizer-Ausgabe ist unvollstaendig")
        if (values["OUTCOME"] !~ /^(done|blocked|budget_exhausted)$/) reject("unbekanntes Finalizer-OUTCOME")
      }
      for (key in seen) if (values[key] == "") reject("leerer Wert bei " key)
      exit bad ? 1 : 0
    }
  ' "$file"
}

validate_manager_manage() {
  file=$1
  awk '
    function reject(message) { print "role-output: " message > "/dev/stderr"; bad=1 }
    /^[[:space:]]*$/ { next }
    $0 == "---" {
      delimiters++
      if (delimiters == 1) inside=1
      else if (delimiters == 2) inside=0
      else reject("mehr als ein Frontmatter-Block")
      next
    }
    /^[a-z_]+:[[:space:]]*/ {
      if (!inside) { reject("Feld ausserhalb des Frontmatters"); next }
      key=$0; sub(/:.*/, "", key)
      value=substr($0, length(key)+2); sub(/^[[:space:]]*/, "", value)
      if (seen[key]++) reject("doppeltes Feld " key)
      if (key !~ /^(action|task_id|worker_kind|reason_code)$/) reject("unbekanntes Feld " key)
      values[key]=value
      next
    }
    { reject("unerlaubte Zeile: " $0) }
    END {
      if (delimiters != 2 || inside) reject("genau ein Frontmatter-Block ist erforderlich")
      if (!("action" in seen) || !("task_id" in seen) || !("worker_kind" in seen) || !("reason_code" in seen)) reject("Manager-Entscheidung ist unvollstaendig")
      if (values["action"] !~ /^(dispatch|done|blocked|request_human)$/) reject("unbekannte action")
      if (values["worker_kind"] !~ /^(normal|fresh)$/) reject("unbekannter worker_kind")
      if (values["reason_code"] !~ /^[A-Z][A-Z0-9_]*$/) reject("ungueltiger reason_code")
      if (values["action"] == "dispatch" && values["task_id"] !~ /^[0-9]+$/) reject("dispatch benoetigt genau eine numerische task_id")
      if (values["action"] != "dispatch" && values["task_id"] !~ /^(-|[0-9]+)$/) reject("ungueltige task_id")
      exit bad ? 1 : 0
    }
  ' "$file"
}

case "${1:-}" in
  validate)
    [ "$#" -eq 3 ] || { echo "Verwendung: $0 validate ROLLE DATEI" >&2; exit 2; }
    role=$2; file=$3
    known_role "$role" || { fail "unbekannte Rolle '$role'"; exit 1; }
    [ -f "$file" ] || { fail "Datei fehlt"; exit 1; }
    if [ "$role" = manager-manage ]; then validate_manager_manage "$file" || exit 1
    else validate_lines "$role" "$file" || exit 1; fi
    echo "role-output: GREEN ($role)"
    ;;
  summarize)
    [ "$#" -eq 5 ] || { echo "Verwendung: $0 summarize ROLLE ROHDATEN ZIEL MAX_ZEICHEN" >&2; exit 2; }
    role=$2; input=$3; output=$4; max_chars=$5
    known_role "$role" || { fail "unbekannte Rolle '$role'"; exit 1; }
    [ -f "$input" ] || { fail "Rohdaten fehlen"; exit 1; }
    [ ! -L "$input" ] || { fail "Rohdaten duerfen kein Symlink sein"; exit 1; }
    case "$max_chars" in ''|*[!0-9]*) fail "ungueltiges Zeichenlimit"; exit 1 ;; esac
    [ "$max_chars" -ge 300 ] || { fail "Zeichenlimit ist zu klein"; exit 1; }
    [ ! -e "$output" ] || { fail "Zieldatei existiert bereits und bleibt unveraendert"; exit 1; }
    output_dir=$(dirname -- "$output")
    mkdir -p "$output_dir" || exit 1
    input_dir=$(CDPATH= cd -- "$(dirname -- "$input")" && pwd -P) || exit 1
    output_dir=$(CDPATH= cd -- "$output_dir" && pwd -P) || exit 1
    case "$input_dir/" in */.agent-runs/*) ;; *) fail "Rohdaten muessen physisch unter .agent-runs liegen"; exit 1 ;; esac
    case "$output_dir/" in */.agent-runs/*) ;; *) fail "Zusammenfassung muss physisch unter .agent-runs liegen"; exit 1 ;; esac
    output="$output_dir/$(basename -- "$output")"
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-summary.XXXXXX") || exit 1
    trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
    redacted="$temp_dir/redacted"
    body="$temp_dir/body"
    summary="$temp_dir/summary"
    agent_redact < "$input" > "$redacted"
    original_size=$(wc -c < "$input" | tr -d ' ')
    header="# Gekuerzte Rollenausgabe\n\n- role: $role\n- original_chars: $original_size\n\n## Sicherer Auszug\n\n"
    footer="\n[GEKUERZT: vollstaendige Rohantwort bleibt lokal]\n"
    available=$((max_chars - ${#header} - ${#footer}))
    agent_truncate_blocks "$redacted" "$available" Rohoutput > "$body"
    printf '%b' "$header" > "$summary"
    cat "$body" >> "$summary"
    printf '%b' "$footer" >> "$summary"
    size=$(wc -c < "$summary" | tr -d ' ')
    [ "$size" -le "$max_chars" ] || { fail "Zusammenfassung ueberschreitet das Limit"; exit 1; }
    tmp=$(mktemp "$output_dir/.summary.tmp.XXXXXX") || exit 1
    cp "$summary" "$tmp" || { rm -f "$tmp"; exit 1; }
    mv -f "$tmp" "$output" || { rm -f "$tmp"; exit 1; }
    echo "role-output: SUMMARY $output"
    ;;
  *) echo "Verwendung: $0 validate ... | summarize ..." >&2; exit 2 ;;
esac
