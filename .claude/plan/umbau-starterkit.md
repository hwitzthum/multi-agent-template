# Umbauplan: Prompt-und-Script-Starterkit

Stand dieser Datei: 2026-09-06 · Planfassung 1 · Fortschritt wird hier gepflegt.

## Fortschrittsübersicht

Statuswerte: `offen` → `in Arbeit` → `umgesetzt` (Code fertig, Tests grün) →
`geprüft` (Abnahmekriterien belegt) → `gemergt` (Freigabe des Besitzers, in `main`).

| Nr  | Feature                                  | Branch                            | Status    | Tests | Gemergt am |
| --- | ---------------------------------------- | --------------------------------- | --------- | ----- | ---------- |
| F0  | Verhaltensbenannte Testsuite mit Runner  | `test/behaviour-suite`            | gemergt   | 417   | 2026-09-06 |
| F1  | Ballast entfernen                        | `chore/remove-ballast`            | gemergt   | 400   | 2026-09-06 |
| F2  | Git-basierte Manifeste und Snapshot      | `perf/git-manifests`              | gemergt   | 424   | 2026-09-06 |
| F3  | Turnier streichen, Fresh-Versuch, Router | `refactor/drop-tournament`        | gemergt   | 402   | 2026-09-06 |
| F4  | Laufzustand unversioniert                | `refactor/run-state-unversioned`  | gemergt   | 395   | 2026-09-06 |
| F5  | Ledger-Schema und Task-Kommandos         | `refactor/ledger-schema`          | gemergt   | 449   | 2026-09-06 |
| F6  | JSON-Ergebnisse, drei Rollen, Eskalation | `refactor/json-results-and-roles` | gemergt   | 547   | 2026-09-06 |
| F7  | Zwei Runner: Claude und Codex            | `feat/codex-runner`               | gemergt   | 666   | 2026-09-06 |
| F8  | Prüftor verschlanken                     | `refactor/verify-gate`            | gemergt   | 677   | 2026-09-06 |
| F9  | Dokumentation                            | `docs/architecture`               | geprüft   | 693   | –          |

Reihenfolge ist verbindlich (jedes Feature setzt auf dem vorigen auf). Vor jedem
Merge: Testsuite grün, Abnahmekriterien belegt, ausdrückliche Freigabe des Besitzers.

## Fortschrittsprotokoll

Neueste Einträge oben. Format: `Datum · Feature · was passiert ist · Beleg`.

