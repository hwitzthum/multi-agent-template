#!/usr/bin/env bash
# Einzige Anbietergrenze fuer Agentenaufrufe. Zwei Adapter hinter einem
# Vertrag: `claude -p` und `codex exec`. Beide schreiben dasselbe result.json
# und dieselben Metadaten; sie unterscheiden sich nur in der Sicherheitshuelle
# (Claude: Rechte und Hooks im Prozess, Codex: Sandbox des CLI).
# Die vollstaendige Anbieterantwort bleibt als <ergebnis>.provider.json im
# Laufordner. Welcher Adapter laeuft, steht in .agent/config.env (AGENT_RUNNER).
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/common.sh"

usage() {
  echo "Verwendung: $0 --contract | schema_path ROLE | validate_result ROLE DATEI" >&2
  echo "            $0 run_agent ROLE KONTEXT WORKDIR ERGEBNIS METADATEN" >&2
  echo "            $0 render_result ROLE ANBIETER_JSON ERGEBNIS WERTE" >&2
  echo "            $0 render_codex_result JSONL NACHRICHT ERGEBNIS WERTE" >&2
  echo "            $0 runner_settings DATEI [WORKDIR] | validate_metadata DATEI" >&2
  exit 2
}

known_role() {
  case "$1" in manager|worker|finalizer) return 0 ;; *) return 1 ;; esac
}

schema_path() {
  known_role "$1" || { echo "runner: unbekannte Rolle '$1'" >&2; return 1; }
  path="$script_dir/schemas/$1.json"
  [ -f "$path" ] || { echo "runner: Schema fehlt: $path" >&2; return 1; }
  printf '%s\n' "$path"
}

# Prueft ein Rollenergebnis gegen sein Schema: genau die geforderten Felder,
# jeder Wert eine Zeichenkette, enum und pattern eingehalten. `jq -e` liefert
# genau dann 0, wenn der Ausdruck wahr ist.
validate_result() {
  role=$1
  file=$2
  schema=$(schema_path "$role") || return 1
  [ -f "$file" ] || { echo "runner: Ergebnisdatei fehlt: $file" >&2; return 1; }
  jq -e --slurpfile schema "$schema" '
    . as $doc
    | $schema[0] as $s
    | ($s.required | sort) as $required
    | ($doc | type) == "object"
      and (($doc | keys) == $required)
      and all($required[];
            . as $key
            | $s.properties[$key] as $property
            | ($doc[$key] | type) == "string"
              and ($property.enum == null or ($property.enum | index($doc[$key])) != null)
              and ($property.pattern == null or ($doc[$key] | test($property.pattern))))
  ' "$file" >/dev/null 2>&1 || { echo "runner: Ergebnis verletzt das Schema der Rolle $role" >&2; return 1; }
}

claude_supports() {
  claude --help 2>/dev/null | grep -q -- "$1"
}

write_metadata() {
  destination=$1; model=$2; started=$3; finished=$4; exit_status=$5
  tokens_total=$6; tokens_in=$7; tokens_out=$8; cost_estimate=$9
  abort_reason=${10}; output_status=${11}
  directory=$(dirname -- "$destination")
  mkdir -p "$directory" || return 1
  temp=$(mktemp "${TMPDIR:-/tmp}/agent-metadata.XXXXXX") || return 1
  trap 'rm -f "$temp"' EXIT HUP INT TERM
  {
    printf 'model=%s\n' "$model"
    printf 'started_at=%s\n' "$started"
    printf 'finished_at=%s\n' "$finished"
    printf 'exit_status=%s\n' "$exit_status"
    printf 'tokens_total=%s\n' "$tokens_total"
    printf 'tokens_in=%s\n' "$tokens_in"
    printf 'tokens_out=%s\n' "$tokens_out"
    printf 'cost_estimate=%s\n' "$cost_estimate"
    printf 'abort_reason=%s\n' "$abort_reason"
    printf 'output_status=%s\n' "$output_status"
  } > "$temp"
  agent_atomic_write "$destination" "$temp"
}

