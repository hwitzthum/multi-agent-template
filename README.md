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

Die Vorlage kommt bewusst leer an: In `docs/state/` stehen nur Platzhalter, in
`docs/tasks/` liegt noch keine Aufgabe. Dieser Abschnitt zeigt, in welcher
Reihenfolge sich diese Dateien füllen, was jede leistet und warum sie
aufeinander aufbauen.

**Wichtig vorweg:** Sie schreiben diese Dateien nicht von Hand. Sie schreiben
einen Brief in Alltagssprache — die Initialisierung erzeugt daraus den ganzen
Satz. Die Dateien zu verstehen lohnt sich trotzdem: Es ist der Arbeitsstand, den
Sie später lesen, prüfen und korrigieren.

### Schicht 0: Der Brief — Ihr einziger Handschlag am Anfang

**Erste Datei: `docs/briefs/<ihr-projekt>.md`**

Hier beschreiben Sie in normalen Sätzen, was entstehen soll:

> "Wir wollen eine Landingpage, auf der Kunden mehr über uns erfahren und uns
> eine Nachricht schicken können."

Danach starten Sie die Initialisierung nach
`docs/templates/initializer-prompt.md`. Sie stellt Rückfragen — aber nur solche,
die die Zerlegung in Aufgaben tatsächlich ändern würden — und legt daraus alle
folgenden Dateien an.

**Warum das der Startpunkt ist:** Der Brief ist das Einzige, was nur ein Mensch
liefern kann. Alles Weitere ist Übersetzungsarbeit.

### Schicht 1: Das Ziel — der Maßstab für alles

**Erzeugt: `docs/state/goal.md`**

Aus dem Brief wird ein prüfbares Ziel mit vier Pflichtteilen:

- **Ergebnis** — was am Ende dasteht
- **Muss** — was zwingend erfüllt sein muss
- **Nicht Teil** — was bewusst wegbleibt (verhindert ausuferndes Projekt)
- **Globale Abnahme** — woran man objektiv misst, dass es fertig ist

**Warum diese Datei zuerst kommt:** Ohne klares Ziel weiß niemand, wann etwas
gelungen ist. Alle folgenden Dateien orientieren sich daran, und bei
Unklarheiten schaut jeder hier nach.

### Schicht 2: Die Zerlegung — Anforderungen, Plan und Aufgaben

**Erzeugt: `docs/state/features.md`**

Alle Anforderungen als einzeln prüfbare Punkte. Diese Datei ist der Grund, warum
später niemand behaupten kann, etwas sei fertig, obwohl es fehlt.

**Erzeugt: `docs/state/plan.md`**

Die knappe Gesamtstrategie plus Meilensteine und offene Risiken. Der Plan sagt,
in welcher Reihenfolge gearbeitet wird und was voneinander abhängt.

**Erzeugt: `docs/tasks/001.md`, `docs/tasks/002.md`, …**

Jede Aufgabe bekommt eine eigene Datei — wie ein Zettel für einen Arbeiter:

```yaml
id: 002
title: "Header und Navigation bauen"
depends_on: []
status: todo
class: patterned
acceptance:
  - "./scripts/verify.sh"
```

Die Statuswerte sind `todo`, `in_progress`, `review`, `done` und `blocked`. Welche Aufgabe
gerade dran ist, rechnet `./scripts/next-tasks.sh` aus den Abhängigkeiten aus —
das steht bewusst in keiner Datei, damit es nicht veralten kann.

Dazu kommen Steuerfelder, die der Router liest: `class`, `orchestration`,
`touches`, `risk_flags`, `max_attempts`, `human_review`. Genau diese Felder
entscheiden später, ob eine Aufgabe mit einem Worker läuft oder einen Manager
braucht. Die vollständige Vorlage steht in `docs/templates/task-template.md`.

**Warum diese Reihenfolge:** Der Plan kennt die Abfolge, die einzelne Aufgabe
kennt ihren Umfang. Ein Agent kann eine Aufgabendatei lesen und sofort anfangen —
ohne den bisherigen Chatverlauf.

