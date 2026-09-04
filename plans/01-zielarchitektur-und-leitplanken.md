---
phase_id: "01"
depends_on: []
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/01-handoff.md"
plan_version: "1.1"
---

# Phase 01 — Zielarchitektur und Leitplanken festziehen

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 01** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln. Phase 01 muss `READY`, `IN_PROGRESS` oder `BLOCKED` sein.
2. Minimaler zusätzlicher Kontext: `CLAUDE.md`, `.claude/settings.json`,
   `.gitignore`, `docs/state/decisions.md`, `scripts/bash-guard.sh` und
   `scripts/commit-gate.sh`. Weitere Dateien nur bei konkretem Bedarf öffnen.
3. Setze Phase 01 vor Änderungen im Fortschrittsboard auf `IN_PROGRESS`.
4. Implementiere ausschließlich Ziel, Schritte und Abnahmekriterien dieser
   Datei. Erstelle keine Teile späterer Phasen vorab.
5. Führe die Tests dieser Phase und die vorhandene globale Prüfung aus.
6. Bei Erfolg: `plans/handoffs/01-handoff.md` anlegen, Board und README-
   Frontmatter aktualisieren, Phase 01 auf `DONE` und Phase 02 auf `READY`
   setzen. Bei Fehler: `BLOCKED` oder `IN_PROGRESS` mit konkretem Handoff.
7. Stoppe danach; Phase 02 wird nicht automatisch begonnen.

## Ziel

Vor dem ersten Loop werden Zuständigkeiten, Sicherheitsgrenzen und
Kompatibilitätsregeln festgelegt. Diese Phase verhindert, dass später mehrere
Dateien denselben Status beanspruchen oder ein Agent sich selbst freigibt.

## Ausgangslage

- `docs/tasks/*.md` enthält bereits Task-ID, Abhängigkeiten, Klasse,
  Akzeptanzbefehle und Status.
- `scripts/next-tasks.sh` und `scripts/verify.sh` sind derzeit Platzhalter.
- `docs/state/features.md`, `decisions.md`, `handoff.md` und `metrics.csv`
  bilden bereits einen langlebigen Projektzustand.
- `.claude/settings.json` startet eine kurze Zustandszusammenfassung und schützt
  Commits sowie riskante Befehle.
- Das Zielverzeichnis enthält außerdem noch ein neutrales Python-Skelett
  (`main.py`, `pyproject.toml`), während das mitgelieferte Profil Node.js
  vorsieht. Der Orchestrator darf deshalb nicht an einen Produkt-Stack
  gekoppelt werden.

## Verbindliche Zuständigkeiten

| Information | Verbindliche Quelle | Schreibberechtigt |
|---|---|---|
| ursprüngliches Ziel | `docs/state/goal.md` | Nutzer/Initializer, danach nur kontrolliert |
| Gesamtstrategie | `docs/state/plan.md` | Manager |
| Task-Status und Abhängigkeiten | `docs/tasks/*.md` | Status-Gate; Manager nur Inhalt/Zerlegung |
| Erkenntnisse und Fehler | `docs/state/notes.md` | Brainstorm, Worker, Verifier über Ledger-Funktion |
| techn. Entscheidungen | `docs/state/decisions.md` | zuständiger Agent, verständlich dokumentiert |
| aktueller Lauf | `docs/state/current-run.md` | Orchestrator |
| Prüfurteil | `docs/verification/latest.md` | Verifier-Skript |
| Feature-Status | `docs/state/features.md` | vorhandener Verify-Ablauf |
| Betriebsübergabe | `docs/state/handoff.md` | Finalizer/Session-Abschluss |

Der Manager darf Produktcode weder bearbeiten noch als geprüft einstufen. Der
Worker darf Plan und Task-Zerlegung nicht nebenbei neu definieren. Der Verifier
verändert keinen Produktcode.

## Umsetzungsschritte

