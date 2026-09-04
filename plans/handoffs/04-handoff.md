---
phase: "04"
result: done
plan_version: "1.1"
implementation_ref: "working-tree:bea91e7cfc5a4c4aaf62c272aeb67a279b18a373c9925e73a1d5e3664f6e6f1d"
verification: green
completed_at: "2026-09-04T09:15:43Z"
next_phase: "05"
---

# Handoff Phase 04

## Ergebnis

- Sieben Rollen-Prompts besitzen denselben Sicherheits- und Ausgabegrundvertrag,
  aber jeweils genau ein Planungs-, Arbeits-, Prüf- oder Übergabeziel.
- `context.sh` erzeugt rollenbezogene, größenbegrenzte und inhaltsadressierte
  Kontextdateien in fester Abschnittsreihenfolge.
- Secret- und Pfadfilter entfernen ausgeschlossene Inhalte; Code-Includes werden
  auch gegen Symlink-Ausbruch und manipulierte Pfade geprüft.
- Fresh Worker erhalten weder Notes, Planbegründungen noch frühere Fehler;
  Reviewer und Manager bekommen ebenfalls nur ihre benötigten Abschnitte.
- `output.sh` validiert alle Rollenformate und fasst große Rohantworten sicher
  lokal zusammen, ohne den Rohoutput zu verändern.

## Geänderte Dateien

- `docs/templates/agents/*.md` — sieben verbindliche Rollen-Prompts.
- `scripts/agent/{common,context,output}.sh` — Redaktion, Kontextaufbau,
  Hashing, Outputvalidierung und lokale Zusammenfassung.
- `scripts/agent/policy.sh` — konkrete Prompt-Rollen an Schreibgrenzen gebunden.
- `docs/state/metrics.csv`, `scripts/route-task.sh` — Prompt-/Kontext-Hashes,
  Rolle und Run-ID im gemeinsamen atomaren Metrikformat.
- `.agent/README.md`, `docs/state/{plan,decisions}.md` — verständlicher Vertrag
  und begründete Kontextentscheidung.
- `tests/orchestrator/test-phase-04.sh`, `test-phase-03.sh` — 64 neue
  Kontext-/Outputtests und angepasstes Metrikschema.

## Verifikation

- `bash -n scripts/route-task.sh scripts/agent/*.sh tests/orchestrator/*.sh` — GREEN.
- `./tests/orchestrator/test-phase-01.sh` — GREEN, 29 Tests.
- `./tests/orchestrator/test-phase-02.sh` — GREEN, 29 Tests.
- `./tests/orchestrator/test-phase-03.sh` — GREEN, 33 Tests.
- `./tests/orchestrator/test-phase-04.sh` — GREEN, 64 Tests.
- `./scripts/validate-ledger.sh` — GREEN.
- `./scripts/verify.sh` — GREEN; Produktprüfung bleibt bis zur Initialisierung
  der dokumentierte Platzhalter.
- `git diff --check` — GREEN.

## Entscheidungen und Abweichungen

- Kontextdateien sind schreibgeschützt und über ihren Inhalts-Hash benannt;
  identische Eingaben erzeugen keine doppelte Metrikzeile.
- Der Fresh-Kontext enthält statt eines früheren Prüfberichts nur den statischen
  Hinweis, die Acceptance-Befehle des Tasks unabhängig auszuführen.
- Phase 04 startet vertragsgemäß noch keine Modelle und keinen Orchestrator-Loop.

## Offene Punkte

- Keine Restarbeit aus Phase 04; die tatsächliche Aufrufschleife folgt in Phase 05.

## Kontext für die nächste Phase

- `context.sh build` validiert das Ledger vor jedem Kontextaufbau.
- Rollenoutputs müssen vor jeder Auswertung durch `output.sh validate` laufen.
- Der Loop darf nur gezielt freigegebene Codepfade als `--include` übergeben.
- Hash-Metriken verwenden das in Phase 04 erweiterte CSV-Schema.
- Schreibgeschützte Kontextdateien und Rohoutputs bleiben lokal in `.agent-runs/`.

## Wiederaufnahme

- `Setze Phase 05 aus plans/05-orchestrator-und-manager-worker-loop.md um und beginne keine weitere Phase.`