validate_metadata() {
  file=$1
  [ -f "$file" ] || { echo "runner: Metadaten fehlen" >&2; return 1; }
  awk '
    function fail(message) { print "runner: " message > "/dev/stderr"; bad=1 }
    /^[A-Za-z_]+=/ {
      key=$0; sub(/=.*/, "", key); value=substr($0,length(key)+2)
      if (seen[key]++) fail("doppeltes Metadatenfeld " key)
      if (key !~ /^(model|started_at|finished_at|exit_status|tokens_total|tokens_in|tokens_out|cost_estimate|abort_reason|output_status)$/) fail("unbekanntes Metadatenfeld " key)
      values[key]=value
      next
    }
    { fail("ungueltige Metadatenzeile") }
    END {
      required[1]="model"; required[2]="started_at"; required[3]="finished_at"; required[4]="exit_status"; required[5]="tokens_total"; required[6]="abort_reason"; required[7]="output_status"
      for (i=1;i<=7;i++) if (!(required[i] in seen) || values[required[i]] == "") fail("Pflichtfeld fehlt: " required[i])
      if (values["exit_status"] !~ /^[0-9]+$/) fail("exit_status ist nicht numerisch")
      if (values["tokens_total"] !~ /^([0-9]+|unknown)$/) fail("tokens_total ist ungueltig")
      if (("tokens_in" in seen) && values["tokens_in"] !~ /^([0-9]+|unknown)?$/) fail("tokens_in ist ungueltig")
      if (("tokens_out" in seen) && values["tokens_out"] !~ /^([0-9]+|unknown)?$/) fail("tokens_out ist ungueltig")
      if (("cost_estimate" in seen) && values["cost_estimate"] !~ /^([0-9]+([.][0-9]+)?|unknown)?$/) fail("cost_estimate ist ungueltig")
      if (values["output_status"] !~ /^(ok|truncated|empty|error)$/) fail("output_status ist ungueltig")
      exit bad ? 1 : 0
    }
  ' "$file"
}

# Die Sicherheitshuelle des Claude-Adapters als eigene Einstellungsdatei:
# Deny-Liste, der bash-guard als PreToolUse-Hook und der Ausschluss der
# persoenlichen CLAUDE.md und Regeln des Bedieners (sie beschreiben
# interaktive Arbeitsweisen und gehoeren nicht in einen Headless-Lauf).
# Die Einstellungen der interaktiven Sitzung gelten hier ausdruecklich nicht.
# Die Deny-Muster stehen als Bausteine, damit die Datei selbst keinen
# ausfuehrbar aussehenden Befehlstext traegt.
# Die Ausschlussliste deckt zwei Quellen ab, und beide sind noetig: die
# CLAUDE.md des Bedieners unter $HOME und die des Projekts im Arbeitsbaum.
# Letztere ist Repository-Inhalt und damit untrusted data — als Regelwerk
# gehoert sie nicht in einen Rollenaufruf. `--restricted` haelt sie heraus,
# aber genau der Worker laeuft ohne dieses Flag.
runner_settings() {
  destination=$1
  project_root=${2:-$PWD}
  guard=$(CDPATH= cd -- "$script_dir/.." && pwd) || return 1
  guard="$guard/bash-guard.sh"
  perl -e '
    use strict; use warnings; use JSON::PP;
    my ($path, $guard, $home, $root) = @ARGV;
    my @deny = map { "Bash($_)" } ("git push *", "rm -rf*", "curl *", "wget *");
    my %settings = (
      permissions => { deny => \@deny },
      hooks => { PreToolUse => [ { matcher => "Bash",
        hooks => [ { type => "command", command => $guard } ] } ] },
    );
    my @excludes;
    push @excludes, "$home/.claude/CLAUDE.md", "$home/.claude/rules/**" if length $home;
    push @excludes, "$root/CLAUDE.md", "$root/**/CLAUDE.md" if length $root;
    $settings{claudeMdExcludes} = \@excludes if @excludes;
    open(my $out, ">", $path) or exit 1;
    print $out JSON::PP->new->canonical->utf8->encode(\%settings);
    close $out;
    exit 0;
  ' "$destination" "$guard" "${HOME:-}" "$project_root"
}

