#!/usr/bin/env bash
# bash-guard.sh — PreToolUse-Hook (matcher: Bash). Harte Sperre für das, was
# der Agent nie tun darf: hochladen (git push, curl, wget), rekursiv löschen
# (rm -r…) und ungespeicherte Arbeit verwerfen (git reset --hard, git clean -f,
# git checkout -- / . / -f, git restore).
# Die deny-Regeln in .claude/settings.json bleiben als erste Schicht, sind aber
# Präfix-Muster: `rm -fr`, `bash -c "git push"` oder `echo x && curl …` rutschen
# durch. Dieses Skript prüft deshalb den GANZEN Befehlstext, auch innerhalb
# von Anführungszeichen. Fehlalarme (z.B. `grep curl datei`) sind gewollt —
# lieber einmal zu viel blockieren; die Meldung sagt dem Agenten, warum.
# Exit 2 = blockiert (stderr geht an den Agenten), Exit 0 = frei.
# Grenze: Stolperdraht, kein Sandkasten — `node -e "fetch(…)"` oder ein
# git-Alias wären nicht erfasst. Echte Isolation bietet die Sandbox von
# Claude Code (/sandbox), sobald sie auf allen Kursrechnern läuft.
set -uo pipefail

# Befehl aus dem Hook-JSON auf stdin lesen (kein jq — nicht überall vorhanden).
cmd=""
[ -t 0 ] || cmd=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' | head -n 1)
cmd=${cmd%%'","'*}            # alles ab dem nächsten JSON-Feld abschneiden
cmd=$(printf '%s' "$cmd" | sed 's/\\n/;/g')   # JSON-Zeilenumbrüche = Befehlstrenner
[ -n "$cmd" ] || exit 0

hit() { printf '%s' "$cmd" | grep -Eq "$1"; }
block() {
  echo "Blockiert durch scripts/bash-guard.sh: $1. Das darf der Agent nicht — der Auftraggeber macht es selbst (KURSANLEITUNG, «Was Claude nicht darf»)." >&2
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
exit 0
