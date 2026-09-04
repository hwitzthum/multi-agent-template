---
phase_id: "06"
depends_on: ["05"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/06-handoff.md"
plan_version: "1.1"
---

# Phase 06 — Verification Gateway und Statusübergänge härten

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 06** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/05-handoff.md`. Phase 05 muss `DONE` sein.
2. Minimaler zusätzlicher Kontext: `scripts/verify.sh`, `scripts/commit-gate.sh`,
   Task-Schema, Status-Helfer, Orchestrator-Verifikationsschnittstelle und die
   bestehenden Tests. Frühere Phasenpläne nicht erneut laden.
3. Setze Phase 06 vor Änderungen auf `IN_PROGRESS`.
4. Implementiere nur Verification Gateway, Berichte, Fingerprints und sichere
   Statusübergänge. Ändere Prüfungen nicht, um bestehende Fehler zu verbergen.
5. Teste positive und absichtlich negative Kontrollfälle sowie
   Kandidaten-Invalidierung.
6. Bei Erfolg: `plans/handoffs/06-handoff.md` anlegen, Board aktualisieren,
   Phase 06 auf `DONE` und Phase 07 auf `READY` setzen. Bei Fehler nicht `DONE`
   setzen und den Verifierfehler getrennt vom Produktfehler dokumentieren.
7. Stoppe danach; Phase 07 wird nicht automatisch begonnen.

## Ziel

Deterministische Evidenz entscheidet über den Status. Ein Workerbericht ist
eine Eingabe für die Prüfung, niemals die Abnahme selbst.

## Verifikationsstufen

`scripts/verify-task.sh <task-id>` führt in definierter Reihenfolge aus:

1. **Ledger:** Schema, Abhängigkeiten und erlaubte Dateiänderungen;
2. **Syntax/Compile:** stackabhängige schnelle Prüfung;
3. **Unit Tests:** betroffene Logik;
4. **Integration Tests:** Schnittstellen und Zusammenspiel;
5. **Lint/Typecheck:** statische Qualitätsregeln;
6. **Build:** ausführbares/auslieferbares Artefakt;
7. **Akzeptanz:** taskbezogene, explizite Checks;
8. **Human Gate:** nur Statusprüfung, kein automatisches Urteil.

Das bestehende `scripts/verify.sh` bleibt die zentrale globale Prüfung. Der neue
Wrapper ergänzt Task-Bezug, Zeitlimits, Bericht und Status-Gate.

## Sichere Ausführung von Akzeptanzbefehlen

Das aktuelle Task-Template enthält Shellbefehle unter `acceptance`. Diese dürfen
nicht blind mit `eval` oder `bash -c` ausgeführt werden.

Vorgehen für die erste Version:

1. Jeder Befehl muss exakt einem erlaubten Präfix entsprechen, zum Beispiel
   `./scripts/verify.sh`, `npm test`, `npm run`, `pytest`, `ruff`, `mypy`.
2. Shell-Metazeichen, Umleitungen, Substitutionen und Befehlsketten werden
   abgewiesen.
3. Argumente werden als Array übergeben, nicht als neu interpretierter String.
4. Projektprofile dürfen die Präfixliste verschärfen oder um benannte Runner
   ergänzen.
5. Langfristig soll `acceptance` auf benannte Check-IDs migrieren; rohe Befehle
   bleiben nur als validierte Kompatibilitätsschicht.

## Prüfbericht

`docs/verification/latest.md` erhält ein festes Format:

```yaml
---
run_id: 20260904T091500Z-T017
task_id: 017
attempt: 2
result: red
started_at: 2026-09-04T09:20:00Z
finished_at: 2026-09-04T09:20:31Z
candidate_fingerprint: <sha256>
verifier_version: <sha256>
---

# Verification

## Stufen
- ledger: GREEN
- unit: RED
- integration: SKIPPED_AFTER_TIMEOUT

## Erster relevanter Fehler
...

## Vollständiger Log
`.agent-runs/<run-id>/verify/attempt-2.log`
```

Alle vorgesehenen Stufen werden nach Möglichkeit ausgeführt, damit der Worker
nicht Fehler einzeln nacheinander entdeckt. Bericht und letzte Zeile verwenden
weiter die vorhandene Konvention `verify: GREEN|RED`.

## Statusregeln

| Situation | Folgestatus |
|---|---|
| alle maschinellen Gates grün, `human_review: false` | `done` |
| alle maschinellen Gates grün, `human_review: true` | `review` |
| rot, Versuche übrig | `todo` oder im aktiven Loop `in_progress` |
| rot, Versuche ausgeschöpft | `blocked` |
| Verifier selbst fehlerhaft/timeout | nicht `done`; technischer Fehler |
| Kandidat und Prüfbericht haben unterschiedliche Fingerprints | ungültig, neu prüfen |

Der Prüfbericht ist nur für exakt den geprüften Kandidaten gültig. Jede
nachträgliche relevante Dateiänderung invalidiert `last_verification: green`.

## Vertrauen in den Verifier

Das Paper berichtet einen Fehler im Evaluator, durch den korrekte Lösungen
falsch bewertet wurden und der öffentliche Sample-Verifier trotzdem grün war.
Darum wird auch die Prüfung selbst getestet:

- positive und negative Kontroll-Fixtures;
- mindestens ein Test, der sicher scheitern muss;
- Vergleich echter Prozessausführung mit Test-Harness bei I/O-Code;
- Version/Fingerprint der Prüflogik im Bericht;
- für riskante Änderungen mehrere unabhängige Stufen statt eines einzigen
  LLM-Reviews;
- Änderungen an Verifiern erzwingen eine erneute Verifikation betroffener Tasks.

## Umsetzungsschritte

1. Einheitliche `step`-Funktion aus dem vorhandenen Verify-Vertrag verwenden:
   alle Stufen sammeln, pro Fehler nur relevanten Log-Auszug zeigen.
2. Taskbezogene Check-Auswahl implementieren, ohne globale Pflichtstufen zu
   umgehen.
3. Timeout und Prozessstatus je Stufe erfassen.
4. Kandidaten- und Verifier-Fingerprint berechnen.
5. Bericht atomar nach `latest.md` und `history/` schreiben.
6. Status-Gate mit Compare-and-set-Übergängen anbinden.
7. `commit-gate.sh` erweitern: Commit bleibt blockiert, wenn `verify.sh --quick`
   rot oder das Ledger inkonsistent ist.
8. `features.md` nur aus nachweisbaren Abnahmen aktualisieren; LLM-Text allein
   ändert keinen Feature-Status.

## Tests

- Worker meldet „fertig“, Test schlägt fehl: Task bleibt offen;
- Test wird nach grünem Bericht verändert: Green-Beleg wird ungültig;
- Kandidat wird nach Prüfung verändert: Statuswechsel wird verweigert;
- `human_review: true`: Ergebnis wird `review`;
- ein absichtlich defekter Test-Harness wird durch Kontroll-Fixture erkannt;
- Metazeichen in `acceptance` werden abgewiesen und nie ausgeführt;
- Timeout und fehlender Befehl erzeugen Rot, nicht Grün;
- alle Fehlerstufen werden kompakt berichtet.

## Abnahmekriterien

- Kein Codepfad setzt `done` ohne passenden grünen Fingerprint.
- Verifikation ist reproduzierbar und ihr eigener Stand nachvollziehbar.
- Human Review ist ein eigener sichtbarer Zustand.
- Fehlerberichte sind kurz genug für den nächsten Worker und vollständig genug
  für einen Menschen über den lokalen Logpfad.
- Das vorhandene Commit-Gate bleibt wirksam.
