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
Produktänderung den ausgeführten und den empfohlenen Modus. Eine bestimmte
Aufgabe startet mit `./scripts/orchestrate.sh --task 017`. Die globale
Projektprüfung bleibt immer `./scripts/verify.sh`.

Der ausgelieferte Rollout steht auf `shadow`: Empfehlungen werden sichtbar,
automatisch ausgeführt wird zunächst die geprüfte Basisvariante. Managed- oder
Fresh-Modi werden nur nach ausdrücklicher Wahl beziehungsweise einer späteren
Pilotentscheidung verwendet. Offene Aufgaben sowie Text, Optik und Rechtliches
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

#### 3. **Adaptive Arbeitsmodi**

- Kleine Aufgaben? Schnelle, direkte Lösung
- Komplexe Aufgaben? Erst planen, dann arbeiten, dann prüfen
- Festgefahrene Probleme? Unabhängige zweite Lösung
- Nicht alle Aufgaben brauchen 5 Agenten — nur wenn nötig

#### 4. **Vollständige Nachvollziehbarkeit**

- Warum wurde diese Design-Entscheidung getroffen? Steht in
  `docs/state/decisions.md`
- Wer hat was geändert? Git-Historie
- Was wurde geprüft? `docs/verification/`

#### 5. **Sicherheit von Anfang an**

- Agenten führen niemals ungepfüften Code aus
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
