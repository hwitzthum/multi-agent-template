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

---

## Was ist dieses System? (Überblick für Laien)

Stell dir vor, du hast ein großes Projekt mit vielen Aufgaben und möchtest KI-Agenten bei der Arbeit nutzen. Dieses System ist wie ein **Projektmanager, der Aufgaben verwaltet und KI-Helfer kontrolliert einsetzt**.

### Das Kernprinzip

Das System:

1. **Zerlegt dein Projekt** in kleine, nachvollziehbare Aufgaben (jede in einer Datei)
2. **Überwacht jeden KI-Agenten** — Was darf der Agent anfassen? Wann muss es doppelt geprüft werden?
3. **Prüft das Ergebnis** — War die Arbeit fehlerfrei? Passt sie zu deinen Anforderungen?
4. **Entscheidet automatisch** — Einfache Aufgaben erledigt ein Agent allein. Komplexe Aufgaben bekommen einen Manager, der Plant, einen Worker, der umgesetzt, und einen Verifier, der prüft.

Das macht es sicher: Der Agent kann nicht einfach Dateien löschen, ins Internet hochladen oder Code verstümmeln. Der Menschen behält die Kontrolle.

---

## Schnelteinstieg: So nutzt du das System

### Schritt 1: Vor dem ersten Lauf — Setup prüfen

```bash
./scripts/doctor.sh
```

Das Skript prüft:

- ✓ Ist `git` installiert und ist das Projekt ein Repository?
- ✓ Ist der Runner (`claude` oder `codex`) installiert?
- ✓ Sind alle notwendigen Tools vorhanden (`jq`, `awk`, `sed`, etc.)?
- ✓ Ist die `.agent/config.env` Konfiguration korrekt?

**Ergebnis:** Zeigt `OK` oder `BEFUND`. Bei Fehlern werden diese angezeigt und können behoben werden.

### Schritt 2: Projekt einmalig initialisieren

Das machst du nur einmal am Anfang:

```bash
# Öffne diese Datei in deinem Editor
nano docs/prompts/init.md

# Schreibe deine Projektbeschreibung unten in die Datei ein
# (ersetze den Platzhalter)

# Kopiere dann den kompletten Inhalt dieser Datei
# und öffne eine neue Claude Code Sitzung
# Paste den Prompt dort ein und führe ihn aus
```

Der Initializer wird:

- Ein Ziel in `docs/state/goal.md` anlegen
- Einen Plan in `docs/state/plan.md` erstellen
- Die ersten Tasks in `docs/tasks/` erzeugen
- `scripts/verify.sh` durch deine Projekt-Prüfung ersetzen

### Schritt 3: Den ersten Task anschauen

```bash
# Zeige die nächsten bereitstehenden Tasks
./scripts/next-tasks.sh
```

**Ausgabe zum Beispiel:**

```
Task 001: "Frontend-Komponente für Dashboard" (todo)
Task 003: "API-Endpoint für Benutzerdaten" (todo)
(Task 002 wartet auf Task 001)
```

### Schritt 4: Task bearbeiten lassen

```bash
# Starte den nächsten bereitstehenden Task
./scripts/orchestrate.sh --next
```

Das System wird:

1. Den Task analysieren (ist er einfach oder komplex?)
2. Entscheiden, ob Manager/Worker/Verifier nötig sind
3. Agenten arbeiten lassen
4. Das Ergebnis prüfen
5. Task-Status automatisch aktualisieren

**Das passiert im Hintergrund — du wirst informiert, wenn es fertig ist.**

### Schritt 5: Aktuellen Stand checken

```bash
# Zeige in zwei Zeilen den aktuellen Stand
./scripts/state-summary.sh
```

**Ausgabe zum Beispiel:**

```
Status: 5 todo | 2 in_progress | 3 done | 1 blocked
Fehler: keine
```

### Schritt 6: Wenn ein Task blockiert ist

Ein Task steht auf `blocked`, wenn:

- Der Agent eine Frage hat (z.B. "Welche Farbe soll der Button haben?")
- Etwas Unerwartetes passiert ist

**Das machst du:**

```bash
# Öffne die Task-Datei und lese die Frage
nano docs/tasks/001.md
# Suche nach "# Offene Frage"

# Beantworte die Frage direkt in der Datei

# Öffne den Task wieder
./scripts/task.sh reopen 001

# Lasse den Agent erneut versuchen
./scripts/orchestrate.sh --task 001
```

### Schritt 7: Wenn ein Task auf "review" wartet

Nach einem erfolgreichen Lauf kann ein Task auf `review` warten. Das bedeutet:

- Das Ergebnis ist technisch korrekt ✓
- Der Mensch (du) muss es aber freigeben (z.B. für Design-Check, Text-Review, Rechtliches)

**Das machst du:**

```bash
# Öffne den Task und überprüfe das Ergebnis
nano docs/tasks/001.md

# Wenn alles gut aussieht:
./scripts/task.sh approve 001
```

Der Task wird jetzt auf `done` gesetzt.

### Schritt 8: Fehlerbehebung — Wenn etwas nicht stimmt

```bash
# Tiefe Prüfung des ganzen Projekts
./scripts/verify.sh --deep
```

Das zeigt:

- Task-Struktur-Fehler
- Ungültige Status-Übergänge
- Abhängigkeitsprobleme
- Prüf-Bericht-Fehler

**Häufige Probleme:**

| Problem                                            | Lösung                                                   |
| -------------------------------------------------- | -------------------------------------------------------- |
| Task hat keinen Status                             | Öffne die Task-Datei und ergänze das `status`-Feld       |
| Task ist in `blocked`, aber ich habe nicht gefragt | Lese die Frage unter `# Offene Frage` und beantworte sie |
| Prüfung schlägt fehl                               | Führe `./scripts/verify-task.sh 001` aus für Details     |
| Agent konnte nicht weiterkommen                    | Versuche `./scripts/orchestrate.sh --task 001` erneut    |

### Schritt 9: Täglicher Workflow (nach dem Setup)

```bash
# Morgens: Überblick
./scripts/state-summary.sh

# Nächste Task: Bereit?
./scripts/next-tasks.sh

# Task bearbeiten lassen
./scripts/orchestrate.sh --next

# Mittags: Status checken
./scripts/state-summary.sh

# Blockierte Tasks? Fragen beantworten
# Approval-Tasks? Freigeben
./scripts/task.sh approve 001

# Abends: Alles validieren
./scripts/verify.sh --quick

# Commit und Push
git add -A
git commit -m "daily progress"
```

---

## Wie funktioniert die Architektur?

### Die Kernkomponenten

