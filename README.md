  # Adaptives Agentensystem für Projektarbeit

Dieses Template hält Ziel, Aufgaben, Prüfungen und Übergaben in Dateien fest.
Es wählt für jede Aufgabe den kleinsten sicheren Arbeitsmodus: eine einfache
Änderung kann direkt bearbeitet werden, eine komplexe oder festgefahrene
Aufgabe erhält zusätzliche Planung, Prüfung oder einen zweiten Anlauf ohne
Vorgeschichte. Mehrere Agenten sind deshalb eine Möglichkeit,
nicht der Standard für jede Aufgabe.

Der technische Betriebs- und Sicherheitsvertrag steht in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Dieses README ist die
Bedienanleitung.

## Vor dem ersten Lauf

Das Projekt braucht ein eigenes Git-Repository mit einem ersten Commit. Wer die
GitHub-Vorlage verwendet und sie klont, hat diesen Ausgangsstand bereits. Ein
ZIP-Download genügt nicht: Manifeste, Snapshot-Rücksetzung und die
Fresh-Versuche beziehen Dateiliste und Hashes von Git. Ausser Bash brauchen die
Skripte nur `git`, `awk`, `sed`, `shasum`, `jq` und `perl`; dazu das CLI des
gewählten Runners (`claude` oder `codex`).

```bash
./scripts/doctor.sh    # Werkzeuge, Konfiguration, Runner, Repository-Zustand
```

Jede Zeile ist `OK`, `BEFUND` (behebbar und blockierend) oder `HINWEIS`; ein
kaputt installiertes CLI erscheint als Befund mit Text, nicht als Absturz.

Danach wird das Projekt einmalig mit [`docs/prompts/init.md`](docs/prompts/init.md)
eingerichtet: Projektbeschreibung unten in die Datei eintragen, dann den ganzen
Prompt in eine eigene Sitzung kopieren. Der Initializer legt Ziel, Plan, die
ersten Aufgaben und das Projektskelett an — und ersetzt `scripts/verify.sh`
durch die Prüfung des Produkts.

## Die drei Hauptbefehle

```bash
./scripts/next-tasks.sh          # 1. Nächste ausführbare Aufgaben anzeigen
./scripts/orchestrate.sh --next  # 2. Die nächste Aufgabe kontrolliert bearbeiten
./scripts/state-summary.sh       # 3. Prüfstand und offene Arbeit in zwei Zeilen
```

Vor einem echten Lauf zeigt `./scripts/orchestrate.sh --next --dry-run` ohne
jeden Schreibzugriff den vom Router gewählten Modus, die Limits und die
geplanten Rollen. Eine bestimmte Aufgabe startet mit
`./scripts/orchestrate.sh --task 017`; ein bewusst schmutziger Arbeitsbaum
braucht zusätzlich `--allow-dirty`. Die globale Projektprüfung bleibt immer
`./scripts/verify.sh` (`--quick` für den Commit-Hook, `--deep` für alles).

Der Router entscheidet pro Aufgabe, wie viel Begleitung sie braucht, und diese
Entscheidung wird sofort ausgeführt: Routine läuft mit einem Worker (`single`),
Fachlogik mit Korrekturschleife (`verified`), offene oder riskante Aufgaben im
Manager-Worker-Loop (`managed`). Jede rote Prüfung hebt die Stufe um genau eine
Position; der letzte erlaubte Versuch läuft ohne Vorgeschichte. Eine bewusste
Vorgabe ist über `--mode` oder `orchestration:` im Task möglich, kann aber nie
unter das Sicherheitsminimum senken. Offene Aufgaben sowie Text, Optik und
Rechtliches bleiben unter menschlicher Aufsicht.

## Die zwei menschlichen Statuswechsel

```bash
./scripts/task.sh reopen 017    # blockierte Aufgabe wieder öffnen
./scripts/task.sh approve 017   # Aufgabe im Review freigeben
```

