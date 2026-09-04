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
