# Entscheidungen

<!-- Jede Tech-Entscheidung: Was / Warum in Alltagssprache / Folge für den Auftraggeber.
     Wird bei der Initialisierung gefüllt und danach bei jeder neuen Entscheidung ergänzt. -->

## 2026-09-04 — Das bestehende Task-System bleibt die einzige Aufgabenquelle

**Was:** Die Dateien unter `docs/tasks/*.md` bleiben die verbindliche Quelle für
Aufgaben, Abhängigkeiten, Status und Akzeptanz. Die geplante
Manager–Worker-Orchestrierung ergänzt dieses System und führt kein paralleles
`tasks.json` ein.

**Warum:** Zwei Aufgabenlisten könnten auseinanderlaufen. Dann wäre unklar,
welcher Status stimmt und welche Aufgabe als Nächstes bearbeitet werden darf.
Das vorhandene Markdown-Format ist bereits für Menschen verständlich und wird
von den bestehenden Skripten verwendet.

**Folge für den Auftraggeber:** Der Arbeitsstand bleibt an einer Stelle lesbar.
Die spätere Automatisierung kann ausgetauscht werden, ohne Aufgaben oder
Projektwissen zu verlieren.

## 2026-09-04 — Orchestrierung bleibt vom Produkt-Stack und Anbieter getrennt

**Was:** Gemeinsame Agentenregeln liegen unter `.agent/` und
`scripts/agent/`. Ein späterer Modell- oder Anbieteraufruf wird ausschließlich
über `scripts/agent/runner.sh` angebunden.

**Warum:** Das mitgelieferte Profil erwartet Node.js, im Zielordner liegen aber
noch ein neutrales Python-Beispiel und `pyproject.toml`. Die Orchestrierung darf
weder von diesem Beispiel noch vom später gewählten Produkt-Stack abhängen.

**Folge für den Auftraggeber:** Ein Wechsel des Modells, Agenten-CLI oder
Produkt-Stacks soll nur den Adapter betreffen. `main.py` und `pyproject.toml`
werden in dieser Phase bewusst weder gelöscht noch verändert.

## 2026-09-04 — Lokale Agentenartefakte werden nicht versioniert

**Was:** Vollständige Prompts, Rohantworten, Logs und temporäre Kandidaten liegen
später ausschließlich in `.agent-runs/`; der Ordner ist in `.gitignore`
ausgeschlossen. Das versionierte Ledger enthält nur kuratierte Ergebnisse.

**Warum:** Rohdaten können sehr groß werden, irrelevante Historie enthalten und
versehentlich vertrauliche Inhalte wiederholen. Für neue Sitzungen reicht ein
kleiner, geprüfter Projektzustand.

**Folge für den Auftraggeber:** Das Repository bleibt übersichtlich. Lokale
Rohprotokolle werden nicht automatisch hochgeladen; sie müssen bei Bedarf vor
einer Weitergabe separat geprüft werden.

## 2026-09-04 — Statuswechsel brauchen einen überprüfbaren Beleg

**Was:** Automatische Statuswechsel laufen ausschließlich über ein Status-Gate.
Es vergleicht den erwarteten alten Status, prüft erlaubte Übergänge und verlangt
vor `done` einen passenden grünen Prüfbericht. Dateien werden erst nach einer
erfolgreichen Prüfung ersetzt.

**Warum:** Ein verspäteter Agent könnte sonst neuere Arbeit überschreiben oder
eine Aufgabe allein aufgrund seiner eigenen Behauptung als fertig markieren.
Ein unterbrochener Schreibvorgang könnte außerdem eine halbe Datei hinterlassen.

**Folge für den Auftraggeber:** „Fertig“ bedeutet künftig, dass eine konkrete
Prüfung grün war. Bei Text, Optik oder anderen menschlichen Entscheidungen bleibt
die Aufgabe zunächst sichtbar auf `review`.

## 2026-09-04 — Zusätzliche Agentenarbeit wird nach Risiko gewählt

**Was:** Ein deterministischer Router wählt zwischen `single`, `verified`,
`managed` und `managed-fresh`. Kleine mechanische Änderungen beginnen günstig;
offene, sicherheitsrelevante, bereichsübergreifende oder wiederholt gescheiterte
Aufgaben werden stärker begleitet. Nach einem Fehlschlag steigt der Modus genau
eine Stufe, höchstens bis zum Versuchslimit.

**Warum:** Mehr Agentenrollen erhöhen Zeit und Kosten und sind bei einfachen
Änderungen nicht automatisch besser. Bei riskanten oder festgefahrenen Aufgaben
ist eine unabhängige Prüfung oder frische Perspektive dagegen wertvoll.

**Folge für den Auftraggeber:** Der gewählte Modus und sein Grund bleiben im
Laufstand sichtbar. Eine bewusste Vorgabe ist möglich, kann aber Prüfungen,
Sicherheitsminimum oder eine notwendige menschliche Freigabe nicht abschalten.
