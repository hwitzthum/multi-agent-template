# Umbauplan: Prompt-und-Script-Starterkit

Stand dieser Datei: 2026-09-06 · Planfassung 1 · Fortschritt wird hier gepflegt.

## Fortschrittsübersicht

Statuswerte: `offen` → `in Arbeit` → `umgesetzt` (Code fertig, Tests grün) →
`geprüft` (Abnahmekriterien belegt) → `gemergt` (Freigabe des Besitzers, in `main`).

| Nr  | Feature                                  | Branch                            | Status | Tests | Gemergt am |
| --- | ---------------------------------------- | --------------------------------- | ------ | ----- | ---------- |
| F0  | Verhaltensbenannte Testsuite mit Runner  | `test/behaviour-suite`            | gemergt | 417   | 2026-09-06 |
| F1  | Ballast entfernen                        | `chore/remove-ballast`            | gemergt | 400   | 2026-09-06 |
| F2  | Git-basierte Manifeste und Snapshot      | `perf/git-manifests`              | offen  | –     | –          |
| F3  | Turnier streichen, Fresh-Versuch, Router | `refactor/drop-tournament`        | offen  | –     | –          |
| F4  | Laufzustand unversioniert                | `refactor/run-state-unversioned`  | offen  | –     | –          |
| F5  | Ledger-Schema und Task-Kommandos         | `refactor/ledger-schema`          | offen  | –     | –          |
| F6  | JSON-Ergebnisse, drei Rollen, Eskalation | `refactor/json-results-and-roles` | offen  | –     | –          |
| F7  | Zwei Runner: Claude und Codex            | `feat/codex-runner`               | offen  | –     | –          |
| F8  | Prüftor verschlanken                     | `refactor/verify-gate`            | offen  | –     | –          |
| F9  | Dokumentation                            | `docs/architecture`               | offen  | –     | –          |

Reihenfolge ist verbindlich (jedes Feature setzt auf dem vorigen auf). Vor jedem
Merge: Testsuite grün, Abnahmekriterien belegt, ausdrückliche Freigabe des Besitzers.

## Fortschrittsprotokoll

Neueste Einträge oben. Format: `Datum · Feature · was passiert ist · Beleg`.

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

```
.agent/config.env              MAX_GLOBAL_ITERATIONS MAX_TASK_ATTEMPTS MAX_NO_PROGRESS
                               CONTEXT_MAX_CHARS NOTES_MAX_CHARS VERIFY_TIMEOUT_SECONDS
                               AGENT_TIMEOUT_SECONDS AGENT_MAX_TURNS MAX_INFRA_RETRIES
                               AGENT_RUNNER AGENT_MODEL FINALIZER
.agent/verification-allowlist
.claude/settings.json          Hooks + Deny-Liste der interaktiven Sitzung
.claude/plan/umbau-starterkit.md   diese Datei
scripts/
  orchestrate.sh (≤400 Z.)  verify-task.sh (≤200)  validate-ledger.sh (≤200)
  status.sh (≤90)  task.sh (≤60)  next-tasks.sh  state-summary.sh  doctor.sh
  verify.sh (Projekt-Platzhalter)  bash-guard.sh  commit-gate.sh
  lib/ common.sh (≤150) ledger.sh (≤200) context.sh (≤200) runner.sh (≤300)
       route.sh (≤40) policy.sh  schemas/*.json
docs/
  ARCHITECTURE.md   README.md (Wurzel)   CLAUDE.md (Wurzel)
  prompts/ manager.md worker.md finalizer.md init.md
  templates/ task.md handoff.md
  state/ goal.md plan.md notes.md decisions.md handoff.md
  tasks/   verification/latest.md
tests/ run.sh lib.sh fixture.sh fake-runner.sh unit/ integration/ e2e/ lint/
```

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

| Was                       | Dateien                                                    |
| ------------------------- | ---------------------------------------------------------- |
| Kursmaterial              | `docs/KURSANLEITUNG.md`                                    |
| Landingpage-Profil        | `docs/profil/**` (7), `docs/briefs/`                       |
| Feature-Liste             | `docs/state/features.md`                                   |
| Wartungs- und Hilfsskript | `migrate-tasks.sh`, `autoformat.sh`, `archive-notes.sh`, `agent-metrics.sh` |
| Tests dazu                | `tests/integration/{notes-archive,task-migration}.sh`      |

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

Branch `perf/git-manifests` · Status: **offen**

