#!/usr/bin/env bash
# Testbare Basispolicy für Kontextpfade und rollenbezogene Schreibbereiche.
set -uo pipefail

normalize_repo_path() {
  candidate=$1
  while [ "${candidate#./}" != "$candidate" ]; do candidate=${candidate#./}; done
  case "$candidate" in
    ''|/*|../*|*/../*|*/..|..) return 1 ;;
  esac
  printf '%s\n' "$candidate"
}

context_path_allowed() {
  path=$(normalize_repo_path "$1") || return 1
  base=${path##*/}
  lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')

  case "$path" in
    .env|.env.*|*/.env|*/.env.*|.git|.git/*|*/.git/*|.venv|.venv/*|*/.venv/*|node_modules|node_modules/*|*/node_modules/*|.agent-runs|.agent-runs/*|*/.agent-runs/*) return 1 ;;
  esac
  case "$lower" in
    *.pem|*.key|id_rsa|id_ed25519|credentials|credentials.*|secrets|secrets.*|*secret*.json|*credential*.json|*.log) return 1 ;;
  esac
  case "$lower" in
    *.doc|*.docx|*.xls|*.xlsx|*.ppt|*.pptx|*.pdf|*.zip|*.tar|*.gz|*.7z|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.mp3|*.wav|*.mp4|*.mov|*.avi|*.bin) return 1 ;;
  esac
  return 0
}

worker_path_allowed() {
  path=$1
  case "$path" in
    .agent|.agent/*|.agent-runs|.agent-runs/*|.claude|.claude/*|plans|plans/*|docs/state|docs/state/*|docs/tasks|docs/tasks/*|docs/verification|docs/verification/*|scripts/agent|scripts/agent/*|scripts/bash-guard.sh|scripts/commit-gate.sh|.git|.git/*|.gitignore) return 1 ;;
    *) context_path_allowed "$path" ;;
  esac
}

role_may_write() {
  role=$1
  path=$(normalize_repo_path "$2") || return 1
  case "$role" in
    manager|manager-plan|manager-manage)
      case "$path" in docs/state/plan.md|docs/tasks/*.md) return 0;; *) return 1;; esac ;;
    brainstorm|worker-brainstorm)
      [ "$path" = docs/state/notes.md ] ;;
    worker|worker-task|worker-fresh)
      worker_path_allowed "$path" ;;
    verifier)
      case "$path" in docs/verification/*|docs/state/notes.md) return 0;; *) return 1;; esac ;;
    reviewer)
      return 1 ;;
    status-gate)
      case "$path" in docs/tasks/*.md) return 0;; *) return 1;; esac ;;
    finalizer)
      case "$path" in docs/state/handoff.md|docs/state/notes.md) return 0;; *) return 1;; esac ;;
    orchestrator)
      case "$path" in docs/state/current-run.md|.agent-runs/*) return 0;; *) return 1;; esac ;;
    *) return 1 ;;
  esac
}

usage() {
  echo "Verwendung: $0 context-path PATH | role-write ROLE PATH"
}

case "${1:-}" in
  context-path)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    if context_path_allowed "$2"; then echo "ALLOWED: $2"; else echo "DENIED: $2"; exit 1; fi ;;
  role-write)
    [ "$#" -eq 3 ] || { usage >&2; exit 2; }
    if role_may_write "$2" "$3"; then echo "ALLOWED: $2 -> $3"; else echo "DENIED: $2 -> $3"; exit 1; fi ;;
  *) usage >&2; exit 2 ;;
esac
