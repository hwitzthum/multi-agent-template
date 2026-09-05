# Adaptives Agentensystem für Projektarbeit

Dieses Template hält Ziel, Aufgaben, Prüfungen und Übergaben in Dateien fest.
Es wählt für jede Aufgabe den kleinsten sicheren Arbeitsmodus: eine einfache
Änderung kann direkt bearbeitet werden, eine komplexe oder festgefahrene
Aufgabe erhält zusätzliche Planung, Prüfung oder eine unabhängige zweite
Lösung. Mehrere Agenten sind deshalb eine Möglichkeit, nicht der Standard für
jede Aufgabe.

Das mitgelieferte Beispielprofil ist die **Landingpage-Fabrik**. Andere
Projektarten können über `docs/profil/` beschrieben werden.

## Vor dem ersten Lauf

Das Projekt braucht ein eigenes Git-Repository mit einem ersten Commit. Wer die
GitHub-Vorlage verwendet und sie klont, hat diesen Ausgangsstand bereits. Ein
ZIP-Download genügt nicht: sichere Vergleiche, Wiederaufnahme und isolierte
Fresh-Worker-Läufe benötigen die Git-Historie.

Danach wird das Projekt einmalig mit
`docs/templates/initializer-prompt.md` eingerichtet. Die vollständige
Nutzerreise steht in [docs/KURSANLEITUNG.md](docs/KURSANLEITUNG.md). Eine
Word-Fassung lässt sich bei Bedarf daraus erzeugen, zum Beispiel mit
`pandoc docs/KURSANLEITUNG.md -o KURSANLEITUNG.docx`.

## Die drei Hauptbefehle

```bash
# 1. Nächste ausführbare Aufgaben anzeigen
./scripts/next-tasks.sh

# 2. Die nächste Aufgabe kontrolliert bearbeiten
./scripts/orchestrate.sh --next

# 3. Projektstand und nächsten Handlungsbedarf erklären
./scripts/state-summary.sh
```

Vor einem echten Lauf zeigt `./scripts/orchestrate.sh --next --dry-run` ohne
Produktänderung den vom Router gewählten Modus und die geplanten Rollen. Eine bestimmte
Aufgabe startet mit `./scripts/orchestrate.sh --task 017`. Die globale
Projektprüfung bleibt immer `./scripts/verify.sh`.

Der Router entscheidet pro Aufgabe, wie viel Begleitung sie braucht, und diese
Entscheidung wird direkt ausgeführt: Routine läuft mit einem Worker, Fachlogik
mit Korrekturschleife, offene oder riskante Aufgaben im Manager-Worker-Loop,
festgefahrene mit zwei unabhängigen Lösungen. Eine bewusste Vorgabe ist über
`--mode` oder `orchestration:` im Task möglich, kann aber nie unter das
Sicherheitsminimum senken. Offene Aufgaben sowie Text, Optik und Rechtliches
bleiben unter menschlicher Aufsicht.

## So funktioniert die Architektur (verständlich erklärt)

### Das Grundprinzip: Aufgaben statt Chat

Traditionelle Projekte funktionieren oft wie ein langes Gespräch — Anforderungen
fliegen hin und her, Fortschritt ist unsichtbar, niemand erinnert sich später,
warum eine Entscheidung getroffen wurde. Dieses Template funktioniert anders:

**Alles läuft über strukturierte Aufgaben und Dateien.** So wie ein Rezeptbuch:
Zutat, Menge, Schritt, Überprüfung — alles aufgeschrieben, nachvollziehbar,
wiederverwendbar.

### Die vier Dateitypen

1. **Aufgaben** (`docs/tasks/*.md`): Was muss getan werden?
   - Ähnlich wie ein Post-it mit einer konkreten Aufgabe
   - Status: offen, in Arbeit, warten auf Prüfung oder fertig
   - Beispiel: "Landingpage mit Kontaktformular erstellen"

2. **Zustand** (`docs/state/`): Wo steht das Projekt gerade?
   - Ziel: Was wollen wir insgesamt erreichen?
   - Plan: Wie viele Aufgaben, in welcher Reihenfolge?
   - Entscheidungen: Warum haben wir X statt Y gewählt?
   - Übergabe: Was kommt nächstes, falls jemand anders weitermacht?

3. **Prüfbelege** (`docs/verification/`): Hat es funktioniert?
   - Automatisch generierte Berichte — wie ein TÜV-Prüfsiegel
   - "Seite baut? Ja. Alle Links funktionieren? Ja."

4. **Arbeitnotizen** (`.agent-runs/`): Rohdaten während der Arbeit
   - Nur lokal, wird nicht gespeichert (wie der Schreibblock eines
     Arbeiters, nicht das Protokoll)

