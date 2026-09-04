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

- Stelle ihm NUR Fragen, die er beantworten kann — welche das sind,
  zeigen die Achsen des Fragenkatalogs. Keine Tech-Fragen.
- Alle technischen Entscheidungen triffst DU. Jede davon dokumentierst
  du in docs/state/decisions.md mit: Was / Warum in Alltagssprache /
  Folge für den Auftraggeber (Kosten, Aufwand, Datenschutz).
- Wähle den einfachsten Stack, der das Produkt sauber erzeugt — im
  Rahmen der Stack- und Werkzeug-Regeln aus technik.md.

Erzeuge genau:

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

4. scripts/state-summary.sh — ersetzt den Platzhalter. Läuft als
   SessionStart-Hook (.claude/settings.json); seine Ausgabe landet direkt
   im Kontext jeder neuen Sitzung. Vertrag:
   ≤ 250 Tokens, Obergrenze PRO ABSCHNITT (kein globales Abschneiden):
   1 Zeile git (Branch, uncommitted, letzter Commit) · Scoreboard
   "N/M passing" · max. 8 FAILING-Features des aktuellen Meilensteins
   (gefiltert über docs/state/current-milestone) · handoff.md komplett
   · 1 Zeile Verify-Urteil (./scripts/verify.sh --quick | tail -n 1).
   Lege docs/state/current-milestone an (eine Zeile; den ersten
   Meilenstein nennt technik.md).
   docs/state/metrics.csv existiert bereits (Kopfzeile); jede
   abgeschlossene Aufgabe hängt eine Zeile an — nicht ändern.

   scripts/next-tasks.sh — ersetzt den Platzhalter. Liest das
   Frontmatter in docs/tasks/, gibt Aufgaben mit status: todo aus,
   deren depends_on alle status: done sind. Eine Zeile pro Aufgabe:
   "READY: <id> | <titel> | <class>". Nur bash + grep/awk/sed,
   keine Abhängigkeiten.

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
   docs/templates/handoff-template.md, inkl. "Für den Auftraggeber zu prüfen".

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

Bevor du irgendetwas erzeugst: Stelle mir die Fragen, deren Antwort die
Zerlegung ändern würde — in Business-Sprache, jede als Entscheidung mit
benannten Optionen ("A, B oder C?"), nicht als offenes Thema. Nutze den
Fragenkatalog in docs/profil/fragenkatalog.md als Mindestmenge; stelle
zusätzlich die Fragen, die sich aus produkt.md und dem Brief ergeben.
Erst nach meinen Antworten erzeugst du alles.

Zur Erinnerung: KEIN Produktcode in dieser Sitzung.