# Schreibt das Ergebnisobjekt der Anbieterantwort als result.json und die
# Kennzahlen als KEY=WERT. Ohne Ergebnisobjekt bleibt result.json leer.
render_result() {
  [ "$#" -eq 4 ] || usage
  role=$1; json_file=$2; result_destination=$3; values_destination=$4
  known_role "$role" || { echo "runner: unbekannte Rolle '$role'" >&2; return 1; }
  perl -e '
    use strict; use warnings; use JSON::PP;
    my ($json_path, $result_path, $values_path) = @ARGV;
    open(my $in, "<", $json_path) or exit 1;
    local $/; my $text = <$in>; close $in;
    my $data = eval { JSON::PP->new->utf8->decode($text) };
    if (!defined $data || ref $data ne "HASH") { print STDERR "runner: Antwort ist kein JSON-Objekt\n"; exit 1; }
    my $usage = (ref $data->{usage} eq "HASH") ? $data->{usage} : {};
    my $int = sub { my $v = shift; return (defined $v && $v =~ /^[0-9]+$/) ? $v : undef };
    my $in_tokens = 0; my $in_known = 0;
    for my $key (qw(input_tokens cache_creation_input_tokens cache_read_input_tokens)) {
      my $v = $int->($usage->{$key}); if (defined $v) { $in_tokens += $v; $in_known = 1; }
    }
    my $out_tokens = $int->($usage->{output_tokens});
    my $cost = $data->{total_cost_usd};
    $cost = (defined $cost && $cost =~ /^[0-9.eE+-]+$/) ? sprintf("%.6f", $cost) : "";
    my @models = (ref $data->{modelUsage} eq "HASH") ? sort keys %{ $data->{modelUsage} } : ();
    my $model = @models == 1 ? $models[0] : (@models > 1 ? "mixed" : "");
    $model =~ s/[^A-Za-z0-9._:-]//g;
    my $subtype = defined $data->{subtype} ? $data->{subtype} : "";
    $subtype =~ s/[^A-Za-z0-9_]//g;
    my $so = $data->{structured_output};
    my $structured = (ref $so eq "HASH") ? "yes" : "no";
    open(my $values, ">", $values_path) or exit 1;
    print $values "is_error=" . ($data->{is_error} ? "true" : "false") . "\n";
    print $values "subtype=$subtype\n";
    print $values "num_turns=" . (defined $int->($data->{num_turns}) ? $data->{num_turns} : "") . "\n";
    print $values "tokens_in=" . ($in_known ? $in_tokens : "") . "\n";
    print $values "tokens_out=" . (defined $out_tokens ? $out_tokens : "") . "\n";
    print $values "cost_estimate=$cost\n";
    print $values "model=$model\n";
    print $values "structured=$structured\n";
    close $values;
    open(my $result, ">", $result_path) or exit 1;
    print $result JSON::PP->new->canonical->pretty->utf8->encode($so) if $structured eq "yes";
    close $result;
    exit 0;
  ' "$json_file" "$result_destination" "$values_destination"
}