Kein Agent kann diese beiden auslösen. Eine Aufgabe steht auf `blocked`, wenn
der Lauf eine Entscheidung braucht; die Frage steht dann unter `# Offene Frage`
in der Task-Datei. Antwort dort hineinschreiben, dann `reopen`, dann wieder
`./scripts/orchestrate.sh --task 017`. `approve` schliesst eine Aufgabe ab, die
nach grünen Tests auf `review` wartet, weil sie `human_review: true` oder
`class: open` trägt.

## Sicherheit: Was ein Agent nicht darf — mit Absicht

Das Template hat eingebaute Sperren. Ein Agent darf **nicht**:

- **Etwas ins Internet hochladen** — `git push`, `curl`, `wget` sind blockiert.
  Du selbst kontrollierst, was hochgeladen wird.
- **Dateien massenhaft löschen** — `rm -r…` für Ordner ist blockiert.
- **Ungespeicherte Arbeit verwerfen** — `git reset --hard`, `git checkout --`,
  `git clean`, `git restore` sind blockiert.
- **Prüf-Hooks umgehen** — `git … --no-verify` ist blockiert, und vor jedem
  `git commit` muss `./scripts/verify.sh --quick` grün sein.

Im Headless-Lauf des Orchestrators kommen Sperren dazu, die interaktiv nicht
gelten: `git commit`, `merge`, `rebase`, `stash`, `worktree`, `git branch -D`,
`pip install` und `npm publish`. Historie und Zweige führt der Orchestrator und
am Ende du — nicht der Agent.

Diese Grenzen stehen in `scripts/bash-guard.sh` und `scripts/commit-gate.sh`
und greifen bei jedem Befehl, auch versteckt in einem längeren Befehl oder
hinter JSON-Steuerzeichen. Sie sind ein Stolperdraht, kein Sandkasten: Dinge wie
`node -e "fetch(…)"` oder ein git-Alias erfassen sie nicht. Die Skripte selbst
laden Ledger- und Agententext nie mit `source` oder `eval`.

Ein Agent kann eine Aufgabe auch nicht durch seine eigene Behauptung
abschliessen: `done` und `review` setzt allein das Status-Gate, und nur mit
einem aktuellen grünen Prüfbericht. Bei einer Aufgabe mit menschlicher Prüfung
führt ein grüner Maschinencheck zunächst zu `review`, nie direkt zu `done`.

Zwei Runner stehen zur Wahl, `AGENT_RUNNER=claude` oder `AGENT_RUNNER=codex` in
`.agent/config.env`. Beide liefern denselben Ergebnisvertrag, aber eine andere
Sicherheitshülle: Claude bekommt rollenabhängige Werkzeuge und eine eigene
Einstellungsdatei mit Deny-Liste und `bash-guard`-Hook; Codex läuft in der
Sandbox seines CLI (`--sandbox workspace-write`, Netz aus). Kosten meldet codex
nicht. Die Grenzen des Laufs — Iterationen, Versuche, Zeitlimits, Modell —
stehen ebenfalls in `.agent/config.env`; alle dreizehn Schlüssel sind in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) erklärt.

## Weitere Befehle

```bash
./scripts/validate-ledger.sh   # Task-Graph, Ledger-Schema und Prüfbelege prüfen
./scripts/verify-task.sh 017   # nur die Akzeptanzbefehle einer Aufgabe fahren
./tests/run.sh                 # Testsuite des Kits (--fast lässt e2e weg)
```

## Wo der Stand liegt

- `docs/tasks/*.md` ist die einzige Aufgabenquelle; eine Aufgabe pro Datei, der
  Dateiname ist die ID. Vorlage: `docs/templates/task.md`.
- `docs/state/` enthält Ziel, Plan, Entscheidungen, Notizen und die aktuelle
  Übergabe (Vorlage: `docs/templates/handoff.md`).
- `docs/verification/<id>.md` ist der Prüfbeleg je Aufgabe; `latest.md` ist die
  Kopie des zuletzt geschriebenen Berichts.
- `.agent-runs/` enthält Laufzustand, Rohdaten und `metrics.csv` (eine Zeile
  pro Lauf) und wird nicht versioniert. Ein Lauf ist zwischen zwei Aufrufen
  zustandslos; es gibt kein Fortsetzen.
