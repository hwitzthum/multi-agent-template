# Ziel

## Ergebnis

Ein wiederverwendbares Projekt-Template, in dem Aufgaben über verständliche
Markdown-Dateien geplant, ausgeführt und nachvollziehbar geprüft werden.

## Muss

- `docs/tasks/*.md` bleibt die einzige verbindliche Aufgabenquelle.
- Statusänderungen und Prüfergebnisse müssen deterministisch validierbar sein.
- Ein neuer Agentenlauf kann den Arbeitsstand ohne frühere Chat-Historie lesen.
- Ungeprüfter Markdown-Inhalt wird niemals als Shellcode ausgeführt.

## Nicht Teil

- Ein anbieterspezifischer Agenten-Loop oder Router in dieser Ausbauphase.
- Produktentscheidungen für ein später aus dem Template erzeugtes Projekt.

## Globale Abnahme

- `./scripts/validate-ledger.sh` meldet `GREEN`.
- `./scripts/verify.sh` bleibt die zentrale Projektprüfung.
- Abgebrochene Schreibvorgänge hinterlassen gültige Ledger-Dateien.
