---
title: "Landingpage-Fabrik — Kursanleitung"
subtitle: "Wie Sie mit Claude Code Landingpages bauen, ohne zu programmieren"
lang: de-CH
---

# Worum es geht

Sie erhalten ein vorbereitetes Projekt: die **Landingpage-Fabrik**. Damit erstellen Sie Landingpages für Ihre Organisation — mit Claude Code als Arbeitskraft und Ihnen als Auftraggeberin oder Auftraggeber.

Sie schreiben keinen Code. Ihre Aufgaben sind drei:

1. **Beschreiben**, was eine Seite erreichen soll (der «Brief»).
2. **Fragen beantworten**, die Claude Ihnen stellt.
3. **Prüfen**, was entstanden ist — im Browser, mit Ihren Augen.

Alles Technische übernimmt Claude. Jede technische Entscheidung wird Ihnen in Alltagssprache erklärt, damit Sie sie nachvollziehen und bei Bedarf ändern können.

## Das Grundprinzip: Schichtarbeit

Claude hat kein Gedächtnis zwischen zwei Sitzungen. Jede Sitzung beginnt bei null — wie ein Mitarbeiter, der jeden Morgen neu anfängt und nichts vom Vortag weiss.

Die Fabrik löst das mit einem einfachen Trick: **Alles Wichtige steht in Dateien, nicht im Chat.** Jede Sitzung beginnt damit, dass Claude eine kurze Zusammenfassung des Projektstands liest. Jede Sitzung endet damit, dass Claude eine Übergabenotiz für die nächste schreibt. So arbeitet Claude wie ein Team im Schichtbetrieb: Die Schicht wechselt, das Wissen bleibt.

Für Sie heisst das: Sie müssen Claude nie erklären, wo das Projekt steht. Das steht in den Dateien.

# Voraussetzungen

Bevor Sie beginnen, brauchen Sie:

- **Claude Code** installiert und eingerichtet (Anleitung: claude.com/claude-code).
- **Ein GitHub-Konto** (kostenlos, github.com) und **GitHub Desktop** (kostenlos, desktop.github.com) — damit holen Sie sich das Projekt ohne Terminal.
- **Ein Terminal**, in dem Sie Claude Code starten. Auf dem Mac ist das die App «Terminal». Unter Windows brauchen Sie **Git Bash** (kostenlos, wird mit Git installiert) — die normale Windows-Eingabeaufforderung reicht nicht.

Sie müssen im Terminal nur zwei Dinge können:

- In den Projektordner wechseln: `cd Pfad/zum/Ordner/<ihr-projektname>`
- Claude Code starten: `claude`

Alles Weitere geschieht im Gespräch mit Claude.

## Schritt 0: Das Projekt holen (einmalig, ca. 10 Minuten)

Das Startkit liegt als Vorlage auf GitHub. Sie erstellen daraus Ihr **eigenes** Projekt — eine Kopie, die nur Ihnen gehört.

1. Öffnen Sie im Browser: **https://github.com/hwitzthum/project-template**
2. Klicken Sie oben rechts auf den grünen Button **«Use this template»** → **«Create a new repository»**.
3. Geben Sie einen Namen (z.B. `landingpages-meinverein`), wählen Sie **Private**, und klicken Sie **«Create repository»**. Sie haben jetzt Ihr eigenes Projekt auf GitHub.
4. Auf diesem neuen Projekt: grüner Button **«Code»** → **«Open with GitHub Desktop»**. GitHub Desktop fragt, wo der Ordner auf Ihrem Computer liegen soll — merken Sie sich diesen Pfad.
5. In GitHub Desktop: **«Repository» → «Open in Terminal»** (Mac) bzw. **«Open in Git Bash»** (Windows). Dort tippen Sie `claude` — fertig.
6. Beim allerersten Start fragt Claude Code, ob Sie den Dateien in diesem Ordner vertrauen. Antworten Sie mit **Ja** — bei «Nein» beendet sich Claude Code sofort. Erst mit dieser Bestätigung gelten die eingebauten Schutzregeln (siehe unten «Was Claude nicht darf»).

Wichtig: **Nicht als ZIP herunterladen.** Die ZIP-Variante hat keine Projekt-Historie, und ohne sie funktionieren die eingebauten Sicherheitsprüfungen nicht.