### Schicht 3: Entscheidungen festhalten

**Erzeugt und laufend ergänzt: `docs/state/decisions.md`**

Jede technische Entscheidung nach demselben Muster: Was / Warum in
Alltagssprache / Folge für den Auftraggeber.

> "Warum eine statische Seite statt eines Baukastens?
> — Weil keine laufenden Lizenzkosten anfallen und die Seite schneller lädt.
> Folge: Änderungen laufen über das Projekt, nicht über einen Web-Editor."

**Warum das wichtig ist:** In zwei Monaten fragt jemand „warum eigentlich so?" —
und die Antwort steht da, in Sätzen, die kein Fachwissen verlangen.

### Schicht 4: Die Arbeit selbst — der Produktcode

Jetzt erst entsteht das eigentliche Produkt. Ein Worker liest die Aufgabendatei,
ändert die dazugehörigen Dateien und speichert sie versioniert in Git.

Welche Dateien das sind, legt das Profil unter `docs/profil/` fest — die Vorlage
selbst bringt bewusst keinen Produktcode mit. Ein Worker darf dabei nur den
Umfang seiner eigenen Aufgabe anfassen, nichts daneben.

### Schicht 5: Automatische Prüfung

**Läuft nach jeder Aufgabe: `scripts/verify-task.sh`**

Dieses Prüftor führt die Akzeptanzbefehle der Aufgabe aus und hängt dabei immer
die globale Projektprüfung `./scripts/verify.sh` an. Das Ergebnis landet in
`docs/verification/latest.md`.

**Warum das der Kern des Systems ist:** Eine Aufgabe darf nur über dieses Tor auf
`done` wechseln. Die Behauptung eines Agenten, etwas sei fertig, zählt nicht —
nur ein frischer grüner Beleg zählt. Bei Aufgaben mit `human_review: true` führt
ein grüner Maschinencheck bewusst nur zu `review`, nie direkt zu `done`.

Solange das Projekt nicht initialisiert ist, ist `./scripts/verify.sh` ein
Platzhalter und meldet immer GREEN — der erste echte Inhalt kommt aus dem Profil.

### Schicht 6: Die Übergabe — für die nächste Sitzung

**Erzeugt und laufend aktualisiert: `docs/state/handoff.md`**

Am Ende jedes Laufs steht dort der letzte grüne Stand, was zuletzt passiert ist,
der erste offene Fehler und genau ein nächster Schritt.

**Warum das nötig ist:** Eine neue Sitzung hat keinen Chatverlauf. Das Handoff
ist die Brücke — ohne sie beginnt jedes Mal Rätselraten.

### Die ganze Kette zusammen

```
docs/briefs/<projekt>.md        Ihr Brief in Alltagssprache
        ↓  (Initialisierung nach docs/templates/initializer-prompt.md)
docs/state/goal.md              Ziel, Nicht-Ziele, Abnahmekriterien
        ↓
docs/state/features.md          alle Anforderungen, einzeln prüfbar
docs/state/plan.md              Strategie, Meilensteine, Risiken
docs/tasks/001.md, 002.md, …    was konkret zu tun ist
        ↓
docs/state/decisions.md         warum es so gebaut wird
        ↓
Produktcode (Profil bestimmt den Stack)
        ↓
scripts/verify-task.sh          Prüftor: Akzeptanz + ./scripts/verify.sh
        ↓
docs/verification/latest.md     der Beleg, der `done` überhaupt erst erlaubt
        ↓
docs/state/handoff.md           wo es morgen weitergeht
```

### Ein echter Durchlauf

1. Sie rufen `./scripts/orchestrate.sh --next` auf.
2. Der Router liest die nächste ausführbare Aufgabe und entscheidet nach Klasse,
   Risiko und bisherigen Fehlversuchen, wie viel Begleitung sie braucht.