# Dasselbe fuer codex: der Ereignisstrom (JSONL) traegt Tokens und Fehler, das
# Ergebnisobjekt steht in der Datei aus --output-last-message. Fehlt sie oder
# ist sie kein JSON-Objekt, gibt es kein Rollenergebnis. Kosten meldet codex
# nicht; sie bleiben `unknown`.
render_codex_result() {
  [ "$#" -eq 4 ] || usage
  jsonl_file=$1; message_file=$2; result_destination=$3; values_destination=$4
  perl -e '
    use strict; use warnings; use JSON::PP;
    my ($jsonl_path, $message_path, $result_path, $values_path) = @ARGV;
    open(my $in, "<", $jsonl_path) or exit 1;
    my $decoder = JSON::PP->new->utf8;
    my $int = sub { my $v = shift; return (defined $v && $v =~ /^[0-9]+$/) ? $v : undef };
    my ($tokens_in, $tokens_out, $model, $failure, $seen_event);
    while (my $line = <$in>) {
      $line =~ s/\s+\z//;
      next unless length $line;
      my $event = eval { $decoder->decode($line) };
      next unless defined $event && ref $event eq "HASH";
      $seen_event = 1;
      my $type = defined $event->{type} ? $event->{type} : "";
      $model = $event->{model} if defined $event->{model} && !ref $event->{model};
      if ($type eq "turn.completed" && ref $event->{usage} eq "HASH") {
        my $usage = $event->{usage};
        my $sum = 0; my $known = 0;
        for my $key (qw(input_tokens cached_input_tokens)) {
          my $v = $int->($usage->{$key}); if (defined $v) { $sum += $v; $known = 1 }
        }
        $tokens_in = $sum if $known;
        $tokens_out = $int->($usage->{output_tokens});
      }
      if ($type eq "turn.failed") {
        my $error = $event->{error};
        $failure = (ref $error eq "HASH" && defined $error->{message} && !ref $error->{message})
          ? $error->{message} : "turn_failed";
      }
    }
    close $in;
    if (!$seen_event) { print STDERR "runner: codex lieferte keinen auswertbaren Ereignisstrom\n"; exit 1 }
    my $structured = "no";
    my $decoded;
    if (length $message_path && -s $message_path) {
      open(my $message, "<", $message_path) or exit 1;
      local $/; my $text = <$message>; close $message;
      $decoded = eval { $decoder->decode($text) };
      $structured = "yes" if defined $decoded && ref $decoded eq "HASH";
    }
    $model = "" unless defined $model;
    $model =~ s/[^A-Za-z0-9._:-]//g;
    my $subtype = defined $failure ? $failure : "";
    $subtype =~ s/[^A-Za-z0-9]/_/g;
    $subtype = substr($subtype, 0, 60);
    open(my $values, ">", $values_path) or exit 1;
    print $values "is_error=" . (defined $failure ? "true" : "false") . "\n";
    print $values "subtype=$subtype\n";
    print $values "tokens_in=" . (defined $tokens_in ? $tokens_in : "") . "\n";
    print $values "tokens_out=" . (defined $tokens_out ? $tokens_out : "") . "\n";
    print $values "cost_estimate=unknown\n";
    print $values "model=$model\n";
    print $values "structured=$structured\n";
    close $values;
    open(my $result, ">", $result_path) or exit 1;
    print $result JSON::PP->new->canonical->pretty->utf8->encode($decoded) if $structured eq "yes";
    close $result;
    exit 0;
  ' "$jsonl_file" "$message_file" "$result_destination" "$values_destination"
}

value_of() {
  awk -F= -v wanted="$1" '$1 == wanted { print substr($0, length(wanted) + 2); exit }' "$2"
}

