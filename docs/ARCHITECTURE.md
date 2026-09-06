# Architektur- und Sicherheitsvertrag der Agenten-Orchestrierung

Rohfassung: mit F9 wird diese Datei die normative Beschreibung.

Kontrollflusstests unter `tests/` verwenden ausschließlich einen
Fake Runner; echte Aufrufe bleiben hinter dem Runner-Adapter gekapselt.

## Verbindliche Zuständigkeiten

| Information               | Verbindliche Quelle              | Darf schreiben                                           |
| ------------------------- | -------------------------------- | -------------------------------------------------------- |
| ursprüngliches Ziel       | `docs/state/goal.md`             | Nutzer/Initializer, später kontrolliert                  |
| Gesamtstrategie           | `docs/state/plan.md`             | Manager                                                  |
| Task-Inhalt/Zerlegung     | `docs/tasks/*.md`                | Manager                                                  |
| Task-Status               | `docs/tasks/*.md`                | ausschließlich Status-Gate                               |
| Task-Versuchszähler       | `docs/tasks/*.md`                | Router bei Eskalation, Orchestrator bei roter Prüfung    |
| Erkenntnisse und Fehler   | `docs/state/notes.md`            | Rollen im Schreibbereich, Orchestrator bei roter Prüfung |
| technische Entscheidungen | `docs/state/decisions.md`        | zuständiger Agent, in Alltagssprache                     |
| aktueller Lauf            | `.agent-runs/<run-id>/run.env`   | Orchestrator                                             |
| Laufmetrik                | `.agent-runs/metrics.csv`        | Orchestrator, eine Zeile pro Lauf                        |
| lokale Laufdetails        | `.agent-runs/<run-id>/metadata/` | Runner, Router und Orchestrator                          |
| Prüfurteil                | `docs/verification/`             | Verifier                                                 |
| Betriebsübergabe          | `docs/state/handoff.md`          | Finalizer/Sitzungsabschluss                              |

`docs/tasks/*.md` ist die einzige Aufgabenquelle; eine zweite Aufgabenquelle
daneben gibt es nicht. `scripts/validate-ledger.sh` prüft Task-Graph und
Prüfbelege und lässt höchstens einen Task `in_progress` zu. `scripts/agent/status.sh` ist der einzige
maschinelle Schreibweg für Statusübergänge und weist veraltete Schreibversuche
ab.

Zum Nachsehen einzelner Ledger-Werte dient
`scripts/agent/ledger.sh scalar|list|active-notes`.

## Rollenmatrix

Die Basispolicy in `scripts/agent/policy.sh` erzwingt Pfadgrenzen. Feldregeln,
insbesondere die Trennung zwischen Task-Inhalt und Task-Status, erzwingen
Ledger-Validator und Status-Gate.

Es gibt drei Modellrollen — `manager`, `worker` und `finalizer` — und drei
Rollen, die nur Skripte einnehmen.

| Rolle          | Zweck                                     | erlaubte Schreibbereiche                           |
| -------------- | ----------------------------------------- | -------------------------------------------------- |
| `manager`      | Plan pflegen, Tasks kuratieren, entscheiden | `docs/state/plan.md`, `docs/tasks/*.md`          |
| `worker`       | genau einen Task implementieren           | Produkt-/Testdateien außerhalb der Steuerungspfade |
| `finalizer`    | sicheren Stand übergeben (opt-in)         | `docs/state/handoff.md`, `docs/state/notes.md`     |
| `verifier`     | unabhängige Prüfberichte schreiben        | `docs/verification/`, `docs/state/notes.md`        |
| `status-gate`  | geprüfte Task-Statusübergänge             | `docs/tasks/*.md`                                  |
| `orchestrator` | Laufzustand und lokale Artefakte führen   | `.agent-runs/`                                     |

`fresh` ist keine eigene Rolle, sondern eine Variante des Workers: derselbe
Schreibbereich, derselbe Prompt, nur ein Kontext ohne Vorgeschichte.

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

`scripts/agent/ledger.sh` liest eine Datei in genau einem awk-Durchlauf und gibt
je Wert eine Zeile `schlüssel<TAB>wert` aus; Rumpfüberschriften der Ebene 1
erscheinen unter dem Schlüssel `#`. Der Leser kennt nur Einzelwerte und einfache
Listen, keine Feldnamen — welche Felder ein Task tragen muss, entscheidet allein
`scripts/validate-ledger.sh`. Unbekannte Felder werden nie als Befehle oder
Konfiguration interpretiert. Jede Änderung wird zuerst in einer temporären Datei
im selben Ordner validiert und erst danach atomar an ihren Zielpfad verschoben.

