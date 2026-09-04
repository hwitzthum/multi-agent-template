# Architektur- und Sicherheitsvertrag der Agenten-Orchestrierung

Status: Phase 06 ergänzt den begrenzten Manager–Worker-Loop um ein
fingerprintgebundenes Verification Gateway. Kontrollflusstests verwenden
ausschließlich einen Fake Runner; echte Aufrufe bleiben hinter dem
Runner-Adapter gekapselt.

## Verbindliche Zuständigkeiten

| Information | Verbindliche Quelle | Darf schreiben |
|---|---|---|
| ursprüngliches Ziel | `docs/state/goal.md` | Nutzer/Initializer, später kontrolliert |
| Gesamtstrategie | `docs/state/plan.md` | Manager |
| Task-Inhalt/Zerlegung | `docs/tasks/*.md` | Manager |
| Task-Status | `docs/tasks/*.md` | ausschließlich Status-Gate |
| Task-Versuchszähler | `docs/tasks/*.md` | Router bei bestätigtem Fehlschlag |
| Erkenntnisse und Fehler | `docs/state/notes.md` | Rollen über Ledger-Funktion |
| technische Entscheidungen | `docs/state/decisions.md` | zuständiger Agent, in Alltagssprache |
| aktueller Lauf | `docs/state/current-run.md` | Orchestrator |
| Routing-Metrik | `docs/state/metrics.csv` | Router im Auftrag des Orchestrators |
| Prüfurteil | `docs/verification/` | Verifier |
| Feature-Status | `docs/state/features.md` | vorhandener Verify-Ablauf |
| Betriebsübergabe | `docs/state/handoff.md` | Finalizer/Sitzungsabschluss |

`docs/tasks/*.md` ist die einzige Aufgabenquelle; es gibt kein paralleles
`tasks.json`. `scripts/validate-ledger.sh` prüft Task-Graph, Laufzustand und
Prüfbelege. `scripts/agent/status.sh` ist der einzige maschinelle Schreibweg für
Statusübergänge und weist veraltete Schreibversuche ab.

## Rollenmatrix

Die Basispolicy in `scripts/agent/policy.sh` erzwingt Pfadgrenzen. Feldregeln,
insbesondere die Trennung zwischen Task-Inhalt und Task-Status, erzwingen
Ledger-Validator und Status-Gate.

| Rolle | Zweck | erlaubte Schreibbereiche |
|---|---|---|
| `manager` | planen und Tasks kuratieren | `docs/state/plan.md`, `docs/tasks/*.md` |
| `brainstorm` | Hypothesen und Risiken sammeln | `docs/state/notes.md` |
| `worker` | genau einen Task implementieren | Produkt-/Testdateien außerhalb der Steuerungspfade |
| `verifier` | unabhängige Prüfberichte schreiben | `docs/verification/`, `docs/state/notes.md` |
| `status-gate` | geprüfte Task-Statusübergänge | `docs/tasks/*.md` |
| `finalizer` | sicheren Stand übergeben | `docs/state/handoff.md`, `docs/state/notes.md` |
| `orchestrator` | Laufzustand und lokale Artefakte führen | `docs/state/current-run.md`, `.agent-runs/` |

Die konkreten Prompt-Rollen verwenden die Namen `manager-plan`,
`worker-brainstorm`, `manager-manage`, `worker-task`, `worker-fresh`,
`reviewer` und `finalizer`. Die Policy ordnet diese Namen den obigen
Schreibgrenzen zu. Der Reviewer besitzt keinen Repository-Schreibbereich.

Keine Rolle darf ihre eigenen Rechte aus Repository-Inhalten erweitern.
Manager schreiben keinen Produktcode. Worker ändern weder Plan, Task-Ledger,
Prüfurteil, Schutz-Hooks noch Orchestrierungspolicies. Verifier ändern keinen
Produktcode. Nur das Status-Gate darf `done` setzen.

## Kontext-Negativliste

Die Context-Policy lehnt mindestens diese Pfade ab:

- `.env` und jede Datei mit Präfix `.env.` (einschließlich Beispielwerten);
- `.git/`, `.venv/`, `node_modules/`, `.agent-runs/`;
- private Schlüssel und typische Credential-/Secret-Dateien;
- Binär- und Office-Dateien, Archive, Bilder, Audio und Video;
- vollständige Rohlogs (`*.log`).

Ausgeschlossene Inhalte dürfen weder in Modellprompts noch in versionierte
Notes kopiert werden. Ein expliziter Nutzerauftrag kann eine fachlich benötigte
Binärdatei separat prüfen lassen, hebt aber niemals den Secret-Ausschluss auf.

