---
phase: "08"
result: done
plan_version: "1.1"
implementation_ref: "working-tree:883a89cf7821de5c0a9871c95cb24d2e7c8aa34e531a8f8aef8a7aa40fa98be1"
verification: green
completed_at: "2026-09-04T19:50:38Z"
next_phase: "09"
---

# Handoff Phase 08

## Ergebnis

- Pro finalisiertem Run entsteht genau eine gesperrt und idempotent geschriebene
  CSV-Zeile; vollständige Details bleiben lokal im Run-Metadatenordner.
- Runner-, Router- und Verifierdaten werden getrennt erfasst; fehlende Token-,
  Kosten-, Diff- oder Qualitätswerte bleiben sichtbar leer.
- Fünf rückstellbare Rollout-Stufen sind konfiguriert; ausgeliefert wird
  `shadow`, offene Aufgaben bleiben auch nach grüner Prüfung im Review.
- Dry-Runs erzeugen nur ausdrücklich markierte lokale Metadaten und zählen nie
  als Implementierungserfolg.
- Pilot-v1-Stratifizierung, blinde Rubrik, vorab festgelegte Rohzahlschwellen und
  Basis-Fingerprint-Prüfung sind versioniert.

## Geänderte Dateien

- `scripts/agent/metrics.sh`, `scripts/agent-metrics.sh` — Schema-Migration,
  Laufaggregation, atomische Finalisierung, Summary und Paarvergleich.
- `scripts/orchestrate.sh`, `scripts/route-task.sh`, `scripts/agent/runner.sh`,
  `scripts/agent/status.sh` — Laufdaten, Rollout-Gates, Outcomes und Review.
- `.agent/config.env`, `scripts/agent/config.sh`, `scripts/state-summary.sh`,
  `scripts/validate-ledger.sh` — Schalter, Kurzansicht und zentrale Validierung.
- `docs/state/{metrics.csv,decisions.md}`, `.agent/README.md`,
  `docs/templates/initializer-prompt.md` — Schema und Betriebsentscheidungen.
- `docs/evaluation/pilot-v1/`, `tests/orchestrator/test-phase-08.sh` —
  Pilot-Fixtures, Rubrik und 24 neue deterministische Prüfungen.
- `tests/orchestrator/test-phase-{02,03,04,05,07}.sh` — bestehende Verträge an
  die Eine-Zeile-pro-Run- und Review-Regeln angepasst.

## Verifikation

- `test-phase-01.sh` bis `test-phase-08.sh` — GREEN
  (29/29/33/65/48/39/34/24 Tests).
- `validate-ledger.sh`, `verify.sh`, Shell-Syntax, Summary-Budget und
  `git diff --check` — GREEN.

## Entscheidungen und Abweichungen

- Der echte Pilot wurde nicht ausgeführt, weil reale Modellläufe Kosten
  verursachen. Phase 08 schließt technisch grün mit Rollout-Stufe `shadow`.
- Ein abgebrochener, später fortgesetzter Run wird atomar wieder geöffnet;
  dadurch bleibt seine CSV-Zeile eindeutig und zeigt am Ende das letzte Outcome.

## Offene Punkte

- Für den kostenpflichtigen Pilot müssen 20 reale Task-Referenzen ausgewählt,
  eingefroren, randomisiert und ausdrücklich zur Ausführung beauftragt werden.

## Kontext für die nächste Phase

- Das produktive CSV-Schema besitzt 19 Spalten und genau eine Zeile je Run.
- `ROLLOUT_STAGE=shadow`; Rückfall auf `single-verify` braucht keine Migration.
- `pilot_status` bleibt `not_started`; leere Felder sind keine Nullwerte.
- Externe Telemetrie wird weder benötigt noch verwendet.

## Wiederaufnahme

- `Setze Phase 09 aus plans/09-dokumentation-und-betriebsuebergabe.md um und beginne keine weitere Phase.`