Ein Task darf nur mit einem passenden grünen Bericht unter
`docs/verification/<id>.md` auf `done` wechseln. Bei `human_review: true` führt
der direkte Weg von `in_progress` zuerst über `review`. Von `blocked` zurück auf
`todo` kommt eine Aufgabe nur menschlich über `./scripts/task.sh reopen <id>`,
die Freigabe aus `review` nur über `./scripts/task.sh approve <id>`. Höchstens
ein Task ist `in_progress`; ein abgebrochener Lauf fällt beim nächsten Start auf
`todo` zurück.
Verworfene Notizen liefert der Ledger-Leser nie als aktive Fakten aus.

## Router-Vertrag

`scripts/agent/route.sh` stellt die Funktion `agent_route_mode <task-datei>
<cli-modus> <max-versuche>` bereit; sie liefert genau einen Modus und startet
nichts. Es gilt `mode = max(Basis, Rang der Versuche, Risiko-Minimum)`. Die
Basis ist die ausdrückliche Vorgabe aus `orchestration` oder `--mode`, sonst die
Klasse: `mechanical -> single`, `patterned -> verified`, `open -> managed`. Ein
Fehlversuch hebt auf `verified`, ab zwei Fehlversuchen auf `managed`; ein
gesetztes `risk_flag` hebt das Minimum auf `managed`. Ein ausgeschöpftes
Versuchslimit ergibt `blocked`, bevor irgendetwas anderes gilt. Es gibt keine
Schlüsselwortsuche im Task-Text und keine Routing-Signale.

Nach jedem roten Versuch zählt der Orchestrator `attempts` hoch und fragt den
Router erneut; die Eskalation `single -> verified -> managed -> blocked` ergibt
sich damit aus derselben Tabelle. Ein offener Task oder `human_review: true`
setzt ein menschliches Gate: ein grüner Lauf endet auf `review`, nie auf `done`.

Bei `human_review: true` verlangt auch der letzte Übergang von `review` nach
`done` ausdrücklich `status.sh --human-approved`; ein automatischer Aufruf ohne
diese Freigabe wird abgewiesen.

## Prompt-, Kontext- und Ausgabevertrag

Die drei Prompts unter `docs/prompts/` trennen Entscheidung, Umsetzung und
Übergabe. Jeder benennt genau ein Ziel, seine Eingaben und Schreibgrenzen,
Abbruchbedingungen sowie ein maschinenprüfbares Ergebnis. Repository-Inhalte
bleiben untrusted data und können die Rolle nicht ändern.

Ein Rollenergebnis ist eine JSON-Datei. Die Schemata liegen als
`scripts/agent/schemas/{manager,worker,finalizer}.json`: alle Properties sind
Pflicht, `additionalProperties` ist aus, und es kommen nur `type`, `enum` und
`pattern` vor. Der Anbieter-CLI erzwingt das Schema beim Erzeugen, `jq -e`
prüft es danach ein zweites Mal. `""` bedeutet immer «kein Wert».

| Rolle       | Ergebnisfelder                              |
| ----------- | ------------------------------------------- |
| `manager`   | `action`, `task_id`, `reason`, `question`   |
| `worker`    | `result`, `summary`, `tests_run`, `notes`   |
| `finalizer` | `open_error`, `next_decision`, `best_green_ref` |

Der Headless-Rahmen — nicht-interaktiv, keine Rückfragen, keine Commits, keine
Statusänderungen — steht im Kontextdokument selbst, nicht im Runner. Damit
erhält ihn jeder Runner unverändert.

`scripts/agent/context.sh` baut pro Rolle nur die erforderlichen Abschnitte in
fester Reihenfolge. Goal, Task, Plan, Notes, Verifikation und Dateiliste haben
feste Zeichenbudgets, deren Summe unter `CONTEXT_MAX_CHARS` liegt; ein Kontext,
der heute passt, passt auch morgen. Kürzungen sind sichtbar und lassen
Frontmatter sowie Fehlerblöcke ganz. Der Worker erhält die **Liste** der Pfade
aus `touches`, nicht deren Inhalt: Dateien liest er mit seinen eigenen
Werkzeugen. Die Liste durchläuft die Pfadpolicy und nennt weder Secret- noch
Steuerungspfade.

