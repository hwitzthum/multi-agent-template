# Adaptives Agentensystem für Projektarbeit

Dieses Template hält Ziel, Aufgaben, Prüfungen und Übergaben in Dateien fest.
Es wählt für jede Aufgabe den kleinsten sicheren Arbeitsmodus: eine einfache
Änderung kann direkt bearbeitet werden, eine komplexe oder festgefahrene
Aufgabe erhält zusätzliche Planung, Prüfung oder eine unabhängige zweite
Lösung. Mehrere Agenten sind deshalb eine Möglichkeit, nicht der Standard für
jede Aufgabe.

## Vor dem ersten Lauf

Das Projekt braucht ein eigenes Git-Repository mit einem ersten Commit. Wer die
GitHub-Vorlage verwendet und sie klont, hat diesen Ausgangsstand bereits. Ein
ZIP-Download genügt nicht: Manifeste, Snapshot-Rücksetzung und die
Fresh-Versuche benötigen die Git-Historie.

Danach wird das Projekt einmalig mit
`docs/templates/initializer-prompt.md` eingerichtet: Projektbeschreibung
eintragen, Prompt in eine eigene Sitzung kopieren.

## Die drei Hauptbefehle

```bash
# 1. Nächste ausführbare Aufgaben anzeigen
./scripts/next-tasks.sh

# 2. Die nächste Aufgabe kontrolliert bearbeiten
./scripts/orchestrate.sh --next

# 3. Projektstand und nächsten Handlungsbedarf erklären
./scripts/state-summary.sh
```

Vor einem echten Lauf zeigt `./scripts/orchestrate.sh --next --dry-run` ohne
Produktänderung den vom Router gewählten Modus und die geplanten Rollen. Eine bestimmte
Aufgabe startet mit `./scripts/orchestrate.sh --task 017`. Die globale
Projektprüfung bleibt immer `./scripts/verify.sh`.

Der Router entscheidet pro Aufgabe, wie viel Begleitung sie braucht, und diese
Entscheidung wird direkt ausgeführt: Routine läuft mit einem Worker, Fachlogik
mit Korrekturschleife, offene oder riskante Aufgaben im Manager-Worker-Loop,
festgefahrene mit zwei unabhängigen Lösungen. Eine bewusste Vorgabe ist über
`--mode` oder `orchestration:` im Task möglich, kann aber nie unter das
Sicherheitsminimum senken. Offene Aufgaben sowie Text, Optik und Rechtliches
bleiben unter menschlicher Aufsicht.

## Die Infrastruktur — wie Rollen zusammenhängen

Hinter den Rollen laufen mehrere Skripte, die den Betriebsverkehr regeln:

### `scripts/agent/runner.sh` — Der Modell-Adapter

Wird von `orchestrate.sh` aufgerufen. Nimmt das Kontextpaket, ruft `claude -p` mit dem
JSON-Schema der Rolle auf (das Modell muss exakt die Vertragsfelder liefern), überträgt
das Ergebnis ins geprüfte Zeilenformat und protokolliert Modell, Tokens und Kosten aus
der Antwort. Die vollständige Antwort bleibt lokal als `.json` im Laufordner. Ein neuer
Anbieter-Aufruf würde nur diesen Adapter ändern — die Orchestrierung bleibt gleich.

### `scripts/agent/context.sh` — Der Kontext-Bauer

Baut für jede Rolle nur die erforderlichen Abschnitte: Goal, Task, Plan, Notes,
Verifikation, Code. Jeder Abschnitt hat ein Zeichenbudget. Code erhält nur den
verbleibenden Platz. Ein Fresh-Versuch bekommt bewusst keine Notes oder früheren Fehler.

Kontexte sind schreibgeschützt und inhaltsadressiert — derselbe Inhalt erzeugt dieselbe
Datei. Das ist die Basis für zuverlässiges Caching und Reproduzierbarkeit.

### `scripts/agent/route.sh` — Der Router

Entscheidet pro Task: `single` (Worker allein), `verified` (Worker + Korrektur)
oder `managed` (Manager-Worker-Loop). Ein ausgeschöpftes Versuchslimit ergibt
`blocked`. Daneben erzwingt `scripts/agent/policy.sh` nur die Pfad- und
Schreibgrenzen der Rollen.

Eingaben: Task-Klasse (`mechanical`, `patterned`, `open`), die ausdrückliche
Vorgabe aus `orchestration` oder `--mode`, die bisherigen Versuche und die
Risiko-Signale (`high-risk`, `cross-component`, `repeated-failure`).

Ausgabe: der Modus. Es gilt `max(Basis, Rang der Versuche, Risiko-Minimum)`;
ein gesetztes Risiko-Signal hebt das Minimum auf `managed`.

