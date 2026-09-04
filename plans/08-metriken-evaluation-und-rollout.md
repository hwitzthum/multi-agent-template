---
phase_id: "08"
depends_on: ["07"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/08-handoff.md"
plan_version: "1.1"
---

# Phase 08 — Metriken, Evaluation und adaptiven Rollout einführen

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 08** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/07-handoff.md`. Phase 07 muss `DONE` sein.
2. Minimaler zusätzlicher Kontext: implementierte Runner-Metadaten, Router-
   Reason-Codes, Verifikationsberichte, `docs/state/metrics.csv`, Summary-Skript
   und Pilot-Fixtures. Ältere Phasenpläne nicht erneut laden.
3. Setze Phase 08 vor Änderungen auf `IN_PROGRESS`.
4. Implementiere zuerst Schema, Erfassung und Dry-Run-Auswertung. Kostenpflichtige
   echte Pilotläufe erfordern weiterhin den ausdrücklichen Auftrag des Nutzers.
5. Erfinde keine Token-, Kosten- oder Qualitätswerte. Fehlende Werte bleiben
   sichtbar leer.
6. Bei Erfolg der technischen Phase: `plans/handoffs/08-handoff.md` anlegen,
   Board aktualisieren, Phase 08 auf `DONE` und Phase 09 auf `READY` setzen. Ein
   noch nicht ausgeführter kostenpflichtiger Pilot wird als bewusster offener
   Betriebsauftrag dokumentiert, nicht als erfundene Messung.
7. Stoppe danach; Phase 09 wird nicht automatisch begonnen.

## Ziel

Der Umbau soll nicht nur plausibel wirken, sondern anhand realer Aufgaben zeigen,
wann zusätzliche Rollen Qualität gewinnen und wann sie nur Kosten erzeugen.

## Metrikschema

Die bestehende leere `docs/state/metrics.csv` wird vor dem ersten Produktlauf
additiv auf folgende Spalten migriert:

```text
run_id,task_id,class,mode,model,prompt_version,manager_calls,worker_calls,
verifier_runs,rounds,attempts,tokens_in,tokens_out,cost_estimate,
duration_seconds,verification,human_review,outcome,date
```

Falls bei einem CLI keine Token- oder Kostenwerte verfügbar sind, bleibt das
Feld leer; es wird nicht geschätzt, ohne die Schätzung zu kennzeichnen.

Zusätzlich erhält jeder Run lokal eine maschinenlesbare Metadatendatei unter
`.agent-runs/<run-id>/metadata`. Die CSV enthält nur die kompakte, langfristig
nützliche Zusammenfassung.

## Outcome-Definitionen

- `success`: maschinell grün und gegebenenfalls menschlich freigegeben;
- `review`: maschinell grün, menschliche Prüfung offen;
- `blocked`: Versuchslimit oder echte Abhängigkeit;
- `no_progress`: Guard ausgelöst;
- `infrastructure_error`: Agenten-CLI/Provider nicht nutzbar;
- `verification_error`: Prüfsystem selbst fehlerhaft;
- `cancelled`: bewusst beendet.

Diese Begriffe werden nicht vermischt. Insbesondere zählt ein
Infrastrukturfehler nicht als fachlich falsche Implementierung.

## Pilotdesign

Vor automatischer Standardaktivierung wird ein kontrollierter Pilot gefahren:

1. 20 repräsentative, voneinander unabhängige Coding-Tasks auswählen.
2. Aufgaben nach `mechanical`, `patterned`, `open` sowie Risiko und Größe
   stratifizieren.
3. Möglichst denselben Task zweimal auf demselben Ausgangsstand ausführen:
   - Single/Verified-Baseline;
   - Router-/Manager-Variante.
4. Modell, Version, Temperatur/Reasoning, Toolzugriff, Verifier und Ausgangsstand
   konstant halten.
5. Reihenfolge randomisieren, damit Lern- oder Zeittrends weniger verzerren.
6. Keine Kandidaten gegenseitig als Kontext verwenden.
7. Ergebnisse erst nach deterministischer Prüfung und, wo nötig, blindem
   menschlichem Review bewerten.

Wenn zweimalige Ausführung eines realen Tasks zu teuer ist, wird ein kleineres
festes Evaluationsset aus anonymisierten früheren Tasks mit eingefrorenem
Ausgangsstand verwendet. Diese Einschränkung wird dokumentiert.

## Zu messende Größen

| Dimension | Kennzahl |
|---|---|
| Qualität | grüne Tasks, Regressionen, Human-Review-Korrekturen |
| Effizienz | Modellaufrufe, Tokens, Kosten, Laufzeit |
| Stabilität | Varianz über Wiederholungen, Timeouts, leere Antworten |
| Prozess | Versuche, Runden, No-Progress, Eskalationen |
| Wartbarkeit | Diff-Größe, zurückgenommene Änderungen, neue Defekte |
| Verifier | falsch grüne/rote Fälle, Harness-Fehler |

## Entscheidungsschwellen

Die exakten Schwellen werden vor dem Pilot in `docs/state/decisions.md`
festgelegt, nicht nach Sichtung der Ergebnisse passend gemacht. Ausgangspunkt:

- `mechanical`: Manager bleibt aus, sofern Single + Verify mindestens gleich
  zuverlässig ist;
- `patterned`: Managed wird Standard nur bei messbar höherer Erfolgsquote oder
  deutlich weniger manueller Nacharbeit;
- `open`: kein unbeaufsichtigter Loop unabhängig von Erfolgsquote;
- `managed-fresh`: nur bei belegtem Nutzen in festgefahrenen/hochriskanten
  Fällen;
- keine Aktivierung, wenn Mehrkosten entstehen, ohne die vorher festgelegte
  Qualitätsverbesserung zu erreichen.

Bei nur 20 Tasks sind Prozentwerte explorativ. Es werden Rohzahlen und
taskweise Paarvergleiche berichtet, keine Scheingenauigkeit.

## Rollout-Stufen

1. **Shadow/Dry Run:** Router entscheidet, führt aber nur den vom Nutzer
   gewählten Modus aus.
2. **Single + Verify:** neue Status- und Verifikationsgates produktiv, Manager
   aus.
3. **Managed opt-in:** einzelne komplexe Tasks per explizitem Feld.
4. **Adaptive Empfehlung:** Router schlägt vor, Nutzer bestätigt.
5. **Adaptive Ausführung:** nur für empirisch freigegebene Klassen; offene und
   human-review Tasks bleiben beaufsichtigt.

Jede Stufe besitzt einen einfachen Schalter in `.agent/config.env` und kann ohne
Datenmigration auf die vorherige Stufe zurückgestellt werden.

## Dashboard ohne neue Abhängigkeiten

`scripts/state-summary.sh` bleibt unter seiner 250-Token-Grenze und zeigt nur:

```text
run: T017 managed iter 2/10 attempt 1/3
verify: RED (unit)
ready: 4 | review: 1 | blocked: 0
```

Eine ausführlichere lokale Auswertung kann `scripts/agent-metrics.sh` als Tabelle
aus der CSV erzeugen. Externe Analytics sind nicht erforderlich.

## Umsetzungsschritte

1. CSV-Migration und robuste Append-Funktion implementieren.
2. Laufmetadaten aus Runner, Router und Verifier zusammenführen.
3. Doppelte oder halbe CSV-Zeilen durch atomisches Anhängen/Sperre verhindern.
4. Dry-Run-Routerentscheidungen getrennt von echten Outcomes markieren.
5. Pilot-Taskset und Bewertungsrubrik versionieren.
6. Baseline und Orchestrierung auf identischem Ausgangsstand ausführen.
7. Ergebnisse taskweise auswerten und Routerregeln erst danach anpassen.
8. Entscheidung über nächste Rollout-Stufe in Alltagssprache dokumentieren.

## Tests

- fehlende Tokenwerte erzeugen gültige CSV-Zeile;
- abgebrochener Lauf erhält genau ein Outcome;
- wiederholtes Finalisieren erzeugt keine doppelte Zeile;
- gleiche Task-/Run-ID wird erkannt;
- Summary hält das Token-/Zeilenbudget ein;
- Dry-Run zählt nicht als Implementierungserfolg;
- Pilotvergleich verwendet nachweislich denselben Basis-Fingerprint.

## Abnahmekriterien

- Nutzen und Kosten sind pro Task und Modus nachvollziehbar.
- Routerregeln beruhen nach dem Pilot auf Daten, nicht nur auf Intuition.
- Rollback auf Single + Verify ist jederzeit möglich.
- Keine externe Telemetrie oder Veröffentlichung wird benötigt.
- Human-Review und Infrastrukturfehler werden getrennt ausgewiesen.