Ein Fresh Worker erhält Goal, Task, Akzeptanz und die Dateiliste, aber keine
Notes, keine Planbegründung und keine früheren Fehler. Die erzeugten Pakete
liegen schreibgeschützt und inhaltsadressiert unter
`.agent-runs/<run-id>/contexts/`. Gleicher Inhalt erzeugt dieselbe Datei.
Prompt- und Kontext-Hash bleiben lokal nachvollziehbar; Zwischenereignisse
erzeugen keine halben CSV-Laufzeilen.

`scripts/agent/runner.sh validate_result <rolle> <datei>` weist mit `jq -e` jedes
Ergebnis ab, das nicht genau die Schemafelder trägt. Die unveränderte
Anbieterantwort bleibt im Laufordner und wird nie automatisch zu einem
Ledger-Fakt.

## Laufzustand und Metrik

Der Laufzustand ist unversioniert. `.agent-runs/<run-id>/run.env` führt Lauf-ID,
Task, Modus, Phase, Runde, Versuch, Fortschrittsfingerprint und Ergebnis;
`.agent-runs/<run-id>/metadata/<aufruf>.env` trägt pro Rollenaufruf die Zahlen
des Runners (Token- und Kostenwerte nur, soweit der Runner sie liefert; nichts
wird geschätzt). Am Laufende hängt der Orchestrator eine Zeile an
`.agent-runs/metrics.csv` an: `run_id,task_id,mode,attempt,outcome,started_at,
finished_at`. `outcome` ist einer aus `success`, `review`, `blocked`,
`ask_human`, `no_progress`, `verification_error`, `infrastructure_error`,
`cancelled` und `failed` (abgebrochen ohne eigene Begründung).

Ein Lauf ist zwischen zwei Aufrufen zustandslos: es gibt kein Fortsetzen und
keine Checkpoints. `scripts/orchestrate.sh --dry-run` zeigt nur die Route und
schreibt keine einzige Datei.

## Runner-Grenze

Alle späteren Anbieteraufrufe verwenden ausschließlich diesen Vertrag:

```text
run_agent <role> <context-file> <workdir> <result-output> <metadata-output>
```

Ein Exitcode `0` bedeutet nur, dass der Modellaufruf technisch beendet wurde.
Er beweist nicht, dass die Aufgabe korrekt oder vollständig ist. Fachliche
Freigabe erfolgt ausschließlich über den späteren Verifier und das Status-Gate.

Der Adapter liegt allein in `scripts/agent/runner.sh`. Er kennt zwei Runner,
`claude` und `codex`; welcher läuft, steht als `AGENT_RUNNER` in
`.agent/config.env`. Pfad und Version werden nicht fest in die Architektur
geschrieben; der Adapter erkennt sie zur Laufzeit, `scripts/doctor.sh` prüft
sie vor dem Lauf. Andere Skripte dürfen `claude` oder `codex` nicht direkt
aufrufen.

Beide Runner liefern denselben Ergebnisvertrag: das Ergebnisobjekt der Rolle
als `result.json` und dieselben Metadatenfelder. Sie unterscheiden sich in der
Sicherheitshülle, und dieser Unterschied ist wesentlich.

**Claude** läuft im dokumentierten Headless-Betrieb von Claude Code: `claude -p`
mit `--output-format json` und dem JSON-Schema der Rolle
(`scripts/agent/schemas/<rolle>.json`), `--no-session-persistence`,
`--max-turns`, optional `--max-budget-usd` und `--model`, sowie
`--permission-prompts none`, sobald das CLI die Option kennt. Die Grenze ist
hier eine Rechtegrenze im Prozess, keine Sandbox des Betriebssystems: Der
Worker bekommt `--allowedTools` mit den Lesewerkzeugen plus `Edit`, `Write`
und `Bash`; Manager und Finalizer laufen mit `--restricted --tools
Read,Glob,Grep,Edit,Write` und haben damit gar kein Werkzeug, das Befehle
ausführt. Der Lauf bekommt eine eigene Einstellungsdatei mit Deny-Liste,
`scripts/bash-guard.sh` als `PreToolUse`-Hook und `claudeMdExcludes`; die
Einstellungen der interaktiven Sitzung gelten dort ausdrücklich nicht.
Auto-Memory bleibt aus. Modell, Tokens und Kosten stammen aus der Antwort.