Der Router wird durch `orchestrate.sh --next` aufgerufen und die Entscheidung **sofort
ausgeführt** — Sie sehen sie mit `--dry-run` vorher, ohne etwas zu verändern.

### `scripts/agent/ledger.sh` — Der Dateiverwalter

Liest und schreibt Task-Dateien, Goal, Plan, Notes — liest nur bekannte Felder aus
definiertem Frontmatter. Unbekannte Felder bleiben bestehen, werden aber nie als
Befehle interpretiert.

Jede Änderung wird zuerst in einer temporären Datei validiert und dann atomar
verschoben. Verhindert halbfertige Dateien bei Unterbrechung.

### `scripts/agent/output.sh` — Der Output-Validator

Prüft, dass ein Agenten-Output alle erwarteten Felder hat, keine zusätzlichen, und
dass der Inhalt nicht mehrdeutig ist. Nur gültige Output-Schemata landen im Ledger.

### `scripts/agent/status.sh` — Das Status-Gate

Einziger Schreibweg für Task-Status. Prüft: Alter Status erlaubt? Prüfbericht vorhanden
und grün? `human_review` benötigt explizite Freigabe?

Verhindert, dass ein Agent nur durch seine eigene Behauptung einen Task auf `done`
setzt. Status wechseln nur mit einem grünen Beleg.

### `scripts/agent/metrics.sh` — Die Laufmetriken

Erfasst pro finalisiertem Lauf: Klasse, Modus, Versuche, Tokens, Kosten, wie lange
es gedauert hat, ob die Prüfung grün war. Landet als Zeile in `docs/state/metrics.csv`.

Gibt einen schnellen Überblick: Welche Modi sind teuer? Welche Klassen fehlen oft?

### `scripts/agent/config.sh` — Die Limits

Lädt und validiert `.agent/config.env` — einfaches Dateiformat, kein Shellskript.
Bekannte Schlüssel, validierte Werte. Wird nie mit `source` oder `eval` ausgeführt.

Die Limits sind hart: Iterations-, Versuche-, No-Progress-, Kontext-, Timeout- und
Retry-Grenzen. Kein Agent kann das übergehen.

## Sicherheit: Was Claude nicht darf — mit Absicht

Das Template hat eingebaute Sperren. Claude (oder jeder Agent) darf **nicht**:

- **Etwas ins Internet hochladen** — `git push`, `curl`, `wget` sind blockiert.  
  Du selbst kontrollierst, was hochgeladen wird.

- **Dateien massenhaft löschen** — `rm -r…` für Ordner ist blockiert.

- **Ungespeicherte Arbeit verwerfen** — `git reset --hard`, `git checkout --`,
  `git clean`, `git restore` sind blockiert.  
  Ein Agent könnte sonst versehentlich einen Entwurf löschen.

- **Prüf-Hooks umgehen** — `git … --no-verify` ist blockiert, und vor jedem
  `git commit` muss `./scripts/verify.sh --quick` grün sein.

Diese Grenzen sind in `scripts/bash-guard.sh` und `scripts/commit-gate.sh`
definiert und greifen bei jedem Befehl, auch versteckt in einem längeren Befehl
oder hinter JSON-Steuerzeichen. Sie sind ein Stolperdraht, kein Sandkasten: Dinge
wie `node -e "fetch(…)"` oder ein git-Alias erfassen sie nicht. Die Skripte selbst
laden Ledger- und Agententext nie mit `source` oder `eval`. Du behältst die volle
Kontrolle: Ein `git push` führst du selbst aus.

## Weitere Befehle

```bash
./scripts/orchestrate.sh --next --dry-run   # Route, Limits und geplante Rollen ohne Änderung
./scripts/orchestrate.sh --resume           # pausierten oder fehlgeschlagenen Lauf fortsetzen
./scripts/validate-ledger.sh                # Task-Graph, Laufstand und Prüfbelege prüfen
```

## Wo der Stand liegt

- `docs/tasks/*.md` ist die einzige Aufgabenquelle.
- `docs/state/` enthält Ziel, Plan, Entscheidungen, Notizen und aktuelle
  Übergabe.
- `docs/verification/` enthält den letzten maschinellen Prüfbeleg.
- `.agent-runs/` enthält lokale Rohdaten und wird nicht versioniert.
- `docs/ARCHITECTURE.md` beschreibt den technischen Betriebs- und
  Sicherheitsvertrag für Maintainer.

`done` ist nur über das Verifikations-Gate möglich. Bei einer Aufgabe mit
menschlicher Prüfung führt ein grüner Maschinencheck zunächst zu `review`, nie
direkt zu `done`.
