---
phase: "07"
result: done
plan_version: "1.1"
implementation_ref: "working-tree:23f854bfd3b7573744eff76e6a2169009b9c379b8acadaee9ee51b780bf24a3c"
verification: green
completed_at: "2026-09-04T19:14:09Z"
next_phase: "08"
---

# Handoff Phase 07

## Ergebnis

- `managed-fresh` erzeugt zwei isolierte Kandidaten vom selben Basis-Commit;
  der Fresh-Aufruf sieht weder historische Notes noch einen Git-Historienlink.
- Beide Kandidaten werden getrennt geprüft; Rot kann Grün nie verdrängen und
  zwei rote Kandidaten ergeben deterministisch `neither`.
- Zwei grüne Kandidaten gehen mit redigierten Diffs und Prüfberichten an den
  Reviewer; genau ein grüner Kandidat wird ohne unnötigen Review gewählt.
- Vor Übernahme wird der Hauptstand verglichen und danach vollständig neu
  geprüft; bei roter Hauptprüfung wird der Produktpatch zurückgenommen.
- Der Finalizer läuft ohne Produktcode und kann nur validierte Handoff-/Notes-
  Änderungen zurückspielen; externe Änderungen pausieren den Lauf.

## Geänderte Dateien

- `scripts/agent/candidates.sh` — Worktrees, Patches, Fingerprints, Übernahme,
  Rollback und kontrolliertes Cleanup.
- `scripts/orchestrate.sh`, `scripts/agent/context.sh` — Fresh-Ablauf,
  Reviewer-Belege, Reverify, Fehler- und Pausenpfade.
- `scripts/agent/{common,config}.sh`, `.agent/config.env` — gekapselte
  Manifestvariablen und separates Infrastruktur-Retry-Budget.
- `tests/orchestrator/{fake-runner,test-phase-07}.sh` — deterministische
  Kandidaten-, Finalizer-, Retry- und Fremdänderungs-Fixtures.
- `.agent/README.md` — Betriebs- und Sicherheitsvertrag für Phase 07.

## Verifikation

- `test-phase-01.sh` bis `test-phase-07.sh` — GREEN
  (29/29/33/64/48/39/34 Tests).
- `verify.sh`, `validate-ledger.sh`, Shell-Syntax und `git diff --check` — GREEN.

## Entscheidungen und Abweichungen

- Temporäre Git-Worktrees erfüllen die Isolation; beim Fresh-Aufruf wird der
  `.git`-Verweis zusätzlich entfernt und erst zur Patchbildung wiederhergestellt.
- Provider-Retries zählen gegen ein eigenes kleines Budget und verändern den
  fachlichen Task-Versuchszähler nicht.

## Offene Punkte

- Keine Restarbeit aus Phase 07.

## Kontext für die nächste Phase

- Kandidatenentscheidungen und kompakte Belege liegen lokal unter
  `.agent-runs/<run-id>/candidates/`; vollständige Rohlogs bleiben ausgeschlossen.
- Das separate Infrastruktur-Retry-Budget ist noch nicht Teil der
  Rollout-Metriken; Messung und Pilotierung gehören zu Phase 08.
- `managed-fresh` verlangt immer einen sauberen versionierten Basisstand;
  `--allow-dirty` hebt diese Grenze nicht auf.

## Wiederaufnahme

- `Setze Phase 08 aus plans/08-metriken-evaluation-und-rollout.md um und beginne keine weitere Phase.`