1. Eine Architekturentscheidung in `docs/state/decisions.md` ergänzen:
   Markdown-Tasks bleiben Source of Truth; die Orchestrierung ergänzt, ersetzt
   sie aber nicht.
2. `.agent/config.env` mit einer kleinen, validierten Schlüsselmenge anlegen:

   ```text
   MAX_GLOBAL_ITERATIONS=10
   MAX_TASK_ATTEMPTS=3
   MAX_NO_PROGRESS=1
   DEFAULT_MODE=auto
   CONTEXT_MAX_CHARS=48000
   NOTES_MAX_CHARS=12000
   VERIFY_TIMEOUT_SECONDS=90
   ```

   Die Datei wird Zeile für Zeile geparst und **nie mit `source` oder `eval`
   ausgeführt**. Unbekannte Schlüssel und ungültige Zahlen sind Fehler.
3. `.agent-runs/` in `.gitignore` aufnehmen. Dort liegen vollständige lokale
   Prompts, Rohantworten und temporäre Kandidaten. Das versionierte Ledger
   enthält nur kuratierte Zusammenfassungen.
4. In `CLAUDE.md` die Rollen- und Statusregeln kompakt ergänzen. Die Datei darf
   nicht zu einer Kopie aller Prompts werden.
5. Eine Negativliste für Kontextaufbau definieren: `.env`, `.env.*`, Schlüssel,
   `.git/`, `.venv/`, `node_modules/`, Binärdateien, vollständige Rohlogs und
   `.agent-runs/` werden nie automatisch in einen Prompt aufgenommen.
6. Das Runner-Interface festlegen, ohne den Kern an einen Anbieter zu binden:

   ```text
   invoke_role <role> <prompt-file> <workdir> <result-file>
   ```

   Exit `0` bedeutet nur „Modellaufruf technisch abgeschlossen“, nicht
   „Aufgabe korrekt“.
7. Vor der späteren Implementierung lokal feststellen, welcher Agenten-CLI
   verfügbar ist und dessen Aufruf ausschließlich in `scripts/agent/runner.sh`
   kapseln. Alle übrigen Skripte arbeiten gegen das Interface.
8. Die noch widersprüchlichen Produkt-Skelette (`main.py`/`pyproject.toml`
   gegenüber Node-Profil) dokumentieren, aber in dieser Phase nicht löschen.

## Sicherheitsregeln

- Kein `git push`, rekursives Löschen oder Verwerfen ungespeicherter Arbeit.
- Manager-Ausgaben werden als untrusted data validiert.
- Kein Shell-Befehl wird mit `eval` aus einem Task- oder Manager-Dokument
  ausgeführt.
- Worker erhalten nur Zugriff auf das Repository und die für ihre Rolle
  erforderlichen Befehle.
- Ein Lauf beginnt nur bei sauber validiertem Ledger. Ein schmutziger Git-Stand
  darf nach ausdrücklicher Konfiguration weiterverwendet werden, wird aber im
  Laufprotokoll markiert.

## Tests

- Konfigurationsparser akzeptiert die Beispielwerte.
- Parser weist unbekannte Schlüssel, negative Limits und Shell-Syntax zurück.
- Kontextfilter schließt eine künstliche `.env` sowie Binär- und Laufdateien aus.
- Rollen-Matrix weist Schreibzugriffe auf falsche Artefakte zurück.
- Bestehende `bash-guard.sh`- und `commit-gate.sh`-Tests bleiben grün.

## Abnahmekriterien

- Genau eine verbindliche Quelle ist für jede Zustandsart benannt.
- Anbieter- oder Modellwechsel erfordert nur eine Runner-Anpassung.
- Keine Phase setzt ein vorhandenes Git-Repository oder Produktprofil voraus.
- Bestehende Schutzregeln sind dokumentiert und werden nicht gelockert.
- Die Phase verändert noch keinen Produktcode und startet keine Agenten.
