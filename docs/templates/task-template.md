---
id: <NNN>
title: "<Verb + Objekt, konkret>"
depends_on: [<ids — nur technische Unmöglichkeit, keine Reihenfolge-Präferenz>]
features: [<ids aus features.md, die diese Aufgabe erfüllt>]
status: todo
class: patterned # mechanical | patterned | open — siehe Test unten
orchestration: auto # auto | single | verified | managed | managed-fresh
fresh_perspective: auto # auto | required | off
touches: [] # optionale Pfade/Komponenten für deterministisches Risiko-Routing
risk_flags: [] # cross-component | high-risk-domain | repeated-failure | conflicting-ledger
attempts: 0
max_attempts: 3
last_verification: never # never | green | red
human_review: false # true: nach grünen Tests zuerst Status review
acceptance:
  - "./scripts/verify.sh"
  - "<aufgabenspezifischer Befehl>"
blocked_reason: ""
# Test "zwei Entwickler": gleicher Code -> mechanical; verschieden, beide
# richtig -> patterned; verschieden und sie würden streiten -> open.
# Der Router leitet daraus den Modus ab: mechanical -> single, patterned ->
# verified, open -> managed (Manager-Worker-Loop) mit menschlichem Gate, d.h.
# ein grüner Lauf endet auf review, nie direkt auf done.
---

Zulässige Statusübergänge: `todo -> in_progress`; von `in_progress` nach
`done`, `review`, `todo` oder `blocked`; von `review` nach `done`, `todo` oder
`blocked`. `done` setzt einen passenden grünen Prüfbericht voraus. Das Feld
`orchestration` ist eine ausdrückliche Vorgabe; `auto` überlässt die Wahl dem
Router. `touches` nennt betroffene Pfade oder Komponenten. `risk_flags` wird nur
für bereits kuratierte Signale verwendet, die sich nicht zuverlässig aus dem
Umfang ableiten lassen; freie oder unbekannte Werte sind ungültig.

Modusbeispiele:

- Routineänderung: `class: mechanical`, `orchestration: auto`,
  `fresh_perspective: off` — empfohlen wird `single`.
- Fachlogik nach vorhandenem Muster: `class: patterned`,
  `orchestration: auto`, `fresh_perspective: auto` — empfohlen wird
  `verified`.
- Offene oder strittige Entscheidung: `class: open`, `human_review: true` —
  empfohlen wird `managed`, die Aufgabe bleibt bis zur menschlichen Freigabe
  auf `review`.
- Festgefahrener Hochrisiko-Task: `risk_flags: [repeated-failure]` oder
  `fresh_perspective: required` — empfohlen wird `managed-fresh`. Dieser Modus
  braucht einen sauberen, versionierten Git-Ausgangsstand.

# Kontext

<2–4 Zeilen: was und warum, mit relevanten Entscheidungen aus decisions.md/handoff.md>

# Umfang

- <was zu tun ist, konkret>

# Nicht Teil dieser Aufgabe

- <was NICHT getan wird — die günstigste Zeile der Datei>

# Akzeptanzkriterien (über die acceptance-Befehle hinaus)

- <konkrete Aussagen, die Tests beweisen müssen>
- <Muster für ein gutes Kriterium — so formulieren:
  "Der Test für X MUSS exakt Y erwarten. Wenn Z den Test wackelig
  macht, behebe Z (z.B. mit einer Fake-Uhr) — NIE die Erwartung
  lockern." Ein Kriterium, das der Agent nicht durch Aufweichen
  des Tests erfüllen kann, ist die wichtigste Zeile dieser Datei.>