**Codex** bringt seine Hülle selbst mit: `codex exec --json --output-schema
<rollenschema> --output-last-message <datei> -C <workdir>
--sandbox workspace-write --color never -c project_doc_max_bytes=0`,
Prompt über stdin.
Schreibzugriffe begrenzt die Sandbox des CLI auf den Arbeitsbaum, das Netz
bleibt aus; eine Werkzeugauswahl pro Rolle gibt es dort nicht. Tokens kommen
aus `turn.completed.usage`, ein `turn.failed` wird zum Abbruchgrund, Kosten
meldet codex nicht und bleiben `unknown`. Fehlt die Datei aus
`--output-last-message`, gilt die Antwort als leer.

Den nicht-interaktiven Rahmen trägt in beiden Fällen das Kontextdokument
selbst, damit ihn jeder Runner unverändert weiterreicht. Die vollständige
Anbieterantwort bleibt als `<ergebnis>.provider.json` im Laufordner.

Der Adapter liest seine Grenzen aus `.agent/config.env`, nicht aus der
Umgebung — ein Lauf soll ohne gesetzte Variablen reproduzierbar sein:

| Schlüssel               | Wirkung                                             | Standard  |
| ----------------------- | --------------------------------------------------- | --------- |
| `AGENT_RUNNER`          | `claude` oder `codex`                               | `claude`  |
| `AGENT_MODEL`           | Modellname; `default` überlässt die Wahl dem CLI    | `default` |
| `AGENT_TIMEOUT_SECONDS` | Zeitlimit eines einzelnen Modellaufrufs in Sekunden | `900`     |
| `AGENT_MAX_TURNS`       | Obergrenze agentischer Runden eines Modellaufrufs   | `60`      |

Zwei Umgebungsvariablen bleiben Sache des Aufrufers, weil sie keine
Projekteigenschaft sind:

| Variable               | Wirkung                                                                 | Standard |
| ---------------------- | ----------------------------------------------------------------------- | -------- |
| `AGENT_MAX_BUDGET_USD` | Kostenobergrenze eines Modellaufrufs (`--max-budget-usd`); leer = keine | leer     |
| `ORCHESTRATOR_RUNNER`  | Pfad zu einem alternativen Runner, z.B. `tests/fake-runner.sh`          | Adapter  |

`scripts/bash-guard.sh` blockt in jedem Fall Hochladen, rekursives Löschen und
das Verwerfen ungespeicherter Arbeit. Unter `AGENT_HEADLESS=1` — das setzt der
Runner — kommen `git commit|merge|rebase|stash|worktree`, `git branch -D`,
`pip install` und `npm publish` dazu: Historie und Zweige führt der
Orchestrator, nicht der Agent.

`scripts/doctor.sh` prüft vor dem ersten Lauf Werkzeuge, Konfiguration, den
gewählten Runner und den Repository-Zustand. Ein kaputt installiertes CLI ist
dort ein Befund mit Text, kein Absturz.

Die Skripte brauchen außer Bash nur `git`, `awk`, `sed`, `shasum`, `jq` und
`perl` (für Zeitlimits, Laufdauern und JSON). Unter macOS, Linux und Git Bash
sind sie vorhanden. `git` ist Pflicht, nicht Kür: Manifeste und Snapshot
beziehen Dateiliste und Hashes von Git.

## Orchestrator-Vertrag

`scripts/orchestrate.sh` sperrt den Lauf, setzt einen Task aus einem
abgebrochenen Vorlauf sichtbar auf `todo` zurück, wählt genau einen bereiten
Task und führt eine Versuchsschleife innerhalb der konfigurierten Grenzen aus.
Der vom Router gewählte Modus bestimmt nur die Startstufe: in `managed` läuft
vor jeder Runde der Manager, sonst geht es direkt zum Worker. Jede rote Prüfung
zählt einen Versuch und hebt den Modus um genau eine Stufe. Ein technischer
Fehler des Prüfwegs (`failure_kind: verifier`) zählt keinen Versuch. Der
bewachte Rollenaufruf selbst steht in `scripts/agent/rolecall.sh`.