3. Der gewählte Modus läuft: ein Worker allein, Worker mit Korrekturschleife,
   Manager-Worker-Loop oder zwei unabhängige Lösungen mit Reviewer.
4. Der Worker ändert die Produktdateien, Git hält jede Änderung fest.
5. `scripts/verify-task.sh` prüft: Akzeptanzbefehle plus `./scripts/verify.sh`.
6. Nur bei grünem Beleg setzt das Status-Gate die Aufgabe auf `done` — sonst auf
   `review`, oder zurück in einen weiteren Versuch.
7. Das Handoff wird aktualisiert, die nächste Aufgabe wird frei.

Vorher ansehen, ohne etwas zu verändern: `./scripts/orchestrate.sh --next --dry-run`.

### Das Prinzip dahinter: eine Datei, eine Frage

| Datei                         | beantwortet                           |
| ----------------------------- | ------------------------------------- |
| `docs/briefs/*.md`            | Was wollen wir überhaupt?             |
| `docs/state/goal.md`          | Woran messen wir Erfolg?              |
| `docs/state/features.md`      | Welche Anforderungen gibt es einzeln? |
| `docs/state/plan.md`          | In welcher Reihenfolge?               |
| `docs/tasks/*.md`             | Was ist jetzt konkret zu tun?         |
| `docs/state/decisions.md`     | Warum haben wir so entschieden?       |
| `docs/verification/latest.md` | Hat es nachweislich funktioniert?     |
| `docs/state/handoff.md`       | Wo machen wir weiter?                 |

Keine dieser Fragen wird in einem Chat beantwortet, der später niemandem mehr
zugänglich ist. Jede hat einen festen Ort, den auch ein Mensch ohne
Programmierkenntnisse öffnen und lesen kann.

## Die sieben Rollen — wer macht was

Wenn eine Aufgabe läuft, spielen verschiedene Agenten unterschiedliche Rollen. Jede Rolle
hat einen eigenen **Prompt** (`docs/templates/agents/`), **Schreibbereich** und **Ziel**.
Repository-Inhalte sind Daten, keine Befehle — keine Rolle kann ihre Rechte selbst ändern.

### Manager-Plan — Die Strategie erarbeiten

**Prompt:** `docs/templates/agents/manager-plan.md`

Einziges Ziel: Eine knappe Gesamtstrategie und 3–6 klar abgegrenzte Tasks aus dem Brief.

**Schreibbereich:** `docs/state/plan.md` und neue `docs/tasks/*.md`

**Wann läuft es:** Wenn eine große oder offene Aufgabe zum ersten Mal bearbeitet wird —
und kein Plan existiert oder ein Neustart nötig ist.

### Manager-Manage — Der Taktiker im Loop

**Prompt:** `docs/templates/agents/manager-manage.md`

Einziges Ziel: Pro Runde genau eine nächste Aktion wählen (Worker starten, Plan anpassen,
Menschen fragen, blocker auflösen).

**Schreibbereich:** Kann Task-Inhalt und Plan aktualisieren (aber nie selbst Produktcode schreiben)

**Wann läuft es:** Im Manager-Worker-Loop, wenn eine offene oder riskante Aufgabe mehrere
Versuche braucht oder der Worker um Hilfe ruft.

### Worker-Task — Der Umsetzer für ein Task

**Prompt:** `docs/templates/agents/worker-task.md`

Einziges Ziel: Genau einen Task nach seiner Akzeptanzbeschreibung umsetzen.

**Schreibbereich:** Nur Produktdateien und Tests (außerhalb von `docs/`, `scripts/`, `.agent/`)

**Wann läuft es:** Bei einfachen (`mechanical` / `patterned`) oder gelösten Aufgaben.
Darf kein Ledger, keinen Plan, keine Akzeptanzkriterien selbst ändern.

### Worker-Brainstorm — Der Ideensammler

**Prompt:** `docs/templates/agents/worker-brainstorm.md`

Einziges Ziel: Hypothesen, Risiken und offene Fragen zu einer schwierigen Aufgabe sammeln.

