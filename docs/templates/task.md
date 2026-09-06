---
id: <NNN>
title: "<Verb + Objekt, konkret>"
depends_on: []
status: todo
class: patterned
orchestration: auto
touches: []
risk_flags: []
attempts: 0
human_review: false
acceptance:
  - "./scripts/verify.sh"
  - "<aufgabenspezifischer Befehl>"
blocked_reason: ""
---

Der Dateiname ist die ID: Task `017` liegt als `docs/tasks/017.md`. Alle Felder
oben sind Pflicht; andere Felder sind ungültig. Kommentare hinter einem Wert
sind erlaubt, hinter einer Liste nur nach der schliessenden Klammer.

Feldwerte:

- `depends_on`: IDs, ohne die diese Aufgabe technisch unmöglich ist — keine
  blosse Reihenfolge-Präferenz.
- `status`: `todo | in_progress | review | done | blocked`. Nur das Status-Gate
  schreibt dieses Feld.
- `class`: `mechanical | patterned | open` — siehe Test unten.
- `orchestration`: `auto | single | verified | managed`. `auto` überlässt die
  Wahl dem Router; jeder andere Wert ist eine ausdrückliche Vorgabe.
- `touches`: Pfade, die dieser Task ändern darf; leer heisst unbeschränkt. Alles
  ausserhalb wird zurückgesetzt und stoppt den Lauf.
- `risk_flags`: `high-risk | cross-component | repeated-failure`. Nur für bereits
  kuratierte Signale; hebt den Modus auf mindestens `managed`. Freie oder
  unbekannte Werte sind ungültig.
- `attempts`: Zähler des Orchestrators. Das Limit steht in `.agent/config.env`
  (`MAX_TASK_ATTEMPTS`), nicht im Task.
- `human_review`: `true` heisst, ein grüner Lauf endet auf `review` und wartet
  auf `./scripts/task.sh approve <id>`.
- `acceptance`: Prüfbefehle als Argumentliste, ohne Shell-Metazeichen.
  `./scripts/verify.sh` läuft ohnehin immer mit.
- `blocked_reason`: nur bei `status: blocked` gefüllt.

Zulässige Statusübergänge: `todo -> in_progress`; von `in_progress` nach
`done`, `review`, `todo` oder `blocked`; von `review` nach `done`, `todo` oder
`blocked`. `blocked -> todo` geht ausschliesslich menschlich über
`./scripts/task.sh reopen <id>`. `review -> done` braucht bei `human_review:
true` oder `class: open` die Freigabe über `./scripts/task.sh approve <id>`.
`done` und `review` setzen einen passenden grünen Prüfbericht unter
`docs/verification/<id>.md` voraus.

Test "zwei Entwickler": gleicher Code -> `mechanical`; verschieden, beide
richtig -> `patterned`; verschieden und sie würden streiten -> `open`. Der
Router leitet daraus den Modus ab: `mechanical -> single`, `patterned ->
verified`, `open -> managed` (Manager-Worker-Loop) mit menschlichem Gate, d.h.
ein grüner Lauf endet auf `review`, nie direkt auf `done`.

Modusbeispiele:

- Routineänderung: `class: mechanical`, `orchestration: auto`; empfohlen wird `single`.
- Fachlogik nach vorhandenem Muster: `class: patterned`,
  `orchestration: auto`; empfohlen wird `verified`.
- Offene oder strittige Entscheidung: `class: open`, `human_review: true` —
  empfohlen wird `managed`, die Aufgabe bleibt bis zur menschlichen Freigabe
  auf `review`.
- Festgefahrener Hochrisiko-Task: `risk_flags: [repeated-failure]` — empfohlen
  wird `managed`. Der letzte erlaubte Versuch läuft dort als Fresh-Versuch: die
  `touches`-Pfade werden auf den Laufstart zurückgesetzt, und der Worker
  arbeitet ohne Notizen und ohne den vorherigen Prüfbericht.

# Kontext

<2–4 Zeilen: was und warum, mit relevanten Entscheidungen aus decisions.md/handoff.md>

# Umfang

- <was zu tun ist, konkret>

# Nicht Teil dieser Aufgabe

- <was NICHT getan wird — die günstigste Zeile der Datei>

# Akzeptanzkriterien

<Über die acceptance-Befehle hinaus: konkrete Aussagen, die Tests beweisen müssen.>

- <konkrete Aussage>
- <Muster für ein gutes Kriterium — so formulieren:
  "Der Test für X MUSS exakt Y erwarten. Wenn Z den Test wackelig
  macht, behebe Z (z.B. mit einer Fake-Uhr) — NIE die Erwartung
  lockern." Ein Kriterium, das der Agent nicht durch Aufweichen
  des Tests erfüllen kann, ist die wichtigste Zeile dieser Datei.>

# Offene Frage

<Optional. Der Manager trägt hier eine Rückfrage ein; die Aufgabe steht dann auf
`blocked` mit `blocked_reason: ASK_HUMAN`. Antwort direkt darunter schreiben,
danach `./scripts/task.sh reopen <id>`.>
