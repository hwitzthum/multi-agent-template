---
phase_id: "02"
depends_on: ["01"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/02-handoff.md"
plan_version: "1.1"
---

# Phase 02 — Ledger und Task-Schema erweitern

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 02** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/01-handoff.md`. Phase 01 muss `DONE` und
   Phase 02 `READY`, `IN_PROGRESS` oder `BLOCKED` sein.
2. Minimaler zusätzlicher Kontext: die in Handoff 01 genannten Änderungen,
   `docs/templates/task-template.md`, `docs/tasks/`, `docs/state/`,
   `scripts/next-tasks.sh` und `scripts/state-summary.sh`.
3. Setze Phase 02 vor Änderungen auf `IN_PROGRESS` und prüfe zuerst, dass Phase
   01 nicht nur dokumentiert, sondern im Repository vorhanden ist.
4. Implementiere ausschließlich Ledger, Schema, Migration und Validator dieser
   Phase; noch keinen Router oder Modell-Loop.
5. Führe alle Schema-, Parser-, Migrations- und Rückwärtskompatibilitätstests aus.
6. Bei Erfolg: `plans/handoffs/02-handoff.md` anlegen, Board aktualisieren,
   Phase 02 auf `DONE` und Phase 03 auf `READY` setzen. Andernfalls den genauen
   gültigen Zwischenstand dokumentieren.
7. Stoppe danach; Phase 03 wird nicht automatisch begonnen.

## Ziel

Das vorhandene Dateisystem wird zu einem validierbaren Ledger erweitert, das
frische Agentenaufrufe ohne vollständige Chat-Historie versorgt. Task-Dateien
bleiben menschenlesbar und zugleich maschinell steuerbar.

## Neue Ledger-Dateien

### `docs/state/goal.md`

Enthält das stabile Ziel, Grenzen und globale Akzeptanz. Es wird nicht bei jeder
Runde umformuliert.

```markdown
# Ziel

## Ergebnis
...

## Muss
- ...

## Nicht Teil
- ...

## Globale Abnahme
- ...
```

### `docs/state/plan.md`

Enthält die aktuelle Strategie, Meilensteine, offene Risiken und einen kurzen
Änderungsverlauf. Der Manager ersetzt die aktive Strategie kontrolliert, statt
jede Runde neue Absätze anzuhängen.

### `docs/state/notes.md`

Enthält kuratierte Fakten, Hypothesen, verworfene Ansätze und aktuelle Fehler.
Jeder Eintrag erhält Datum, Quelle, Vertrauensstatus und betroffene Task-IDs:

```markdown
## N-0042 — API verwendet asynchrone DB-Zugriffe

- tasks: [017, 019]
- source: worker
- confidence: verified
- status: active
- evidence: `tests/test_projects.py`
- finding: ...
```

Zulässige Vertrauenswerte sind `hypothesis`, `observed`, `verified` und
`rejected`. Ein Fresh Worker erhält keine Einträge aus dieser Datei.

### `docs/state/current-run.md`

Strenges Frontmatter, nur vom Orchestrator geschrieben:

```yaml
---
run_id: 20260904T091500Z-T017
task_id: 017
mode: managed
phase: verify
iteration: 2
attempt: 1
last_progress_fingerprint: <sha256>
started_at: 2026-09-04T09:15:00Z
---
```

Es gibt höchstens einen aktiven Lauf. Nach Abschluss bleibt der letzte Stand
lesbar, trägt aber `phase: finished`.

### `docs/verification/`

- `latest.md`: letzter strukturierter Prüfbericht;
- `history/<run-id>-<attempt>.md`: kompakte historische Berichte;
- vollständige Konsolenausgaben bleiben lokal in `.agent-runs/`.

## Erweitertes Task-Frontmatter

Das bestehende Schema wird additiv erweitert:

```yaml
---
id: 017
title: "POST projects implementieren"
depends_on: [011, 013]
features: [F-023]
status: todo
class: patterned
orchestration: auto
fresh_perspective: auto
attempts: 0
max_attempts: 3
last_verification: never
human_review: false
acceptance:
  - "./scripts/verify.sh"
  - "npm test -- projects"
blocked_reason: ""
---
```

Zulässige Statuswerte:

```text
todo -> in_progress -> done
                    -> review -> done
                    -> todo
                    -> blocked
```

- `done` ist nur nach grünem Status-Gate zulässig.
- `review` bedeutet: deterministische Prüfungen sind grün, menschliche Prüfung
  ist noch offen.
- `blocked` wird nach ausgeschöpften Versuchen oder einem nicht automatisch
  lösbaren Hindernis gesetzt.
- `orchestration` ist eine optionale explizite Vorgabe: `auto`, `single`,
  `verified`, `managed`, `managed-fresh`.
- `fresh_perspective` kann `auto`, `required` oder `off` sein.

## Umsetzungsschritte

1. Vorlagen für alle vier Ledger-Dateien anlegen.
2. `docs/templates/task-template.md` additiv um die neuen Felder und
   Statusdefinitionen erweitern.
3. Bestehende Tasks migrieren: fehlende Felder erhalten Defaults; unbekannte
   Felder bleiben erhalten; IDs und Abhängigkeiten ändern sich nicht.
4. `scripts/validate-ledger.sh` implementieren. Es prüft:
   - eindeutige Task-IDs;
   - bekannte Status-, Klassen- und Moduswerte;
   - existierende Abhängigkeiten und zyklenfreien Graph;
   - `attempts <= max_attempts`;
   - Pflichtabschnitte und zulässige Frontmatter-Form;
   - Konsistenz zwischen `current-run.md` und aktivem Task;
   - bei `done`: `last_verification: green` und passender Prüfbericht.
5. Frontmatter-Parsing zentral in `scripts/agent/ledger.sh` kapseln. Es werden
   nur bekannte einzelne Werte und einfache Listen gelesen. Freier Markdowntext
   wird nie als Shellcode interpretiert.
6. `scripts/next-tasks.sh` so erweitern, dass nur `todo`-Tasks mit vollständig
   erfüllten Abhängigkeiten erscheinen. Ausgabe bleibt kompatibel:
   `READY: <id> | <title> | <class>`.
7. Notizarchivierung einführen: ab einer festen Größenobergrenze werden
   erledigte oder verworfene Einträge nach `docs/state/notes-archive/` verschoben.
   Aktive, für offene Tasks relevante Einträge bleiben erhalten.
8. Jede Ledger-Änderung atomar schreiben: temporäre Datei im selben Ordner,
   validieren, danach umbenennen. Ein abgebrochener Lauf darf keine halbe
   Frontmatter-Datei hinterlassen.

## Status-Gate

Nur `scripts/agent/status.sh` darf maschinelle Statusübergänge schreiben. Vor
jeder Änderung prüft es den erwarteten bisherigen Status. Dadurch kann ein
veralteter Worker keinen inzwischen geänderten Task überschreiben.

Beispiel:

```text
set_status 017 in_progress todo
set_status 017 done in_progress   # zusätzlich nur mit grünem Prüfbeleg
```

## Tests

- gültiger Task-Graph wird akzeptiert;
- fehlende oder zyklische Abhängigkeit wird abgewiesen;
- `done` ohne grünen Prüfbericht wird abgewiesen;
- `human_review: true` kann nicht automatisch von `in_progress` zu `done`;
- paralleler/veralteter Statuswechsel schlägt fehl;
- Notizen mit `rejected` werden nicht als aktive Fakten in Kontexte übernommen;
- ein Schreibabbruch bewahrt die vorherige gültige Datei.

## Abnahmekriterien

- Das Ledger kann vollständig ohne Chat-Historie verstanden werden.
- Die vorhandenen Markdown-Tasks bleiben die einzige Task-Wahrheit.
- Der Validator liefert konkrete, für Nicht-Entwickler verständliche Fehler.
- Kein Parser verwendet `eval` oder führt Markdown-Inhalte aus.
- Der Zustand bleibt nach Prozessabbruch validierbar und fortsetzbar.