# Der Projektordner — was wo liegt

Sie müssen nicht jede Datei kennen. Diese vier Orte sind für Sie wichtig:

| Ort                       | Was dort ist                                                                            | Wer schreibt dort           |
| ------------------------- | --------------------------------------------------------------------------------------- | --------------------------- |
| `docs/briefs/`            | Ein Brief pro Landingpage: Ihr Auftrag in Ihren Worten                                  | **Sie** (mit Claudes Hilfe) |
| `docs/state/handoff.md`   | Die Übergabenotiz der letzten Sitzung, inkl. Abschnitt «Für den Auftraggeber zu prüfen» | Claude                      |
| `docs/state/decisions.md` | Alle technischen Entscheidungen, in Alltagssprache erklärt                              | Claude                      |
| `docs/state/features.md`  | Die Liste aller Eigenschaften der Seite, jede mit Status «erledigt» oder «offen»        | Claude                      |

Dazu gibt es zwei Ordner mit Vorlagen und fertigen Texten, die Sie in Claude Code einfügen: `docs/profil/` (alles, was speziell für Landingpages ist: Brief-Vorlage, Design-Regeln, Fragen) und `docs/templates/` (die allgemeinen Vorlagen, u.a. der Initialisierungs-Text). Die brauchen Sie in den Schritten unten.

Alles andere (`scripts/`, `src/`, `.claude/`) ist Claudes Werkstatt. Sie müssen dort nichts anfassen.

# Die Schritte

## Schritt 1: Design-Regeln festhalten (einmalig, ca. 20 Minuten)

Damit alle Ihre Landingpages einheitlich aussehen, legen Sie einmal die Design-Regeln Ihrer Organisation fest: Farben, Schrift, Logo, Tonalität, und vor allem: **die eine Handlung**, die Besucher ausführen sollen.

Sie müssen dafür kein Designer sein. Claude führt Sie durch ein Gespräch.

**So geht es:**

1. Terminal öffnen, in den Projektordner wechseln, `claude` eingeben.
2. Die Datei `docs/profil/skills/design-skill-interview-prompt.md` öffnen (mit einem beliebigen Texteditor), den gesamten Inhalt kopieren und in Claude Code einfügen.
3. Claude stellt Ihnen nun Frage für Frage. Antworten Sie kurz. Wenn Sie etwas nicht wissen, sagen Sie das — Claude schlägt Ihnen Optionen vor.
4. Am Ende zeigt Claude Ihnen die fertige Datei. Lesen Sie sie durch. Wenn sie stimmt, antworten Sie mit «ok».

**Hilfreich, wenn Sie es zur Hand haben:** Ihr Logo (als Datei), die Adresse Ihrer bestehenden Website, ein Dokument mit Ihren Farben. Claude kann daraus die Werte ableiten.

**Was dabei entsteht:** Eine Regel-Datei, die Claude in jeder künftigen Sitzung automatisch beachtet — Sie müssen die Regeln nie wiederholen.

## Schritt 2: Den ersten Brief schreiben (ca. 20 Minuten)

Der Brief ist Ihr Auftrag für eine Landingpage. Er beantwortet: Was soll die Seite erreichen? Für wen? Was sollen Besucher tun? Was gehört ausdrücklich **nicht** auf die Seite?

Sie können den Brief allein schreiben (Vorlage: `docs/profil/brief-template.md`) — oder Sie lassen sich von Claude interviewen. Das zweite ist meist besser, weil Claude nachfragt, wo Sie sonst etwas vergessen würden.

**So geht es mit Claude:**

1. Claude Code starten (falls nicht schon offen).
2. Diesen Text einfügen:

> Ich möchte den ersten Brief für eine Landingpage schreiben. Die Vorlage liegt in docs/profil/brief-template.md. Führe mich Abschnitt für Abschnitt durch: Stelle mir pro Abschnitt eine Frage, warte auf meine Antwort, fasse sie in meiner Sprache zusammen. Wenn ich etwas nicht weiss, schlage 2–3 Optionen vor, die typisch sind. Am Ende speichere das Ergebnis als docs/briefs/\<slug\>.md und zeige mir die Datei zum Gegenlesen. Kein Code, keine Tech-Entscheidungen — nur der Brief.

