# Plan

## Aktuelle Strategie

Die Orchestrierung ist vollständig: validiertes Ledger, deterministischer
Router, sieben getrennte Rollen, Verification Gateway, Fresh-Kandidaten und
lokale Metriken sind umgesetzt und durch `tests/orchestrator/` abgedeckt. Die
Vorlage wartet auf die Initialisierung eines ersten Projekts aus einem Brief.

## Meilensteine

- Erledigt: Ledger, Router, Kontextpakete, Manager–Worker-Loop, Fresh-Kandidaten,
  Metriken und Betriebsdokumentation.
- Offen: Initialisierung des ersten Projekts nach
  `docs/templates/initializer-prompt.md`; danach werden die ersten Tasks frei.

## Offene Risiken

- Die zentrale Produktprüfung `scripts/verify.sh` ist bis zur Initialisierung
  ein Platzhalter und meldet immer GREEN.
- Ein erster echter Lauf verursacht Modellkosten; offene oder riskante Tasks
  starten ohne weitere Freigabe den Manager-Loop.

## Änderungsverlauf

- 2026-09-04: Stabiles Ledger und erweitertes Task-Schema für Phase 02 angelegt.
- 2026-09-04: Deterministischen Router und begrenzte Modus-Eskalation für Phase
  03 ergänzt.
- 2026-09-04: Sieben getrennte Rollen-Prompts, begrenzte Kontextpakete,
  Fresh-Worker-Isolation und validierte Rollenoutputs für Phase 04 ergänzt.
- 2026-09-04: Rollout-Stufen, `DEFAULT_MODE`, `ROUTER_ENABLED` und die
  Pilot-Evaluation entfernt; die Router-Entscheidung wird direkt ausgeführt.
