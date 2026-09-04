# Blinde Review-Rubrik

Reviewer sehen weder Modus noch Reihenfolge und bewerten erst nach der
deterministischen Prüfung.

| Feld | Zulässige Werte |
|---|---|
| deterministische_pruefung | green, red, harness_error |
| fachlich_korrekt | ja, nein, unklar |
| regression | ja, nein, unklar |
| manuelle_korrektur | keine, klein, wesentlich |
| wartbarkeit | besser, gleich, schlechter, unklar |
| bevorzugt | baseline, variante, gleich, keine |

Freitext begründet nur `unklar`, `wesentlich`, `schlechter` oder `keine`.
Harness- und Infrastrukturfehler bleiben von fachlich falschen Lösungen
getrennt. Die Auswertung verwendet die in `docs/state/decisions.md` vor dem
Pilot festgelegten Rohzahl-Schwellen.