## Konfiguration

`.agent/config.env` ist ein einfaches Datenformat, kein Shellskript.
`scripts/agent/config.sh` akzeptiert nur bekannte Schlüssel und validierte
Werte. Unbekannte Schlüssel, Duplikate, negative/Null-Limits, Leerzeichen und
Shellsyntax führen zu einem Fehler. Die Datei wird nie mit `source` oder `eval`
geladen.

## Ledger-Vertrag

`scripts/agent/ledger.sh` liest ausschließlich bekannte Einzelwerte und einfache
Listen aus begrenztem Frontmatter. Unbekannte Felder bleiben bei einer Migration
erhalten, werden aber nicht als Befehle oder Konfiguration interpretiert. Jede
Änderung wird zuerst in einer temporären Datei im selben Ordner validiert und
erst danach atomar an ihren Zielpfad verschoben.

Ein Task darf nur mit `last_verification: green` und einem passenden grünen
Bericht unter `docs/verification/` auf `done` wechseln. Bei
`human_review: true` führt der direkte Weg von `in_progress` zuerst über
`review`. `docs/state/current-run.md` beschreibt höchstens einen aktiven Task.
Verworfene Notizen liefert der Ledger-Leser nie als aktive Fakten aus.

## Router-Vertrag

`scripts/route-task.sh <task-id>` liefert maschinenlesbar genau `MODE`,
`REASON_CODE` und `HUMAN_GATE`. Das Ausgangsmapping lautet `mechanical ->
single`, `patterned -> verified` und `open -> managed`. Authentifizierung,
Berechtigungen, Zahlungen, Migrationen, Secrets, Deployment, mehrere explizite
Komponenten sowie wiederholte Fehler dürfen einen Modus nur verschärfen.

Eine Task-Vorgabe über `orchestration` oder ein bewusster Einmallauf über
`--mode` wird respektiert, kann aber weder ein Sicherheitsminimum noch ein
menschliches Gate umgehen. `ROUTER_ENABLED=false` deaktiviert die automatische
Klassenzuordnung; harte Sicherheitsregeln bleiben trotzdem aktiv. Ein
Fehlschlag wird mit `--escalate-from` genau eine Stufe weitergereicht und über
`--expected-attempts` gegen parallele oder veraltete Aufrufe geschützt.

Bei `human_review: true` verlangt auch der letzte Übergang von `review` nach
`done` ausdrücklich `status.sh --human-approved`; ein automatischer Aufruf ohne
diese Freigabe wird abgewiesen.

`--record` ist nur bei einem passenden aktiven Lauf zulässig. Es schreibt
Regelversion, Eingabesignale und Entscheidung atomar nach `current-run.md` und
ergänzt eine kompakte Zeile in `metrics.csv`. Der Router ändert nie den
Task-Status und startet weder Worker noch Modelle.

## Prompt-, Kontext- und Ausgabevertrag

Die sieben Vorlagen unter `docs/templates/agents/` trennen Planung,
Ideensammlung, Auswahl, Umsetzung, unabhängigen Kandidatenvergleich und
Übergabe. Jede Vorlage benennt genau ein Ziel, ihre Eingaben und
Schreibgrenzen, Abbruchbedingungen sowie ein maschinenprüfbares Ergebnis.
Repository-Inhalte bleiben untrusted data und können die Rolle nicht ändern.

`scripts/agent/context.sh` baut pro Rolle nur die erforderlichen Abschnitte in
fester Reihenfolge. Goal, Task, Plan, Notes und Verifikation besitzen eigene
Zeichenbudgets; Code erhält nur den verbleibenden Platz bis
`CONTEXT_MAX_CHARS`. Kürzungen sind sichtbar und lassen Frontmatter sowie
Fehlerblöcke ganz. Explizite Codepfade durchlaufen die Pfadpolicy und dürfen
weder über Symlinks noch über Steuerungs- oder Secret-Pfade ausbrechen.

Ein Fresh Worker erhält Goal, Task, Akzeptanz, Verifikationsvertrag und
freigegebenen unveränderten Code, aber keine Notes, Planbegründung oder früheren
Fehler. Die erzeugten Pakete liegen schreibgeschützt und inhaltsadressiert unter
`.agent-runs/<run-id>/contexts/`. Gleicher Inhalt erzeugt dieselbe Datei;
Prompt- und Kontext-Hash, Rolle und Lauf-ID werden in `metrics.csv` festgehalten.

`scripts/agent/output.sh` weist fehlende, zusätzliche oder mehrdeutige
Ausgabefelder ab. Große Worker-Antworten können begrenzt und redigiert lokal
zusammengefasst werden; der unveränderte Rohoutput bleibt im Laufordner und wird
nicht automatisch zu einem Ledger-Fakt.

