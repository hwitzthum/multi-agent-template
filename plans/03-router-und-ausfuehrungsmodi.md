---
phase_id: "03"
depends_on: ["02"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/03-handoff.md"
plan_version: "1.1"
---

# Phase 03 — Adaptiven Router und Ausführungsmodi bauen

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 03** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/02-handoff.md`. Phase 02 muss `DONE` sein.
2. Minimaler zusätzlicher Kontext: `.agent/config.env`, das implementierte
   Task-Schema, Ledger-Validator/-Parser und vorhandene Router-Test-Fixtures.
3. Setze Phase 03 vor Änderungen auf `IN_PROGRESS` und validiere das Ledger.
4. Implementiere nur Router, Modusregeln, Eskalation und Routertests; rufe noch
   keine echten Modelle auf.
5. Weise mit Tests nach, dass harte Regeln deterministisch und menschliche Gates
   nicht umgehbar sind.
6. Bei Erfolg: `plans/handoffs/03-handoff.md` anlegen, Board aktualisieren,
   Phase 03 auf `DONE` und Phase 04 auf `READY` setzen. Sonst Blockade und
   nächsten konkreten Schritt festhalten.
7. Stoppe danach; Phase 04 wird nicht automatisch begonnen.

## Ziel

Orchestrierung wird nur eingesetzt, wenn ihr erwarteter Nutzen den zusätzlichen
Zeit- und Tokenaufwand rechtfertigt. Das ist eine direkte Reaktion auf den
modellabhängigen Nutzen und die deutlich höheren Kosten im Paper.

## Vier Modi

| Modus | Ablauf | Typische Aufgabe |
|---|---|---|
| `single` | ein Worker, danach Pflichtprüfung | kleine, eindeutige Änderung |
| `verified` | Worker, Verifier, bei Fehler begrenzter Fix-Versuch | normale, lokal begrenzte Änderung |
| `managed` | Plan/Brainstorm, Manager wählt je Runde einen Task, Worker, Verify | komplexe oder bereichsübergreifende Änderung |
| `managed-fresh` | wie `managed`, zusätzlich isolierter unabhängiger Kandidat und Review | sehr unsichere, riskante oder festgefahrene Änderung |

`single` heißt nicht „ungeprüft“: Es entfallen nur weitere Modellrollen. Die
deterministische Prüfung bleibt immer bestehen.

## Routingprinzip

Der Router arbeitet zuerst deterministisch. Nur wenn die Regeln kein klares
Ergebnis liefern, darf ein kurzer Klassifizierungsaufruf beraten. Dessen Antwort
ist nicht bindend und wird validiert.

### Harte Regeln

1. Ein explizites `orchestration` im Task gewinnt, sofern Sicherheitsregeln es
   nicht verschärfen müssen.
2. `human_review: true` verhindert unbeaufsichtigtes `done`.
3. `class: open` läuft nie vollautomatisch; mindestens `managed` plus
   menschliches Gate.
4. Änderungen an Authentifizierung, Berechtigungen, Zahlungsflüssen,
   Datenmigrationen, Secrets, Deployment oder Sicherheits-Hooks werden
   mindestens `managed`.
5. Mehrere voneinander unabhängige Komponenten, unbekannte Architektur oder
   mehr als ein bereits fehlgeschlagener Ansatz erhöhen auf `managed`.
6. Wiederholte identische Fehler, widersprüchliche Notizen oder eine explizite
   `fresh_perspective: required` erhöhen auf `managed-fresh`.
7. Dokumentation, einzelne Textwerte oder mechanische Umbenennungen dürfen
   `single` sein, solange kein `human_review` oder Risiko dagegensteht.

### Ausgangsmapping der vorhandenen Klasse

```text
mechanical -> single
patterned  -> verified
open       -> managed + human gate
```

Weitere Risikosignale dürfen den Modus nur nach oben verschärfen. Eine
Herabstufung unter die Klassenregel verlangt eine explizite menschliche Vorgabe.

## Router-Ausgabe

`scripts/route-task.sh <task-id>` gibt maschinenlesbar genau aus:

```text
MODE=managed
REASON_CODE=CROSS_COMPONENT
HUMAN_GATE=false
```

Freier Erklärungstext wird getrennt in den Laufbericht geschrieben. Zulässige
Reason-Codes sind versioniert, beispielsweise:

- `EXPLICIT_OVERRIDE`
- `MECHANICAL_LOCAL`
- `PATTERNED_LOCAL`
- `OPEN_DECISION`
- `CROSS_COMPONENT`
- `HIGH_RISK_DOMAIN`
- `FAILED_ATTEMPTS`
- `CONFLICTING_LEDGER`
- `FRESH_REQUIRED`

## Umsetzungsschritte

1. Risikosignale als kleine, testbare Regeln in `scripts/route-task.sh`
   implementieren.
2. Task-Pfade und erwartete betroffene Bereiche möglichst aus dem Abschnitt
   „Umfang“ oder einem optionalen Feld `touches` lesen. Fehlt die Angabe, wird
   nicht geraten; `patterned` bleibt mindestens `verified`.
3. Manuelle Modusvorgabe als Task-Feld unterstützen und im Laufbericht
   sichtbar machen.
4. Eine Eskalationsregel nach Verifier-Fehlern implementieren:

   ```text
   single -> verified -> managed -> managed-fresh -> blocked
   ```

   Der Orchestrator eskaliert nur an definierten Übergängen und zählt jeden
   Versuch weiter.
5. Optionalen LLM-Klassifizierer hinter ein Feature-Flag setzen. Sein Kontext
   enthält nur Ziel, Task, Klasse, Abhängigkeiten und Risikomatrix; keine
   komplette Codebasis.
6. Router-Entscheidung mit Regelversion, Eingabesignalen und Reason-Code in
   `current-run.md` und den Metriken protokollieren.
7. Einen `--mode`-Parameter für bewusste Einmalläufe anbieten. Er darf das
   menschliche Gate oder harte Risikoregeln nicht umgehen.

## Beispielentscheidungen

| Task | Ergebnis | Begründung |
|---|---|---|
| Buttontext ändern | `single` | mechanisch und lokal; danach Verify/Human Review nach Task |
| API-Feld ergänzen | `verified` | lokales Muster plus Tests |
| Auth über UI, API und DB | `managed` | mehrere Komponenten und hohes Risiko |
| Architekturrefaktor nach zwei Fehlschlägen | `managed-fresh` | Anchoring- und Regressionsrisiko |

## Tests

- jede harte Regel besitzt mindestens einen positiven und negativen Test;
- explizite Vorgabe wird respektiert, aber Sicherheitsminimum nicht
  unterschritten;
- ein Fehlschlag eskaliert genau einmal und zählt den Versuch;
- unbekannter Modus oder Reason-Code wird abgewiesen;
- identische Eingaben erzeugen ohne LLM-Aufruf dieselbe Entscheidung;
- `open` oder `human_review: true` endet nie automatisch auf `done`.

## Abnahmekriterien

- Einfache Aufgaben erzeugen keinen Manager- oder Brainstorm-Aufruf.
- Der Grund jeder Routingentscheidung ist nachvollziehbar.
- Der Router kann deaktiviert und pro Task überschrieben werden.
- Routing ist deterministisch testbar; ein optionales Modell ist nur Berater.
- Modus-Eskalation endet spätestens am Versuchslimit.
