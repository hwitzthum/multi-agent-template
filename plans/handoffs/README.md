# Vorlage für Phasen-Handoffs

Dieser Ordner enthält nach der Umsetzung jeder Phase genau ein kompaktes
Handoff. Es ersetzt nicht den Projekt-Handoff unter `docs/state/handoff.md`,
sondern übergibt ausschließlich den Stand des Architekturumbaus an die nächste
Phase.

Dateiname:

```text
plans/handoffs/<phase>-handoff.md
```

Beispiel: `plans/handoffs/01-handoff.md`.

## Verbindliche Vorlage

```markdown
---
phase: "01"
result: done                 # done | blocked | partial
plan_version: "1.1"
implementation_ref: "<Git-SHA oder working-tree:fingerprint>"
verification: green         # green | red | partial | not_run
completed_at: "<UTC-Zeit>"
next_phase: "02"
---

# Handoff Phase 01

## Ergebnis
- <maximal fünf konkrete Punkte>

## Geänderte Dateien
- `<Pfad>` — <warum>

## Verifikation
- `<Befehl>` — GREEN/RED

## Entscheidungen und Abweichungen
- <Entscheidung oder „keine“>

## Offene Punkte
- <nur echte Restarbeit oder „keine“>

## Kontext für die nächste Phase
- <maximal fünf Fakten, die nicht zuverlässig aus dem Code ersichtlich sind>

## Wiederaufnahme
- `<genau ein nächster Befehl oder Auftrag>`
```

## Regeln

- Höchstens 80 Zeilen; kurze Fakten statt Sitzungsverlauf.
- Keine vollständigen Logs, Chatverläufe oder erneut kopierten Phasenpläne.
- Nur tatsächlich ausgeführte Prüfungen aufführen.
- Abweichungen vom Plan begründen und im Fortschrittsboard sichtbar machen.
- Bei `done` müssen `verification: green` und der Implementierungs-Fingerprint
  gesetzt sein.
- Die nächste Phase liest nur die ausdrücklich in ihrem Phasenvertrag genannten
  Handoffs.