```
┌─────────────────────────────────────────────────────────────┐
│                   PROJEKT-MANAGEMENT                        │
├─────────────────────────────────────────────────────────────┤
│ docs/state/goal.md     → Was ist das Ziel?                  │
│ docs/state/plan.md     → Wie erreichen wir es?              │
│ docs/state/notes.md    → Was haben wir gelernt?             │
│ docs/state/decisions.md→ Welche Entscheidungen trafen wir?  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   AUFGABENVERWALTUNG                         │
├─────────────────────────────────────────────────────────────┤
│ docs/tasks/001.md      → Task 1 mit Status, Abhängigkeiten  │
│ docs/tasks/002.md      → Task 2 (hängt von Task 1 ab)       │
│ docs/tasks/003.md      → Task 3 usw.                        │
│                                                              │
│ Jeder Task hat:                                              │
│  • Status: todo / in_progress / review / done / blocked      │
│  • Schwierigkeit: mechanical / patterned / open              │
│  • Akzeptanzkriterien: Wie wissen wir, es ist fertig?       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│               ROUTER: "Was ist der nächste Task?"            │
│                    "Wer sollte ihn bearbeiten?"              │
├─────────────────────────────────────────────────────────────┤
│ Einfach (mechanical)? → Ein Worker erledigt es allein       │
│ Mittelschwer (patterned)? → Worker + Verifier-Prüfung       │
│ Komplex/offen (open)? → Manager plant, Worker arbeitet,     │
│                         Verifier prüft                       │
│                                                              │
│ Fehler entdeckt? → Eine Stufe höher wieder versuchen        │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  AUSFÜHRUNG DES TASKS                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ 1. MANAGER (bei komplexen Tasks):                           │
│    • Liest Ziel, Task, Plan und bisherige Erkenntnisse      │
│    • Entscheidet: Was genau tun? Brauche ich Rückfragen?    │
│    • Kann sagen: "Ich brauche eine Entscheidung vom Mensch" │
│                                                              │
│ 2. WORKER:                                                   │
│    • Erhält klare Anweisung und Kontextinformationen        │
│    • Liest und bearbeitet Dateien im Projekt                │
│    • Kann nur die Dateien anfassen, die im Task stehen       │
│    • Kann nicht löschen, nicht hochladen, nicht verstümmeln │
│    • Schreibt Ergebnis auf (was wurde gemacht?)             │
│                                                              │
│ 3. VERIFIER:                                                 │
│    • Führt die Akzeptanzkommandos des Tasks aus             │
│    • Prüft: "Ist das Ergebnis fehlerfrei?"                  │
│    • Schreibt einen Prüfbericht: grün ✓ oder rot ✗          │
│                                                              │
│ 4. STATUS-GATE (automatisch):                               │
│    • Nur diese Komponente darf Task-Status ändern           │
│    • Ist der Bericht grün? → Task auf "review" oder "done"  │
│    • Ist der Bericht rot? → Task bleibt "in_progress",      │
│      Manager versucht es erneut (eine Stufe höher)          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   SICHERHEIT (immer aktiv)                   │
├─────────────────────────────────────────────────────────────┤
│ Ein Agent (Worker/Manager) darf NICHT:                       │
│  • Dateien ins Internet hochladen (git push, curl, wget)    │
│  • Ordner rekursiv löschen (rm -r)                           │
│  • Ungespeicherte Arbeit verwerfen (git reset --hard)       │
│  • Prüfungs-Hooks umgehen (--no-verify)                      │
│                                                              │
│ Diese Sperren sind in den Skripten hart codiert.             │
│ Sie gelten immer, überall, versteckt oder offen.             │
└─────────────────────────────────────────────────────────────┘
```

### Die vier Rollen

| Rolle           | Wer?     | Was tut sie?                                                                                             |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------- |
| **Manager**     | KI-Agent | Liest das Ziel und alle bisherigen Notizen. Entscheidet, was zu tun ist, oder fragt den Menschen um Rat. |
| **Worker**      | KI-Agent | Führt den Plan aus. Bearbeitet Dateien. Meldet Ergebnis zurück.                                          |
| **Verifier**    | Skript   | Führt automatische Tests aus. Prüft: "Ist das Ergebnis richtig?"                                         |
| **Status-Gate** | Skript   | Einzige Komponente, die Task-Status ändern darf. Sperrt Missbrauch.                                      |

### Die vier Betriebsmodi

| Modus        | Aufwand | Wann?               | Ablauf                                    |
| ------------ | ------- | ------------------- | ----------------------------------------- |
| **single**   | niedrig | einfache Tasks      | nur Worker → Verifier → Status-Gate       |
| **verified** | mittel  | mittelschwere Tasks | Worker → Verifier → Status-Gate           |
| **managed**  | hoch    | komplexe Tasks      | Manager → Worker → Verifier → Status-Gate |
| **blocked**  | stoppt  | zu viele Fehler     | Task wartet auf menschliche Entscheidung  |

### Der Ablauf eines Tasks

