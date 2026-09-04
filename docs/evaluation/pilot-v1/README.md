# Pilot v1

Dieser Ordner friert das Design für den kontrollierten, gepaarten Pilot ein.
Der echte Pilot startet erst nach einem ausdrücklichen Auftrag, weil er reale
Modellaufrufe und damit Kosten verursachen kann.

- `taskset.csv` enthält 20 vorab stratifizierte Plätze. `task_ref` und
  `base_fingerprint` bleiben leer, bis reale, voneinander unabhängige Aufgaben
  ausgewählt und ihr Ausgangsstand eingefroren wurden.
- `pairs.csv` wird erst nach den Läufen mit Baseline- und Varianten-Run-ID
  ergänzt. `scripts/agent-metrics.sh compare --manifest
  docs/evaluation/pilot-v1/pairs.csv` weist unterschiedliche Ausgangsstände ab.
- `review-rubric.md` ist die vorab festgelegte menschliche Bewertung.

Pro Aufgabe bleiben Modell, Modellversion, Reasoning, Toolzugriff, Verifier und
Ausgangsstand gleich. Die Reihenfolge von Baseline und Variante wird vor dem
Start randomisiert und in `order` dokumentiert. Kandidaten werden nie als
Kontext füreinander verwendet. Berichtet werden Rohzahlen und taskweise Paare,
keine scheinpräzisen Prozentwerte.

Der Pilotstatus ist bewusst `not_started`. Leere Felder sind keine Nullwerte.