3. Antworten Sie auf die Fragen. Claude schlägt einen Kurznamen («slug») für die Seite vor, z.B. `herbstkurs`.

**Der wichtigste Abschnitt ist «Nicht Teil dieser Seite».** Alles, was Sie dort nicht ausschliessen, baut Claude möglicherweise aus Gefälligkeit mit — und Sie zahlen für Arbeit, die Sie nicht wollten. Nehmen Sie sich für diesen Abschnitt Zeit.

## Schritt 3: Die Initialisierung (einmalig, ca. 45 Minuten)

Jetzt bereitet Claude die Fabrik vor: Es wählt die Technik, baut das Grundgerüst, zerlegt Ihren Brief in kleine Arbeitspakete und richtet die automatischen Prüfungen ein. In dieser Sitzung wird **noch keine Seite gebaut** — nur der Plan und die Werkstatt.

**So geht es:**

1. Eine **neue** Claude-Code-Sitzung starten (Terminal schliessen und neu öffnen, oder in Claude Code `/clear` eingeben).
2. Falls Claude Code Sie nach dem Modell fragt oder Sie es wählen können: Nehmen Sie für diese eine Sitzung **das stärkste verfügbare Modell**. Diese Sitzung legt das Fundament für alle weiteren; hier lohnt sich Qualität.
3. Die Datei `docs/templates/initializer-prompt.md` öffnen. Suchen Sie die Zeile «Erster Brief: docs/briefs/\<slug\>.md ← HIER PFAD EINTRAGEN». Ersetzen Sie `<slug>` durch den Kurznamen Ihres Briefs.
4. Den gesamten Text kopieren und in Claude Code einfügen.
5. **Claude stellt Ihnen jetzt Fragen** — etwa sieben bis zehn, alle in Alltagssprache, jede mit Optionen («A, B oder C?»). Antworten Sie kurz und entschieden. Diese Antworten sind die wertvollsten fünf Minuten des ganzen Projekts: Jede Frage, die Sie jetzt beantworten, erspart später eine Sitzung Nacharbeit.
6. Wenn Claude eine technische Frage stellt: Antworten Sie «Entscheide selbst und dokumentiere es in decisions.md».
7. Nach Ihren Antworten erzeugt Claude alle Dateien. Das dauert einige Minuten.

**Danach prüfen Sie — ohne Code zu lesen:**

- Bitten Sie Claude: «Führe ./scripts/verify.sh aus.» Die letzte Zeile muss `verify: GREEN` lauten. Wenn nicht: «Finde die Ursache und erkläre sie mir in zwei Sätzen, bevor du etwas änderst.»
- Öffnen Sie `docs/state/decisions.md`. Verstehen Sie jede Entscheidung? Wenn nicht: «Erkläre Entscheidung X so, dass ich sie einem Kunden erklären könnte.» Wenn Ihnen eine Folge nicht passt (Kosten, Datenschutz): jetzt ändern lassen, nicht später.
- Öffnen Sie `docs/state/features.md`. Beschreibt jede Zeile etwas, das ein **Besucher der Seite bemerken** würde? Zeilen wie «Formular-Handler bauen» gehören nicht hinein — melden Sie sie Claude.
- Bitten Sie Claude: «Führe ./scripts/next-tasks.sh aus.» Es sollten mehrere Aufgaben als bereit angezeigt werden. Wird nur eine angezeigt, fragen Sie: «Bestätige für jede Abhängigkeit, dass sie technisch zwingend ist.»

## Schritt 4: Arbeitssitzungen (wiederkehrend, je 20–60 Minuten)

Ab jetzt läuft das Projekt in Schichten. Jede Sitzung erledigt eine Aufgabe.

**Eine Sitzung beginnen:**

1. Neue Claude-Code-Sitzung starten.
2. Eingeben: «Führe ./scripts/next-tasks.sh aus und bearbeite die erste bereite Aufgabe.» — Oder, wenn Sie eine bestimmte wollen: «Bearbeite die Aufgabe docs/tasks/004-….md».
3. Claude liest von selbst die Projektzusammenfassung, die Übergabenotiz und die Aufgabe — Sie müssen nichts erklären.
4. Claude arbeitet. Gelegentlich fragt es nach einer Erlaubnis (z.B. für einen Befehl, der nicht auf der Liste steht). Lesen Sie kurz, was es tun will, und bestätigen Sie, wenn es zur Aufgabe passt.