```
1. ./scripts/next-tasks.sh
   → Zeigt Tasks mit erfüllten Abhängigkeiten an
   → "Welche Tasks kann ich jetzt starten?"

2. ./scripts/orchestrate.sh --next
   → Startet den nächsten Task
   → Router entscheidet Modus
   → Agenten arbeiten (Manager? Worker? Verifier?)
   → Status-Gate aktualisiert Task-Status

3. ./scripts/state-summary.sh
   → Zeigt aktuellen Stand: Wie viele Tasks sind done? Wie viele blockiert?
   → Gibt es Fehler?

4. ./scripts/verify.sh
   → Globale Projektprüfung (nicht Task-spezifisch)
   → Validiert: Ist die Ledger-Struktur korrekt? Gibt es Fehler?
```

---

## Skript-Referenz: Was tut jedes Skript?

Hier sind alle Skripte, die du brauchst, erklärt in Laien-Sprache:

### Haupt-Befehle (du nutzt sie täglich)

| Skript                                | Was tut es?                                                                                                               | Wann nutzen?                                                      | Beispiel                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `./scripts/next-tasks.sh`             | Zeigt die nächsten Tasks, die bereit sind.                                                                                | Zu Beginn einer Session: "Was soll ich als nächstes bearbeiten?"  | `./scripts/next-tasks.sh` → zeigt "Task 001, Task 003 (Task 002 wartet noch)"           |
| `./scripts/orchestrate.sh --next`     | Startet den nächsten bereiten Task. Der Router entscheidet automatisch: braucht er Manager? Nur Worker? Mehrere Versuche? | Nach `next-tasks.sh`: Starte die Arbeit.                          | `./scripts/orchestrate.sh --next` → arbeitet an Task 001, prüft es, aktualisiert Status |
| `./scripts/orchestrate.sh --task 003` | Startet einen bestimmten Task (z.B. 003).                                                                                 | Du willst einen spezifischen Task, nicht den nächsten.            | `./scripts/orchestrate.sh --task 003`                                                   |
| `./scripts/state-summary.sh`          | Zeigt in zwei Zeilen: Wie viele Tasks sind `todo`/`in_progress`/`done`? Welche sind blockiert?                            | Schneller Überblick über den Projektstand.                        | `./scripts/state-summary.sh` → "5 todo, 1 in_progress, 3 done, 1 blocked"               |
| `./scripts/verify.sh`                 | Prüft das ganze Projekt: Ist die Task-Struktur korrekt? Gibt es Fehler in den Dateien?                                    | Nach Änderungen an Task-Dateien: "Habe ich etwas kaputt gemacht?" | `./scripts/verify.sh` → OK oder Liste von Fehlern                                       |
| `./scripts/verify.sh --quick`         | Schnelle Prüfung (pre-commit Hook).                                                                                       | Vor dem Commit: "Ist der aktuelle Stand in Ordnung?"              | Git Hook, läuft automatisch                                                             |
| `./scripts/verify.sh --deep`          | Komplette Prüfung (alles durchschauen).                                                                                   | Wenn `--quick` fehlschlägt oder du alle Details brauchst.         | `./scripts/verify.sh --deep`                                                            |

### Task-Verwaltung (du änderst Task-Status manuell)

| Skript                          | Was tut es?                                                                                                                                                      | Wann nutzen?                                                                                      | Beispiel                                                             |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `./scripts/task.sh approve 003` | Gibt einen Task frei, der auf `review` wartet. Ein Agent hat ihn gemacht, Prüfung war grün, aber der Mensch muss freigeben (z.B. für Design, Text, Rechtliches). | Ein Task steht auf `review`, du hast ihn überprüft, er sieht gut aus.                             | `./scripts/task.sh approve 003` → Task wird `done`                   |
| `./scripts/task.sh reopen 003`  | Öffnet einen blockierten Task wieder. Der Agent konnte nicht weiterkommen, hat gefragt, und du hast die Frage beantwortet.                                       | Ein Task steht auf `blocked` mit einer Frage unter `# Offene Frage`. Du hast die Antwort gegeben. | Schreib die Antwort in den Task, dann `./scripts/task.sh reopen 003` |