# Ein Pfad muss physisch unter <workdir>/.agent-runs/ liegen. Der Agent laeuft
# im Arbeitsbaum; alles ausserhalb des Laufordners waere ein Schreibweg an der
# Orchestrierung vorbei.
resolve_run_path() {
  candidate=$1
  workdir=$2
  directory=$(dirname -- "$candidate")
  case "$directory" in /*) ;; *) directory="$workdir/$directory" ;; esac
  mkdir -p "$directory" || return 1
  directory=$(CDPATH= cd -- "$directory" && pwd -P) || return 1
  case "$directory/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: $candidate muss unter .agent-runs liegen" >&2; return 1 ;; esac
  printf '%s/%s\n' "$directory" "$(basename -- "$candidate")"
}

# Rollenabhaengige Werkzeuge: der Worker schreibt Code und fuehrt Pruefungen
# aus, Manager und Finalizer pflegen nur Text und bekommen kein Werkzeug, das
# Befehle ausfuehrt. `--restricted` traegt jede Rolle — es steuert nicht die
# Werkzeugauswahl, sondern haelt fremde Einstellungsdateien heraus.
invoke_claude() {
  role=$1; context=$2; workdir=$3; provider_output=$4; stderr_file=$5; settings_file=$6
  command -v claude >/dev/null 2>&1 || { echo "runner: claude wurde nicht gefunden" >&2; return 127; }
  claude_supports '--json-schema' || { echo "runner: das installierte claude unterstützt --json-schema nicht; bitte aktualisieren" >&2; return 127; }
  schema_file=$(schema_path "$role") || return 1
  runner_settings "$settings_file" "$workdir" || { echo "runner: Einstellungsdatei konnte nicht geschrieben werden" >&2; return 1; }

  args=(-p --permission-mode acceptEdits --output-format json --json-schema "$(cat "$schema_file")"
    --no-session-persistence --max-turns "$max_turns" --settings "$settings_file")
  # `--restricted` ignoriert Benutzer-, Projekt- und lokale Einstellungsdateien
  # und beschraenkt die Dateiwerkzeuge auf das Arbeitsverzeichnis; die eigene
  # --settings des Laufs gilt weiter. Deshalb traegt es auch der Worker: er
  # verliert Bash nicht, solange --tools es nennt. Ohne das Flag laesen
  # `.claude/settings.json` und die CLAUDE.md des Arbeitsbaums mit — beides
  # Repository-Inhalt und damit untrusted data. --strict-mcp-config haelt
  # zusaetzlich fremde MCP-Server aus dem Lauf.
  args+=(--restricted --strict-mcp-config)
  case "$role" in
    worker) args+=(--tools Read Glob Grep Edit Write Bash) ;;
    *) args+=(--tools Read Glob Grep Edit Write) ;;
  esac
  [ "$model" = default ] || args+=(--model "$model")
  [ -z "$max_budget" ] || args+=(--max-budget-usd "$max_budget")
  if claude_supports '--permission-prompts'; then args+=(--permission-prompts none); fi

  # stderr getrennt halten: Warnungen des CLI duerfen die Antwort nicht
  # verunreinigen. Auto-Memory des Bedieners bleibt aus dem Lauf draussen.
  # Der Headless-Rahmen steht im Kontextdokument, damit ihn jeder Adapter
  # unveraendert weiterreicht.
  (
    cd "$workdir" || exit 1
    CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 AGENT_HEADLESS=1 \
      agent_run_with_timeout "$timeout_seconds" claude "${args[@]}" < "$context" > "$provider_output" 2> "$stderr_file"
  )
}

# Codex bringt seine Sicherheitshuelle selbst mit: `--sandbox workspace-write`
# begrenzt Schreibzugriffe auf den Arbeitsbaum und laesst das Netz aus.
# `project_doc_max_bytes=0` haelt eine AGENTS.md des Projekts aus dem Lauf.
invoke_codex() {
  role=$1; context=$2; workdir=$3; provider_output=$4; stderr_file=$5; message_file=$6
  command -v codex >/dev/null 2>&1 || { echo "runner: codex wurde nicht gefunden" >&2; return 127; }
  schema_file=$(schema_path "$role") || return 1

  args=(exec --json --output-schema "$schema_file" --output-last-message "$message_file"
    -C "$workdir" --sandbox workspace-write --color never -c project_doc_max_bytes=0)
  [ "$model" = default ] || args+=(-m "$model")
  args+=(-)

  (
    cd "$workdir" || exit 1
    AGENT_HEADLESS=1 \
      agent_run_with_timeout "$timeout_seconds" codex "${args[@]}" < "$context" > "$provider_output" 2> "$stderr_file"
  )
}

run_agent() {
  [ "$#" -eq 5 ] || usage
  role=$1; context=$2; workdir=$3; result_output=$4; metadata_output=$5
  known_role "$role" || { echo "runner: unbekannte Rolle '$role'" >&2; return 1; }
  [ -f "$context" ] && [ ! -L "$context" ] || { echo "runner: Kontext fehlt oder ist ein Symlink" >&2; return 1; }
  workdir=$(CDPATH= cd -- "$workdir" 2>/dev/null && pwd -P) || { echo "runner: Arbeitsverzeichnis fehlt" >&2; return 1; }
  context_dir=$(CDPATH= cd -- "$(dirname -- "$context")" 2>/dev/null && pwd -P) || return 1
  case "$context_dir/" in "$workdir/.agent-runs/"*) ;; *) echo "runner: Kontext muss unter .agent-runs liegen" >&2; return 1 ;; esac
  result_output=$(resolve_run_path "$result_output" "$workdir") || return 1
  metadata_output=$(resolve_run_path "$metadata_output" "$workdir") || return 1
  [ ! -e "$result_output" ] && [ ! -e "$metadata_output" ] || { echo "runner: Ausgabedatei existiert bereits" >&2; return 1; }

  # Adapterwahl, Modell und Grenzen stehen in der Projektkonfiguration, nicht
  # in der Umgebung: ein Lauf soll ohne gesetzte Variablen reproduzierbar sein.
  config_file="$workdir/.agent/config.env"
  adapter=$("$script_dir/config.sh" --get AGENT_RUNNER "$config_file") || return 1
  model=$("$script_dir/config.sh" --get AGENT_MODEL "$config_file") || return 1
  timeout_seconds=$("$script_dir/config.sh" --get AGENT_TIMEOUT_SECONDS "$config_file") || return 1
  max_turns=$("$script_dir/config.sh" --get AGENT_MAX_TURNS "$config_file") || return 1
  # Eine Kostenobergrenze ist eine Entscheidung des Aufrufers, kein Projektwert.
  max_budget=${AGENT_MAX_BUDGET_USD:-}
  case "$max_budget" in ''|[0-9]*) ;; *) echo "runner: AGENT_MAX_BUDGET_USD ist ungueltig" >&2; return 1 ;; esac
  case "$max_budget" in *[!0-9.]*) echo "runner: AGENT_MAX_BUDGET_USD ist ungueltig" >&2; return 1 ;; esac

  provider_output="$result_output.provider.json"
  message_file="$result_output.message.json"
  settings_file="$result_output.settings.json"
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  case "$adapter" in
    claude) invoke_claude "$role" "$context" "$workdir" "$provider_output" "$result_output.stderr" "$settings_file" ;;
    codex) invoke_codex "$role" "$context" "$workdir" "$provider_output" "$result_output.stderr" "$message_file" ;;
    *) echo "runner: unbekannter Adapter '$adapter'" >&2; return 1 ;;
  esac
  status=$?
  finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  output_status=ok
  abort_reason=none
  tokens_in=''; tokens_out=''; cost_estimate=''; tokens_total=unknown
  recorded_model=$model
  : > "$result_output"
  values_file=$(mktemp "${TMPDIR:-/tmp}/agent-result-values.XXXXXX") || return 1
  rendered=true
  if [ "$status" -eq 124 ]; then
    output_status=error; abort_reason=timeout
  elif [ ! -s "$provider_output" ]; then
    output_status=error; abort_reason="exit_${status}_no_output"
  else
    case "$adapter" in
      claude) render_result "$role" "$provider_output" "$result_output" "$values_file" || rendered=false ;;
      codex) render_codex_result "$provider_output" "$message_file" "$result_output" "$values_file" || rendered=false ;;
    esac
    if [ "$rendered" = false ]; then
      output_status=error; abort_reason=invalid_json
    else
      tokens_in=$(value_of tokens_in "$values_file")
      tokens_out=$(value_of tokens_out "$values_file")
      cost_estimate=$(value_of cost_estimate "$values_file")
      reported_model=$(value_of model "$values_file")
      [ -z "$reported_model" ] || recorded_model=$reported_model
      if [ -n "$tokens_in" ] && [ -n "$tokens_out" ]; then tokens_total=$((tokens_in + tokens_out)); fi
      subtype=$(value_of subtype "$values_file")
      if [ "$status" -ne 0 ]; then
        output_status=error; abort_reason="exit_$status"
      elif [ "$(value_of is_error "$values_file")" = true ]; then
        output_status=error; abort_reason=${subtype:-result_error}
      elif [ "$(value_of structured "$values_file")" != yes ]; then
        output_status=empty; abort_reason=${subtype:-no_structured_output}
      fi
    fi
  fi
  rm -f "$values_file"
  [ -n "$abort_reason" ] || abort_reason=unknown
  write_metadata "$metadata_output" "$recorded_model" "$started" "$finished" "$status" "$tokens_total" "$tokens_in" "$tokens_out" "$cost_estimate" "$abort_reason" "$output_status" || return 1
  [ "$status" -eq 0 ] || return "$status"
  [ "$output_status" != error ] || return 1
  return 0
}

case "${1:-}" in
  --contract)
    echo "run_agent <role> <context-file> <workdir> <result-output> <metadata-output>"
    echo "role = manager | worker | finalizer"
    echo "adapter = claude | codex (AGENT_RUNNER in .agent/config.env)"
    echo "exit 0 = Modellaufruf technisch beendet; keine fachliche Freigabe"
    echo "result-output = result.json der Rolle; result-output.provider.json = vollständige Antwort" ;;
  schema_path)
    [ "$#" -eq 2 ] || usage
    schema_path "$2" ;;
  validate_result)
    [ "$#" -eq 3 ] || usage
    validate_result "$2" "$3" ;;
  run_agent)
    shift
    run_agent "$@" ;;
  validate_metadata)
    [ "$#" -eq 2 ] || usage
    validate_metadata "$2" ;;
  render_result)
    shift
    render_result "$@" ;;
  render_codex_result)
    shift
    render_codex_result "$@" ;;
  runner_settings)
    [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || usage
    runner_settings "$2" "${3:-}" ;;
  *) usage ;;
esac
