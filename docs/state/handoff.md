# Handoff — 2026-09-04 20:30

## Laufbeleg

- Run-ID: `none`
- Modus: keiner
- Verifierstatus: NEVER — noch keine Task-Prüfung; `./scripts/verify.sh` ist bis
  zur Initialisierung ein Platzhalter und meldet GREEN
- Letzter grüner Stand: Branch `cleanup/bugfixes-und-bereinigung`, noch nicht
  committet; alle neun Testsuiten unter `tests/orchestrator/` GREEN

## Letzte Sitzung

- Fehlerbehebung und Bereinigung der Vorlage (kein Task, keine Initialisierung):
  - `tests/orchestrator/test-phase-09.sh` verlangte `rg` und einen Quellhash in
    einer von Hand erstellten Word-Datei; beides entfernt, Test grün.
  - `scripts/verify-task.sh` erzeugte ohne `--run-id` bei ein- oder zweistelligen
    Task-IDs eine ungültige Run-ID; jetzt dreistellig aufgefüllt.
  - `scripts/agent/runner.sh` mischte stderr des CLI in die Rollenausgabe;
    stderr liegt jetzt separat als `.stderr` im Laufordner. Alias `invoke_role`
    entfernt.
  - `scripts/agent/metrics.sh` migrierte nur ein Zwischenschema des Umbaus;
    jetzt wird jede leere `metrics.csv` (nur Kopfzeile) auf das aktuelle Schema
    umgestellt.
  - Ungenutzte Funktion `agent_atomic_append_line` aus `common.sh` entfernt.
  - Gelöscht: `main.py`, `pyproject.toml`, `.mcp.json`, `KURSANLEITUNG.docx`,
    `plans/` (siehe `docs/state/decisions.md`).

## Achtung nächste Sitzung

- Die lokalen Ordner `.venv/` und `.idea/` sind nicht versioniert und gehören
  zum gelöschten Python-Beispiel; der Auftraggeber kann sie selbst entfernen.
- Der Schutz-Hook blockiert `git rm -r`; versionierte Ordner werden mit
  aufgezählten Dateien über `git ls-files | xargs git rm` entfernt.

## Für den Auftraggeber zu prüfen

- Entscheidung: offen
- Commit und Merge des Branches `cleanup/bugfixes-und-bereinigung` freigeben.
- Entscheiden, ob die gelöschte Word-Fassung der Kursanleitung gebraucht wird;
  sie lässt sich mit `pandoc docs/KURSANLEITUNG.md -o KURSANLEITUNG.docx`
  jederzeit aus dem Markdown erzeugen.

## Fehler und Wiederaufnahme

- Erster offener Fehler: keiner
- Nächster Schritt: Branch committen und in `main` übernehmen; danach
  Initialisierung nach `docs/templates/initializer-prompt.md`.

## Vorgeschlagene nächste Aufgabe

- Initialisierung des ersten Projekts aus einem Brief in `docs/briefs/`; danach
  werden die ersten Tasks unter `docs/tasks/` frei.
