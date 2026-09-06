#!/usr/bin/env bash
# bash-guard.sh — PreToolUse-Hook (matcher: Bash). Harte Sperre für das, was
# der Agent nie tun darf: hochladen (git push, curl, wget), rekursiv löschen
# (rm -r…) und ungespeicherte Arbeit verwerfen (git reset --hard, git clean -f,
# git checkout -- / . / -f, git restore). Dazu `git --no-verify`, das die
# Pruef-Hooks selbst umginge.
# Die deny-Regeln in .claude/settings.json bleiben als erste Schicht, sind aber
# Präfix-Muster: `rm -fr`, `bash -c "git push"` oder `echo x && curl …` rutschen
# durch. Dieses Skript prüft deshalb den GANZEN Befehlstext, auch innerhalb
# von Anführungszeichen. Fehlalarme (z.B. `grep curl datei`) sind gewollt —
# lieber einmal zu viel blockieren; die Meldung sagt dem Agenten, warum.
# Exit 2 = blockiert (stderr geht an den Agenten), Exit 0 = frei.
# Grenze: Stolperdraht, kein Sandkasten — `node -e "fetch(…)"` oder ein
# git-Alias wären nicht erfasst. Echte Isolation bietet die Sandbox von
# Claude Code (/sandbox).
set -uo pipefail

# Befehl aus dem Hook-JSON auf stdin lesen. Der Leser steht in
# scripts/agent/hook-input.sh, damit beide Hooks dieselbe Eingabe sehen.
# Faellt er aus, wird blockiert: ein Guard, der seinen Befehl nicht lesen kann,
# darf nicht durchwinken.
guard_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 2
. "$guard_dir/agent/hook-input.sh" 2>/dev/null || {
  echo "Blockiert durch scripts/bash-guard.sh: die Hook-Eingabe ist nicht lesbar." >&2; exit 2; }
cmd=$(hook_command_text)
[ -n "$cmd" ] || exit 0

hit() { printf '%s' "$cmd" | grep -Eq "$1"; }
block() {
  echo "Blockiert durch scripts/bash-guard.sh: $1. Das darf der Agent nicht — der Auftraggeber macht es selbst." >&2
  exit 2
}

W='(^|[^[:alnum:]_./-])'      # Wortanfang (auch nach Anführungszeichen)
S='[^|;&]*'                   # bis zum nächsten Befehlstrenner

hit "${W}git${S}[[:space:]]push([^[:alnum:]_-]|$)"          && block "git push (hochladen)"
hit "${W}(curl|wget)([^[:alnum:]_-]|$)"                     && block "curl/wget (Netzzugriff)"
hit "${W}rm${S}[[:space:]](-[[:alnum:]]*[rR]|--recursive)" \
                                                            && block "rm rekursiv (massenhaft löschen)"
hit "${W}git${S}[[:space:]]reset[[:space:]]${S}--hard"      && block "git reset --hard (verwirft ungespeicherte Arbeit)"
hit "${W}git${S}[[:space:]]clean[[:space:]]${S}(-[[:alnum:]]*f|--force)" \
                                                            && block "git clean -f (löscht unversionierte Dateien)"
hit "${W}git${S}[[:space:]]checkout([[:space:]]+[^|;&[:space:]]+)*[[:space:]]+(--|\.|-f|--force)([[:space:]]|$)" \
                                                            && block "git checkout -- / . / -f (verwirft ungespeicherte Arbeit)"
hit "${W}git${S}[[:space:]]restore([^[:alnum:]_-]|$)"       && block "git restore (verwirft ungespeicherte Arbeit; zum Entstagen: git reset <datei>)"
hit "${W}git${S}[[:space:]]--no-verify([^[:alnum:]_-]|$)"   && block "git --no-verify (umgeht Prüf-Hooks)"

# Zusätze für den Headless-Lauf (AGENT_HEADLESS=1 setzt der Runner). Ein Agent
# im Orchestrator arbeitet nur im Arbeitsbaum: Historie und Zweige gehören dem
# Orchestrator und dem Menschen, Veröffentlichen und Installieren keinem von
# beiden. Interaktiv bleiben diese Befehle erlaubt — dort steht ein Mensch
# daneben, und `git commit` hat mit commit-gate.sh sein eigenes Prüftor.
[ "${AGENT_HEADLESS:-}" = 1 ] || exit 0

hit "${W}git${S}[[:space:]](commit|merge|rebase|stash|worktree)([^[:alnum:]_-]|$)" \
                                                            && block "git commit/merge/rebase/stash/worktree im Headless-Lauf (Historie und Zweige führt der Orchestrator)"
hit "${W}git${S}[[:space:]]branch[[:space:]]${S}-D([^[:alnum:]_-]|$)" \
                                                            && block "git branch -D (löscht einen Zweig samt Arbeit)"
hit "${W}pip3?${S}[[:space:]]install([^[:alnum:]_-]|$)"     && block "pip install (verändert die Umgebung außerhalb des Arbeitsbaums)"
hit "${W}npm${S}[[:space:]]publish([^[:alnum:]_-]|$)"       && block "npm publish (veröffentlichen)"
exit 0