- 2026-09-06 · F8 · Nach `main` gemergt (`3513184`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (677 Zusicherungen in 28 Dateien)`
- 2026-09-06 · F8 · Prüftor auf einen Ablauf verschlankt: Stufen-Taxonomie,
  benannte Runner, Syntax-Stufe und `touches`-Prüfung entfernt, Allowlist
  generisch und als kommentiertes Beispiel ausgeliefert ·
  `./scripts/verify.sh` → `tests: GREEN (677 Zusicherungen in 28 Dateien)`;
  `wc -l scripts/verify-task.sh` → `198` (vorher 384)
- 2026-09-06 · F7 · Nach `main` gemergt (`f3cf2f6`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (666 Zusicherungen in 28 Dateien)`
- 2026-09-06 · F7 · Zwei Runner hinter einem Vertrag: Claude-Adapter mit
  rollenabhängigen Werkzeugen und eigener Einstellungsdatei (Deny-Liste,
  `bash-guard`-Hook, `claudeMdExcludes`), Codex-Adapter über `codex exec --json`
  mit Sandbox, Runnerwahl und Aufrufgrenzen aus `.agent/config.env` statt aus
  der Umgebung, `scripts/doctor.sh` als Umgebungsprüfung, Headless-Zusätze im
  `bash-guard`, Stack-Allowlist aus `.claude/settings.json` entfernt ·
  `./scripts/verify.sh` → `tests: GREEN (666 Zusicherungen in 28 Dateien)`;
  echter Claude-Lauf (Manager und Worker, haiku): `output_status=ok`,
  schemagültiges `result.json`, `git stash` vom Headless-Guard blockiert;
  echter `doctor.sh` gegen die defekte lokale Codex-Installation:
  `BEFUND   codex ist installiert, antwortet aber nicht auf --version … ENOENT`,
  Exit 1
- 2026-09-06 · F6 · Nach `main` gemergt (`58bddd8`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (547 Zusicherungen in 26 Dateien)`
- 2026-09-06 · F6 · Rollenergebnis ist JSON gegen ein Schema, sechs Prompt-Rollen
  auf `manager`/`worker`/`finalizer` zusammengelegt, ein Modus-Pfad mit
  Eskalation statt drei, `ask_human` als Frage im Task, deterministischer
  Laufbeleg bei jedem Laufende, Finalizer abwählbar ·
  `./scripts/verify.sh` → `tests: GREEN (547 Zusicherungen in 26 Dateien)`;
  `wc -l scripts/orchestrate.sh` → `399`
- 2026-09-06 · F5 · Nach `main` gemergt (`82460fe`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (449 Zusicherungen in 24 Dateien)`
- 2026-09-06 · F5 · Frontmatter auf zwölf Felder gekürzt, Parser auf einen
  awk-Durchlauf gestellt (60 Tasks 9,2 s → 0,3 s), Prüfbeleg je Task unter
  `docs/verification/<id>.md`, `scripts/task.sh reopen|approve` als einzige
  menschliche Übergänge ·
  `./scripts/verify.sh` → `tests: GREEN (449 Zusicherungen in 24 Dateien)`
- 2026-09-06 · F4 · Nach `main` gemergt (`6ac7fd2`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (395 Zusicherungen in 23 Dateien)`
- 2026-09-06 · F4 · Laufzustand nach `.agent-runs/<run>/run.env` verlegt,
  Metrik-Subsystem, `--resume` und Checkpoints entfernt, EXIT-Trap gibt
  `in_progress` frei, Stale-Lauf wird beim Start übernommen ·
  `./scripts/verify.sh` → `tests: GREEN (395 Zusicherungen in 23 Dateien)`
- 2026-09-06 · F3 · Nach `main` gemergt (`b13c527`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (402 Zusicherungen in 25 Dateien)`
- 2026-09-06 · F3 · Turnier, Reviewer und `managed-fresh` entfernt, Router als
  Funktion `agent_route_mode`, Fresh als Versuchsvariante mit
  Snapshot-Rücksetzung, Out-of-Scope-Änderungen werden zurückgesetzt ·
  `./scripts/verify.sh` → `tests: GREEN (402 Zusicherungen in 25 Dateien)`
- 2026-09-06 · F2 · Nach `main` gemergt (`ee358cb`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (424 Zusicherungen in 26 Dateien)`
- 2026-09-06 · F2 · Manifeste und Snapshot auf Git umgestellt, Vorher-Manifeste
  aus dem Arbeitsbaum genommen, Task-Lookup auf den Dateinamen gestellt ·
  `./scripts/verify.sh` → `tests: GREEN (424 Zusicherungen in 26 Dateien)`
- 2026-09-06 · F1 · Nach `main` gemergt (`4c8f189`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (400 Zusicherungen in 25 Dateien)`
- 2026-09-06 · F1 · Kurs-, Landingpage- und Ursprungsprojekt-Ballast entfernt,
  `.agent/README.md` → `docs/ARCHITECTURE.md`, Doku-Lint nachgezogen ·
  `./scripts/verify.sh` → `tests: GREEN (400 Zusicherungen in 25 Dateien)`
- 2026-09-06 · F0 · Nach `main` gemergt (`e5cbd52`), Suite auf `main` grün ·
  `./scripts/verify.sh` → `tests: GREEN (417 Zusicherungen in 27 Dateien)`
- 2026-09-06 · F0 · Suite nach Verhalten in vier Stufen zerlegt, gemeinsame
  Helfer und Fixtures gebaut, `tests/run.sh` und `scripts/verify.sh` verdrahtet ·
  `./scripts/verify.sh` → `tests: GREEN (417 Zusicherungen in 27 Dateien)`
- 2026-09-06 · Plan · Befund abgeschlossen, Entscheidungen des Besitzers eingeholt,
  Plan angelegt · diese Datei

---

## Kontext

Das Repository ist ein Orchestrierungs-Gerüst aus Bash-Skripten und Markdown-Prompts,
das `claude -p` headless in Rollen aufruft und den Projektzustand in Dateien hält
(Tasks, Plan, Notizen, Prüfbelege, Handoff). Es entstand aus einem Kursprojekt
(«Landingpage-Fabrik», Zielgruppe ohne Terminal-Erfahrung).

Neues Ziel: ein Starterkit für beliebige Themen, betrieben von einem einzelnen
technischen Nutzer.

Entscheidungen des Besitzers (2026-09-06):

1. Bash behalten, aber verschlanken.
2. Landingpage-Profil und Kursmaterial entfernen.
3. Claude Code und Codex als Runner.
4. Ballast selbst finden und entfernen.
5. Kandidaten-Turnier streichen; Ersatz ist ein Fresh-Versuch ohne Vorgeschichte.
6. Laufzustand und Metriken unversioniert unter `.agent-runs/`.
7. `jq` wird Pflichtabhängigkeit.
8. Worker dürfen Bash; Sperre durch `bash-guard.sh` und Deny-Liste; Schreibumfang
   wird nach dem Lauf geprüft und zurückgesetzt.

Umgebung: bash 3.2 (kein `mapfile`, keine assoziativen Arrays), git 2.55, jq 1.8,
perl 5 Core, claude 2.1.263, codex 0.130.0 mit defekter npm-Installation (natives
Binary fehlt; Codex-Adapter wird hier nur gegen Fixtures getestet).

## Befund (Kurzfassung)

### Tragfähig, bleibt

- Dateien als einzige Wahrheit; deterministisches Prüftor mit Fingerprints;
  Runner als einzige Anbietergrenze mit Schema-JSON; Schreibrechte pro Rolle über
  Manifeste; Kontextpaket mit Secret-Redaktion; nie `source`/`eval` auf Repo-Inhalte;
  atomare Schreibvorgänge; Sperren mit Stale-PID-Erkennung; Human-Review-Gate;
  `bash-guard.sh`, `commit-gate.sh`.

### Defekte (gemessen auf Scratch-Kopie mit 60 Tasks)

| Messung                                          | Ist                       | Ursache                                               |
| ------------------------------------------------ | ------------------------- | ----------------------------------------------------- |
| `validate-ledger.sh`                             | 11 s                      | ~40 Prozesse pro Task                                 |
| `next-tasks.sh`                                  | 48 s                      | Lookup O(n²) mit Prozessstarts                        |
| `orchestrate.sh --dry-run`                       | 92 s                      | Validator mehrfach + Manifest                         |
| Repo-Manifest mit 2000 Dateien in `node_modules` | 23 s, 3× pro Rollenaufruf | `find` ignoriert `.gitignore`, ein `shasum` pro Datei |
| dasselbe via `git ls-files` + `git hash-object`  | 0,02 s                    | eine Prozessgruppe                                    |

- `--resume` ist tot: verlangt byteidentisches Repo inkl. `docs/tasks`, die Antwort
  auf `request_human` macht Resume unmöglich.
- Eskalation nur in `verified` erreichbar; `single` fällt auf `todo`, meldet `blocked`.
- Infrastruktur-Retry nur im Kandidatenpfad.
- Out-of-Scope-Änderungen bleiben nach Abbruch liegen.
- Worker-Rechte stackgebunden (`Bash(npm run *)`), Rest wird headless still verweigert.
- Drei Formate für ein Ergebnis (JSON → KEY=VALUE/YAML → awk); Prompt-Lücken.
- `.agent-runs/` vom Worker beschreibbar: Vorher-Manifeste manipulierbar;
  `.git/hooks`, `.git/config`, `.git/info/exclude` in keinem Manifest.
- Feld-Whitelist im Ledger ohne Nutzen; `plan_is_placeholder` hängt an einem
  deutschen Platzhaltersatz; doppelte `touches`-Prüfung über `git status`.

### Ballast

- Doku: KURSANLEITUNG, `docs/profil/**`, `docs/briefs/`, `features.md`,
  `README.md:52-455`, `.agent/README.md` (wird ARCHITECTURE.md), `tasks.json`-Verbote.
- Skripte: `migrate-tasks`, `autoformat` (+Hook), `archive-notes`, `agent-metrics`,
  `metrics.sh`, `candidates.sh`, `output.sh`, Resume/Checkpoints,
  Finalizer-Arbeitskopie, Router-Heuristik, Stufen-Taxonomie im Prüftor.
- Felder: `features`, `fresh_perspective`, `last_verification`, `max_attempts`,
  `route_*`, `PROMPT_VERSION`, `diff_lines`, `new_defects`. Rollen 7 → 3.
- Tests: Phasen-Benennung, 9 Helfer-Kopien in zwei Generationen, 5 Fixture-Kopien,
  82 Doku-Greps, ein Test braucht echtes `claude`.

## Zielentwurf

### Grundsätze

1. Abhängigkeiten: bash 3.2+, git, jq, perl-Core (portabler Timeout).
   `scripts/doctor.sh` prüft sie und den Runner.
2. Git liefert Dateilisten und Hashes; `.gitignore` gilt für Manifeste.
3. Rollenergebnis = JSON-Datei, vom CLI schema-validiert, mit `jq -e` geprüft.
4. Versioniert nur fachliche Belege: Tasks, Plan, Notizen, Entscheidungen,
   Prüfberichte, Handoff. Laufzustand, Rohantworten, Metriken unter `.agent-runs/`.
5. Ein Lauf ist zwischen Aufrufen zustandslos; das Ledger trägt alles.
6. Bash-3.2-kompatibel: awk gibt `key<TAB>value` aus, gelesen mit `while read`.

### Ledger-Schema

Task-Frontmatter: `id title status class orchestration depends_on touches risk_flags
attempts human_review acceptance blocked_reason`. Dateiname `<id>.md` (Validator
erzwingt). `class ∈ mechanical|patterned|open`, `orchestration ∈ auto|single|
verified|managed`, `risk_flags ⊆ {high-risk, cross-component, repeated-failure}`,
`status ∈ todo|in_progress|review|done|blocked`. Body: `# Kontext`, `# Umfang`,
`# Nicht Teil dieser Aufgabe`, `# Akzeptanzkriterien`; optional `# Offene Frage`.

Prüfberichte: `docs/verification/<id>.md` pro Task plus `latest.md`; `history/`
entfällt, Logs unter `.agent-runs/`. Invariante «höchstens ein Task `in_progress`»
im Validator.

### Rollen (3)

| Rolle                                | Aufgabe                                                                                                         | Schreibbereich                                                                                                         | Ergebnis (alle Felder required, `""` = keins)                             |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `manager`                            | Plan pflegen, Tasks anlegen/schärfen (Risiken, Prüfideen im Body), pro Runde eine Aktion                        | `docs/state/plan.md`, `docs/tasks/*.md` (Steuerfelder `status/attempts/blocked_reason` geschützt; neue Tasks `todo/0`) | `{action: dispatch\|done\|blocked\|ask_human, task_id, reason, question}` |
| `worker`                             | einen Task umsetzen; Variante `fresh`: Kontext ohne Notizen/Vorbericht, Arbeitsbaum auf Laufstart zurückgesetzt | Pfade unter `touches`; nie Ledger, `scripts/`, `.claude/`, `.agent/`, `.git/`, `**/.gitignore`                         | `{result: implemented\|partial\|blocked, summary, tests_run, notes}`      |
| `finalizer` (opt-in `FINALIZER=llm`) | Erzähl-Handoff bei `blocked`                                                                                    | `docs/state/handoff.md`, `docs/state/notes.md`                                                                         | `{open_error, next_decision, best_green_ref}`                             |

Der Orchestrator schreibt bei jedem Laufende deterministisch den Abschnitt
«Laufbeleg» in `handoff.md`. Der Headless-Rahmen steht im Kontextdokument, damit
beide Runner ihn erhalten.

### Modi, Eskalation, Rückfragen

- Router (`lib/route.sh`): `mode = max(base(class), rank(attempts))`, Override durch
  `orchestration` oder `--mode`; `risk_flags` heben das Minimum auf `managed`.
- Versuchsschleife in einem Aufruf: Worker → Prüfung; rot ⇒ `attempts+1`, Modus neu
  (single → verified → managed → blocked) bis grün, `blocked`, `ask_human` oder
  `MAX_TASK_ATTEMPTS`. `failure_kind=verifier` zählt keinen Versuch. Letzter Versuch
  in `managed` läuft `fresh`.
- `managed`: Manager-Loop mit `MAX_GLOBAL_ITERATIONS`, Fortschritts-Fingerprint,
  `MAX_NO_PROGRESS`.
- `ask_human`: Frage unter `# Offene Frage` im Task, Status `blocked`,
  `blocked_reason: ASK_HUMAN`, kein Versuch verbraucht. Antwort im Task, dann
  `scripts/task.sh reopen N` (`blocked→todo`, nur menschlich), dann
  `orchestrate.sh --task N`. `scripts/task.sh approve N` für `review→done`.
- EXIT-Trap lässt nie `in_progress` zurück; Stale-Run ohne lebende Sperre wird beim
  Start mit Notiz auf `todo` gesetzt.
- Infrastruktur-Retry gilt für jeden Rollenaufruf.

### Manifeste, Snapshot, Rücksetzen

- Liste: `git ls-files -z -co --exclude-per-directory=.gitignore` plus `.git/hooks/*`,
  `.git/config`, `.git/info/exclude`; Symlinks als `symlink`, gelöschte als `missing`,
  neue ignorierte Pfade nur mit Namen (`git ls-files -oi`).
- Hashes: `git hash-object -w --stdin-paths` (Blobs = Snapshot). Vorher-Manifest bis
  zum Nachher-Manifest ausserhalb des Arbeitsbaums.
- Rücksetzen: verändert/gelöscht → `git cat-file blob`; neu → Quarantäne unter
  `.agent-runs/<run>/quarantine/`. Genutzt für Out-of-Scope-Änderungen (Lauf stoppt),
  Fresh-Versuch, Aufräumen bei `blocked`. Nach rotem Versuch in nicht-fresh-Modi
  bleibt der Diff liegen.
- Externe Änderung zwischen zwei Aufrufen ⇒ `EXTERNAL_CHANGE`.
- Dirty-Check ignoriert Ledger-Pfade, sonst `--allow-dirty`.

### Runner (`lib/runner.sh`, `AGENT_RUNNER=claude|codex`)

Beide liefern `result.json` + `metadata.env`. Schemata als Dateien
`lib/schemas/{manager,worker,finalizer}.json` (alle Properties required,
`additionalProperties:false`, nur `type/enum/pattern`).

- claude: `claude -p --output-format json --json-schema "$(cat schema)"
--permission-mode acceptEdits --permission-prompts none --no-session-persistence
--max-turns N --settings <runner-json> [--model] [--max-budget-usd]`. Worker mit
  `--allowedTools` Read-Tools + `Edit,Write,Bash`; Manager/Finalizer `--restricted
--tools Read,Glob,Grep,Edit,Write`. Runner-`--settings` trägt Deny-Liste,
  `bash-guard`-Hook und `claudeMdExcludes`. `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`,
  `AGENT_HEADLESS=1`.
- codex: `codex exec --json --output-schema schema.json --output-last-message
result.json -C workdir --sandbox workspace-write --color never
-c project_doc_max_bytes=0 [-m model] -` (Prompt via stdin). Tokens aus
  `turn.completed.usage`; Kosten `unknown`; fehlende Datei ⇒ `empty`. Sandbox
  Pflicht, Netz aus. ARCHITECTURE.md benennt die unterschiedlichen Sicherheitshüllen.
- `bash-guard.sh` blockt unter `AGENT_HEADLESS=1` zusätzlich `git commit|merge|
rebase|stash|worktree|branch -D`, `pip install`, `npm publish`.

### Kontext (`lib/context.sh`)

Headless-Rahmen, Rollenvertrag, Ziel, Task (+ Abhängigkeiten oder Inventar), Plan +
Entscheidungen (Manager), aktive Notizen (nicht `fresh`), letzter Prüfbericht (nicht
`fresh`), Dateiliste aus `touches`, Ausgabeformat. Feste Budgets, ein Durchlauf,
Datei `.agent-runs/<run>/<seq>-<role>.context.md`.

### Prüftor (`verify-task.sh`)

Jeden `acceptance`-Befehl als argv (Metazeichen-Sperre, Allowlist
`.agent/verification-allowlist`, Defaults `./scripts/verify.sh npm pytest go cargo
make`), immer `./scripts/verify.sh`, Timeout, Ergebnis pro Befehl, `failure_kind`,
Fingerprints; Bericht nach `docs/verification/<id>.md` + `latest.md`.

### Sperren

Orchestrator-Lock (stale-PID-fähig) und Status-Gate-Lock. Sonst keine.

### Zielstruktur

Nachgeführt mit F9 auf den tatsächlich gebauten Stand; die Zeilenbudgets sind
die gemessenen Grössen, nicht mehr die ursprünglichen Schätzungen.

```
.agent/config.env              MAX_GLOBAL_ITERATIONS MAX_TASK_ATTEMPTS MAX_NO_PROGRESS
                               CONTEXT_MAX_CHARS NOTES_MAX_CHARS VERIFY_TIMEOUT_SECONDS
                               AGENT_TIMEOUT_SECONDS AGENT_MAX_TURNS MAX_INFRA_RETRIES
                               RETRY_BACKOFF_SECONDS AGENT_RUNNER AGENT_MODEL FINALIZER
.agent/verification-allowlist
.claude/settings.json          Hooks + Deny-Liste der interaktiven Sitzung
.claude/plan/umbau-starterkit.md   diese Datei
scripts/
  orchestrate.sh (≤400 Z.)  verify-task.sh (≤200)  validate-ledger.sh (≤260)
  task.sh (≤60)  next-tasks.sh  state-summary.sh  doctor.sh
  verify.sh (Projekt-Platzhalter)  bash-guard.sh  commit-gate.sh
  agent/ common.sh (≤380) ledger.sh (≤370) context.sh (≤300) runner.sh (≤430)
         rolecall.sh (≤150) status.sh (≤100) config.sh (≤100)
         route.sh (≤45) policy.sh  schemas/*.json
docs/
  ARCHITECTURE.md   README.md (Wurzel)   CLAUDE.md (Wurzel)
  prompts/ manager.md worker.md finalizer.md init.md
  templates/ task.md handoff.md
  state/ goal.md plan.md notes.md decisions.md handoff.md
  tasks/   verification/latest.md
tests/ run.sh lib.sh fixture.sh fake-runner.sh unit/ integration/ e2e/ lint/
```

`scripts/agent/` statt `scripts/lib/` und `status.sh` unterhalb davon: das
Status-Gate ist Orchestrierung, kein allgemeines Hilfsmittel, und alles, was ein
Lauf braucht, liegt damit in einem Ordner. `rolecall.sh` kam mit F6 dazu, weil
der bewachte Rollenaufruf sonst 140 Zeilen in den Orchestrator getragen hätte.

---

## Features

Jedes Feature hat Ziel, Aufgaben (abhakbar), Abnahmekriterien und einen
Review-Abschnitt, der beim Abschluss ausgefüllt wird.

### F0 · Verhaltensbenannte Testsuite mit Runner

Branch `test/behaviour-suite` · Status: **gemergt**

Ziel: eine Suite, die sich mit einem Befehl vollständig ausführen lässt, ohne
Logikänderung am Kit. Grundlage für alle folgenden Features.

Aufgaben:

- [x] `tests/lib.sh`: Helfer aus `test-phase-06.sh:8-14` (Ausgabe bei Fehler), alle
      Variablen `local`, `finish_suite` scheitert bei 0 Assertions
- [x] `tests/fixture.sh`: `new_project_fixture --with-git`, `make_task` mit benannten
      Optionen, ein `verify.sh`-Stub, Config-Override per Schlüssel statt `sed`
- [x] `tests/run.sh`: Tiers `unit/integration/e2e`, `--fast`, e2e parallel (`xargs -P`)
- [x] Phase-Dateien nach Verhalten umbenennen und aufteilen; Phase 09 nach
      `tests/lint/check-docs.sh`; Test 01:63 (`runner --check`) nach `doctor.sh`
- [x] `scripts/verify.sh` des Kits: `--quick` = `tests/run.sh --fast`, voll = alles

Abnahme:

- [x] `tests/run.sh` grün mit derselben Assertion-Zahl wie zuvor (417) abzüglich der
      verschobenen Doku-Greps und des Umgebungstests
- [x] Kein Testfile definiert eigene Helfer
- [x] Ein absichtlich kaputter Fixture-Schritt (`cp` auf fehlende Datei) lässt den
      Test rot werden

Review:

Aufteilung (27 Dateien statt 9 Phasen-Dateien):

| Stufe         | Dateien | Zusicherungen |
| ------------- | ------- | ------------- |
| `unit`        | 9       | 114           |
| `integration` | 9       | 127           |
| `e2e`         | 8       | 93            |
| `lint`        | 1       | 83            |

`unit + integration + e2e = 334` — genau die alten 417 minus der 82 Doku-Greps
(jetzt `tests/lint/check-docs.sh`) und minus des Umgebungstests
`runner.sh --check`. Die Suite meldet insgesamt 417, weil `check-docs.sh` eine
Zusicherung dazubekommen hat: `tests/run.sh --help`.

Belege:

- `./scripts/verify.sh` → `tests: GREEN (417 Zusicherungen in 27 Dateien)`, 2:56 min
- `./scripts/verify.sh --quick` → `tests: GREEN (324 …)`, 1:03 min (ohne `e2e`)
- `grep -rn '^[a-z_]*() *{' tests/{unit,integration,e2e,lint}` → keine Treffer
- ein zusätzliches `fixture_copy docs/state/gibt-es-nicht.md` machte vier
  Unit-Dateien rot (`fixture: Quelle fehlt: …`), danach zurückgenommen

Abweichungen vom Plan:

- `runner.sh --check` wurde ersatzlos aus der Suite entfernt, nicht verschoben:
  `scripts/doctor.sh` entsteht erst in F7. Dort ist die Prüfung nachzuziehen.
- Statt `new_project_fixture --with-git` gibt es `fixture_git_init`: ein
  `managed-fresh`-Lauf verlangt einen sauberen Arbeitsbaum, also muss der
  Basiscommit erst nach dem Befüllen des Fixtures entstehen.
- Neben `new_project_fixture` liegen drei benannte Fixtures in `fixture.sh`
  (`new_app_fixture`, `new_candidate_fixture`, `new_populated_fixture`), damit
  keine Testdatei eigene Fixtures baut.
- `scripts/verify.sh` bekam eine Rekursionsbremse (`AGENT_TEST_SUITE`): die Suite
  prüft den Commit-Hook, und der startet `verify.sh --quick`.
- Nachgezogen in F1: `docs/state/plan.md` und `docs/state/handoff.md` behaupteten
  noch, `scripts/verify.sh` sei ein Platzhalter, der immer GREEN meldet.

### F1 · Ballast entfernen

Branch `chore/remove-ballast` · Status: **gemergt**

Ziel: alles weg, was nur für Kurs, Landingpage-Profil oder das Ursprungsprojekt da
war, ohne Verhaltensänderung des Orchestrators.

Aufgaben:

- [x] Löschen: `docs/KURSANLEITUNG.md`, `docs/profil/**`, `docs/briefs/`,
      `docs/state/features.md`, `scripts/migrate-tasks.sh`, `scripts/autoformat.sh`
      (+ PostToolUse-Hook), `scripts/archive-notes.sh`, `scripts/agent-metrics.sh`
- [x] `.agent/README.md` → `docs/ARCHITECTURE.md` (Rohfassung, wird in F9 normativ)
- [x] `bash-guard.sh:14,26`: Kurs-Verweise entfernt
- [x] `.gitignore`: `.astro/` entfernt, `dist/` behalten; `tasks.json`-Verbote in
      CLAUDE.md und Initializer-Prompt entfernt
- [x] Tests und Doku-Lint an die gelöschten Dateien angepasst

Abnahme:

- [x] `grep -ri 'landingpage\|kurs\|profil\|tasks.json' --exclude-dir=.git .` liefert
      nur diese Plandatei — mit einer Einschränkung, siehe Review
- [x] `tests/run.sh` grün

Review:

Gelöscht (16 Dateien, 1324 Zeilen entfernt, 71 hinzugefügt):

| Was                       | Dateien                                                                     |
| ------------------------- | --------------------------------------------------------------------------- |
| Kursmaterial              | `docs/KURSANLEITUNG.md`                                                     |
| Landingpage-Profil        | `docs/profil/**` (7), `docs/briefs/`                                        |
| Feature-Liste             | `docs/state/features.md`                                                    |
| Wartungs- und Hilfsskript | `migrate-tasks.sh`, `autoformat.sh`, `archive-notes.sh`, `agent-metrics.sh` |
| Tests dazu                | `tests/integration/{notes-archive,task-migration}.sh`                       |

Verschoben: `.agent/README.md` → `docs/ARCHITECTURE.md` (F9 macht sie normativ).
`.agent/` enthält jetzt nur noch `config.env`.

Angepasst: `README.md` 581 → 162 Zeilen (Block 52–455 wie geplant raus, dazu die
Verweise auf gelöschte Dateien); `.claude/settings.json` ohne PostToolUse-Hook;
`scripts/agent/common.sh` ohne die zwei Manifest-Ausnahmen der gelöschten
Skripte; `docs/templates/initializer-prompt.md` ohne Profil-, Brief- und
`features.md`-Schritt (Projektbeschreibung wird jetzt direkt in die Datei
eingetragen; Punkte neu durchnummeriert 0–6); `docs/state/{goal,notes}.md`,
`docs/templates/task-template.md`, `tests/lint/check-docs.sh`,
`tests/integration/{metrics,verify-gate}.sh`.

Nachgezogen aus F0: `docs/state/plan.md` und `docs/state/handoff.md` sagten
noch, `scripts/verify.sh` sei ein immer-grüner Platzhalter. Beide sagen jetzt,
dass die Prüfung bis zur Initialisierung das Starterkit selbst prüft; auch
`initializer-prompt.md` spricht nicht mehr vom «Platzhalter».

Belege:

- `./scripts/verify.sh` → `tests: GREEN (400 Zusicherungen in 25 Dateien)`
- `bash -n` über alle 25 Skripte in `scripts/` und `tests/`: fehlerfrei
- `./scripts/validate-ledger.sh` → `GREEN`; `state-summary.sh`, `next-tasks.sh`,
  `orchestrate.sh --help` laufen auf dem leeren Starter
- Abnahme-Grep ohne die deutschen Falschtreffer liefert nur diese Plandatei:
  `grep -ri 'landingpage\|kurs\|profil\|tasks.json' --exclude-dir=.git . | grep -vi 'rekurs\|diskurs\|exkurs'`

Abweichungen vom Plan:

- Der Abnahme-Grep ist wörtlich nicht erfüllbar: «kurs» steckt als Teilwort in
  «rekursiv»/«Rekursionsbremse». Übrig bleiben nur solche Treffer in
  `scripts/bash-guard.sh`, `scripts/verify.sh`, `tests/unit/bash-guard.sh` und
  `docs/ARCHITECTURE.md`. Der Grep oben mit `grep -vi 'rekurs\|diskurs\|exkurs'`
  ist die tragfähige Fassung.
- Zusicherungen 417 → 400: entfallen sind `notes-archive` (5) und
  `task-migration` (3) als ganze Dateien, `agent-metrics --help` (1) und die
  10 Begriffs- plus 5 Bedienfall-Greps gegen die KURSANLEITUNG; dafür prüft
  `check-docs.sh` jetzt 6 Begriffe gegen `docs/ARCHITECTURE.md`.
- `.gitignore`: `.astro/` war Astro-spezifisch und ist raus, `dist/` bleibt
  (stackneutral üblich). Die Node-Überschrift heisst jetzt
  «Build- und Abhaengigkeitsordner».
- Nicht angefasst, weil einem späteren Feature zugeordnet:
  `scripts/agent/metrics.sh` und `docs/state/metrics.csv` (F4),
  `candidates.sh` (F3), `output.sh` (F6), Feld `features` im Task-Frontmatter
  (F5), `docs/state/notes-archive/` (F5).
- Vorgefunden, nicht behoben (gehört in den README-Audit von F9):
  `docs/templates/initializer-prompt.md` verweist auf `tests/orchestrator/`,
  ein Pfad, den es seit F0 nicht mehr gibt.
- Weiterhin offen für F7: die mit F0 gestrichene Umgebungsprüfung
  `runner.sh --check` fehlt der Suite, bis `scripts/doctor.sh` entsteht.

### F2 · Git-basierte Manifeste und Snapshot

Branch `perf/git-manifests` · Status: **gemergt**

Ziel: Manifeste in Millisekunden statt Sekunden, `.gitignore` gilt, Manipulation
durch Worker ausgeschlossen, Wiederherstellung aus Snapshot möglich.

Aufgaben:

- [x] `agent_repo_manifest`, `agent_product_manifest`, `ledger_candidate_fingerprint`
      auf `git ls-files -z -co --exclude-per-directory=.gitignore` +
      `git hash-object -w --stdin-paths`
- [x] Einträge `missing` (gelöscht), `symlink` (Modus 120000), ignorierte neue Pfade
      nur mit Namen; `.git/hooks/*`, `.git/config`, `.git/info/exclude` aufnehmen
- [x] Vorher-Manifest bis zum Nachher-Manifest ausserhalb des Arbeitsbaums halten
- [x] `agent_snapshot_restore <manifest> <pfad…>`: Blob zurückschreiben oder neue
      Datei in Quarantäne verschieben
- [x] Validator: Dateiname `<id>.md` == `id`; `ledger_task_path_by_id` → `[ -f ]`
- [x] `agent_manifest_changes`, Masking-awk, `ledger_verifier_fingerprint` unverändert
      übernehmen

Abnahme:

- [~] Scratch-Kopie (60 Tasks, 2000 Dateien in `node_modules`): Manifest < 0,5 s
  **erfüllt (0,11 s)**, `validate-ledger` < 1 s **nicht erfüllt (10,6 s)**,
  `next-tasks` < 1 s **nicht erfüllt (11,9 s)** — siehe Review
- [x] Tests: gitignored unsichtbar; neue untracked sichtbar; gelöschte sichtbar; neue
      ignorierte Namen sichtbar (`.env`); Restore stellt geänderte Datei her und
      quarantänisiert neue; Besitzer-Dirt in derselben Datei überlebt

Review:

Manifestformat: eine sortierte Zeile `<feld>  <pfad>` je Eintrag.

| Feld             | Bedeutung                                                             |
| ---------------- | --------------------------------------------------------------------- |
| `<hash>`         | Blob-Hash des Inhalts; damit ist jedes Manifest zugleich ein Snapshot |
| `exec:<hash>`    | dasselbe mit gesetztem Ausführungsbit                                 |
| `symlink:<hash>` | Hash des Linkziels, nie des Inhalts dahinter                          |
| `missing`        | im Index, aber nicht im Arbeitsbaum                                   |
| `ignored`        | von `.gitignore` erfasst: nur der Name                                |

Messungen auf der Scratch-Kopie (60 Tasks, 2000 Dateien in `node_modules`):

| Messung                    | vorher | nachher | Ziel    |
| -------------------------- | ------ | ------- | ------- |
| Repo-Manifest              | 23 s   | 0,11 s  | < 0,5 s |
| Produkt-Manifest           | 23 s   | 0,04 s  | < 0,5 s |
| `validate-ledger.sh`       | 11 s   | 10,6 s  | < 1 s   |
| `next-tasks.sh`            | 48 s   | 11,9 s  | < 1 s   |
| `orchestrate.sh --dry-run` | 92 s   | 33,5 s  | –       |

Belege:

- `./scripts/verify.sh` → `tests: GREEN (424 Zusicherungen in 26 Dateien)`
- neue Datei `tests/integration/manifests.sh` (24 Zusicherungen) deckt die
  gesamte Abnahmeliste ab, dazu Git-Hooks im Manifest, `missing`-Eintrag,
  Rückkehr einer gelöschten Datei und die Abweisung eines Pfads mit `..`
- `bash -n` über alle Skripte in `scripts/` und `tests/`: fehlerfrei

Offen aus dieser Abnahme:

- `validate-ledger` und `next-tasks` bleiben über einer Sekunde. Die verbleibende
  Zeit sind die **~40 Prozesse pro Task** aus dem Befund, nicht mehr der
  O(n²)-Lookup: den erledigt der Dateiname-Lookup (`next-tasks` 48 s → 11,9 s,
  davon 10,6 s der Validator, den es aufruft). Den Rest löst erst der eine
  awk-Durchlauf pro Datei — der steht als Aufgabe in **F5** und trägt dort
  dieselbe Abnahme (`validate-ledger` mit 60 Tasks < 1 s). Die Zahl gehört in
  F2 also verfrüht in die Abnahme; sie wird mit F5 erfüllt.

Abweichungen vom Plan:

- `agent_manifest_changes` wurde **nicht** unverändert übernommen: die alte
  Fassung schnitt Feld und Pfad an fester Spalte 67 (SHA-256 + zwei Leerzeichen).
  Git-Blob-Hashes sind 40 Zeichen, `missing`/`ignored` kürzer. Die Fassung
  trennt jetzt am ersten Doppelleerzeichen; die Diff-Logik selbst ist gleich.
- Symlinks stehen als `symlink:<hash des Linkziels>`, nicht nur als `symlink`.
  Ohne den Hash bliebe ein umgehängter Symlink unsichtbar und liesse sich nicht
  zurücksetzen. Aus demselben Grund gibt es `exec:<hash>`: ein gesetztes
  Ausführungsbit ist eine Änderung, und ein Restore muss es wiederherstellen.
- `agent_snapshot_restore` nimmt Projektpfad und Quarantäneordner als Argumente
  (`<projekt> <manifest> <quarantäne> <pfad…>`). Das Vorher-Manifest liegt
  ausserhalb des Arbeitsbaums, sein Ort taugt also nicht zur Herleitung.
- Ignorierte Ordner werden mit `git ls-files -oi --directory` als **ein** Eintrag
  geführt (`node_modules/`). Sonst stünden 2000 Namen in jedem Manifest.
- Git wird damit zur harten Voraussetzung. Deshalb ist jedes Test-Fixture jetzt
  ein Repository (`new_project_fixture` macht `git init`, `fixture_git_init`
  setzt nur noch den Basiscommit), und die Finalizer-Arbeitskopie bekommt ein
  eigenes `git init`.
- Drei Prüfungen liefen bisher nur zufällig nicht, weil Fixtures kein Git hatten;
  mit Git wurden sie sichtbar und laufen jetzt gegen `HEAD` statt gegen
  «irgendein Git-Verzeichnis»: der Dirty-Check des Orchestrators, der
  `touches`-Abgleich in `verify-task.sh` und der Git-Vergleich beim Resume
  (`git rev-parse HEAD` schrieb ohne Commit `HEAD` **und** `unborn` in die
  Variable; jetzt `--verify -q`). Ohne Commit gibt es keinen Vergleichsstand.
- Der Dirty-Check ignoriert zusätzlich `docs/tasks`, `docs/state` und
  `docs/verification` — vorgezogen aus dem Zielentwurf, weil der Orchestrator
  diese Pfade selbst schreibt. F4 führt dieselbe Aufgabe nochmals; dort ist sie
  dann erledigt.
- `agent_repo_manifest`/`agent_product_manifest` schreiben Blobs in den
  Objektspeicher, auch im `--dry-run`. Der Dry-Run-Test vergleicht deshalb ohne
  `.git/`. Versionierte und produktive Dateien bleiben unberührt; Git-Objekte
  sind inhaltsadressiert und werden vom `git gc` des Besitzers abgeräumt.
- Vorgezogen für die Kandidaten- und Finalizer-Pfade: auch deren Vorher-Manifeste
  liegen jetzt ausserhalb des Arbeitsbaums. Beide Rollen laufen in Verzeichnissen,
  in die sie selbst schreiben dürfen; F3 und F6 entfernen die Pfade später ganz.

### F3 · Turnier streichen, Fresh-Versuch, Router

Branch `refactor/drop-tournament` · Status: **gemergt**

Ziel: Ein Eskalationspfad `single → verified → managed → blocked`, Fresh als
Kontextvariante mit Snapshot-Rücksetzung, Router ohne Magie.

Aufgaben:

- [x] Entfernen: `scripts/agent/candidates.sh`, Rolle `reviewer`, `managed_fresh_loop`,
      `run_candidate_worker`, `verify_isolated_candidate`, `.git`-Tausch,
      Kandidatenbelege in `context.sh`
- [x] `scripts/agent/route.sh` (Funktion `agent_route_mode`, 22 Z.): Klasse →
      Basismodus, Override, Versuche → Rang, `risk_flags` → Minimum `managed`;
      kein `--record`, keine Signale, keine Keyword-Heuristik, kein
      `--escalate-from`
- [x] Feld `fresh_perspective` entfernen; `risk_flags` auf
      `high-risk|cross-component|repeated-failure`
- [x] Fresh-Versuch: `touches` per `agent_snapshot_restore` auf Laufstart, Kontext ohne
      Notizen/Vorbericht
- [x] `path_in_task_scope`, `check_role_changes` übernehmen; bei Verstoss Restore +
      Abbruch

Abnahme:

- [x] Router-Tabelle als Test: alle Klassen × Overrides × Versuche × Flags
      (`tests/unit/router-decisions.sh`, 30 Zusicherungen)
- [x] Test: Fresh-Versuch startet vom Snapshot und Kontext enthält keine Notizen
      (`tests/e2e/orchestrate-fresh.sh`)
- [x] Test: Out-of-Scope-Änderung wird zurückgesetzt, Lauf stoppt, Ledger gültig
      (`tests/e2e/orchestrate-fresh.sh`)

Review:

- Der Modus `managed-fresh` ist weg. Fresh ist eine Versuchsvariante innerhalb
  von `managed`: der Manager kann sie verlangen, und der letzte erlaubte Versuch
  läuft immer so. Der Orchestrator setzt dabei alle seit dem Laufstart
  veränderten Pfade innerhalb von `touches` auf den Snapshot zurück; Pfade, die
  es beim Laufstart nicht gab, wandern nach `.agent-runs/<run>/quarantine/`.
- `route-task.sh` als CLI ist entfallen; der Router ist eine eingebundene
  Funktion ohne Seiteneffekt. Die Eskalation entsteht dadurch von selbst: nach
  jedem roten Versuch zählt der Orchestrator `attempts` hoch und fragt dieselbe
  Tabelle erneut. `--record`, `REASON_CODE` und die Routing-Signale sind weg.
- Vorgezogen aus F6: der Infrastruktur-Retry sitzt jetzt in `run_role` statt im
  gelöschten `run_candidate_worker`. Ohne diesen Schritt hätte F3 eine
  getestete Fähigkeit verloren und `MAX_INFRA_RETRIES` verwaist. Leere oder
  abgeschnittene Antworten gelten weiterhin nicht als Providerfehler.
- Bewusst nicht angefasst: die Felder `route_rule_version`,
  `route_reason_code` und `route_signals` in `current-run.md` stehen jetzt fest
  auf ihren Vorgabewerten. `route_human_gate` schreibt der Orchestrator beim
  Laufstart selbst. F5 entfernt die `route_*`-Felder.
- Der Modus steht ab F3 direkt beim Anlegen von `current-run.md`; das
  nachträgliche Protokollieren durch den Router entfällt ersatzlos.

### F4 · Laufzustand unversioniert

Branch `refactor/run-state-unversioned` · Status: **gemergt**

Ziel: Kein Lauf macht den Git-Stand ausserhalb der fachlichen Belege schmutzig;
kein Resume, keine Checkpoints, kein Metrik-Subsystem.

Aufgaben:

- [x] Entfernen: `scripts/agent/metrics.sh`, `docs/state/metrics.csv`,
      `docs/state/current-run.md`, `--resume`, `checkpoint_*`, CSV-Prüfung im Validator
- [x] Laufzustand in `.agent-runs/<run>/run.env`; `metadata.env` pro Aufruf bleibt die
      Metrik; einfache `.agent-runs/metrics.csv` (eine Zeile pro Lauf, append-only)
- [x] Invariante «höchstens ein `in_progress`» in `validate_task_set`
- [x] EXIT-Trap: nie `in_progress` hinterlassen; Stale-Run beim Start auf `todo`
- [x] `--dry-run` nur Routenausgabe, keine Nebenwirkung
- [x] `state-summary.sh` auf Prüfstand + offene Arbeit (2 Zeilen)
- [x] Dirty-Check ignoriert `docs/state`, `docs/tasks`, `docs/verification`

Abnahme:

- [x] Nach einem grünen Fake-Lauf sind nur Task, Prüfbericht, Handoff geändert
      (`tests/e2e/orchestrate-run-state.sh`, Prüfung über `git status --porcelain`)
- [x] Test: abgebrochener Lauf (kill) hinterlässt kein `in_progress`; Stale-Lock wird
      übernommen; zweiter Orchestrator wird abgewiesen
      (`tests/e2e/orchestrate-run-state.sh`)

Review:

- Der Laufzustand liegt jetzt als flache `KEY=VALUE`-Datei in
  `.agent-runs/<run>/run.env` und wird nur innerhalb eines Aufrufs gelesen.
  `docs/state/current-run.md` ist weg, ebenso seine Validierung und die
  `route_*`-Felder aus der Ledger-Whitelist (F3 hatte sie schon eingefroren).
- Das Metrik-Subsystem ist ersatzlos gestrichen. Statt `metrics.sh` mit Schema,
  Sperre, Migration und idempotenter Finalisierung hängt der Orchestrator am
  Laufende eine Zeile an `.agent-runs/metrics.csv` an. Die Verbrauchswerte
  bleiben, wo sie ohnehin entstehen: in `metadata/<aufruf>.env` pro Rollenaufruf.
- Die Outcome-Namen bleiben, verlieren aber ihr Schema-Gate: der Orchestrator
  schreibt sie einfach in die Zeile. Neu sind `failed` (Abbruch ohne eigene
  Begründung) und `paused`; letzteres, weil eine Pause auf eine menschliche
  Entscheidung ohne Resume trotzdem eine Zeile bekommt und kein Fehlschlag ist.
- «Höchstens ein `in_progress`» hing bisher am Vorhandensein von
  `current-run.md` und galt damit nur bei aktivem Lauf. Die Invariante steht
  jetzt in `validate_task_set` und gilt immer.
- Zwei Wege sorgen dafür, dass kein Task in `in_progress` hängen bleibt: der
  EXIT-Trap gibt ihn beim geregelten Abbruch frei (auch bei `SIGTERM`), und wer
  danach die Sperre bekommt, setzt einen überlebenden `in_progress`-Task
  sichtbar auf `todo` zurück. Der zweite Weg deckt `kill -9` und Stromausfall ab.
- `--dry-run` legt keinen Laufordner mehr an und berührt keine Datei; die Zeile
  `METADATA=` in seiner Ausgabe ist entfallen.
- Die Reihenfolge beim Start ist neu: erst Sperre, dann Stale-Aufräumen, dann
  Taskwahl und Schmutz-Check. Ohne die Sperre vorweg könnte ein zweiter Lauf
  den `in_progress`-Task eines laufenden ersten für verwaist halten.
- `state-summary.sh` hat nur noch zwei Zeilen: Prüfstand und offene Arbeit. Die
  Laufzeile hatte ohne versionierten Laufzustand keinen Inhalt mehr.
- Der Schmutz-Check übergeht `docs/tasks`, `docs/state` und `docs/verification`
  schon seit F2 — das blieb unverändert und ist jetzt durch den Grün-Lauf-Test
  belegt.

### F5 · Ledger-Schema und Task-Kommandos

Branch `refactor/ledger-schema` · Status: **gemergt**

Ziel: Schlankes Frontmatter, schneller Parser, menschliche Übergänge als Kommandos.

Aufgaben:

- [x] Felder entfernen: `features`, `last_verification`, `max_attempts`, `route_*`,
      `PROMPT_VERSION` (Config); Feld-Whitelist in `ledger.sh` entfernen
- [x] Ein awk-Durchlauf pro Datei (`key<TAB>value`), Bash-3.2-kompatibel
- [x] `status.sh`: Übergangstabelle, CAS-Prüfung, Human-Gate übernehmen; neu
      `blocked→todo` nur mit `--human-approved`; Grünprüfung über
      `docs/verification/<id>.md`
- [x] `verify-task.sh` schreibt `docs/verification/<id>.md` + `latest.md`; `history/`
      und `notes-archive/` entfallen
- [x] `scripts/task.sh reopen N | approve N`
- [x] `docs/templates/task.md` an das Schema anpassen; Validator an Schema und
      Pflichtabschnitte anpassen

Abnahme:

- [x] Tests: `done` nur mit aktuellen Fingerprints; Änderung an `touches`-Datei oder
      `verify.sh` widerruft; `review`-Pfad; `reopen`/`approve`
      (`tests/integration/verify-gate.sh`, `tests/integration/task-commands.sh`)
- [x] `validate-ledger` mit 60 Tasks < 1 s (gemessen 0,28–0,65 s; als Zusicherung
      in `tests/integration/ledger-validation.sh`)

Review:

- Das Frontmatter trägt genau zwölf Felder: `id title status class orchestration
attempts human_review blocked_reason` als Einzelwerte und `depends_on touches
risk_flags acceptance` als Listen. Alle zwölf sind Pflicht — `touches` und
  `risk_flags` waren vorher optional. Ein dreizehntes Feld ist ein Fehler; damit
  fällt ein altes `features:` oder `max_attempts:` beim ersten Validatorlauf auf,
  statt still liegen zu bleiben.
- `ledger.sh` kennt keine Feldnamen mehr. `ledger_parse` liest eine Datei in
  einem awk-Durchlauf und gibt je Wert eine Zeile `schlüssel<TAB>wert` aus;
  Rumpfüberschriften der Ebene 1 erscheinen unter dem Schlüssel `#`, der als
  Feldname ausgeschlossen ist. Ein Einzelfeld liefert genau eine Zeile, eine
  leere Liste genau eine Zeile mit leerem Wert — daran unterscheidet der
  Validator «fehlt» von «ist leer». Welche Felder gelten, entscheidet allein
  `validate-ledger.sh`.
- Der Validator liest damit pro Task eine Datei mit einem Prozess statt mit rund 75. 60 Tasks: 9,2 s → 0,28 s warm, 0,65 s kalt. Zwei weitere Stellen trugen
  bei: `basename` ist durch `${file##*/}` ersetzt, und die Zyklensuche ist eine
  Kahn-Sortierung in einem awk statt einer Schleife aus je einem `awk` und `mv`
  pro Task.
- Der Prüfbeleg liegt jetzt je Aufgabe unter `docs/verification/<id>.md`;
  `latest.md` ist nur noch die Kopie des zuletzt geschriebenen Berichts.
  `history/` entfällt: die Historie stand bereits im Log unter `.agent-runs/`,
  und die versionierte Kopie wuchs mit jedem Versuch. `docs/state/notes-archive/`
  ist ebenfalls weg — der Ordner hatte seit F1 keinen Schreiber mehr.
- `last_verification` ist ersatzlos gestrichen. Der Prüfstand stand doppelt: im
  Task und im Bericht. Das Feld war ein Duplikat, das nur der Verifier schreiben
  durfte, und der Statusübergang prüfte ohnehin zusätzlich den Bericht. Jetzt
  gibt es eine Quelle: `docs/verification/<id>.md`. `verify-task.sh` schreibt
  seitdem keine Task-Datei mehr an.
- `max_attempts` im Task ist gestrichen: das Limit stand an zwei Orten, und der
  Orchestrator hat den kleineren der beiden Werte genommen — der Taskwert konnte
  das Limit also nur senken, nie heben. Jetzt gilt `MAX_TASK_ATTEMPTS` aus
  `.agent/config.env` allein.
- Neu ist der Übergang `blocked → todo`. Er existierte vorher gar nicht: eine
  blockierte Aufgabe war eine Sackgasse. Er ist an `--human-approved` gebunden,
  weil der Orchestrator sonst genau den Lauf wiederholen würde, der sie
  blockiert hat.
- `scripts/task.sh` (49 Zeilen) ist der menschliche Zugang zu den beiden
  Übergängen, die kein Agent auslösen darf: `reopen <id>` öffnet eine blockierte
  Aufgabe und räumt dabei `blocked_reason` weg, `approve <id>` gibt eine Aufgabe
  im Review frei. Beide gehen durch dasselbe Status-Gate wie jeder andere
  Übergang; das Skript setzt nur die menschliche Freigabe.
- Die Task-Vorlage hiess `task-template.md` und heisst jetzt `task.md`. Sie
  hatte ausserdem einen Fehler: `touches: [] # Pfade …` — ein Kommentar hinter
  einer Liste hat den Leser bisher scheitern lassen. Eine Aufgabe, die jemand
  wörtlich aus der Vorlage abgeschrieben hätte, wäre ungültig gewesen. Der
  Parser erlaubt den Kommentar jetzt nach der schliessenden Klammer, und die
  Vorlage erklärt jedes Feld in einer eigenen Zeile.
- Der Pflichtabschnitt heisst `# Akzeptanzkriterien` statt
  `# Akzeptanzkriterien (über die acceptance-Befehle hinaus)`; der Zusatz steht
  jetzt als Fliesstext darunter. `# Offene Frage` ist als optionaler Abschnitt
  in der Vorlage vorgesehen — F6 füllt ihn.
- Bewusst nicht angefasst: `scripts/agent/status.sh` bleibt unter `agent/`,
  obwohl die Zielstruktur `scripts/status.sh` nennt; der Umzug gehört nicht zu
  diesem Feature. `context.sh` liest weiter `latest.md` statt `<id>.md` — F6
  baut den Kontext ohnehin neu. In `tests/integration/verify-gate.sh` stehen elf
  Aufrufe eines `make_active_run`, das es seit F4 nicht mehr gibt; sie tun
  nichts und gehören zum Aufräumen von F6.

### F6 · JSON-Ergebnisse, drei Rollen, Eskalation

Branch `refactor/json-results-and-roles` · Status: **gemergt**

Ziel: Der Orchestrator wird auf ≤400 Zeilen mit einem klaren Ablauf; drei Prompts;
ein Format.

Aufgaben:

- [x] `scripts/agent/schemas/{manager,worker,finalizer}.json`; Runner schreibt
      `result.json`; `output.sh` gelöscht; Prüfung mit `jq -e`
- [x] `docs/prompts/{manager,worker,finalizer}.md` (Rollenvertrag, Schreibbereich,
      Abbruchregeln, Ausgabeformat als JSON-Beispiel mit allen Feldern)
- [x] Manager mit Steuerfeld-Schutz (`ledger_control_snapshot`) und Regel «neue
      Tasks `todo/0`»; `plan_is_placeholder` weg
- [x] `run_role` mit Infra-Retry (`MAX_INFRA_RETRIES`), Manifest vor/nach,
      Scope-Prüfung, Restore
- [x] Versuchsschleife mit Eskalation; `failure_kind=verifier` zählt nicht;
      No-Progress-Guard; `MAX_GLOBAL_ITERATIONS`
- [x] `ask_human`: Frage in Task, `blocked/ASK_HUMAN`, kein Versuch
- [x] Deterministischer Laufbeleg in `handoff.md` bei jedem Ende; Finalizer opt-in
      (`FINALIZER=llm`) ohne Arbeitskopie
- [x] Headless-Rahmen in `context.sh`; Dateiliste statt Dateiinhalte; feste Budgets
- [x] `append_failure_note`, `progress_fingerprint`, `agent_redact`,
      `agent_truncate_blocks`, `validate_metadata`, `write_metadata` übernommen

Abnahme:

- [x] Tests: single/verified/managed grün und rot; Eskalation genau eine Stufe pro
      rotem Versuch; Verifier-Fehler ohne Versuch; `ask_human` → `blocked`, nach
      `reopen` sieht der Manager die Antwort; ungültiges JSON stoppt, Ledger gültig;
      Infra-Retry für jede Rolle (Timeout, leer, ungültig); Laufbeleg bei
      grün/blocked/ask_human; Manager kann Steuerfelder nicht ändern
      (`tests/e2e/orchestrate-{single,verified,escalation,managed,fresh,ask-human,
    failures}.sh`, `tests/unit/result-contract.sh`)
- [x] `wc -l scripts/orchestrate.sh` ≤ 400 (gemessen 399)

Review:

- Ein Rollenergebnis ist jetzt eine JSON-Datei. Der Anbieter-CLI erzwingt das
  Schema beim Erzeugen, danach prüft `runner.sh validate_result` es ein zweites
  Mal mit `jq -e`: genau die geforderten Felder, jeder Wert eine Zeichenkette,
  `enum` und `pattern` eingehalten. Zwei unabhängige Prüfungen, weil die erste
  vom Anbieter kommt und niemand sie im Repository nachweisen kann.
  `scripts/agent/output.sh` (181 Zeilen mit zwei awk-Parsern für zwei
  Textformate) ist ersatzlos weg — mit ihm das Zeilenformat `KEY=WERT` und das
  Manager-Frontmatter.
- Aus sechs Prompt-Rollen sind drei geworden. `manager-plan` und
  `manager-manage` waren dieselbe Rolle mit zwei Prompts; `worker-brainstorm`
  ist ersatzlos gestrichen, weil eine Runde «Risiken sammeln» ohne Prüftor
  keinen belegbaren Fortschritt erzeugt hat; `worker-fresh` ist keine Rolle
  mehr, sondern eine Variante des Workers — derselbe Prompt, derselbe
  Schreibbereich, nur ein Kontext ohne Vorgeschichte.
- Der grösste Gewinn ist der Ablauf. Vorher gab es drei Codepfade (`single`,
  `verified`, `managed`) plus `managed_loop`; jetzt gibt es eine Schleife. Der
  Modus entscheidet nur noch, ob vor der Runde der Manager läuft. Jede rote
  Prüfung zählt einen Versuch, und der Router liefert daraus die nächste Stufe
  — `single → verified → managed → blocked` ergibt sich, statt programmiert zu
  werden.
- Das ändert das Verhalten sichtbar: ein `single`-Task lief früher genau eine
  Runde und war dann fertig oder offen. Jetzt eskaliert derselbe Task innerhalb
  **eines** Aufrufs bis `MAX_TASK_ATTEMPTS`. Wer die alte Enge will, setzt
  `MAX_TASK_ATTEMPTS=1`. Der Plan verlangt das so («Versuchsschleife in einem
  Aufruf»), aber es ist der Punkt, an dem ein Lauf teurer werden kann als
  vorher.
- `failure_kind: verifier` zählt keinen Versuch mehr. Ein fehlendes Programm
  oder ein Zeitlimit im Prüfweg ist keine Aussage über den Kandidaten; vorher
  hat es trotzdem eine Aufgabe Richtung Blockade geschoben.
- `ask_human` ist neu und ersetzt `request_human`. Die Frage steht als
  `# Offene Frage` im Task, die Aufgabe ist `blocked/ASK_HUMAN`, kein Versuch
  ist verbraucht. Der Mensch antwortet in derselben Datei und öffnet sie mit
  `./scripts/task.sh reopen <id>`; beim nächsten Lauf steht die Antwort im
  Manager-Kontext, weil der Task-Rumpf vollständig mitgeht. Der Lauf endet mit
  Exitcode 1 wie jedes andere Ende ohne `done`/`review` — Exit 0 heisst
  weiterhin genau: die Aufgabe ist durch.
- Den Laufbeleg schreibt der Orchestrator bei **jedem** Ende selbst, auch bei
  Absturz und Abbruch: Run-ID, Modus, Ergebnis, Task mit Status, Verifierstatus
  und letzter grüner Stand. Er ersetzt den vorhandenen Abschnitt, statt ihn
  anzuhäufen. Dafür braucht es kein Modell — der Finalizer ist jetzt abwählbar
  und im Auslieferungsstand aus (`FINALIZER=off`). Läuft er, dann wie jede
  andere Rolle im Arbeitsbaum; die 52 Zeilen, die vorher eine Arbeitskopie
  samt eigenem `git init` aufgebaut und Ergebnisse zurückgespielt haben, sind
  weg. Bei `ASK_HUMAN` läuft er auch mit `FINALIZER=llm` nicht: eine Frage
  braucht eine Antwort, keine Erzählung.
- Der Worker bekommt die **Liste** der Pfade aus `touches` statt deren Inhalt.
  Dateien liest er mit seinen eigenen Werkzeugen; der Kontext wird dadurch klein
  und vorhersagbar. Zusammen mit festen Budgets je Abschnitt konnte die
  Schrumpfschleife in `context.sh` (bis zu zwölf Runden Nachrechnen) entfallen:
  passt ein Kontext heute, passt er auch morgen. Passt er nicht, sagt das Skript
  das mit Zahl statt still zu kürzen.
- Der Headless-Rahmen steht jetzt im Kontextdokument statt in
  `--append-system-prompt`. Das ist die Vorbereitung für F7: beide Runner
  reichen dieselbe Datei weiter, und keiner muss den Rahmen kennen.
- Zwei Fehler sind dabei aufgefallen und behoben. Erstens war die Regel «neue
  Tasks `todo/0`» tot: das Muster `*'|todo|0|never|'*` konnte auf eine Zeile
  `<id>|todo|0|` nie passen, ein Manager hätte also nie einen Task anlegen
  können. Zweitens kollidierte der Infrastruktur-Retry mit der Regel des
  Runners, keine bestehende Ausgabedatei zu überschreiben — mit dem echten
  Runner wäre jeder zweite Versuch sofort gescheitert. Jeder Retry bekommt jetzt
  eigene Dateien (`<label>.retry1`), und beide Fälle haben einen Test.
- Ein Verstoss gegen die Steuerfelder setzt den Arbeitsbaum jetzt genauso zurück
  wie ein Verstoss gegen den Schreibbereich. Vorher stoppte der Lauf zwar, liess
  aber die manipulierte Task-Datei liegen — der nächste Lauf hätte darauf
  aufgesetzt.
- `docs/verification/<id>.md` ist seit F5 der Prüfbeleg eines Tasks;
  `context.sh` liest jetzt ihn statt `latest.md`. Die elf toten Aufrufe von
  `make_active_run` in `tests/integration/verify-gate.sh` sind entfernt.
- Zwei bewusste Abweichungen von der Zielstruktur. Erstens gibt es eine siebte
  Bibliotheksdatei: `scripts/agent/rolecall.sh` (142 Zeilen) trägt den
  bewachten Rollenaufruf — Kontext bauen, Runner rufen, Ergebnis prüfen,
  Manifest vergleichen, Verstoss zurücksetzen. Ohne diese Trennung wären es
  540 Zeilen im Orchestrator statt 399; die Zielstruktur nennt sie noch nicht.
  Zweitens ist `context.sh` mit 291 Zeilen über den dort genannten 200; das
  bleibt für ein späteres Feature offen. Der Umzug von `scripts/agent/` nach
  `scripts/lib/` gehört weiterhin zu keinem Feature — er sollte einen eigenen
  bekommen.

### F7 · Zwei Runner: Claude und Codex

Branch `feat/codex-runner` · Status: **gemergt**

Ziel: `AGENT_RUNNER=claude|codex` mit identischem Ergebnisvertrag und jeweils
passender Sicherheitshülle.

Aufgaben:

- [x] `lib/runner.sh`: Dispatch; Claude-Adapter (Flags wie im Zielentwurf,
      rollenabhängige Tools, `--restricted` für Manager/Finalizer)
- [x] Runner-eigenes `--settings`-JSON: Deny-Liste, `bash-guard`-Hook,
      `claudeMdExcludes`
- [x] Codex-Adapter: `codex exec --json --output-schema … --output-last-message …
  --sandbox workspace-write …`, JSONL-Parsing (`turn.completed.usage`,
      `turn.failed`), Prompt via stdin
- [x] `config.sh`: String-Schlüssel (`AGENT_RUNNER`, `AGENT_MODEL`, `FINALIZER`),
      Runner-Grenzen aus Env in die Config
- [x] `scripts/doctor.sh`: bash, git, jq, perl, gewählter Runner (`claude --version`
      mit `--json-schema`; `codex --version`), Repo-Zustand
- [x] `bash-guard.sh`: Headless-Zusätze unter `AGENT_HEADLESS=1`
- [x] `.claude/settings.json`: nur interaktive Hooks und Deny-Liste, keine Stack-Allowlist

Abnahme:

- [x] Tests mit Fixtures: Claude-`result.json` (ok, Fehler, kein JSON) und
      Codex-JSONL (ok, `turn.failed` ohne Datei) liefern korrekte `metadata.env`
- [x] `doctor.sh` meldet die defekte Codex-Installation als Befund, nicht als Absturz
- [x] `doctor.sh` ersetzt die mit F0 gestrichene Umgebungsprüfung `runner.sh --check`
      und ist wieder in der Suite (Stufe `lint` oder `integration`)
- [x] Vermerk im Commit: Codex-Adapter nicht gegen echtes CLI geprüft

Review:

- Der Claude-Adapter ist gegen das echte CLI gelaufen, nicht nur gegen Stubs.
  Ein Manager-Aufruf (`--restricted --tools Read,Glob,Grep,Edit,Write`) liefert
  ein schemagültiges `result.json`; ein Worker-Aufruf (`--allowedTools` mit
  `Edit,Write,Bash`) schreibt die Datei, führt `verify.sh` aus und bekommt
  `git stash` vom Headless-Guard blockiert — die Einstellungsdatei des Laufs
  wird also wirklich geladen und der Hook feuert. Damit ist die Sicherheitshülle
  belegt und nicht nur behauptet.
- Der Codex-Adapter ist **nicht** gegen das echte CLI gelaufen. Die lokale
  Installation ist defekt (`codex --version` bricht mit `ENOENT` ab). Geprüft
  sind der dokumentierte Aufruf und die Auswertung des Ereignisstroms gegen
  Fixtures; der erste echte Lauf steht aus. Genau diese kaputte Installation
  hat aber `doctor.sh` verifiziert: sie erscheint als Befund mit dem Text des
  CLI, die Prüfung läuft danach weiter und endet mit Exit 1.
- Die Aufrufgrenzen sind aus der Umgebung in `.agent/config.env` gewandert
  (`AGENT_RUNNER`, `AGENT_MODEL`, `AGENT_TIMEOUT_SECONDS`, `AGENT_MAX_TURNS`).
  `config.sh` kennt dafür jetzt drei Werttypen statt zwei: Zahl, Aufzählung,
  Zeichenkette. In der Umgebung bleiben nur die zwei Werte, die keine
  Projekteigenschaft sind: `AGENT_MAX_BUDGET_USD` (Entscheidung des Aufrufers)
  und `ORCHESTRATOR_RUNNER` (Testnaht).
- `runner.sh --check` ist ersatzlos entfallen; `scripts/doctor.sh` prüft
  stattdessen Werkzeuge, Konfiguration, den gewählten Runner und den
  Repository-Zustand. Die Prüfung liegt in `tests/integration/doctor.sh`, weil
  sie mehrere Skripte gegen ein Fixture fährt und keine Doku prüft.
- `.claude/settings.json` hat seine gesamte `allow`-Liste verloren, nicht nur
  die npm-Einträge. Ein Starterkit soll keine Rechte für den Bediener
  vorwegnehmen; übrig bleiben Hooks und Deny-Liste. Für Headless-Läufe ist das
  ohnehin folgenlos — dort gilt allein die Einstellungsdatei des Runners.
- Eine bewusste Abweichung von der Zielstruktur: `runner.sh` ist mit 428 Zeilen
  deutlich über den dort genannten 300. Zwei Adapter mit je eigenem Parser
  passen nicht in dieses Budget, und die Alternative wäre eine weitere Datei
  gewesen, die die Zielstruktur ebenso wenig kennt. Die Grenze sollte mit F9
  auf einen realistischen Wert gesetzt oder der Codex-Parser ausgelagert
  werden.
- Der Codex-Adapter meldet keine Kosten (`unknown`). Wer Budgets braucht, muss
  bis auf Weiteres `AGENT_RUNNER=claude` fahren; `--max-budget-usd` hat auf der
  Codex-Seite keine Entsprechung.

### F8 · Prüftor verschlanken

Branch `refactor/verify-gate` · Status: **gemergt**

Ziel: `verify-task.sh` ≤200 Zeilen, ein Ablauf: Befehle prüfen, ausführen,
Bericht schreiben.

Aufgaben:

- [x] Entfernen: Stufen-Taxonomie, `classify_command`, `run_planned_stage`, benannte
      Runner (`.agent/verification-runners`), Syntax-Stage (`bash -n`, `py_compile`),
      `touches`-Prüfung über `git status`
- [x] Übernehmen: `split_command`, `normalize_command`, `command_allowed`, `step`,
      `record_failure`, `write_report`, `failure_kind`
- [x] Default-Allowlist generisch; `.agent/verification-allowlist` als Beispiel
      ausliefern

Abnahme:

- [x] Tests: Metazeichen und fremde Präfixe abgewiesen; fehlender Befehl =
      Verifier-Fehler; Timeout = Verifier-Fehler; Fingerprints im Bericht

Review:

- `verify-task.sh` ist von 384 auf 198 Zeilen geschrumpft und hat nur noch einen
  Ablauf: jeden `acceptance`-Befehl prüfen, ausführen, eine Ergebniszeile
  schreiben. Der Bericht nennt statt sieben erfundener Stufen die tatsächlich
  gelaufenen Befehle (`- acceptance-2: TIMEOUT`). Die Stufen waren ohnehin
  geraten — `classify_command` hat `pytest` zu `unit` und alles Unbekannte zu
  `acceptance` erklärt, ohne dass irgendjemand die Einteilung gelesen hat.
- Die Ledger-Stufe ist ersatzlos entfallen, und das ist kein Loch: Der
  Orchestrator validiert den ganzen Graphen beim Laufstart, und das Status-Gate
  validiert den Task bei **jedem** Schreibvorgang. Ein `done` mit kaputtem
  Ledger war also nie nur über das Prüftor zu haben.
- Ebenso entfallen ist die `touches`-Prüfung über `git status`. Sie war die
  zweite, schwächere Kopie der Umfangskontrolle: Der Orchestrator vergleicht
  Manifeste, setzt Pfade ausserhalb des Umfangs zurück und stellt sie unter
  `.agent-runs/<run>/quarantine/`. Die Prüfung im Prüftor lief zudem nur mit
  vorhandenem `HEAD` und hat den Befund als Produktfehler ausgewiesen, obwohl
  der Kandidat inhaltlich grün sein konnte.
- Die Syntax-Stufe (`bash -n` über `scripts/` und `tests/`, `py_compile` über
  alle `.py`) war der einzige Rest, der einen Stack vorwegnahm. Sie gehört in
  das `scripts/verify.sh` des jeweiligen Projekts, nicht in das Gerüst.
- Benannte Runner (`.agent/verification-runners`, `runner:name`) sind weg. Ein
  Task kann seinen Befehl direkt in `acceptance` schreiben; die Indirektion hat
  nur eine zweite Konfigurationsdatei und ein zweites Parserformat gekostet.
- Die Standard-Allowlist ist generisch geworden: `./scripts/verify.sh npm pytest
  go cargo make` statt der bisherigen Python-Schlagseite (`ruff`, `mypy`,
  `python -m …`). Verglichen wird jetzt einheitlich auf Wortgrenze — `go`
  erlaubt `go test`, aber nicht `gofmt`. Wer `ruff` braucht, trägt es in
  `.agent/verification-allowlist` ein; die Datei liegt als kommentiertes
  Beispiel mit genau den Standardwerten bei und ersetzt die eingebaute Liste
  vollständig.
- Eine Verhaltensänderung, die auffallen kann: Das Pflicht-`./scripts/verify.sh`
  läuft jetzt in Ledger-Reihenfolge, nicht mehr am Ende einer Stufenkette. Nennt
  ein Task es nicht selbst, wird es angehängt.
- Das Human Gate erscheint nicht mehr im Prüfbericht. Es hat dort nie
  entschieden; `status.sh` verlangt für `human_review: true` weiterhin die
  ausdrückliche Freigabe, und genau das prüft die Suite.
- `docs/ARCHITECTURE.md` ist im Abschnitt «Verification Gateway» mitgezogen
  worden, weil die alte Beschreibung sonst aktiv falsch gewesen wäre. Die
  vollständige Doku-Runde bleibt F9.

### F9 · Dokumentation

Branch `docs/architecture` · Status: **geprüft**

Ziel: Eine normative Beschreibung, ein kurzes README, ein CLAUDE.md für die
interaktive Sitzung, ein generischer Init-Prompt. Vollständigkeit gegen den Code.

Aufgaben:

- [x] `docs/ARCHITECTURE.md`: Rollenmatrix, Schreibbereiche, Ablauf, Eskalation,
      Runner und ihre Sicherheitshüllen, Config-Schlüssel, Schemata, Ledger-Schema,
      Manifest/Snapshot, Sperren
- [x] `README.md` (129 Z.): Zweck, Voraussetzungen, `doctor`, Initialisierung, drei
      Hauptbefehle, `task.sh`, Sicherheit, Verweis auf ARCHITECTURE.md
- [x] `CLAUDE.md`: Betriebsregeln der interaktiven Sitzung, Zeile 1 korrigiert
- [x] `docs/prompts/init.md`: generisch, Projektbeschreibung in der Datei,
      Pflichtüberschriften und erlaubte Werte ausdrücklich
- [x] `docs/templates/handoff.md` mit Abschnitt «Laufbeleg»
- [x] README-Audit: jedes Skript, jedes Flag, jeder Config-Schlüssel dokumentiert

Abnahme:

- [x] `tests/lint/check-docs.sh`: jeder in README/ARCHITECTURE genannte Pfad und
      jedes Flag existiert; jedes Skript mit `--help` ist genannt
- [ ] Besitzer liest README und ARCHITECTURE einmal durch

Review:

- Zwei Umbenennungen bringen die Ablage auf die Zielstruktur:
  `docs/templates/initializer-prompt.md` → `docs/prompts/init.md` und
  `docs/templates/handoff-template.md` → `docs/templates/handoff.md`; fünfzehn
  Verweise in README, ARCHITECTURE, `docs/state/*` und der Suite sind
  nachgezogen. `init.md` liegt damit neben den drei Rollenverträgen, ist aber
  selbst keine Rolle — `context.sh` kennt weiterhin nur `manager`, `worker` und
  `finalizer`, und der Kopf der Datei sagt das ausdrücklich.
- `docs/ARCHITECTURE.md` ist von 401 auf 541 Zeilen gewachsen und trägt jetzt
  die fünf Dinge, die vorher nur im Code standen: ein **Skriptinventar** mit
  jedem Skript und jeder Option, die **vollständige Tabelle aller dreizehn
  Konfigurationsschlüssel** (bisher waren vier davon erklärt), das
  **Task-Schema** mit erlaubten Werten und Pflichtabschnitten, das
  **Berichtsschema** des Prüftors und einen Abschnitt **Sperren**. Der Satz
  «Rohfassung: mit F9 wird diese Datei die normative Beschreibung» ist weg; die
  Datei ist jetzt die normative Beschreibung.
- `README.md` ist von 201 auf 129 Zeilen geschrumpft. Weggefallen ist der Block
  «Die Infrastruktur — wie Rollen zusammenhängen»: er beschrieb sieben Skripte
  ein zweites Mal, neben ARCHITECTURE, und musste damit doppelt gepflegt
  werden. Neu sind der Abschnitt zu den zwei menschlichen Statuswechseln und
  die Liste der Werkzeugvoraussetzungen.
- Zwei stille Falschaussagen in `CLAUDE.md` sind behoben: der Laufstand liegt
  seit F4 unversioniert unter `.agent-runs/` und nicht unter `docs/state/`, und
  `state-summary.sh` gibt zwei Zeilen aus, nicht drei. Zeile 1 heisst nicht mehr
  `# project-template`.
- Der mit F1 vorgefundene Verweis auf `tests/orchestrator/` in der
  Initialisierung ist behoben. Der Prompt zählt jetzt Frontmatterfelder,
  erlaubte Werte und die vier Pflichtüberschriften einer Task-Datei wörtlich
  auf, ebenso die Pflichtabschnitte von `goal.md`, `plan.md` und `notes.md`.
  Neu ist der Hinweis auf `.agent/verification-allowlist`: wer einen Stack mit
  anderen Prüfwerkzeugen aufsetzt, dessen `acceptance`-Befehle würde das
  Prüftor sonst schweigend abweisen.
- `check-docs.sh` prüft jetzt beide Richtungen und ist von 108 auf 191 Zeilen
  gewachsen (91 → 107 Zusicherungen). Neu sind vier Struktur-Zusicherungen, die
  nicht auf eine Wortliste setzen: jeder in README/ARCHITECTURE genannte Pfad
  existiert, jedes dort genannte Flag kommt in einem Skript des Kits vor (auch
  die der beiden Anbieter-CLIs), jedes Skript unter `scripts/` und `tests/run.sh`
  ist genannt, und jeder Schlüssel aus `.agent/config.env` ist in ARCHITECTURE
  erklärt. Alle vier sind negativ getestet: ein erfundener Pfad, ein erfundenes
  Flag, ein umbenanntes Skript und ein umbenannter Schlüssel machen die Suite
  jeweils rot.
- Zwei Ausnahmen trägt die Pfadprüfung, beide kommentiert: `docs/tasks/017.md`
  ist das laufende Beispiel, `docs/tasks/.status-lock` existiert nur während
  eines Statuswechsels.
- Die Zielstruktur oben ist auf den gebauten Stand nachgeführt. Die Budgets sind
  jetzt die gemessenen Grössen; damit ist auch die aus F7 offene Frage
  beantwortet: `runner.sh` bleibt mit 428 Zeilen ein Adapter, der Codex-Parser
  wird nicht ausgelagert. Eine zusätzliche Datei hätte die Zeilen nur verschoben.
- Zusicherungen 677 → 693.
- Ein einzelner Suite-Lauf während der Arbeit war rot (1 von 28 Dateien, 641
  statt 693 Zusicherungen); welche Datei, ist wegen eines abgeschnittenen
  Protokolls nicht festgehalten. Dreizehn Läufe danach waren grün, reproduzieren
  liess es sich nicht. Der Punkt bleibt offen und ist nicht behoben.
- Die letzte Abnahme — der Besitzer liest README und ARCHITECTURE durch — war
  beim Merge noch offen; der Besitzer hat die Freigabe vorher erteilt.

---

## Verifikation des Gesamtumbaus

- Nach jedem Feature: `tests/run.sh` grün; `bash -n` über alle Skripte;
  `./scripts/validate-ledger.sh` grün auf leerem Starter.
- Leistungsnachweis (Scratch-Kopie, 60 Tasks, 2000 Dateien in `node_modules`):
  `validate-ledger` < 1 s, `next-tasks` < 1 s, Manifest < 0,5 s, `--dry-run` < 3 s.
- Echter Lauf durch den Besitzer (eigenes Terminal, Kosten): `doctor.sh`, dann
  `orchestrate.sh --task 001` mit `AGENT_RUNNER=claude` auf einem Mini-Projekt (ein
  mechanischer Task, ein `verify.sh` mit einem Test). Codex-Lauf nach Reparatur der
  Installation (`npm i -g @openai/codex`).

## Abschluss-Review

**Was erreicht wurde.** Aus einem Kit mit Turnier-Modus, zwei Konfigurations-
formaten, zwei Textparsern und einer kursorientierten Dokumentation ist ein
Starterkit mit einem Ablauf geworden: ein Router, drei Modelrollen, ein Prüftor,
ein Status-Gate, zwei austauschbare Runner. Jede Grenze steht an genau einer
Stelle, und die Suite prüft sie nach Verhalten statt nach Wortlaut.

**Zeilenbilanz** (`.sh`, `.md`, `.json`, ohne diese Plandatei), gemessen gegen
den Stand vor F0:

| Bereich                   | vorher | nachher |
| ------------------------- | ------ | ------- |
| `scripts/`                | 4333   | 3170    |
| `docs/` + README + CLAUDE | 1668   | 1241    |
| `tests/`                  | 2045   | 2936    |
| **gesamt**                | 8367   | 7385    |

Produktcode und Dokumentation sind um rund 1600 Zeilen leichter, die Testsuite
um 900 Zeilen schwerer — 417 → 693 Zusicherungen. Genau das war die Absicht.

**Abweichungen vom Plan, alle bewusst und in den Feature-Reviews begründet.**
`scripts/agent/` statt `scripts/lib/`, mit `status.sh` darin (F6). Eine siebte
Bibliotheksdatei `rolecall.sh` für den bewachten Rollenaufruf (F6). Drei
Zeilenbudgets über der ursprünglichen Schätzung: `context.sh` 291 statt 200,
`runner.sh` 428 statt 300, `validate-ledger.sh` 257 statt 200. Die Zielstruktur
ist mit F9 auf die gemessenen Werte nachgeführt statt weiter danebenzustehen.

**Offene Punkte.**

- Der echte Lauf durch den Besitzer steht aus: `doctor.sh`, dann
  `orchestrate.sh --task 001` mit `AGENT_RUNNER=claude` auf einem Mini-Projekt.
  Die Suite fährt ausschliesslich den Fake Runner; kein Test hat je ein echtes
  Modell gerufen.
- Der Codex-Weg ist ungeprüft, solange `npm i -g @openai/codex` nicht läuft.
  `doctor.sh` meldet das als Befund, nicht als Absturz.
- Codex meldet keine Kosten (`unknown`); wer Budgets braucht, fährt
  `AGENT_RUNNER=claude` mit `AGENT_MAX_BUDGET_USD`.
- Der Besitzer hat README und ARCHITECTURE noch nicht durchgelesen; das ist die
  letzte offene Abnahme von F9.