Ziel: Manifeste in Millisekunden statt Sekunden, `.gitignore` gilt, Manipulation
durch Worker ausgeschlossen, Wiederherstellung aus Snapshot möglich.

Aufgaben:

- [ ] `agent_repo_manifest`, `agent_product_manifest`, `ledger_candidate_fingerprint`
      auf `git ls-files -z -co --exclude-per-directory=.gitignore` +
      `git hash-object -w --stdin-paths`
- [ ] Einträge `missing` (gelöscht), `symlink` (Modus 120000), ignorierte neue Pfade
      nur mit Namen; `.git/hooks/*`, `.git/config`, `.git/info/exclude` aufnehmen
- [ ] Vorher-Manifest bis zum Nachher-Manifest ausserhalb des Arbeitsbaums halten
- [ ] `agent_snapshot_restore <manifest> <pfad…>`: Blob zurückschreiben oder neue
      Datei in Quarantäne verschieben
- [ ] Validator: Dateiname `<id>.md` == `id`; `ledger_task_path_by_id` → `[ -f ]`
- [ ] `agent_manifest_changes`, Masking-awk, `ledger_verifier_fingerprint` unverändert
      übernehmen

Abnahme:

- [ ] Scratch-Kopie (60 Tasks, 2000 Dateien in `node_modules`): Manifest < 0,5 s,
      `validate-ledger` < 1 s, `next-tasks` < 1 s
- [ ] Tests: gitignored unsichtbar; neue untracked sichtbar; gelöschte sichtbar; neue
      ignorierte Namen sichtbar (`.env`); Restore stellt geänderte Datei her und
      quarantänisiert neue; Besitzer-Dirt in derselben Datei überlebt

Review: –

### F3 · Turnier streichen, Fresh-Versuch, Router

Branch `refactor/drop-tournament` · Status: **offen**

Ziel: Ein Eskalationspfad `single → verified → managed → blocked`, Fresh als
Kontextvariante mit Snapshot-Rücksetzung, Router ohne Magie.

Aufgaben:

- [ ] Entfernen: `scripts/agent/candidates.sh`, Rolle `reviewer`, `managed_fresh_loop`,
      `run_candidate_worker`, `verify_isolated_candidate`, `.git`-Tausch,
      Kandidatenbelege in `context.sh`
- [ ] `lib/route.sh` (Funktion, ≤40 Z.): Klasse → Basismodus, Override, Versuche →
      Rang, `risk_flags` → Minimum `managed`; kein `--record`, keine Signale, keine
      Keyword-Heuristik, kein `--escalate-from`
- [ ] Feld `fresh_perspective` entfernen; `risk_flags` auf
      `high-risk|cross-component|repeated-failure`
- [ ] Fresh-Versuch: `touches` per `agent_snapshot_restore` auf Laufstart, Kontext ohne
      Notizen/Vorbericht
- [ ] `path_in_task_scope`, `check_role_changes` übernehmen; bei Verstoss Restore +
      Abbruch

Abnahme:

- [ ] Router-Tabelle als Test: alle Klassen × Overrides × Versuche × Flags
- [ ] Test: Fresh-Versuch startet vom Snapshot und Kontext enthält keine Notizen
- [ ] Test: Out-of-Scope-Änderung wird zurückgesetzt, Lauf stoppt, Ledger gültig

Review: –

### F4 · Laufzustand unversioniert

Branch `refactor/run-state-unversioned` · Status: **offen**

Ziel: Kein Lauf macht den Git-Stand ausserhalb der fachlichen Belege schmutzig;
kein Resume, keine Checkpoints, kein Metrik-Subsystem.

Aufgaben:

- [ ] Entfernen: `scripts/agent/metrics.sh`, `docs/state/metrics.csv`,
      `docs/state/current-run.md`, `--resume`, `checkpoint_*`, CSV-Prüfung im Validator
- [ ] Laufzustand in `.agent-runs/<run>/run.env`; `metadata.env` pro Aufruf bleibt die
      Metrik; einfache `.agent-runs/metrics.csv` (eine Zeile pro Lauf, append-only)
- [ ] Invariante «höchstens ein `in_progress`» in `validate_task_set`
- [ ] EXIT-Trap: nie `in_progress` hinterlassen; Stale-Run beim Start auf `todo`
- [ ] `--dry-run` nur Routenausgabe, keine Nebenwirkung
- [ ] `state-summary.sh` auf Prüfstand + offene Arbeit (2–3 Zeilen)
- [ ] Dirty-Check ignoriert `docs/state`, `docs/tasks`, `docs/verification`