Meldet der Manager `ask_human`, schreibt der Orchestrator die Frage als
Abschnitt `# Offene Frage` in den Task, setzt ihn auf `blocked` mit
`blocked_reason: ASK_HUMAN` und verbraucht keinen Versuch. Der Mensch antwortet
im Task und öffnet ihn mit `./scripts/task.sh reopen <id>` wieder. `--dry-run` zeigt Route,
Budgets und geplante Rollen ohne jeden Schreibzugriff. Ein Lauf endet nie mit
einem Task in `in_progress`: der EXIT-Trap gibt ihn frei. Ein absichtlich
schmutziger Git-Stand benötigt `--allow-dirty`; der Schmutz-Check übergeht
`docs/tasks`, `docs/state` und `docs/verification`, weil der Orchestrator diese
Pfade selbst schreibt.

Rollenänderungen werden aus tatsächlichen Dateihashes ermittelt. Verbotene
Steuerungspfade, Änderungen an geschützten Task-Feldern oder Produktpfade
außerhalb von `touches` werden auf das Vorher-Manifest zurückgesetzt und
stoppen den Lauf. Rohoutput und Runner-Metadaten bleiben
unter `.agent-runs/<run-id>/`; kein Agentenergebnis wird ungeprüft ausgewertet.

## Manifeste und Snapshot

Ein Manifest ist die sortierte Liste `<feld>  <pfad>` eines Projektstands.
Dateiliste und Hashes kommen von Git (`git ls-files`, `git hash-object -w`), nicht
von `find` und `shasum`: das ist eine Prozessgruppe statt eines Prozesses pro
Datei, und `.gitignore` gilt ohne eigene Ausschlussliste. Das Kit setzt deshalb
ein Git-Repository voraus.

| Feld             | Bedeutung                                                           |
| ---------------- | ------------------------------------------------------------------- |
| `<hash>`         | Blob-Hash des Inhalts; der Inhalt liegt damit im Git-Objektspeicher |
| `exec:<hash>`    | dasselbe mit gesetztem Ausführungsbit                               |
| `symlink:<hash>` | Hash des Linkziels, nie des Inhalts dahinter                        |
| `missing`        | im Index, aber nicht im Arbeitsbaum (gelöscht)                      |
| `ignored`        | von `.gitignore` erfasst: nur der Name, der Inhalt wird nie gelesen |

Ein vollständig ignorierter Ordner wie `node_modules/` zählt als ein Eintrag.
Änderungen darin bleiben unsichtbar, ein **neu** angelegter ignorierter Pfad wie
`.env` wird über seinen Namen sichtbar. `.git/config`, `.git/info/exclude` und
`.git/hooks/*` stehen im Repo-Manifest, weil sie das Verhalten des Projekts
ändern; kein Agent darf sie schreiben.

Weil `git hash-object -w` die Inhalte in den Objektspeicher schreibt, ist jedes
Manifest zugleich ein Snapshot. `agent_snapshot_restore` setzt daraus einzelne
Pfade zurück: bekannte Inhalte kommen aus dem Objektspeicher, Pfade, die das
Manifest nicht kennt, wandern in die Quarantäne unter `.agent-runs/<run-id>/`
statt gelöscht zu werden. Der Snapshot hält den Arbeitsbaum **zum Laufstart**
fest, nicht `HEAD`: unversionierte Arbeit des Besitzers in derselben Datei
überlebt ein Zurücksetzen.

Das Vorher-Manifest eines Rollenaufrufs liegt bis zum Nachher-Manifest außerhalb
des Arbeitsbaums. Unter `.agent-runs/` könnte der laufende Agent es passend zu
seinen eigenen Änderungen umschreiben.

## Fresh- und Finalizer-Vertrag

Fresh ist kein eigener Modus, sondern eine Versuchsvariante innerhalb von
`managed`. Sie greift, wenn der Manager sie verlangt, und immer beim letzten
erlaubten Versuch. Der Orchestrator setzt dann alle seit dem Laufstart
veränderten Pfade innerhalb von `touches` über `agent_snapshot_restore` auf den
Snapshot des Laufstarts zurück; Pfade, die es beim Laufstart noch nicht gab,
wandern nach `.agent-runs/<run-id>/quarantine/` statt gelöscht zu werden. Die
Der Worker läuft dann in seiner Fresh-Variante: er erhält Goal, Task und die
Dateiliste, aber weder Notizen noch den vorherigen Prüfbericht.

