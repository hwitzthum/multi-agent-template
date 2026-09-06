#!/usr/bin/env bash
# Liest .agent/config.env als validierte Daten. Niemals source/eval verwenden.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1
default_config="$project_dir/.agent/config.env"

fail() {
  echo "config: $1" >&2
  return 1
}

required_keys='MAX_GLOBAL_ITERATIONS MAX_TASK_ATTEMPTS MAX_NO_PROGRESS CONTEXT_MAX_CHARS NOTES_MAX_CHARS VERIFY_TIMEOUT_SECONDS AGENT_TIMEOUT_SECONDS AGENT_MAX_TURNS MAX_INFRA_RETRIES RETRY_BACKOFF_SECONDS AGENT_RUNNER AGENT_MODEL FINALIZER'

known_key() {
  for candidate in $required_keys; do [ "$1" = "$candidate" ] && return 0; done
  return 1
}

# Drei Werttypen: Grenzen sind positive ganze Zahlen, AGENT_RUNNER und
# FINALIZER sind Aufzaehlungen, AGENT_MODEL ist eine Zeichenkette. Der
# Finalizer ist ein zusaetzlicher Modellaufruf und deshalb ausdruecklich
# abwaehlbar (`off`), nicht stillschweigend an. `default` ueberlaesst dem
# gewaehlten CLI die Modellwahl.
valid_value() {
  key=$1
  value=$2
  case "$key" in
    FINALIZER) case "$value" in off|llm) return 0 ;; *) return 1 ;; esac ;;
    AGENT_RUNNER) case "$value" in claude|codex) return 0 ;; *) return 1 ;; esac ;;
    AGENT_MODEL) case "$value" in *[!A-Za-z0-9._:-]*) return 1 ;; *) return 0 ;; esac ;;
    *) case "$value" in ''|*[!0-9]*|0) return 1 ;; *) return 0 ;; esac ;;
  esac
}

validate_config() {
  config_file=$1
  [ -f "$config_file" ] || { fail "Datei fehlt: $config_file"; return 1; }

  seen='|'
  line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    case "$line" in
      ''|'#'*) continue ;;
      *[!A-Za-z0-9_.:=-]*) fail "unerlaubte Zeichen in Zeile $line_no"; return 1 ;;
      *=*) ;;
      *) fail "KEY=VALUE erwartet in Zeile $line_no"; return 1 ;;
    esac

    key=${line%%=*}
    value=${line#*=}
    [ -n "$key" ] && [ -n "$value" ] || { fail "leerer Schlüssel oder Wert in Zeile $line_no"; return 1; }
    known_key "$key" || { fail "unbekannter Schlüssel $key"; return 1; }
    case "$seen" in
      *"|$key|"*) fail "doppelter Schlüssel $key"; return 1 ;;
    esac
    valid_value "$key" "$value" || { fail "ungültiger Wert für $key"; return 1; }
    seen="${seen}${key}|"
  done < "$config_file"

  for required in $required_keys; do
    case "$seen" in
      *"|$required|"*) ;;
      *) fail "Pflichtschlüssel fehlt: $required"; return 1 ;;
    esac
  done
}

get_value() {
  requested=$1
  config_file=$2
  known_key "$requested" || { fail "unbekannter Schlüssel $requested"; return 1; }
  validate_config "$config_file" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$requested="*) printf '%s\n' "${line#*=}"; return 0 ;;
    esac
  done < "$config_file"
  fail "Pflichtschlüssel fehlt: $requested"
}

usage() {
  echo "Verwendung: $0 --check [config] | --get KEY [config]"
}

case "${1:-}" in
  --check)
    validate_config "${2:-$default_config}" ;;
  --get)
    [ -n "${2:-}" ] || { usage >&2; exit 2; }
    get_value "$2" "${3:-$default_config}" ;;
  *)
    usage >&2
    exit 2 ;;
esac
