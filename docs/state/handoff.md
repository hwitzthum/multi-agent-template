# Handoff — 2026-09-05 00:30

## Laufbeleg

- Run-ID: `none`
- Modus: keiner
- Verifierstatus: NEVER — noch keine Task-Prüfung; `./scripts/verify.sh` ist bis
  zur Initialisierung ein Platzhalter und meldet GREEN
- Letzter grüner Stand: Branch `refactor/manager-worker-standard` (noch nicht
  committet), Basis `main` bei `c783a3d`; alle neun Testsuiten unter
  `tests/orchestrator/` GREEN, `validate-ledger.sh` GREEN

## Letzte Sitzung

- Vereinfachung der Vorlage (kein Task, keine Initialisierung): Der Router
  entscheidet weiterhin nach Klasse, Risiko und Fehlversuchen — seine
  Entscheidung wird jetzt direkt ausgeführt.
  - Entfernt: `ROLLOUT_STAGE` mit allen fünf Stufen, `DEFAULT_MODE`,
    `ROUTER_ENABLED`, Router-Option `--execution`, Ausgabefelder
    `RECOMMENDED_MODE`/`ROLLOUT_STAGE`, Metadatenfelder `recommended_mode`/
    `rollout_stage`, `agent-metrics.sh compare`, `docs/evaluation/pilot-v1/`.
  - Unverändert: alle vier Modi, beide Loops, harte Sicherheitsregeln,
    Eskalation um eine Stufe, menschliches Gate, Profil-System, CSV-Schema.
  - Tests angepasst (phase-01/03/05/08/09), nicht gelöscht. Dry-Run-Demo auf
    Wegwerf-Fixture: mechanical → single, patterned → verified, open →
    managed, fresh_perspective:required → managed-fresh, Auth-Umfang → managed.
  - Begründung in `docs/state/decisions.md` (Eintrag „Der Router entscheidet
    und führt aus"), Doku in README, KURSANLEITUNG, `.agent/README.md`,
    Task-Vorlage nachgezogen.

## Achtung nächste Sitzung

- Ein offener, riskanter oder wiederholt gescheiterter Task startet jetzt ohne
  weitere Freigabe den Manager-Loop bzw. zwei isolierte Worker — das kostet
  echte Modellaufrufe. Vor dem ersten echten Lauf `--dry-run` ansehen.
- Der Schutz-Hook blockiert rekursives Löschen, auch als Text in Heredocs;
  Demo-Fixtures unter `$TMPDIR/pilot-demo.*` und versionierte Ordner räumt der
  Auftraggeber auf.

## Für den Auftraggeber zu prüfen

- Entscheidung: offen — Commit und Merge des Branches
  `refactor/manager-worker-standard` in `main` freigeben.
- Demo-Fixture `$TMPDIR/pilot-demo.*` löschen (vom Agenten nicht erlaubt).

## Fehler und Wiederaufnahme

- Erster offener Fehler: keiner
- Nächster Schritt: nach Freigabe committen und mit Merge-Commit in `main`
  übernehmen; danach Initialisierung nach
  `docs/templates/initializer-prompt.md` auf einem neuen Branch ab `main`.

## Vorgeschlagene nächste Aufgabe

- Initialisierung des ersten Projekts aus einem Brief in `docs/briefs/`; danach
  werden die ersten Tasks unter `docs/tasks/` frei.