### Diagnose & Validierung (wenn es Fehler gibt)

| Skript                         | Was tut es?                                                                                   | Wann nutzen?                                                              | Beispiel                                                                      |
| ------------------------------ | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `./scripts/doctor.sh`          | Prüft: Ist alles installiert? Ist der Runner konfiguriert? Ist das Git-Repository in Ordnung? | Beim ersten Mal oder nach Fehler-Meldungen.                               | `./scripts/doctor.sh` → "OK" oder "BEFUND: Claude CLI nicht gefunden"         |
| `./scripts/validate-ledger.sh` | Prüft die Task-Dateien auf Fehler: Sind alle Pflichtfelder da? Sind die Status korrekt?       | Nach Änderungen an Task-Dateien: "Habe ich die Struktur richtig gemacht?" | `./scripts/validate-ledger.sh` → OK oder "Fehler: Task 005 hat keinen Status" |
| `./scripts/verify-task.sh 003` | Prüft nur einen Task: Laufen die Akzeptanzbefehle?                                            | Du willst nur einen Task testen, nicht das ganze Projekt.                 | `./scripts/verify-task.sh 003` → OK oder Fehler mit Details                   |

### Debug & Kontrolle (Profis)

| Skript                                   | Was tut es?                                                                                                                | Wann nutzen?                                                                                       | Beispiel                                                                          |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `./scripts/orchestrate.sh --dry-run`     | Zeigt, was passieren würde: Welcher Task? Welcher Modus? Wie viele Manager/Worker/Verifier-Runden? Schreibt KEINE Dateien. | Bevor du `orchestrate.sh --next` aufrufst: "Lass mich checken, was passiert, bevor ich es starte." | `./scripts/orchestrate.sh --dry-run` → "TASK_ID=003 MODE=managed PLANNED_CALLS=3" |
| `./scripts/orchestrate.sh --allow-dirty` | Erlaubt, einen Task zu starten, auch wenn es ungespeicherte Änderungen im Projekt gibt.                                    | Du hast lokal Änderungen und willst nicht committen, sondern trotzdem einen Task starten.          | `./scripts/orchestrate.sh --task 003 --allow-dirty`                               |

### Interne Skripte (die `orchestrate.sh` selbst nutzt)

Diese brauchst du normalerweise nicht direkt. Sie werden von `orchestrate.sh` aufgerufen:

| Skript                      | Was tut es?                                                                                                             | Innere Funktionsweise                                                                                    |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `scripts/agent/config.sh`   | Liest und validiert `.agent/config.env`. Prüft: Sind alle 13 Konfigurationsschlüssel vorhanden? Sind die Werte korrekt? | `orchestrate.sh` prüft damit, dass die Konfiguration stimmt, bevor ein Agent startet.                    |
| `scripts/agent/context.sh`  | Baut das Kontext-Paket für einen Agent: Ziel, Task, Plan, bisherige Fehler, Dateiliste.                                 | Der Agent bekommt nicht das ganze Projekt als Kontext — nur, was er braucht.                             |
| `scripts/agent/policy.sh`   | Prüft Pfad-Grenzen. Darf der Agent diese Datei anfassen?                                                                | Sperrt den Agent: "Du darfst nur in deinem Task-Ordner arbeiten, nicht im Projekt-Konfigurationsordner." |
| `scripts/agent/runner.sh`   | Adapter für den gewählten Runner (`claude` oder `codex`). Startet den Agent mit den richtigen Optionen.                 | Versteckt die Unterschiede zwischen Claude und Codex.                                                    |
| `scripts/agent/status.sh`   | Einzige Komponente, die Task-Status ändern darf. Validiert: Ist der Prüfbericht grün? Dann kann ich den Status ändern.  | "Nur ich darf Task-Status ändern — kein Agent, kein Mensch per Hand."                                    |
| `scripts/agent/ledger.sh`   | Liest Task-Dateien. Extrahiert Felder wie Status, Abhängigkeiten, Akzeptanzkriterien.                                   | Der Orchestrator fragt: "Was steht im Task 003?" — Ledger antwortet.                                     |
| `scripts/agent/route.sh`    | Der Router. Entscheidet: Welcher Modus für diesen Task? `single`? `verified`? `managed`?                                | Berücksichtigt: Task-Klasse, Fehlversuche, Risikoflaggen.                                                |
| `scripts/agent/rolecall.sh` | Startet eine Rolle (Manager/Worker/Verifier). Setzt Timeouts, Limits, überwacht die Ausführung.                         | Der Orchestrator ruft ihn auf: "Starte einen Worker mit diesen Grenzen."                                 |
| `scripts/agent/common.sh`   | Hilfsfunktionen: Manifeste erstellen (Snapshot des Zustands vor einem Agent), Zeiten limitieren, etc.                   | Intern genutzt von anderen `agent/*`-Skripten.                                                           |

