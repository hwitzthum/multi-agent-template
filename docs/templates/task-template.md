---
id: <NNN>
title: "<Verb + Objekt, konkret>"
depends_on: [<ids — nur technische Unmöglichkeit, keine Reihenfolge-Präferenz>]
features: [<ids aus features.md, die diese Aufgabe erfüllt>]
status: todo
acceptance:
  - "./scripts/verify.sh"
  - "<aufgabenspezifischer Befehl>"
human_review: false   # true, wenn Text oder Optik betroffen — dann prüft der Auftraggeber im Browser
class: patterned      # mechanical | patterned | open — siehe Test unten
# Test "zwei Entwickler": gleicher Code -> mechanical; verschieden, beide
# richtig -> patterned; verschieden und sie würden streiten -> open.
# Das Modell folgt der Klasse: mechanical = klein, patterned = mittel,
# open = stark + beaufsichtigt (läuft nie im Loop).
---

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
