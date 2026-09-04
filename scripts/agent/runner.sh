#!/usr/bin/env bash
# Anbietergrenze der späteren Orchestrierung. Phase 01 startet keine Agenten.
set -uo pipefail

usage() {
  echo "Verwendung: $0 --contract | --check | invoke_role ROLE PROMPT WORKDIR RESULT"
}

case "${1:-}" in
  --contract)
    echo "invoke_role <role> <prompt-file> <workdir> <result-file>"
    echo "exit 0 = Modellaufruf technisch beendet; keine fachliche Freigabe" ;;
  --check)
    if command -v claude >/dev/null 2>&1; then
      echo "runner: Claude Code verfügbar"
      exit 0
    fi
    echo "runner: kein unterstützter Agenten-CLI gefunden" >&2
    exit 1 ;;
  invoke_role)
    echo "runner: Agentenaufrufe werden erst in Phase 05 implementiert" >&2
    exit 64 ;;
  *) usage >&2; exit 2 ;;
esac