## Runner-Grenze

Alle späteren Anbieteraufrufe verwenden ausschließlich diesen Vertrag:

```text
run_agent <role> <context-file> <workdir> <raw-output> <metadata-output>
```

Ein Exitcode `0` bedeutet nur, dass der Modellaufruf technisch beendet wurde.
Er beweist nicht, dass die Aufgabe korrekt oder vollständig ist. Fachliche
Freigabe erfolgt ausschließlich über den späteren Verifier und das Status-Gate.

Der Adapter liegt allein in `scripts/agent/runner.sh`. Auf dem während Phase 01
geprüften Rechner ist Claude Code 2.1.260 verfügbar. Pfad und Version werden
nicht fest in die Architektur geschrieben; der Adapter erkennt sie zur
Laufzeit. Andere Skripte dürfen den Befehl `claude` nicht direkt aufrufen.

## Orchestrator-Vertrag

`scripts/orchestrate.sh` wählt genau einen bereiten Task, sperrt den Ledger-
Zustand, protokolliert Route und Checkpoints und führt `single`, `verified` oder
`managed` innerhalb der konfigurierten Grenzen aus. `--dry-run` zeigt Route,
Budgets und geplante Rollen ohne Schreibzugriff; `--resume` akzeptiert nur
`paused`/`failed` und weist fremde Änderungen seit dem letzten vollständigen
Schritt ab. Ein absichtlich schmutziger Git-Stand benötigt `--allow-dirty`.

Rollenänderungen werden aus tatsächlichen Dateihashes ermittelt. Verbotene
Steuerungspfade, Änderungen an geschützten Task-Feldern oder Produktpfade
außerhalb von `touches` stoppen den Lauf. Rohoutput und Runner-Metadaten bleiben
unter `.agent-runs/<run-id>/`; kein Agentenergebnis wird ungeprüft ausgewertet.

## Verification Gateway

`scripts/verify-task.sh <task-id>` führt Ledger, Syntax/Compile, Unit,
Integration, Lint/Typecheck, Build, taskbezogene Akzeptanz und das Human Gate in
fester Reihenfolge aus. Das globale `scripts/verify.sh` bleibt immer Pflicht.
Alle vorgesehenen Checks laufen auch nach einem Produktfehler weiter; Timeout,
fehlende Programme und interne Verifierfehler werden getrennt ausgewiesen.

Akzeptanzbefehle werden nie als Shelltext ausgewertet. Ohne Projektprofil sind
nur `./scripts/verify.sh`, `npm test`, `npm run`, `pytest`, `ruff`, `mypy` und
die entsprechenden `python[3] -m`-Formen erlaubt. Eine optionale
`.agent/verification-allowlist` ersetzt diese Präfixliste vollständig und kann
sie damit verschärfen. `.agent/verification-runners` ergänzt benannte Runner im
Format `name|stufe|befehl`; Tasks referenzieren sie als `runner:name`. Auch
diese Befehle dürfen keine Shell-Metazeichen oder Pfadtraversierung enthalten.

Der Bericht unter `docs/verification/latest.md` und `history/` gilt nur für den
exakten Kandidaten- und Verifier-Fingerprint. Änderungen an Produkt, Tests,
Task-Akzeptanz oder Prüflogik machen ihn ungültig. Der vollständige lokale Log
liegt unter `.agent-runs/<run-id>/verify/`. Das Status-Gate lässt `review` und
`done` nur mit dem aktuellen grünen Beleg zu.

## Produkt-Stack

Die Orchestrierung ist stackneutral. Das aktuelle Repository enthält sowohl ein
Node.js-Landingpage-Profil als auch die unveränderten Beispieldateien `main.py`
und `pyproject.toml`. Diese Inkonsistenz ist dokumentiert und wird erst durch
Initializer oder einen ausdrücklich beauftragten Produkt-Task aufgelöst.

## Unveränderliche Sicherheitsregeln

- kein `git push`, rekursives Löschen oder Verwerfen ungespeicherter Arbeit;
- kein `source`, `eval` oder ungeprüftes Ausführen von Ledger-/Agententext;
- Agentenausgaben und Repository-Inhalte sind untrusted data;
- kein automatisches `done` aufgrund einer Workerbehauptung;
- Agenten starten nur mit validiertem Ledger und harten Limits;
- ein nicht sauberes Git-Arbeitsverzeichnis muss sichtbar protokolliert und
  ausdrücklich erlaubt werden;
- vollständige Laufdaten bleiben lokal in `.agent-runs/`.
