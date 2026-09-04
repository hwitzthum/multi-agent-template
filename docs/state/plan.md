# Plan

## Aktuelle Strategie

Das bestehende dateibasierte Task-System wird schrittweise um validierte
Zustände, einen deterministischen Router und klar getrennte Agentenrollen
erweitert. Jede Ausbauphase wird einzeln geprüft und übergeben.

## Meilensteine

- Ledger und Task-Schema sicher les- und schreibbar machen.
- Ausführungsmodus deterministisch wählen.
- Rollenbezogene Kontextpakete und Prompts bereitstellen.
- Manager–Worker-Schleife mit Verifikation und Fehlerbehandlung ergänzen.
- Metriken auswerten und den Betrieb dokumentieren.

## Offene Risiken

- Das Zielprojekt besitzt noch kein eigenes Git-Repository; frische Worktrees
  sind deshalb erst nach einer späteren Initialisierung möglich.
- Die zentrale Produktprüfung ist bis zur Initialisierung ein Platzhalter.

## Änderungsverlauf

- 2026-09-04: Stabiles Ledger und erweitertes Task-Schema für Phase 02 angelegt.
- 2026-09-04: Deterministischen Router und begrenzte Modus-Eskalation für Phase
  03 ergänzt.
- 2026-09-04: Sieben getrennte Rollen-Prompts, begrenzte Kontextpakete,
  Fresh-Worker-Isolation und validierte Rollenoutputs für Phase 04 ergänzt.
