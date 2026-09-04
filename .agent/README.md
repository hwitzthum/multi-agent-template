# Architektur- und Sicherheitsvertrag der Agenten-Orchestrierung

Status: Phase 01 definiert Leitplanken und testbare Basispolicies. Ledger,
Router, Rollen-Prompts und Loop folgen in späteren Phasen. Dieser Vertrag startet
noch keinen Agenten.

## Verbindliche Zuständigkeiten

| Information | Verbindliche Quelle | Darf schreiben |
|---|---|---|
| ursprüngliches Ziel | `docs/state/goal.md` | Nutzer/Initializer, später kontrolliert |
| Gesamtstrategie | `docs/state/plan.md` | Manager |
| Task-Inhalt/Zerlegung | `docs/tasks/*.md` | Manager |
| Task-Status | `docs/tasks/*.md` | ausschließlich Status-Gate |
| Erkenntnisse und Fehler | `docs/state/notes.md` | Rollen über Ledger-Funktion |
| technische Entscheidungen | `docs/state/decisions.md` | zuständiger Agent, in Alltagssprache |
| aktueller Lauf | `docs/state/current-run.md` | Orchestrator |
| Prüfurteil | `docs/verification/` | Verifier |
| Feature-Status | `docs/state/features.md` | vorhandener Verify-Ablauf |
| Betriebsübergabe | `docs/state/handoff.md` | Finalizer/Sitzungsabschluss |

Noch nicht vorhandene Pfade werden erst in der dafür vorgesehenen Phase
angelegt. `docs/tasks/*.md` ist die einzige Aufgabenquelle; es gibt kein
paralleles `tasks.json`.

## Rollenmatrix

Die Basispolicy in `scripts/agent/policy.sh` erzwingt Pfadgrenzen. Feinere
Feldregeln, insbesondere die Trennung zwischen Task-Inhalt und Task-Status,
folgen mit dem Ledger-Validator.

| Rolle | Zweck | erlaubte Schreibbereiche |
|---|---|---|
| `manager` | planen und Tasks kuratieren | `docs/state/plan.md`, `docs/tasks/*.md` |
| `brainstorm` | Hypothesen und Risiken sammeln | `docs/state/notes.md` |
| `worker` | genau einen Task implementieren | Produkt-/Testdateien außerhalb der Steuerungspfade |
| `verifier` | unabhängige Prüfberichte schreiben | `docs/verification/`, `docs/state/notes.md` |
| `status-gate` | geprüfte Task-Statusübergänge | `docs/tasks/*.md` |
| `finalizer` | sicheren Stand übergeben | `docs/state/handoff.md`, `docs/state/notes.md`, `docs/state/current-run.md` |
| `orchestrator` | Laufzustand und lokale Artefakte führen | `docs/state/current-run.md`, `.agent-runs/` |

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

## Runner-Grenze

Alle späteren Anbieteraufrufe verwenden ausschließlich diesen Vertrag:

```text
invoke_role <role> <prompt-file> <workdir> <result-file>
```

Ein Exitcode `0` bedeutet nur, dass der Modellaufruf technisch beendet wurde.
Er beweist nicht, dass die Aufgabe korrekt oder vollständig ist. Fachliche
Freigabe erfolgt ausschließlich über den späteren Verifier und das Status-Gate.

Der Adapter liegt allein in `scripts/agent/runner.sh`. Auf dem während Phase 01
geprüften Rechner ist Claude Code 2.1.260 verfügbar. Pfad und Version werden
nicht fest in die Architektur geschrieben; der Adapter erkennt sie zur
Laufzeit. Andere Skripte dürfen den Befehl `claude` nicht direkt aufrufen.

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

