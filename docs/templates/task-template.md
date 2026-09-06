---
id: <NNN>
title: "<Verb + Objekt, konkret>"
depends_on: [<ids — nur technische Unmöglichkeit, keine Reihenfolge-Präferenz>]
features: [<Anforderungs-IDs, die diese Aufgabe erfüllt>]
status: todo
class: patterned # mechanical | patterned | open — siehe Test unten
orchestration: auto # auto | single | verified | managed
touches: [] # Pfade, die dieser Task ändern darf; leer heisst unbeschränkt
risk_flags: [] # high-risk | cross-component | repeated-failure
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
Router. `touches` nennt die Pfade, die der Worker ändern darf; alles ausserhalb
wird zurückgesetzt und stoppt den Lauf. `risk_flags` wird nur für bereits
kuratierte Signale verwendet und hebt den Modus auf mindestens `managed`; freie
oder unbekannte Werte sind ungültig.

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

# Akzeptanzkriterien (über die acceptance-Befehle hinaus)

- <konkrete Aussagen, die Tests beweisen müssen>
- <Muster für ein gutes Kriterium — so formulieren:
  "Der Test für X MUSS exakt Y erwarten. Wenn Z den Test wackelig
  macht, behebe Z (z.B. mit einer Fake-Uhr) — NIE die Erwartung
  lockern." Ein Kriterium, das der Agent nicht durch Aufweichen
  des Tests erfüllen kann, ist die wichtigste Zeile dieser Datei.>