### Warum ist das State-of-the-Art?

#### 1. **Niemand verliert den Überblick**

- Ein neuer Agentenlauf kann den Stand verstehen, ohne vorherige
  Chat-Nachrichten zu lesen
- Wie eine Betriebsanleitung statt Kurznachrichten: präzise, vollständig

#### 2. **Automatische Qualitätskontrolle**

- Nach jeder Aufgabe läuft ein Prüfskript: Seite baut? Tests grün? Links
  korrekt?
- Fehler werden sofort sichtbar, nicht erst in der Produktion
- Wie eine Fabrik mit Qualitätskontrolle statt "hoffen, dass es funktioniert"

#### 3. **Der Router entscheidet, wie viel Begleitung eine Aufgabe braucht**

- Kleine Aufgaben? Ein Worker, dann prüfen — schnell und günstig
- Komplexe oder offene Aufgaben? Manager plant, Worker setzt um, Prüfung, Wiederholung
- Festgefahrene Probleme? Zwei unabhängige Lösungen, ein Reviewer wählt
- Die Entscheidung ist deterministisch und nachvollziehbar (Klasse, Risiko,
  Fehlversuche) — nicht alle Aufgaben brauchen fünf Agenten, nur die, die es
  brauchen

**Wie der Router konkret entscheidet:**

Der Router wird aktiv, sobald Sie `./scripts/orchestrate.sh --next` aufrufen (oder
eine bestimmte Aufgabe mit `--task 017` starten). Er schaut sich die Aufgabe an
und fragt:

1. **Welche Art Aufgabe ist das?**
   - _Mechanisch_ (z.B. Variablenname umbenennen) → Braucht nur einen Worker
   - _Gemustert_ (z.B. neue Seite nach bestehendem Muster) → Braucht einen Worker
     plus einen Korrekturversuch, wenn es beim ersten Mal nicht klappt
   - _Offen_ (z.B. „Schreib einen überzeugende Hero-Text") → Braucht einen Manager
     zum Planen, dann einen Worker, dann Überprüfung — kann mehrfach wiederholt
     werden
   - _Festgefahren_ (im Task ist `repeated-failure` oder `conflicting-ledger`
     als Risikosignal eingetragen, oder Sie haben „braucht frische Perspektive"
     angekreuzt) → Braucht zwei vollständig unabhängige Lösungen + einen
     Reviewer, der die beste wählt

2. **Gibt es Risikosignale?**
   - _Authentifizierung, Berechtigungen, Zahlungen, Datenmigration?_ → Hochrisiko,
     braucht mindestens einen Manager
   - _Mehrere verschiedene Bereiche gleichzeitig?_ (Frontend + Backend + Datenbank)
     → Cross-Component, braucht mindestens einen Manager
   - _Andere Fehler haben sich bei dieser Sache schon einmal widersprochen?_ →
     Ledger-Konflikt, braucht zwei unabhängige Lösungen

3. **Wie oft ist diese Aufgabe schon gescheitert?**
   - Beim ersten Versuch: nach Plan
   - Nach einem Fehlschlag: eskaliert um genau eine Stufe (z.B. von „verified"
     zu „managed"); ab zwei Fehlschlägen ist der Manager-Loop das Minimum
   - Beim dritten Fehlschlag: blockiert (wird ein Entscheidungs-Fall für Sie)

Die Entscheidung wird _sofort_ ausgeführt — Sie sehen sie mit `--dry-run` vorher
ohne etwas zu verändern. Sie können den Router auch übersteuern: `--mode managed`
sagt dem Router „auf dieser Aufgabe trotzdem ein Manager, bitte"; unter das
Sicherheitsminimum (Auth, mehrere Komponenten, offene Aufgaben) lässt sich aber
nicht senken.

#### 4. **Vollständige Nachvollziehbarkeit**

- Warum wurde diese Design-Entscheidung getroffen? Steht in
  `docs/state/decisions.md`
- Wer hat was geändert? Git-Historie
- Was wurde geprüft? `docs/verification/`

#### 5. **Sicherheit von Anfang an**

- Agenten führen niemals ungeprüften Code aus
- Eingaben werden validiert, bevor etwas passiert
- Wie eine Bank mit mehreren Unterschriften, nicht ein Vertrauensvorschuss

#### 6. **Klare Rollen, keine Chaos**

- Manager: Planen
- Worker: Umsetzen (nur deren Aufgabe)
- Reviewer: Prüfen (nicht ändern)
- Finalizer: Handoff
- Keiner kann einfach die Rechte der anderen übernehmen — das würde zu
  Fehlern führen

### Ein reales Beispiel

Sagen Sie, Sie wollen eine Webseite bauen. Das könnte so laufen:

| Schritt                    | Das System                            | Ergebnis                                                 |
| -------------------------- | ------------------------------------- | -------------------------------------------------------- |
| 1. Ziel definieren         | Inhalt in `docs/state/goal.md`        | Alle wissen, worum es geht                               |
| 2. Aufgaben schreiben      | 10 konkrete Aufgaben in `docs/tasks/` | Kein Durcheinander, klare Reihenfolge                    |
| 3. Nächste Aufgabe starten | `./scripts/orchestrate.sh --next`     | System entscheidet: einfach bearbeiten oder erst planen? |
| 4. Agent arbeitet          | Agentenlauf, Datei wird geändert      | Nachvollziehbar, git-versioniert                         |
| 5. Automatisch testen      | `./scripts/verify.sh` läuft           | Seite baut? Typos? Links kaputt?                         |
| 6. Übergabe festhalten     | `docs/state/handoff.md` aktualisiert  | Nächster kann nahtlos weitermachen                       |

## So würde man die App selbst bauen: Von der ersten Datei zum fertigen System

Stellen Sie sich vor, Sie wollen diese Anwendung von Grund auf selbst entwickeln. Welche Datei würden Sie zuerst anlegen? Und welche bauen darauf auf? So funktioniert es:

### Schicht 1: Das Fundament — Das Ziel (Startpunkt)

**Erste Datei: `docs/state/goal.md`**

Hier schreiben Sie auf, was das Projekt überhaupt soll. Nicht technisch — einfach:

> "Wir wollen eine Landingpage, auf der Kunden mehr über uns erfahren und uns eine Nachricht schicken können."

**Warum das die erste Datei ist:**

- Ohne klares Ziel weiß niemand, was gelungen ist und wann man fertig ist
- Alle anderen Dateien orientieren sich danach
- Wenn später etwas unklar ist, schauen alle hier nach, was eigentlich geplant war

### Schicht 2: Die Arbeitsplanung — Aufgaben und Plan

**Aufbauend darauf: `docs/state/plan.md`**

Jetzt zerlegen Sie das Ziel in Schritte:

- Aufgabe 1: Design der Seite festlegen
- Aufgabe 2: Header und Navigation bauen
- Aufgabe 3: Kontaktformular programmieren
- Aufgabe 4: Formularversand testen
- ...und so weiter

Der Plan sagt: "Insgesamt 12 Aufgaben, in dieser Reihenfolge, und Aufgabe 5 hängt von Aufgabe 3 ab."

**Dann: `docs/tasks/001.md`, `docs/tasks/002.md`, ... (viele Dateien)**

Jede Aufgabe bekommt ihre eigene Datei:

```
Titel: Header und Navigation bauen
Beschreibung: Ein Header mit Logo und Navigation oben auf jeder Seite
Status: offen
```

Das ist wie ein Zettel für einen Arbeiter — präzise, konkret, prüfbar.

**Warum diese Reihenfolge:**

- Der Plan weiß, in welcher Reihenfolge die Aufgaben kommen
- Jede Aufgabe weiß, was sie soll
- Ein neuer Agent kann die Aufgabe später lesen und sofort anfangen

### Schicht 3: Entscheidungen festhalten

**Parallel dazu: `docs/state/decisions.md`**

Wenn Sie sich während der Arbeit für etwas Wichtiges entscheiden, schreiben Sie es hier auf:

> "Warum verwenden wir React statt Vue?
> — Grund: Der Entwickler kennt React besser und die Seite braucht viele interaktive Elemente."

**Warum das wichtig ist:**

- In zwei Monaten fragt jemand: "Warum haben wir das so gemacht?" Antwort ist sofort da.
- Neue Entwickler verstehen die Logik, nicht nur den Code.

### Schicht 4: Die Arbeit selbst — Code und Dateien

**Dann, wenn die Aufgaben laufen: Der eigentliche Code**

Ein Agent (oder Sie selbst) bearbeitet die Aufgabe und:

- Ändert `src/components/Header.jsx` — oder erstellt es neu
- Ändert `index.html`
- Vielleicht `styles/header.css`
- Alles wird in Git versioniert

**Hier passiert der Kern der Arbeit:**

- Der Entwickler liest die Aufgabendatei
- Programmiert, was darin steht
- Speichert die Änderungen mit Git-Commit

### Schicht 5: Automatische Prüfung

**Nach jeder Aufgabe: `./scripts/verify.sh` läuft automatisch**

Dieses Skript prüft:

- "Baut der Code noch?" (Keine Syntaxfehler)
- "Funktionieren alle Links?" (Keine 404-Fehler)
- "Sind die Tests grün?" (Kein Rückschritt)

Das Ergebnis landet in `docs/verification/latest.md`:

```
Build:  ✅ erfolgreich
Links:  ✅ alle funktionstüchtig
Tests:  ✅ 24/24 grün
```

**Warum das genial ist:**

- Fehler werden sofort sichtbar, nicht erst später
- Man sieht objektiv: "Hat es funktioniert oder nicht?"
- Keine versteckten Probleme

### Schicht 6: Die Übergabe — Für den nächsten

**Zum Abschluss: `docs/state/handoff.md`**

Wenn Sie die Arbeit unterbrechen (zum Abendessen, bis morgen, oder ein anderer übernimmt), schreiben Sie:

> "Aufgabe 003 fertig, Test grün. Nächster: Aufgabe 004 starten mit `./scripts/orchestrate.sh --next`."

**Das ist wie eine Notiz an Sie selbst (oder einen Kollegen):**

- Wo bin ich?
- Ist der Stand sauber?
- Was kommt nächstes?

### Die ganze Kette zusammen

```
goal.md (Ziel)
    ↓
plan.md (Reihenfolge)
    ↓
tasks/001.md, tasks/002.md, ... (Was ist zu tun?)
    ↓
decisions.md (Warum diese Entscheidungen?)
    ↓
Echter Code: src/, styles/, index.html, ... (Die Umsetzung)
    ↓
verify.sh (Hat es funktioniert?)
    ↓
verification/latest.md (Prüfergebnis)
    ↓
handoff.md (Was kommt nächstes?)
```

### Ein echtes Beispiel: Sie starten eine Aufgabe

1. Sie rufen auf: `./scripts/orchestrate.sh --next`
2. Das System liest `docs/tasks/004.md` (nächste offene Aufgabe)
3. Darin steht: "Kontaktformular in HTML schreiben, Felder: Name, E-Mail, Nachricht"
4. Ein Agent (oder Sie) öffnet `src/components/ContactForm.jsx` und schreibt den Code
5. Der Agent speichert das mit Git
6. `./scripts/verify.sh` läuft: "Baut alles? Ja." → `verification/latest.md` wird grün
7. Status in `docs/tasks/004.md` wechselt zu `done`
8. Der nächste Zettel wird angeschaut — Aufgabe 005

### Das Geheimnis: Schichten, nicht Chaos

**Jede Datei hat genau eine Aufgabe:**

- `goal.md` antwortet auf: "Was ist das Projekt?"
- `plan.md` antwortet auf: "Was sind die Schritte?"
- `tasks/*.md` antwortet auf: "Was ist konkret zu tun?"
- `decisions.md` antwortet auf: "Warum haben wir so entschieden?"
- `verify.sh` antwortet auf: "Hat es funktioniert?"
- `handoff.md` antwortet auf: "Wo machen wir morgen weiter?"

**Das ist nicht chaotisch wie ein Chat — es ist strukturiert wie ein Rezeptbuch.** Jeder weiß, wo die Information ist, und jeder kann sie verstehen.

## Weitere Befehle

```bash
./scripts/orchestrate.sh --next --dry-run   # Route, Limits und geplante Rollen ohne Änderung
./scripts/orchestrate.sh --resume           # pausierten oder fehlgeschlagenen Lauf fortsetzen
./scripts/validate-ledger.sh                # Task-Graph, Laufstand und Prüfbelege prüfen
./scripts/agent-metrics.sh summary          # finalisierte Läufe nach Klasse und Modus
./scripts/archive-notes.sh                  # erledigte/verworfene Notizen oberhalb der Quote archivieren
./scripts/migrate-tasks.sh                  # Tasks eines älteren Schemas um fehlende Felder ergänzen
```

Archivierung und Migration laufen nie automatisch; beide Befehle werden
bewusst von Hand gestartet.

## Wo der Stand liegt

- `docs/tasks/*.md` ist die einzige Aufgabenquelle.
- `docs/state/` enthält Ziel, Plan, Entscheidungen, Notizen und aktuelle
  Übergabe.
- `docs/verification/` enthält den letzten maschinellen Prüfbeleg.
- `.agent-runs/` enthält lokale Rohdaten und wird nicht versioniert.
- `.agent/README.md` beschreibt den technischen Betriebs- und
  Sicherheitsvertrag für Maintainer.

`done` ist nur über das Verifikations-Gate möglich. Bei einer Aufgabe mit
menschlicher Prüfung führt ein grüner Maschinencheck zunächst zu `review`, nie
direkt zu `done`.

Für ein anderes Projekt als Landingpages: `docs/profil/README.md`.