Der Snapshot des Laufstarts liegt außerhalb des Arbeitsbaums, damit ein Agent
ihn nicht passend zu seinen eigenen Änderungen umschreiben kann.

Provider-/Timeoutfehler besitzen mit `MAX_INFRA_RETRIES` und
`RETRY_BACKOFF_SECONDS` ein separates kleines Retry-Budget. Leere oder
abgeschnittene Ausgaben werden nicht als Infrastruktur-Retry umgedeutet und nie
in das Ledger übernommen.

Der Finalizer ist abwählbar und im Auslieferungsstand aus (`FINALIZER=off` in
`.agent/config.env`); erst `FINALIZER=llm` erlaubt den zusätzlichen
Modellaufruf bei einer Blockade. Er läuft wie jede andere Rolle im Arbeitsbaum
und darf ausschließlich `docs/state/handoff.md` und `docs/state/notes.md`
ändern; Manifestvergleich und Policy setzen alles andere zurück. Taskstatus und
Laufabschluss bleiben beim Orchestrator und Status-Gate.

Unabhängig davon schreibt der Orchestrator bei **jedem** Laufende den Abschnitt
«Laufbeleg» in `docs/state/handoff.md` — Run-ID, Modus, Ergebnis, Task,
Verifierstatus und letzter grüner Stand. Der Beleg ist deterministisch und
braucht kein Modell.

## Verification Gateway

`scripts/verify-task.sh <task-id>` führt Ledger, Syntax/Compile, Unit,
Integration, Lint/Typecheck, Build, taskbezogene Akzeptanz und das Human Gate in
fester Reihenfolge aus. Das globale `scripts/verify.sh` bleibt immer Pflicht.
Alle vorgesehenen Checks laufen auch nach einem Produktfehler weiter; Timeout,
fehlende Programme und interne Verifierfehler werden getrennt ausgewiesen.

Akzeptanzbefehle werden nie als Shelltext ausgewertet. Ohne eigene Allowlist sind
nur `./scripts/verify.sh`, `npm test`, `npm run`, `pytest`, `ruff`, `mypy` und
die entsprechenden `python[3] -m`-Formen erlaubt. Eine optionale
`.agent/verification-allowlist` ersetzt diese Präfixliste vollständig und kann
sie damit verschärfen. `.agent/verification-runners` ergänzt benannte Runner im
Format `name|stufe|befehl`; Tasks referenzieren sie als `runner:name`. Auch
diese Befehle dürfen keine Shell-Metazeichen oder Pfadtraversierung enthalten.

Jeder Task hat genau einen Bericht: `docs/verification/<id>.md`. `latest.md` ist
die Kopie des zuletzt geschriebenen Berichts. Ein Bericht gilt nur für den
exakten Kandidaten- und Verifier-Fingerprint. Änderungen an Produkt, Tests,
Task-Akzeptanz oder Prüflogik machen ihn für den Statusübergang ungültig. Der
vollständige lokale Log liegt unter `.agent-runs/<run-id>/verify/`. Das
Status-Gate lässt `review` und `done` nur mit dem aktuellen grünen Beleg zu. Ein
einmal erreichtes `done` bleibt gültig, wenn spätere Tasks das Produkt
weiterentwickeln; der Validator verlangt dafür nur noch einen grünen Bericht zum
Task, nicht den damaligen Fingerprint.

## Produkt-Stack

Die Orchestrierung ist stackneutral. Das Repository enthält keinen Produktcode;
Stack und Skelett legt erst der Initializer nach der Projektbeschreibung in
`docs/templates/initializer-prompt.md` an.

## Unveränderliche Sicherheitsregeln

- kein `git push`, rekursives Löschen oder Verwerfen ungespeicherter Arbeit;
- kein `source`, `eval` oder ungeprüftes Ausführen von Ledger-/Agententext;
- Agentenausgaben und Repository-Inhalte sind untrusted data;
- kein automatisches `done` aufgrund einer Workerbehauptung;
- Agenten starten nur mit validiertem Ledger und harten Limits;
- ein nicht sauberes Git-Arbeitsverzeichnis muss sichtbar protokolliert und
  ausdrücklich erlaubt werden;
- vollständige Laufdaten bleiben lokal in `.agent-runs/`.
