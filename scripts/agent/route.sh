#!/usr/bin/env bash
# Deterministischer Modus-Router. Diese Datei wird eingebunden, nicht gestartet;
# sie liest nur den Task und startet weder Modelle noch Agenten.
#
# Regel: mode = max(Basis, Rang(Versuche), Risiko-Minimum).
#   Basis    Override (--mode oder orchestration), sonst die Klasse.
#   Versuche 0 hebt nichts, 1 hebt auf verified, ab 2 auf managed.
#   Risiko   ein gesetztes risk_flag hebt das Minimum auf managed.
# Ein ausgeschoepftes Versuchslimit ergibt blocked, bevor irgendetwas anderes gilt.
set -uo pipefail

agent_route_rank() {
  case "$1" in single) echo 1 ;; verified) echo 2 ;; managed) echo 3 ;; *) return 1 ;; esac
}

agent_route_mode_of_rank() {
  case "$1" in 1) echo single ;; 2) echo verified ;; 3) echo managed ;; *) return 1 ;; esac
}

# agent_route_mode <task-datei> <cli-modus oder ""> <max-versuche>
agent_route_mode() {
  local task_file=$1 cli_mode=$2 max_attempts=$3 base rank attempts flags
  attempts=$(ledger_scalar "$task_file" attempts) || return 1
  case "$attempts:$max_attempts" in *[!0-9:]*) return 1 ;; esac
  if [ "$attempts" -ge "$max_attempts" ]; then printf '%s\n' blocked; return 0; fi
  base=$cli_mode
  [ -n "$base" ] || base=$(ledger_scalar "$task_file" orchestration) || return 1
  if [ "$base" = auto ] || [ -z "$base" ]; then
    case "$(ledger_scalar "$task_file" class)" in
      mechanical) base=single ;;
      patterned) base=verified ;;
      open) base=managed ;;
      *) return 1 ;;
    esac
  fi
  rank=$(agent_route_rank "$base") || return 1
  case "$attempts" in 0) ;; 1) [ "$rank" -ge 2 ] || rank=2 ;; *) rank=3 ;; esac
  flags=$(ledger_list "$task_file" risk_flags 2>/dev/null || true)
  case "$flags" in *[![:space:]]*) [ "$rank" -ge 3 ] || rank=3 ;; esac
  agent_route_mode_of_rank "$rank"
}