**Eine Sitzung beenden:**

Claude beendet die Aufgabe selbst: Es prüft, speichert («commit») und schreibt die Übergabenotiz. Falls es das vergisst, sagen Sie: «Aktualisiere docs/state/handoff.md.»

**Ihre Prüfung nach jeder Sitzung:**

Öffnen Sie `docs/state/handoff.md` und lesen Sie den Abschnitt **«Für den Auftraggeber zu prüfen»**. Dort listet Claude auf, was nur ein Mensch beurteilen kann — Texte, Optik, Rechtliches. Für alles Sichtbare:

1. Sagen Sie Claude: «Starte die Vorschau» (oder `npm run dev`). Claude nennt Ihnen eine Adresse wie `http://localhost:…`.
2. Öffnen Sie diese Adresse im Browser. Schauen Sie sich die Seite an — auch auf dem Handy oder mit schmalem Browserfenster.
3. Was nicht stimmt, sagen Sie Claude in der nächsten Sitzung in normalen Worten: «Die Überschrift ist zu lang», «Der Button soll grün sein wie im Logo».

**Welches Modell für welche Aufgabe?** Jede Aufgabe trägt eine Klasse:

- `mechanical` — Routinearbeit, ein günstiges Modell reicht.
- `patterned` — Fachlogik, das mittlere Modell.
- `open` — Texte, Design, Entscheidungen: das starke Modell, **und Sie bleiben dabei**.

Wenn Sie in Claude Code das Modell wählen können (`/model`), richten Sie sich danach. Wenn nicht, ist das kein Problem — es geht nur um Kosten, nicht um Funktion.

## Schritt 5: Meilenstein-Review (alle paar Wochen, ca. 30 Minuten)

Wenn eine Seite fertig ist oder ein grösserer Abschnitt abgeschlossen, machen Sie eine kurze Bestandsaufnahme:

1. **Übergabenotiz aufräumen.** Bitten Sie Claude: «Lies docs/state/handoff.md. Welche Fallen oder Regeln sind mehr als einmal aufgetreten? Schlage vor, wohin sie gehören (CLAUDE.md, eine Skill, oder ein Mechanismus), und lösche, was sich nicht wiederholt hat.» Sie entscheiden, was Claude vorschlägt.
2. **CLAUDE.md prüfen.** Diese Datei liest Claude in jeder Sitzung — jede Zeile kostet. Fragen Sie: «Welche Zeile in CLAUDE.md hast du in den letzten zehn Sitzungen nicht gebraucht?» Was nicht gebraucht wurde, kommt raus.
3. **Zahlen anschauen.** In `docs/state/metrics.csv` steht pro erledigter Aufgabe, wie viele Runden und Tokens sie gekostet hat. Sie müssen das nicht auswerten — aber wenn eine Aufgabe auffällig teuer war, fragen Sie Claude warum. Meist ist die Antwort: Die Aufgabe war zu gross oder zu vage.

## Weitere Seiten

Für jede weitere Landingpage: Schritt 2 (neuer Brief), dann eine kurze Initialisierung nur für diese Seite. Sagen Sie Claude: «Es gibt einen neuen Brief in docs/briefs/\<slug\>.md. Ergänze features.md um eine Gruppe für diese Seite und lege die zugehörigen Aufgaben in docs/tasks/ an — nach demselben Vorgehen wie in docs/templates/initializer-prompt.md, aber nur für diese Seite. Stelle mir vorher die Fragen, deren Antwort die Zerlegung ändern würde.» Dann weiter mit Schritt 4.

# Was Sie wissen sollten

## Was Claude nicht darf — mit Absicht

Die Fabrik hat Sperren eingebaut. Claude darf **nicht**:

- etwas ins Internet hochladen (`git push`, `curl`, `wget`),
- Dateien massenhaft löschen (`rm -r…`),
- ungespeicherte Arbeit verwerfen (`git reset --hard`, `git checkout --`, `git clean`, `git restore`),
- speichern («commit»), wenn die automatische Prüfung rot ist.

