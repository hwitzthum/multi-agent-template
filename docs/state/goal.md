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

- Produktcode oder ein Produkt-Stack; beides legt erst der Initializer nach
  dem Profil an.
- Produktentscheidungen für ein später aus dem Template erzeugtes Projekt.
- Ein direkter Anbieteraufruf außerhalb von `scripts/agent/runner.sh`.

## Globale Abnahme

- `./scripts/validate-ledger.sh` meldet `GREEN`.
- `./scripts/verify.sh` bleibt die zentrale Projektprüfung.
- Abgebrochene Schreibvorgänge hinterlassen gültige Ledger-Dateien.