### Hooks & Sperren (Sicherheit)

| Skript                   | Was tut es?                                                                  | Wann aktiv?                                                              |
| ------------------------ | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `scripts/bash-guard.sh`  | Blockiert gefährliche Befehle: `git push`, `rm -r`, `git reset --hard`, etc. | Läuft als `PreToolUse`-Hook, bevor ein Agent einen Bash-Befehl ausführt. |
| `scripts/commit-gate.sh` | Blockiert Commits, bis `./scripts/verify.sh --quick` grün ist.               | Läuft als `PreToolUse`-Hook, bevor ein Agent `git commit` ausführt.      |

### Tests (du brauchst diese normalerweise nicht)

| Skript                | Was tut es?                                                  |
| --------------------- | ------------------------------------------------------------ |
| `tests/run.sh`        | Startet die Test-Suite. Prüft alle Skripte, Logik, Struktur. |
| `tests/run.sh --fast` | Schnelle Tests (überspringt langsame Integration/E2E).       |

---

## Konfiguration: `.agent/config.env`

Diese 13 Schlüssel kontrollieren, wie Agenten arbeiten:

| Schlüssel                | Beispiel              | Was bedeutet es?                                                 |
| ------------------------ | --------------------- | ---------------------------------------------------------------- |
| `MAX_GLOBAL_ITERATIONS`  | `10`                  | Wie viele Runden einer Task darf es geben? (Default: 10)         |
| `MAX_TASK_ATTEMPTS`      | `3`                   | Wie viele rote Versuche, bevor Task blockiert? (Default: 3)      |
| `MAX_NO_PROGRESS`        | `1`                   | Wie viele Runden ohne Fortschritt, bevor blockiert? (Default: 1) |
| `CONTEXT_MAX_CHARS`      | `48000`               | Wie groß darf der Kontextpaket sein? (Default: 48000)            |
| `NOTES_MAX_CHARS`        | `12000`               | Wie viel Platz für Notizen im Kontext? (Default: 12000)          |
| `VERIFY_TIMEOUT_SECONDS` | `90`                  | Zeitlimit für einen Prüfbefehl. (Default: 90s)                   |
| `AGENT_TIMEOUT_SECONDS`  | `900`                 | Zeitlimit für einen Modellaufruf. (Default: 900s = 15 Min)       |
| `AGENT_MAX_TURNS`        | `60`                  | Max. Runden in einer Agent-Konversation. (Default: 60)           |
| `MAX_INFRA_RETRIES`      | `1`                   | Wie oft bei Provider-Fehler wiederholen? (Default: 1)            |
| `RETRY_BACKOFF_SECONDS`  | `1`                   | Warten vor Retry? (Default: 1s)                                  |
| `AGENT_RUNNER`           | `claude` oder `codex` | Welcher Runner? Claude oder Codex? (Default: claude)             |
| `AGENT_MODEL`            | `default`             | Welches Modell? `default` = Läuft nur davon ab                   |
| `FINALIZER`              | `off` oder `llm`      | Zusätzlicher Modellaufruf bei Blockade? (Default: off)           |

---

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