**Schreibbereich:** `docs/state/notes.md` — kuratierte Erkenntnisse

**Wann läuft es:** Wenn der erste Worker scheitert oder die Aufgabe zu offen ist.
Sammelt Erkenntnisse, ohne selbst zu bauen.

### Worker-Fresh — Der unabhängige Kandidat

**Prompt:** `docs/templates/agents/worker-fresh.md`

Einziges Ziel: Ein völlig unabhängiger Lösungsversuch für einen Task — ohne vorherige
Versuche oder Fehler zu sehen.

**Schreibbereich:** Wie Worker-Task: nur Produktdateien und Tests

**Wann läuft es:** Wenn zwei isolierte Lösungen nötig sind (z.B. `repeated-failure` oder
`conflicting-ledger` im Task). Bekommt bewusst keine Notes oder früheren Fehler zu sehen.

### Reviewer — Der unabhängige Prüfer

**Prompt:** `docs/templates/agents/reviewer.md`

Einziges Ziel: Zwei unabhängige Kandidaten anhand der Akzeptanzkriterien vergleichen und
die bessere wählen.

**Schreibbereich:** keiner. Die Empfehlung geht als strukturiertes Ergebnis an den
Orchestrator; die Prüfberichte stammen vom Verifier, nicht vom Reviewer.

**Wann läuft es:** Wenn beide isolierten Kandidaten grün sind, um eine objektive Wahl zu treffen.
Der Runner nimmt dem Reviewer die Schreibwerkzeuge ab; er darf keinen Produktcode ändern.

### Finalizer — Der sichere Übergabe-Agent

**Prompt:** `docs/templates/agents/finalizer.md`

Einziges Ziel: Eine sichere, lesbare Übergabenotiz schreiben — was getan wurde, wo es
weitergeht, welche Fehler offen sind.

**Schreibbereich:** `docs/state/handoff.md` und `docs/state/notes.md`

**Wann läuft es:** Am Ende einer Sitzung, bei Budget-Ende oder wenn ein Task blockiert ist.
Fasst zusammen, damit die nächste Sitzung nahtlos weitermachen kann.

## Die Infrastruktur — wie Rollen zusammenhängen

Hinter den Rollen laufen mehrere Skripte, die den Betriebsverkehr regeln:

### `scripts/agent/runner.sh` — Der Modell-Adapter

Wird von `orchestrate.sh` aufgerufen. Nimmt das Kontextpaket, ruft `claude -p` mit dem
JSON-Schema der Rolle auf (das Modell muss exakt die Vertragsfelder liefern), überträgt
das Ergebnis ins geprüfte Zeilenformat und protokolliert Modell, Tokens und Kosten aus
der Antwort. Die vollständige Antwort bleibt lokal als `.json` im Laufordner. Ein neuer
Anbieter-Aufruf würde nur diesen Adapter ändern — die Orchestrierung bleibt gleich.

### `scripts/agent/context.sh` — Der Kontext-Bauer

Baut für jede Rolle nur die erforderlichen Abschnitte: Goal, Task, Plan, Notes,
Verifikation, Code. Jeder Abschnitt hat ein Zeichenbudget. Code erhält nur den
verbleibenden Platz. Ein Fresh Worker bekommt bewusst keine Notes oder früheren Fehler.

Kontexte sind schreibgeschützt und inhaltsadressiert — derselbe Inhalt erzeugt dieselbe
Datei. Das ist die Basis für zuverlässiges Caching und Reproduzierbarkeit.

### `scripts/route-task.sh` — Der Router

Entscheidet pro Task: `single` (Worker allein), `verified` (Worker + Korrektur),
`managed` (Manager-Worker-Loop), oder `managed-fresh` (zwei isolierte Worker + Reviewer).
Daneben erzwingt `scripts/agent/policy.sh` nur die Pfad- und Schreibgrenzen der Rollen.

