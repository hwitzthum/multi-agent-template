#!/usr/bin/env bash
# Umgebungspruefung vor dem ersten Lauf: sind die Werkzeuge da, ist der
# gewaehlte Runner brauchbar, ist das Repository in einem Zustand, aus dem ein
# Fresh Worker starten kann.
#
# Jede Pruefung meldet eine Zeile. `OK` heisst brauchbar, `BEFUND` heisst
# behebbar und blockierend, `HINWEIS` heisst nur beachtenswert. Exit 1, sobald
# ein BEFUND vorliegt. Ein kaputt installierter Runner ist ein BEFUND, kein
# Absturz: die Meldung soll sagen, was zu reparieren ist.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd) || exit 1
config_reader="$script_dir/agent/config.sh"
. "$script_dir/agent/common.sh"

usage() {
  echo "Verwendung: $0 [--project-dir PFAD]"
  echo "Prüft Werkzeuge, den gewählten Agenten-Runner und den Repository-Zustand."
  echo "Exit 0 = einsatzbereit, Exit 1 = mindestens ein Befund."
}

while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --project-dir) [ -n "${2:-}" ] || { usage >&2; exit 2; }; project_dir=$2; shift ;;
    *) echo "doctor: unbekannte Option '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || {
  echo "doctor: Projektpfad fehlt" >&2; exit 2; }

findings=0

ok() { printf 'OK       %s\n' "$1"; }
finding() { printf 'BEFUND   %s\n' "$1"; findings=$((findings + 1)); }
note() { printf 'HINWEIS  %s\n' "$1"; }

# --- Werkzeuge --------------------------------------------------------------
# Genau die Werkzeuge, die docs/ARCHITECTURE.md als Voraussetzung nennt: sie
# tragen Ledger, Manifeste, Fingerprints, Schemapruefung und Zeitlimits.
for tool in bash git awk sed shasum jq perl; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool gefunden ($(command -v "$tool"))"
  else
    finding "$tool fehlt; ohne dieses Werkzeug läuft die Orchestrierung nicht"
  fi
done

# --- Konfiguration ----------------------------------------------------------
config_file="$project_dir/.agent/config.env"
adapter=''
if [ ! -f "$config_file" ]; then
  finding "Konfiguration fehlt: $config_file"
elif ! config_error=$("$config_reader" --check "$config_file" 2>&1); then
  finding "Konfiguration ist ungültig: $config_error"
else
  adapter=$("$config_reader" --get AGENT_RUNNER "$config_file" 2>/dev/null) || adapter=''
  model=$("$config_reader" --get AGENT_MODEL "$config_file" 2>/dev/null) || model='?'
  ok "Konfiguration gültig (AGENT_RUNNER=$adapter, AGENT_MODEL=$model)"
fi

# --- Gewaehlter Runner ------------------------------------------------------
# Geprueft wird nur der Runner, der laut Konfiguration laufen wuerde. Ein
# fehlerhaft installiertes CLI beantwortet `--version` nicht; genau das ist
# hier der Befund.
check_claude() {
  command -v claude >/dev/null 2>&1 || {
    finding "claude wurde nicht gefunden; AGENT_RUNNER=claude braucht das Claude-Code-CLI"; return; }
  if ! version=$(claude --version 2>&1); then
    finding "claude ist installiert, antwortet aber nicht auf --version: $(printf '%s' "$version" | head -n 1)"
    return
  fi
  # Der Adapter reicht diese Optionen bei jedem Rollenaufruf durch: das
  # Rollenschema und die Sicherheitshuelle. Fehlt eine, bricht jeder Lauf mit
  # einem CLI-Fehler ab — das gehoert hierher, vor den Lauf.
  help=$(claude --help 2>/dev/null)
  missing=''
  for option in --json-schema --restricted --strict-mcp-config --tools --settings; do
    printf '%s\n' "$help" | grep -q -- "$option" || missing="$missing $option"
  done
  if [ -z "$missing" ]; then
    ok "claude einsatzbereit ($(printf '%s' "$version" | head -n 1))"
  else
    finding "claude kennt nicht:$missing ($(printf '%s' "$version" | head -n 1)); bitte aktualisieren"
  fi
}

check_codex() {
  command -v codex >/dev/null 2>&1 || {
    finding "codex wurde nicht gefunden; AGENT_RUNNER=codex braucht das Codex-CLI"; return; }
  if ! version=$(codex --version 2>&1); then
    finding "codex ist installiert, antwortet aber nicht auf --version: $(printf '%s' "$version" | head -n 1)"
    return
  fi
  ok "codex einsatzbereit ($(printf '%s' "$version" | head -n 1))"
}

case "$adapter" in
  claude) check_claude ;;
  codex) check_codex ;;
  '') note "Runner nicht geprüft: die Konfiguration nennt keinen" ;;
  *) finding "unbekannter Runner in der Konfiguration: $adapter" ;;
esac

# --- Repository -------------------------------------------------------------
# Manifeste und Fingerprints beziehen Dateiliste und Hashes von Git; ohne
# Repository gibt es keinen Snapshot und keinen Fresh-Versuch. Ein Basiscommit
# ist dagegen keine Bedingung: die Inhalte kommen ueber `git hash-object -w`
# aus dem Arbeitsbaum, nicht aus HEAD. Ohne Commit fehlt nur dem Menschen eine
# Rueckfallebene.
if ! git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  finding "kein Git-Repository: $project_dir"
else
  head_commit=$(git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || true)
  if [ -z "$head_commit" ]; then
    note "Repository ohne Basiscommit; Snapshot und Rücksetzen arbeiten trotzdem, nur ein committeter Stand zum Zurückfallen fehlt"
  elif agent_worktree_is_dirty "$project_dir"; then
    note "Arbeitsbaum ist schmutzig; ein Lauf verlangt --allow-dirty"
  else
    ok "Arbeitsbaum sauber auf $head_commit"
  fi
fi

if [ "$findings" -eq 0 ]; then
  echo "doctor: GREEN (einsatzbereit)"
  exit 0
fi
echo "doctor: RED ($findings Befund(e))" >&2
exit 1