Diese Sperren prüfen jeden Befehl, bevor er läuft — auch versteckt in einem längeren Befehl. Sie sind ein Stolperdraht, kein Tresor: Wer Claude ausdrücklich bittet, eine Sperre zu umgehen, bekommt vielleicht einen Weg. Bitten Sie also nicht darum.

Wenn Claude sagt, es dürfe etwas nicht: Das ist kein Fehler, sondern der Schutz. Veröffentlichen Sie Seiten bewusst und selbst — Claude erklärt Ihnen, wie.

## Geheimnisse

Falls ein Dienst (z.B. für Formulare) einen Zugangsschlüssel braucht, legt Claude eine Datei `.env.example` an. Sie zeigt, **welche** Schlüssel gebraucht werden — nicht die Werte. Die echten Werte tragen Sie selbst in eine Datei `.env` ein (Claude erklärt Ihnen, wie). **Tippen Sie Schlüssel nie in den Chat.** Der Chat ist kein Tresor.

## Wenn etwas schiefgeht

- **Die Prüfung ist rot und Sie verstehen nicht, warum:** Neue Sitzung, dann: «verify.sh schlägt fehl. Finde die Ursache in einem Subagenten und erkläre mir das Ergebnis in zwei Sätzen, bevor du etwas änderst.»
- **Claude will einen Test «lockern», damit er besteht:** Nein. Sagen Sie: «Behebe die Ursache, nicht den Test.» Ein Test, der immer besteht, prüft nichts.
- **Claude baut mehr als verlangt («da ich schon dabei bin»):** Verweisen Sie auf die Aufgabe: «Das steht unter _Nicht Teil dieser Aufgabe_. Mach es rückgängig.»
- **Sie haben den Faden verloren:** Bitten Sie Claude: «Führe ./scripts/state-summary.sh aus und erkläre mir in fünf Sätzen, wo das Projekt steht.»
- **Etwas ist kaputt und war vorher gut:** Alles ist in Git gespeichert. Sagen Sie: «Zeige mir die letzten Commits und erkläre, was sich seit dem letzten funktionierenden Stand geändert hat.»

## Drei Regeln, die alles zusammenhalten

1. **Ein Brief pro Seite, vollständig ausgefüllt.** Jede Lücke wird eine Rückfrage oder eine Nacharbeit.
2. **Jede Sitzung beginnt mit der Zusammenfassung und endet mit der Übergabe.** Das ist in den Regeln der Fabrik verankert — Claude macht es von selbst. Wenn nicht, erinnern Sie es.
3. **Sie prüfen das Sichtbare, die Maschine prüft den Rest.** Sie müssen keinen Code lesen. Sie müssen die Seite anschauen.

# Kleines Glossar

| Begriff         | Bedeutung                                                                                    |
| --------------- | -------------------------------------------------------------------------------------------- |
| Brief           | Ihr Auftrag für eine Seite, in Ihren Worten. Liegt in `docs/briefs/`.                        |
| Initialisierung | Die einmalige Vorbereitungssitzung: Technik wählen, Plan erstellen, Werkstatt einrichten.    |
| Feature         | Eine Eigenschaft, die ein Besucher bemerkt. Status: offen (FAILING) oder erledigt (PASSING). |
| Aufgabe (Task)  | Ein Arbeitspaket, das in einer Sitzung erledigt wird. Liegt in `docs/tasks/`.                |
| Handoff         | Die Übergabenotiz zwischen zwei Sitzungen.                                                   |
| verify          | Die automatische Prüfung. GREEN = alles in Ordnung, RED = etwas ist kaputt.                  |
| Commit          | Ein gespeicherter Stand des Projekts. Kann jederzeit wiederhergestellt werden.               |
| Skill           | Eine Regel-Datei, die Claude bei Bedarf automatisch liest — z.B. Ihre Design-Regeln.         |
| human_review    | Kennzeichen an einer Aufgabe: «Das muss ein Mensch anschauen.»                               |
| Klasse (class)  | Wie anspruchsvoll eine Aufgabe ist: mechanical, patterned, open. Bestimmt das Modell.        |