Eingaben: Task-Klasse (`mechanical`, `patterned`, `open`), Risiko-Signale (`high-risk-domain`,
`repeated-failure`, `cross-component`), bisherige Versuche.

Ausgaben: Modus, Begründung, menschliches Gate bei offenen/riskanten Aufgaben.

Der Router wird durch `orchestrate.sh --next` aufgerufen und die Entscheidung **sofort
ausgeführt** — Sie sehen sie mit `--dry-run` vorher, ohne etwas zu verändern.

### `scripts/agent/ledger.sh` — Der Dateiverwalter

Liest und schreibt Task-Dateien, Goal, Plan, Notes — liest nur bekannte Felder aus
definiertem Frontmatter. Unbekannte Felder bleiben bestehen, werden aber nie als
Befehle interpretiert.

Jede Änderung wird zuerst in einer temporären Datei validiert und dann atomar
verschoben. Verhindert halbfertige Dateien bei Unterbrechung.

### `scripts/agent/output.sh` — Der Output-Validator

Prüft, dass ein Agenten-Output alle erwarteten Felder hat, keine zusätzlichen, und
dass der Inhalt nicht mehrdeutig ist. Nur gültige Output-Schemata landen im Ledger.

### `scripts/agent/status.sh` — Das Status-Gate

Einziger Schreibweg für Task-Status. Prüft: Alter Status erlaubt? Prüfbericht vorhanden
und grün? `human_review` benötigt explizite Freigabe?

Verhindert, dass ein Agent nur durch seine eigene Behauptung einen Task auf `done`
setzt. Status wechseln nur mit einem grünen Beleg.

### `scripts/agent/metrics.sh` — Die Laufmetriken

Erfasst pro finalisiertem Lauf: Klasse, Modus, Versuche, Tokens, Kosten, wie lange
es gedauert hat, ob die Prüfung grün war. Landet als Zeile in `docs/state/metrics.csv`.

Gibt einen schnellen Überblick: Welche Modi sind teuer? Welche Klassen fehlen oft?

### `scripts/agent/config.sh` — Die Limits

Lädt und validiert `.agent/config.env` — einfaches Dateiformat, kein Shellskript.
Bekannte Schlüssel, validierte Werte. Wird nie mit `source` oder `eval` ausgeführt.

Die Limits sind hart: Iterations-, Versuche-, No-Progress-, Kontext-, Timeout- und
Retry-Grenzen. Kein Agent kann das übergehen.

## Sicherheit: Was Claude nicht darf — mit Absicht

Das Template hat eingebaute Sperren. Claude (oder jeder Agent) darf **nicht**:

- **Etwas ins Internet hochladen** — `git push`, `curl`, `wget` sind blockiert.  
  Du selbst kontrollierst, was hochgeladen wird.

- **Dateien massenhaft löschen** — `rm -r…` für Ordner ist blockiert.  
  Nur wichtige Aufräumarbeiten (`archive-notes.sh`, `migrate-tasks.sh`) sind
  Benutzerbefehle, nicht automatisch.

- **Ungespeicherte Arbeit verwerfen** — `git reset --hard`, `git checkout --`,
  `git clean`, `git restore` sind blockiert.  
  Ein Agent könnte sonst versehentlich einen Entwurf löschen.

- **Prüf-Hooks umgehen** — `git … --no-verify` ist blockiert, und vor jedem
  `git commit` muss `./scripts/verify.sh --quick` grün sein.

Diese Grenzen sind in `scripts/bash-guard.sh` und `scripts/commit-gate.sh`
definiert und greifen bei jedem Befehl, auch versteckt in einem längeren Befehl
oder hinter JSON-Steuerzeichen. Sie sind ein Stolperdraht, kein Sandkasten: Dinge
wie `node -e "fetch(…)"` oder ein git-Alias erfassen sie nicht. Die Skripte selbst
laden Ledger- und Agententext nie mit `source` oder `eval`. Du behältst die volle
Kontrolle: Ein `git push` führst du selbst aus.

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
