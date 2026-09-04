---
phase_id: "07"
depends_on: ["06"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/07-handoff.md"
plan_version: "1.1"
---

# Phase 07 — Fresh Worker, Reviewer, Finalizer und Fehlerpfade

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 07** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/06-handoff.md`. Phase 06 muss `DONE` sein.
2. Minimaler zusätzlicher Kontext: Git-/Worktree-Zustand, Fresh- und Reviewer-
   Prompts, Orchestrator-Abbruchpfade, Verifier-Fingerprint-Vertrag und
   Kandidaten-Fixtures.
3. Setze Phase 07 vor Änderungen auf `IN_PROGRESS`. Falls noch kein eigenes
   Git-Repository existiert, setze die Phase mit diesem Grund auf `BLOCKED` und
   ändere keine Kandidatenlogik unisoliert.
4. Implementiere Fresh Worker, Review, sichere Übernahme und Finalizer nur mit
   isolierten Testkandidaten.
5. Beweise, dass kein Kandidat und kein Finalizer ungeprüft den Hauptstand oder
   Taskstatus überschreibt.
6. Bei Erfolg: `plans/handoffs/07-handoff.md` anlegen, Board aktualisieren,
   Phase 07 auf `DONE` und Phase 08 auf `READY` setzen. Bei Fehler den letzten
   grünen Stand festhalten.
7. Stoppe danach; Phase 08 wird nicht automatisch begonnen.

## Ziel

Fehlannahmen im Ledger dürfen nicht alle späteren Worker verankern. Gleichzeitig
darf ein unabhängiger Versuch den besten vorhandenen Stand nicht ungeprüft
überschreiben.

## Wann ein Fresh Worker startet

Mindestens eines dieser Signale muss vorliegen:

- `fresh_perspective: required`;
- zwei unterschiedliche Worker scheitern am gleichen Akzeptanzkriterium;
- Notes enthalten widersprüchliche aktive Hypothesen;
- Manager will eine bereits verworfene Strategie wieder aufnehmen;
- Änderung ist hochriskant und besitzt mindestens zwei plausible Architekturen;
- Fortschrittsfingerprint bleibt in einer Managed-Runde unverändert;
- Nutzer fordert ausdrücklich eine unabhängige Perspektive.

Der Router protokolliert das Signal. Ein Fresh Worker wird nicht routinemäßig
für jede Aufgabe gestartet.

## Isolierung

Nach Initialisierung des eigenen Git-Repositories arbeitet jeder Fresh Worker
in einer separaten Git-Worktree oder einer technisch gleichwertig isolierten
Arbeitskopie:

```text
Hauptstand (unverändert)
  |
  +-- candidate-a: bisheriger Managed-Ansatz
  +-- candidate-b: Fresh Worker ohne Notes/Ansatzhistorie
```

Regeln:

1. Beide Kandidaten starten vom dokumentierten gleichen Basis-Commit.
2. Fresh Worker erhält keine `notes.md`, Managerbegründung oder Candidate-A-Diff.
3. Beide Kandidaten erhalten identisches Goal, Task, Akzeptanz und
   Sicherheitsregeln.
4. Beide werden mit derselben Verifier-Version unabhängig geprüft.
5. Kein Kandidat wird automatisch in den Hauptstand gemischt.
6. Temporäre Worktrees liegen nur unter dem laufbezogenen lokalen Verzeichnis
   und werden erst nach dokumentiertem Abschluss entfernt.

Wenn Git noch nicht initialisiert ist, ist `managed-fresh` blockiert. Es wird
nicht durch eine unisolierte Kopie simuliert.

## Reviewer-Entscheidung

Der Reviewer sieht:

- Task und Akzeptanz;
- Diffs beider Kandidaten;
- strukturierte Prüfberichte;
- Größen-, Komplexitäts- und Risikohinweise;
- keine vertraulichen Rohlogs.

Er gibt genau eine Empfehlung:

```yaml
---
decision: candidate_b # candidate_a | candidate_b | neither | human
reason_code: BOTH_GREEN_SIMPLER_CHANGE
requires_reverify: true
---
```

Deterministische Vorauswahl:

1. Nur grüne Kandidaten dürfen gewinnen.
2. Ist genau einer grün, ist kein LLM-Review zur Qualitätsentscheidung nötig;
   der grüne Kandidat wird dennoch nach Übernahme neu geprüft.
3. Sind beide rot, lautet das Ergebnis `neither`.
4. Sind beide grün, darf der Reviewer anhand kleinerem Diff, einfacherer Lösung,
   besserer Abdeckung und geringerer Risiken empfehlen.
5. Bei semantischer oder geschäftlicher Abwägung lautet das Ergebnis `human`.

## Sichere Übernahme

1. Vor Übernahme prüfen, dass Hauptstand und Basis-Fingerprint unverändert sind.
2. Kandidatenänderungen als expliziten Patch oder Commit-Liste anzeigen.
3. Nur den gewählten Kandidaten übernehmen.
4. Vollständige Verifikation **im Hauptstand erneut** ausführen.
5. Erst danach Status-Gate anwenden.
6. Verlierergebnis und Gründe kompakt protokollieren; keine falschen Hypothesen
   als Fakten in Notes übernehmen.

## Finalizer

Der Finalizer wird ausgelöst bei:

- globalem Iterationslimit;
- Versuchslimit;
- No-Progress;
- ungültiger wiederholter Managerausgabe;
- Timeout/Providerfehler ohne verbleibenden Retry;
- menschlicher Entscheidung;
- nicht sicher fortsetzbarem externen Dateistand.

Er darf ausschließlich `docs/state/handoff.md`, eine Final-Note und den
Laufabschluss aktualisieren. Er dokumentiert:

- letzten grünen Kandidaten oder „kein grüner Kandidat“;
- aktuellen Taskstatus;
- erste relevante Fehler;
- getestete und verworfene Ansätze;
- benötigte menschliche Entscheidung;
- exakten Wiederaufnahmebefehl, falls sicher.

Er darf keinen Produktcode verändern, kein Rot in Grün umdeuten und kein
`blocked` automatisch auflösen.

## Weitere Fehlerpfade

### Modellantwort leer oder abgeschnitten

- technisch als `empty` oder `truncated` protokollieren;
- keine halbfertige Antwort direkt ins Ledger kopieren;
- optionaler Kurz-Summarizer extrahiert nur verwertbare Hypothesen;
- Versuch zählt, außer klarer Infrastrukturfehler ist als kostenloser Retry
  konfiguriert.

### Provider-/CLI-Fehler

- begrenztes Retry mit Backoff innerhalb eines kleinen separaten
  Infrastruktur-Limits;
- kein stiller Wechsel auf ein anderes Modell;
- Modell- oder Providerwechsel muss sichtbar protokolliert werden.

### Externe Dateiänderung

- aktuellen Fingerprint nicht überschreiben;
- Lauf pausieren;
- Nutzer erhält verständliche Auswahl: Änderungen übernehmen und neu planen
  oder den Agentenlauf separat beenden.

### Manager wiederholt sich

- gleiche Task-ID plus gleicher Fortschrittsfingerprint löst No-Progress aus;
- nicht einfach die Runde erneut ausführen;
- Fresh Worker oder Finalizer wählen, abhängig von verbleibendem Budget.

## Tests

- Fresh-Kontext enthält keine historische Note und keinen Candidate-A-Diff;
- Kandidat kann Hauptstand vor Review nicht verändern;
- roter Kandidat kann grünen nie verdrängen;
- nach Kandidatenübernahme wird im Hauptstand erneut geprüft;
- beide rot führt zu `neither`/`blocked`, nicht zu erzwungener Auswahl;
- Budgetende verändert keinen Produktcode durch den Finalizer;
- leere, abgeschnittene und ungültige Rollenoutputs beschädigen das Ledger nicht;
- externe Änderungen pausieren den Lauf zuverlässig.

## Abnahmekriterien

- Unabhängigkeit des Fresh Workers ist technisch und nicht nur per Prompt
  gewährleistet.
- Der beste bekannte grüne Stand bleibt bis zur erneuten Prüfung geschützt.
- Jeder Abbruch endet mit gültigem Ledger und verständlicher Übergabe.
- Kein Fehlerpfad erzeugt automatisch `done`.
- Temporäre Kandidaten sind pro Lauf auffindbar und kontrolliert entfernbar.