Abnahme:

- [ ] Nach einem grünen Fake-Lauf sind nur Task, Prüfbericht, Handoff geändert
- [ ] Test: abgebrochener Lauf (kill) hinterlässt kein `in_progress`; Stale-Lock wird
      übernommen; zweiter Orchestrator wird abgewiesen

Review: –

### F5 · Ledger-Schema und Task-Kommandos

Branch `refactor/ledger-schema` · Status: **offen**

Ziel: Schlankes Frontmatter, schneller Parser, menschliche Übergänge als Kommandos.

Aufgaben:

- [ ] Felder entfernen: `features`, `last_verification`, `max_attempts`, `route_*`,
      `PROMPT_VERSION` (Config); Feld-Whitelist in `ledger.sh` entfernen
- [ ] Ein awk-Durchlauf pro Datei (`key<TAB>value`), Bash-3.2-kompatibel
- [ ] `status.sh`: Übergangstabelle, CAS-Prüfung, Human-Gate übernehmen; neu
      `blocked→todo` nur mit `--human-approved`; Grünprüfung über
      `docs/verification/<id>.md`
- [ ] `verify-task.sh` schreibt `docs/verification/<id>.md` + `latest.md`; `history/`
      und `notes-archive/` entfallen
- [ ] `scripts/task.sh reopen N | approve N`
- [ ] `docs/templates/task.md` an das Schema anpassen; Validator an Schema und
      Pflichtabschnitte anpassen

Abnahme:

- [ ] Tests: `done` nur mit aktuellen Fingerprints; Änderung an `touches`-Datei oder
      `verify.sh` widerruft; `review`-Pfad; `reopen`/`approve`
- [ ] `validate-ledger` mit 60 Tasks < 1 s

Review: –

### F6 · JSON-Ergebnisse, drei Rollen, Eskalation

Branch `refactor/json-results-and-roles` · Status: **offen**

Ziel: Der Orchestrator wird auf ≤400 Zeilen mit einem klaren Ablauf; drei Prompts;
ein Format.

Aufgaben:

- [ ] `lib/schemas/{manager,worker,finalizer}.json`; Runner schreibt `result.json`;
      `output.sh` löschen; Prüfung mit `jq -e`
- [ ] `docs/prompts/{manager,worker,finalizer}.md` (Rollenvertrag, Schreibbereich,
      Abbruchregeln, Ausgabeformat als JSON-Beispiel mit allen Feldern)
- [ ] Manager mit Steuerfeld-Schutz (`task_control_snapshot`) und Regel «neue Tasks
      `todo/0`»; `plan_is_placeholder` weg
- [ ] `run_role` mit Infra-Retry (`MAX_INFRA_RETRIES`), Manifest vor/nach,
      Scope-Prüfung, Restore
- [ ] Versuchsschleife mit Eskalation; `failure_kind=verifier` zählt nicht;
      No-Progress-Guard; `MAX_GLOBAL_ITERATIONS`
- [ ] `ask_human`: Frage in Task, `blocked/ASK_HUMAN`, kein Versuch
- [ ] Deterministischer Laufbeleg in `handoff.md` bei jedem Ende; Finalizer opt-in
      (`FINALIZER=llm`) ohne Arbeitskopie
- [ ] Headless-Rahmen in `context.sh`; Dateiliste statt Dateiinhalte; feste Budgets
- [ ] `append_failure_note`, `progress_fingerprint`, `agent_redact`,
      `agent_truncate_blocks`, `validate_metadata`, `write_metadata` übernehmen

Abnahme:

- [ ] Tests: single/verified/managed grün und rot; Eskalation genau eine Stufe pro
      rotem Versuch; Verifier-Fehler ohne Versuch; `ask_human` → `blocked`, nach
      `reopen` sieht der Manager die Antwort; ungültiges JSON stoppt, Ledger gültig;
      Infra-Retry für jede Rolle (Timeout, leer, ungültig); Laufbeleg bei
      grün/blocked/ask_human; Manager kann Steuerfelder nicht ändern
- [ ] `wc -l scripts/orchestrate.sh` ≤ 400

Review: –

### F7 · Zwei Runner: Claude und Codex

Branch `feat/codex-runner` · Status: **offen**

Ziel: `AGENT_RUNNER=claude|codex` mit identischem Ergebnisvertrag und jeweils
passender Sicherheitshülle.

Aufgaben:

