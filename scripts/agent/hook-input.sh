#!/usr/bin/env bash
# Gemeinsame Zerlegung der Hook-Eingabe fuer bash-guard.sh und commit-gate.sh.
# Beide Hooks bekommen dasselbe JSON auf stdin und muessen daraus denselben
# Befehlstext lesen; zwei Kopien dieser Zeilen sind bereits auseinandergelaufen.
# Kein jq: es ist nicht ueberall vorhanden, und ein Hook darf an einer
# fehlenden Abhaengigkeit nicht scheitern.
#
# Diese Datei wird eingebunden, nicht gestartet. Wer sie einbindet, muss ihr
# Scheitern selbst als Blockade behandeln — ein Hook, der seinen Befehl nicht
# lesen kann, darf nicht stillschweigend durchwinken.

# Liest das Hook-JSON von der Standardeingabe und gibt den Befehlstext aus.
hook_command_text() {
  hook_command=""
  [ -t 0 ] || hook_command=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' | head -n 1)
  hook_command=${hook_command%%'","'*}   # alles ab dem naechsten JSON-Feld abschneiden
  # JSON-Escapes: \n trennt zwei Befehle, \t und \r sind Zwischenraum.
  printf '%s' "$hook_command" | sed 's/\\n/;/g; s/\\[tr]/ /g'
}
