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

## 2026-09-04 — Jede Rolle erhält ein kleines, nachvollziehbares Kontextpaket

**Was:** Jeder Modellaufruf bekommt einen festen Rollenvertrag und nur die für
diese Rolle nötigen Auszüge. Die Pakete werden nach Abschnitten begrenzt,
vertrauliche Muster werden entfernt und Inhalt sowie Prompt werden per
Prüfsumme dokumentiert. Gleiche Eingaben bleiben als dieselbe lokale Datei
nachvollziehbar.

**Warum:** Eine vollständige Projekthistorie macht Aufrufe teuer und kann alte
Irrwege oder Anweisungen aus Repository-Dateien ungewollt weitertragen. Kleine,
feste Pakete machen deutlicher, worauf eine Entscheidung beruhte, ohne
Frontmatter oder zusammengehörige Fehlertexte mitten im Block abzuschneiden.

**Folge für den Auftraggeber:** Läufe lassen sich später anhand ihrer
Prüfsummen vergleichen. Der Fresh Worker sieht bewusst weder frühere Notizen
noch Lösungsbegründungen oder Fehler und liefert dadurch eine unabhängige
Perspektive; Sicherheitsregeln, Ziel und Akzeptanz bleiben trotzdem verbindlich.

## 2026-09-04 — Fortschritt wird ohne Betriebsartefakte gemessen

**Was:** Der Loop zählt Produktänderungen, stabile Task-/Prüfzustände, neue
Notiz-IDs und die Managerentscheidung. Neue Prüfprotokolle oder ein erhöhter
Versuchszähler allein gelten nicht als Fortschritt.

**Warum:** Sonst könnte eine unveränderte Reparaturschleife allein durch neue
Zeitstempel und Logdateien endlos wie Fortschritt aussehen.

**Folge für den Auftraggeber:** Ein unveränderter Wiederholungsversuch führt
kontrolliert zum Finalizer; der letzte konsistente Stand bleibt fortsetzbar.

## 2026-09-04 — Rollout-Schwellen werden vor dem Pilot eingefroren

**Aufgehoben** durch den Eintrag „Der Router entscheidet und führt aus;
Rollout-Stufen und Pilot entfernt“ (2026-09-04). Bleibt nur als Historie stehen.

**Was:** Der Pilot umfasst 20 gepaarte Aufgaben: sechs mechanische, acht
regelbasierte und sechs offene. Die Manager-Variante wird für `patterned` nur
freigegeben, wenn sie mindestens zwei zusätzliche grüne Paare erreicht oder bei
gleicher Zahl grüner Paare mindestens drei menschliche Korrekturen vermeidet.
Dabei darf sie keine zusätzliche Regression erzeugen. `managed-fresh` wird nur
für festgefahrene oder hochriskante Fälle freigegeben, wenn es dort mindestens
zwei zusätzliche grüne Paare ohne zusätzliche Regression erzielt. Für
`mechanical` bleibt Single + Verify Standard, solange die Manager-Variante nicht
nachweislich zuverlässiger ist. Offene Aufgaben bleiben immer beaufsichtigt.

**Warum:** Bei nur 20 Aufgaben wären fein aufgelöste Prozentwerte irreführend.
Vorab festgelegte Rohzahl-Schwellen verhindern, dass die Regeln nach Sichtung
der Ergebnisse passend gemacht werden. Infrastruktur- und Harness-Fehler werden
separat ausgewiesen und entscheiden nicht über fachliche Qualität.

**Folge für den Auftraggeber:** Höhere Kosten allein können keine Aktivierung
rechtfertigen. Ohne die festgelegte Qualitätsverbesserung bleibt oder fällt der
Schalter auf `single-verify` zurück. Der noch nicht beauftragte echte Pilot ist
eine offene Betriebsaufgabe und keine fehlende technische Messung.

## 2026-09-04 — Offene Aufgaben bleiben menschlich beaufsichtigt

**Was:** Aufgaben mit `class: open` oder `human_review: true` dürfen nach einer
grünen Maschinenprüfung nur auf `review` wechseln. Erst eine ausdrückliche
menschliche Freigabe erlaubt `done`. Fehlende Entscheidungen führen nicht zu
einer stillen Annahme, sondern zu einer Rückfrage oder Blockade.

**Warum:** Texte, Gestaltung, Rechtliches und strittige Produktentscheidungen
lassen sich nicht vollständig durch technische Tests beurteilen. Ein grüner
Test beweist dort Funktionsfähigkeit, aber nicht, dass die Entscheidung für den
Auftraggeber richtig ist.

**Folge für den Auftraggeber:** Offene Arbeit verschwindet nicht automatisch
aus der Aufgabenliste. Der Auftraggeber sieht im Handoff genau, was geprüft
werden muss, und bestätigt die Entscheidung bewusst.

