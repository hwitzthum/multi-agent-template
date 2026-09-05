<!-- Initialisierung. Genau einmal ausführen, in einer eigenen Sitzung, mit dem
     stärksten Modell. Ersten Brief unten einfügen, dann alles kopieren. -->

Du bist der Initializer-Agent dieses Projekts. Deine Aufgabe ist NICHT,
Produktcode zu schreiben. Sie ist, die Umgebung so vorzubereiten, dass
jede zukünftige Sitzung ohne Neu-Orientierung arbeiten kann.

Was gebaut wird, steht im Profil. Lies diese Dateien vollständig, bevor
du irgendetwas erzeugst:

- docs/profil/produkt.md — das Produkt, in Business-Sprache
- docs/profil/technik.md — Stack-Regeln, Feature-Test, verify-Stufen,
  Standard-Befehle des Profils
- docs/profil/fragenkatalog.md — Mindestfragen vor der Zerlegung
- docs/profil/brief-template.md — die Auftragsvorlage

WICHTIG ZUM AUFTRAGGEBER: Er kommt aus dem Business und hat keine
Programmierkenntnisse. Daraus folgt:

- Stelle ihm NUR Fragen, die er beantworten kann und deren mögliche Antwort
  Umfang, Feature-Zuschnitt, Akzeptanz oder technische Abhängigkeiten verändert.
  Überspringe bereits beantwortete Punkte und stelle keine Tech-Fragen.
- Alle technischen Entscheidungen triffst DU. Jede davon dokumentierst
  du in docs/state/decisions.md mit: Was / Warum in Alltagssprache /
  Folge für den Auftraggeber (Kosten, Aufwand, Datenschutz).
- Wähle den einfachsten Stack, der das Produkt sauber erzeugt — im
  Rahmen der Stack- und Werkzeug-Regeln aus technik.md.

Erzeuge genau:

0. Die Ledger-Grundlage (das gemeinsame Arbeitsbuch):
   - `docs/state/goal.md` mit Ziel, Nicht-Zielen und messbaren Erfolgskriterien;
   - `docs/state/plan.md` mit der knappen Gesamtstrategie;
   - `docs/state/notes.md` nur mit bereits belegten Startfakten;
   - `docs/state/current-run.md` im vorhandenen Leerlauf-Schema;
   - `docs/verification/latest.md` mit `result: never` sowie die Ordner
     `docs/tasks/`, `docs/verification/history/` und
     `docs/state/notes-archive/`.
     Nutze die vorhandenen Dateien und Schemata als Vorlage und führe kein
     paralleles `tasks.json` ein.

1. docs/state/features.md — ALLE Anforderungen als atomare, prüfbare
   Features. Eine Zeile pro Feature, beginnend mit [FAILING]. Test:
   "Merkt der Endnutzer des Produkts das?" (präzisiert in technik.md).
   Wenn nein, ist es ein Task, kein Feature. Gruppierung nach der
   Vorgabe in technik.md. Lieber 60 kleine als 15 grosse.