- [ ] `lib/runner.sh`: Dispatch; Claude-Adapter (Flags wie im Zielentwurf,
      rollenabhängige Tools, `--restricted` für Manager/Finalizer)
- [ ] Runner-eigenes `--settings`-JSON: Deny-Liste, `bash-guard`-Hook,
      `claudeMdExcludes`
- [ ] Codex-Adapter: `codex exec --json --output-schema … --output-last-message …
    --sandbox workspace-write …`, JSONL-Parsing (`turn.completed.usage`,
      `turn.failed`), Prompt via stdin
- [ ] `config.sh`: String-Schlüssel (`AGENT_RUNNER`, `AGENT_MODEL`, `FINALIZER`),
      Runner-Grenzen aus Env in die Config
- [ ] `scripts/doctor.sh`: bash, git, jq, perl, gewählter Runner (`claude --version`
      mit `--json-schema`; `codex --version`), Repo-Zustand
- [ ] `bash-guard.sh`: Headless-Zusätze unter `AGENT_HEADLESS=1`
- [ ] `.claude/settings.json`: nur interaktive Hooks und Deny-Liste, keine Stack-Allowlist

Abnahme:

- [ ] Tests mit Fixtures: Claude-`result.json` (ok, Fehler, kein JSON) und
      Codex-JSONL (ok, `turn.failed` ohne Datei) liefern korrekte `metadata.env`
- [ ] `doctor.sh` meldet die defekte Codex-Installation als Befund, nicht als Absturz
- [ ] `doctor.sh` ersetzt die mit F0 gestrichene Umgebungsprüfung `runner.sh --check`
      und ist wieder in der Suite (Stufe `lint` oder `integration`)
- [ ] Vermerk im Commit: Codex-Adapter nicht gegen echtes CLI geprüft

Review: –

### F8 · Prüftor verschlanken

Branch `refactor/verify-gate` · Status: **offen**

Ziel: `verify-task.sh` ≤200 Zeilen, ein Ablauf: Befehle prüfen, ausführen,
Bericht schreiben.

Aufgaben:

- [ ] Entfernen: Stufen-Taxonomie, `classify_command`, `run_planned_stage`, benannte
      Runner (`.agent/verification-runners`), Syntax-Stage (`bash -n`, `py_compile`),
      `touches`-Prüfung über `git status`
- [ ] Übernehmen: `split_command`, `normalize_command`, `command_allowed`, `step`,
      `record_failure`, `write_report`, `failure_kind`
- [ ] Default-Allowlist generisch; `.agent/verification-allowlist` als Beispiel
      ausliefern

Abnahme:

- [ ] Tests: Metazeichen und fremde Präfixe abgewiesen; fehlender Befehl =
      Verifier-Fehler; Timeout = Verifier-Fehler; Fingerprints im Bericht

Review: –

### F9 · Dokumentation

Branch `docs/architecture` · Status: **offen**

Ziel: Eine normative Beschreibung, ein kurzes README, ein CLAUDE.md für die
interaktive Sitzung, ein generischer Init-Prompt. Vollständigkeit gegen den Code.

Aufgaben:

- [ ] `docs/ARCHITECTURE.md`: Rollenmatrix, Schreibbereiche, Ablauf, Eskalation,
      Runner und ihre Sicherheitshüllen, Config-Schlüssel, Schemata, Ledger-Schema,
      Manifest/Snapshot, Sperren
- [ ] `README.md` (~120 Z.): Zweck, Voraussetzungen, `doctor`, Initialisierung, drei
      Hauptbefehle, `task.sh`, Sicherheit, Verweis auf ARCHITECTURE.md
- [ ] `CLAUDE.md`: Betriebsregeln der interaktiven Sitzung, Zeile 1 korrigiert
- [ ] `docs/prompts/init.md`: generisch, Projektbeschreibung in der Datei,
      Pflichtüberschriften und erlaubte Werte ausdrücklich
- [ ] `docs/templates/handoff.md` mit Abschnitt «Laufbeleg»
- [ ] README-Audit: jedes Skript, jedes Flag, jeder Config-Schlüssel dokumentiert

Abnahme:

- [ ] `tests/lint/check-docs.sh`: jeder in README/ARCHITECTURE genannte Pfad und
      jedes Flag existiert; jedes Skript mit `--help` ist genannt
- [ ] Besitzer liest README und ARCHITECTURE einmal durch

Review: –

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

Wird nach F9 ausgefüllt: Was wurde erreicht, was weicht vom Plan ab und warum,
Zeilenbilanz vorher/nachher, offene Punkte.
