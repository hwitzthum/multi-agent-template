---
phase_id: "05"
depends_on: ["04"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/05-handoff.md"
plan_version: "1.1"
---

# Phase 05 — Orchestrator und Manager–Worker-Loop implementieren

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 05** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/04-handoff.md`. Phase 04 muss `DONE` sein.
2. Minimaler zusätzlicher Kontext: Router, Prompt-/Kontextverträge, Ledger-
   Helfer, Status-Gate-Schnittstelle, Runner-Adapter und vorhandene Test-Fixtures.
3. Setze Phase 05 vor Änderungen auf `IN_PROGRESS`.
4. Implementiere den Loop zuerst vollständig gegen den Fake Runner. Echte
   Modellaufrufe sind erst nach grünen Kontrollflusstests zulässig.
5. Implementiere keine Fresh-Worker-Isolierung aus Phase 07 und keine
   Metrik-Evaluation aus Phase 08 vorab.
6. Bei Erfolg: `plans/handoffs/05-handoff.md` anlegen, Board aktualisieren,
   Phase 05 auf `DONE` und Phase 06 auf `READY` setzen. Bei Fehler den letzten
   konsistenten Zustand und Resume-Befehl festhalten.
7. Stoppe danach; Phase 06 wird nicht automatisch begonnen.

## Ziel

Ein deterministisches Skript steuert den probabilistischen Manager. Der Manager
entscheidet über Strategie und nächsten wertvollen Task; das Skript kontrolliert
Bereitschaft, Limits, gültige Übergänge, Ausführung und Abbruch.

## Einstiegspunkte

```text
./scripts/orchestrate.sh --task 017
./scripts/orchestrate.sh --next
./scripts/orchestrate.sh --task 017 --mode verified
./scripts/orchestrate.sh --resume
./scripts/orchestrate.sh --dry-run
```

- `--task`: expliziter Task;
- `--next`: erste deterministisch bereite Aufgabe;
- `--mode`: bewusste Modusvorgabe innerhalb der Sicherheitsgrenzen;
- `--resume`: validierten unterbrochenen Lauf fortsetzen;
- `--dry-run`: Routing, Kontextumfang und geplante Aufrufe zeigen, ohne Modell
  oder Dateien zu verändern.

## Kontrollfluss

### Gemeinsamer Start

1. Projektwurzel bestimmen; niemals vom aktuellen Unterordner abhängig sein.
2. Konfiguration und Ledger validieren.
3. Task auswählen und Abhängigkeiten prüfen.
4. Sperrdatei atomar anlegen. Ein zweiter Orchestrator darf denselben Zustand
   nicht gleichzeitig bearbeiten.
5. Run-ID erzeugen, Laufordner anlegen und Ausgangsfingerprint speichern.
6. Routingmodus bestimmen und protokollieren.
7. Task von `todo` nach `in_progress` setzen.

### Modus `single`

1. Worker-Kontext bauen.
2. genau einen Worker aufrufen;
3. Verifier ausführen;
4. Status-Gate anwenden;
5. Lauf abschließen.

### Modus `verified`

1. Worker aufrufen;
2. Verifier ausführen;
3. bei Rot Fehler kompakt in Notes übernehmen;
4. solange Versuche verfügbar sind, genau einen Fix-Worker mit dem konkreten
   Fehler aufrufen;
5. erneut verifizieren;
6. grün abschließen oder zu `managed` eskalieren.

### Modus `managed`

1. Falls kein aktueller Plan existiert: Manager-Plan aufrufen.
2. Brainstorm Worker einmalig ausführen; er schreibt keinen Code.
3. Brainstorm-Ausgabe validieren und kuratiert in Notes übernehmen.
4. Manager-Manage aufrufen.
5. Managerentscheidung validieren:
   - `dispatch`: Task muss existieren und ready sein;
   - `done`: Gate muss bereits grün sein;
   - `blocked`: Grund muss gesetzt sein;
   - `request_human`: Lauf pausiert kontrolliert.
6. Genau einen Worker für den gewählten Task aufrufen.
7. Geänderte Pfade gegen den Task-Umfang und verbotene Pfade prüfen.
8. Wenn ein Kandidat entstand, Verifier ausführen.
9. Fortschrittsfingerprint aktualisieren und zurück zu Schritt 4.
10. Spätestens bei `MAX_GLOBAL_ITERATIONS` an den sicheren Finalizer übergeben.

## Fortschrittsmessung

Fortschritt ist nicht die Selbsteinschätzung eines Agenten. Der Fingerprint
setzt sich zusammen aus:

- Hash der relevanten Produktdateien;
- Hash der Task-Statusfelder;
- aktuellem Verifier-Code und -Ergebnis;
- Menge aktiver, neuer Note-IDs;
- Managerentscheidung.

Wenn der Manager denselben Task erneut ausgibt und sich weder Kandidat noch
Prüfergebnis oder relevante Erkenntnis geändert hat, greift der
No-Progress-Guard. Ein einmaliger unveränderter Übergang führt zum Finalizer;
wiederholte Reparaturschleifen sind nicht erlaubt.

## Modell-Runner

`scripts/agent/runner.sh` kapselt den tatsächlich installierten Agenten-CLI.
Der Vertrag:

```text
run_agent ROLE CONTEXT WORKDIR RAW_OUTPUT METADATA_OUTPUT
```

Metadata enthält mindestens Modellname, Start/Ende, Exitstatus, Tokenwerte
soweit verfügbar, Abbruchgrund und Output-Status (`ok`, `truncated`, `empty`,
`error`). Providerdetails dürfen außerhalb dieser Datei nicht ausgewertet
werden.

## Wiederaufnahme und Abbruch

- Bei `SIGINT`, Fehler oder Timeout wird `current-run.md` konsistent auf
  `paused` oder `failed` gesetzt und die Sperre entfernt.
- `--resume` prüft Task-ID, Git-Fingerprint und letzten vollständigen Schritt.
- Bei fremden Dateiänderungen wird nicht automatisch fortgesetzt; der Lauf
  fordert eine bewusste Entscheidung.
- Jeder Schritt schreibt erst Rohartefakte, validiert sie und aktualisiert dann
  das versionierte Ledger.
- Zeitlimits gelten sowohl pro Agentenaufruf als auch für Verifikation.

## Umsetzungsreihenfolge

1. `scripts/agent/common.sh`: Root, Logging, Sperre, sichere temporäre Dateien.
2. `scripts/agent/runner.sh`: Anbieteradapter und Metadatenvertrag.
3. `scripts/orchestrate.sh`: Argumente, Start, Single-Modus, Abschluss.
4. Verified-Modus mit Versuchszähler und Fehlerübergabe.
5. Manager-Plan und Brainstorm.
6. Manager-Manage-Schleife mit genau einer Dispatch-Entscheidung.
7. Fortschrittsfingerprint, Limits und Resume.
8. Shell-Integrationstests mit einem Fake Runner; erst danach echte
   Modellaufrufe.

## Fake Runner für Tests

Tests dürfen keine Tokens verbrauchen. Ein Fake Runner liest vorbereitete
Antworten aus Fixtures und simuliert:

- gültige Implementierung;
- ungültigen Managerentscheid;
- leere oder abgeschnittene Antwort;
- Worker behauptet Erfolg, Verifier ist rot;
- wiederholten identischen Task;
- Timeout und Prozessabbruch.

## Abnahmekriterien

- `--dry-run` verändert keine versionierte oder produktive Datei.
- Pro Manager-Runde wird höchstens ein Worker gestartet.
- Zehn Runden und drei Task-Versuche sind harte Standardobergrenzen.
- Ungültige Agentenausgabe stoppt kontrolliert und beschädigt das Ledger nicht.
- Ein unterbrochener Lauf kann fortgesetzt oder verständlich verworfen werden.
- Single- und Verified-Modus funktionieren ohne Manager.
- Alle Kontrollflusstests laufen ohne echten Modellaufruf.