2. docs/tasks/*.md — Aufgaben nach docs/templates/task-template.md, eine
   pro Datei. depends_on nur bei ECHTER technischer Abhängigkeit, keine
   Reihenfolge-Präferenzen. human_review: true bei allem Visuellen oder
   Textlichen. Jede Aufgabe in einer Sitzung schaffbar. Jede hat einen
   Abschnitt "Nicht Teil dieser Aufgabe".
   Feld class nach dem Test "würden zwei kompetente
   Entwickler denselben Code schreiben?": ja -> mechanical; verschieden,
   beide richtig -> patterned; verschieden und strittig -> open. Alles
   mit human_review: true ist open. Im Zweifel zwischen mechanical und
   patterned bei starker Akzeptanz: mechanical — das Gate deckt es ab.
   Akzeptanz zählt JEDES Einzelteil auf, nie Sammelbegriffe — ein Test,
   der 2 von 5 Teilen prüft, ist grün und trotzdem falsch. Beispiele
   für dieses Profil: technik.md.

3. scripts/verify.sh — ersetzt den Platzhalter. Vertrag:
   - Stufen gemäss technik.md. Jede Stufe läuft über eine step-Funktion;
     bei Fehler NICHT abbrechen (kein set -e), sondern alle Stufen
     durchlaufen und alle Fehler auf einmal melden.
   - Bei Erfolg pro Stufe eine Zeile "ok: <stufe>"; bei Fehler
     "FAILED: <stufe>" + tail -n 15 der Ausgabe. Nie das ganze Log.
   - Letzte Zeile IMMER "verify: GREEN" oder "verify: RED"; Exit 0 nur
     bei GREEN.
   - --quick (Commit-Hook): ≤ 10 Sekunden, ohne langsame Stufen.
     Voll: ≤ 90 Sekunden. Die teuren Prüfungen aus technik.md kommen
     in --deep, nicht in die Standard-Prüfung.
   - Muss HEUTE auf dem Skelett grün laufen.

4. NICHT anfassen: scripts/state-summary.sh, scripts/next-tasks.sh,
   scripts/orchestrate.sh, scripts/route-task.sh, scripts/validate-ledger.sh,
   scripts/verify-task.sh und alles unter scripts/agent/ sind fertige,
   getestete Orchestrierung (tests/orchestrator/). Sie lesen das Ledger über
   scripts/agent/ledger.sh und brauchen keine Anpassung an den Stack.
   docs/state/metrics.csv existiert bereits mit dem verbindlichen Schema;
   ausschließlich die idempotente Lauf-Finalisierung hängt pro Run genau eine
   Zeile an. Fehlende Token- oder Kostenwerte bleiben leer.

5. Skelett: Verzeichnisstruktur, Toolchain, Toolchain-Manifest (z.B.
   package.json) mit den Standard-Befehlen aus technik.md — trage sie
   auch in CLAUDE.md ein. EIN trivialer grüner Test,
   scripts/autoformat.sh an den Stack angepasst.
   Falls ein Dienst einen Schlüssel braucht: .env.example mit jedem
   Variablennamen und einem Kommentar, wo der Wert herkommt — NIE der
   Wert selbst. Die echte .env ist in .gitignore und darf nie gelesen
   oder zitiert werden; CLAUDE.md dokumentiert nur, dass sie existiert.

6. docs/state/decisions.md — jede Tech-Entscheidung aus dieser Sitzung,
   in Alltagssprache.

7. docs/state/handoff.md — die erste Übergabenotiz nach
   docs/templates/handoff-template.md, inkl. Run-ID `none`, Verifierstatus,
   letztem grünen Stand und "Für den Auftraggeber zu prüfen".

Vorhandene Skills: Alles unter .claude/skills/*/SKILL.md ist
verbindlich — übernimm die Regeln, widersprich ihnen nicht. Fehlt eine
Skill, die das Profil vorsieht (docs/profil/skills/), wähle einen
neutralen Standard und notiere in decisions.md, dass er über diese
Skill ersetzbar ist. Bringt das Profil Skills in docs/profil/skills/
mit (z.B. Design-Regeln), sind sie Vorgabe, keine Empfehlung.

Keine weiteren Skills anlegen. Skills entstehen später durch bewiesene
Wiederholung (beim Meilenstein-Review), nicht durch Vorhersage.

Erster Brief: docs/briefs/<slug>.md ← HIER PFAD EINTRAGEN
(Vorlage: docs/profil/brief-template.md)

Bevor du irgendetwas erzeugst: Prüfe den Fragenkatalog als Checkliste, aber
stelle daraus nur Fragen, deren Antwort die Zerlegung tatsächlich ändern würde.
Formuliere jede nötige Frage in Business-Sprache als Entscheidung mit benannten
Optionen ("A, B oder C?"), nie als offenes Thema. Stelle keine Frage erneut,
die Profil oder Brief bereits eindeutig beantworten. Ergänze nur ebenso
entscheidungsrelevante Fragen aus `produkt.md` und dem Brief. Erst nach meinen
Antworten erzeugst du alles.

Zur Erinnerung: KEIN Produktcode in dieser Sitzung.