## 2026-09-04 — Modellaufrufe und lokale Logs haben sichtbare Kostenfolgen

**Was:** Zusätzliche Modellaufrufe sind nur erlaubt, wenn Taskklasse, kuratierte
Risikosignale, ein bestätigter Fehlschlag oder eine ausdrückliche Moduswahl sie
begründen. Harte Runden-, Versuchs- und Retry-Limits begrenzen die Nutzung.
Tokens und Kosten werden nur erfasst, wenn der Anbieter echte Werte liefert;
sie werden nie geschätzt. Vollständige Kontexte, Antworten und Logs bleiben
lokal unter `.agent-runs/` und werden nicht versioniert.

**Warum:** Manager-, Review- und Fresh-Worker-Aufrufe können Zuverlässigkeit
erhöhen, verbrauchen aber mehr Zeit und Modellbudget. Lokale Logs helfen bei
Fehleranalyse und Wiederaufnahme, können jedoch Inhalte aus dem Arbeitskontext
wiederholen. Darum werden Secrets vor dem Kontextaufbau ausgeschlossen und
Rohdaten nicht automatisch geteilt.

**Folge für den Auftraggeber:** Ein einfacher Task löst nicht unnötig mehrere
Modelle aus. Vor der Weitergabe eines Laufordners muss dessen Inhalt separat auf
vertrauliche Daten geprüft werden; Löschen lokaler Laufdaten reduziert die
Diagnose- und Wiederaufnahmemöglichkeiten. Der reale Pilot verursacht Kosten
und startet nur nach einem eigenen Auftrag.

## 2026-09-04 — Beispiel- und Bauunterlagen aus der Vorlage entfernt

**Was:** Die von der Entwicklungsumgebung erzeugten Beispieldateien `main.py`
und `pyproject.toml`, die leere `.mcp.json`, der Umbauplan unter `plans/` und
die veraltete Word-Fassung `KURSANLEITUNG.docx` wurden gelöscht. Die
Kursanleitung existiert nur noch als Markdown-Quelle.

**Warum:** Das Python-Beispiel widersprach dem mitgelieferten Node.js-Profil
und hatte keinen Bezug zum Produkt. Der Umbauplan war nach Abschluss aller
Phasen reine Baugeschichte, die in der Git-Historie erhalten bleibt. Die
Word-Datei war von Hand erstellt, nicht mehr mit dem Markdown synchron und
ließ sich nicht automatisch prüfen.

**Folge für den Auftraggeber:** Die Vorlage enthält nur noch, was für den
Betrieb gebraucht wird. Eine Word-Fassung der Kursanleitung wird bei Bedarf mit
einem Befehl aus dem Markdown erzeugt und nicht mehr versioniert.

## 2026-09-04 — Der Router entscheidet und führt aus; Rollout-Stufen und Pilot entfernt

**Was:** Die Rollout-Stufen (`shadow`, `single-verify`, `managed-opt-in`,
`adaptive-recommendation`, `adaptive-execution`), die Schalter `DEFAULT_MODE`
und `ROUTER_ENABLED` sowie die vorbereitete Pilot-Evaluation
(`docs/evaluation/`, `agent-metrics.sh compare`, eingefrorene Rohzahl-Schwellen)
wurden entfernt. Der deterministische Router wählt weiterhin nach Klasse,
Risiko und Fehlversuchen zwischen `single`, `verified`, `managed` und
`managed-fresh` — seine Entscheidung wird jetzt direkt ausgeführt, statt als
Empfehlung neben einer Basisvariante protokolliert zu werden.

**Warum:** Die Stufen und der Pilot dienten dazu, den Wert der Manager-Modi
erst zu beweisen, bevor sie automatisch laufen. Für ein Ein-Personen-Template,
das am lebenden Ablauf gelernt werden soll, war das ein zweiter Steuerkreis um
den ersten herum: mehr Konfiguration, mehr Codepfade, mehr Tests, ohne dass je
ein Lauf davon profitiert hätte. Die Klassen- und Risikoregeln des Routers sind
die eigentliche Entscheidung; sie bleiben vollständig erhalten.

**Folge für den Auftraggeber:** Eine offene, riskante oder wiederholt
gescheiterte Aufgabe löst ab sofort ohne weitere Freigabe den Manager-Loop
beziehungsweise zwei isolierte Worker aus — das kostet dort mehr
Modellaufrufe als bisher. Routineaufgaben bleiben bei einem Worker. Wer einen
anderen Modus will, gibt ihn pro Aufgabe mit `--mode` oder `orchestration:`
vor. Die Metriktabelle zeigt weiterhin pro Klasse und Modus, was ein Lauf
gekostet hat. Am Datenschutz ändert sich nichts: Rohdaten bleiben lokal.
