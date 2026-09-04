---
phase_id: "09"
depends_on: ["08"]
progress_source: "plans/README.md"
handoff_target: "plans/handoffs/09-handoff.md"
plan_version: "1.1"
---

# Phase 09 — Dokumentation, Migration und Betriebsübergabe

## Ausführungsvertrag

Wenn diese Datei als Auftrag übergeben wird, setze **nur Phase 09** um.

1. Lies aus `plans/README.md` nur Frontmatter, Fortschrittsblock und
   Update-Regeln sowie `plans/handoffs/08-handoff.md`. Phase 08 muss `DONE` sein.
2. Minimaler zusätzlicher Kontext: tatsächliche implementierte CLI-Hilfe,
   README/CLAUDE/Kursanleitung, Templates, State Summary und der aktuelle
   globale Verify-Vertrag. Verlasse dich bei Befehlen auf den Code, nicht auf
   alte Planannahmen.
3. Setze Phase 09 vor Änderungen auf `IN_PROGRESS`.
4. Dokumentiere den tatsächlich implementierten Stand; unerledigte Funktionen
   werden nicht als verfügbar beschrieben.
5. Führe Dokumentations-, Pfad-, Beispielbefehls- und Gesamtprüfungen aus.
6. Bei Erfolg: `plans/handoffs/09-handoff.md` anlegen, Phase 09 und
   `overall_status` auf `DONE` setzen, `current_phase` auf `none` und
   `next_action` auf den ausdrücklich vereinbarten Pilot/Betriebsschritt setzen.
7. Stoppe nach der Gesamtübergabe; starte keinen Pilot oder Produkt-Task ohne
   eigenen Auftrag.

## Ziel

Der neue Ablauf bleibt für einen nicht-technischen Auftraggeber verständlich.
Technische Details stehen dort, wo Agenten und Maintainer sie brauchen; die
Kursanleitung beschreibt Entscheidungen und sichtbare Zustände in Alltagssprache.

## Zu aktualisierende Dokumente

### `README.md`

- Template als adaptives Agentensystem beschreiben;
- Quickstart nach Git-Initialisierung;
- drei Hauptbefehle: nächste Aufgabe anzeigen, kontrolliert bearbeiten,
  Projektstand erklären;
- klarstellen, dass Multi-Agent nicht für jede Aufgabe verwendet wird.

### `CLAUDE.md`

Nur dauerhafte, häufig benötigte Regeln:

- Ledger-Pfade und Source of Truth;
- `done` nur über Verifikations-Gate;
- Rollen ändern nicht gegenseitig ihre Zuständigkeitsbereiche;
- Limits und Handoff-Pflicht;
- ein einziger Einstiegspunkt für Orchestrierung und Prüfung.

Keine langen Prompttexte oder Forschungszusammenfassung aufnehmen.

### `docs/KURSANLEITUNG.md`

Neue Nutzerreise:

1. Projekt einmalig initialisieren;
2. nächsten Task anzeigen;
3. vorgeschlagenen Modus in Alltagssprache sehen;
4. einfache Aufgaben direkt, komplexe im kontrollierten Loop bearbeiten;
5. `GREEN`, `RED`, `review` und `blocked` verstehen;
6. menschliche Prüfungen bestätigen;
7. bei No-Progress oder Blockade eine klare Entscheidung treffen;
8. Metriken beim Meilenstein-Review ansehen.

Technische Wörter werden beim ersten Auftreten übersetzt: Ledger = Arbeitsbuch,
Router = Auswahlregel, Fresh Worker = unabhängiger neuer Versuch.

### Vorlagen

- `docs/templates/task-template.md`: neues Frontmatter und Modusbeispiele;
- `docs/templates/handoff-template.md`: Run-ID, letzter grüner Stand,
  Verifierstatus, menschliche Entscheidung;
- `docs/templates/initializer-prompt.md`: legt Goal/Ledger an und stellt nur
  Fragen, die die Zerlegung tatsächlich ändern;
- neue Rollen-Prompts aus Phase 04.

### `docs/state/decisions.md`

Mindestens diese Entscheidungen in Alltagssprache dokumentieren:

- warum Markdown-Tasks statt parallelem `tasks.json`;
- warum jede Aufgabe geprüft wird;
- wann zusätzliche Modellaufrufe erlaubt sind;
- warum offene Aufgaben menschlich beaufsichtigt bleiben;
- warum Fresh Worker isoliert arbeiten;
- welche Kosten-/Datenschutzfolgen Modellaufrufe und lokale Logs haben.

## Migrationsablauf

1. Eigenes Git-Repository initialisieren und Ausgangsstand committen. Das ist
   eine Voraussetzung für sichere Diffs, Wiederaufnahme und Fresh-Worktrees,
   aber nicht Teil der hier vorliegenden Planerstellung.
2. Vorhandene Platzhalter mit `./scripts/verify.sh` und
   `./scripts/next-tasks.sh` als Baseline dokumentieren.
3. Phase 01 und 02 einführen, ohne Agenten aufzurufen.
4. Bestehende Task-Dateien additiv migrieren und Ledger validieren.
5. Single + Verify produktiv schalten; bisheriger Sitzungsablauf bleibt nutzbar.
6. Manager-Loop zunächst nur mit Fake Runner testen.
7. Echten Managed-Modus explizit für einen ungefährlichen Task aktivieren.
8. Fresh Worker erst aktivieren, wenn Git-Isolierung und erneute Verifikation
   nach Übernahme nachweislich funktionieren.
9. Pilot aus Phase 08 durchführen.
10. Adaptive Standardregeln nach Pilotentscheidung aktivieren.
11. Word-Fassung der Kursanleitung aus der Markdown-Quelle neu erzeugen und
    visuell prüfen.

## Rückwärtskompatibilität

- `./scripts/next-tasks.sh` behält sein bestehendes Ausgabeformat.
- `./scripts/verify.sh` bleibt die einzige globale Projektprüfung.
- Tasks ohne neue Felder verwenden dokumentierte Defaults.
- Ein Nutzer kann weiterhin eine einzelne Task-Datei direkt in einer Sitzung
  bearbeiten lassen.
- Orchestrierung kann global deaktiviert werden; Ledger und Verify-Gate bleiben
  dabei nutzbar.
- Vorhandene `features.md`, `decisions.md`, `handoff.md` und Profilstruktur
  werden nicht ersetzt.

## Bedienfälle, die dokumentiert werden müssen

### Normaler Erfolg

```text
Task gewählt -> Modus erklärt -> Bearbeitung -> GREEN -> done/review
```

### Prüfung rot

```text
RED -> konkrete Fehlerstufe -> begrenzter neuer Versuch -> erneut prüfen
```

### Menschliche Prüfung

```text
maschinell GREEN -> review -> Auftraggeber prüft Text/Optik/Rechtliches
```

### Blockade

```text
3 Versuche oder No-Progress -> blocked -> Handoff erklärt Entscheidung
```

### Unterbrochene Sitzung

```text
neue Sitzung -> state-summary -> --resume oder bewusster Neustart
```

## Dokumentationsprüfung

- alle genannten Befehle werden automatisiert gegen `--help` oder Dry Run
  geprüft;
- alle Pfade existieren;
- Statusbegriffe stimmen exakt mit dem Validator überein;
- Beispiele enthalten keine Secrets oder echte Zugangsdaten;
- Kursanleitung wird von einer fachfremden Testperson anhand eines harmlosen
  Tasks durchgespielt;
- Markdown- und Word-Fassung sind inhaltlich synchron;
- `state-summary.sh` bleibt kurz und erklärt den nächsten Handlungsbedarf.

## Abschlussabnahme des Gesamtumbaus

1. Einen `mechanical` Task im Single-Modus vollständig durchführen.
2. Einen `patterned` Task im Verified-Modus mit simuliertem Erstfehler
   durchführen.
3. Einen komplexen Task im Managed-Modus über mindestens zwei Runden
   durchführen.
4. No-Progress und Versuchslimit kontrolliert auslösen.
5. Fresh-Worker-Vergleich mit zwei isolierten Kandidaten durchführen.
6. Einen grünen Task mit `human_review: true` bis `review`, aber nicht `done`,
   führen.
7. Lauf unterbrechen und aus gültigem Ledger fortsetzen.
8. Verifier nach Candidate-Änderung korrekt invalidieren.
9. Sicherstellen, dass `.env`, `.agent-runs` und Rohlogs nicht committed oder in
   Prompts übernommen werden.
10. Pilotbericht und Entscheidung über den Standardmodus dokumentieren.

## Abnahmekriterien

- Ein nicht-technischer Nutzer versteht Status und nächsten Schritt ohne
  Kenntnis der Rollenimplementierung.
- Alte und neue Arbeitsweise können während des Rollouts nebeneinander bestehen.
- Alle Beispielbefehle funktionieren oder sind klar als zukünftige Befehle
  markiert.
- Die Dokumentation beschreibt auch Fehler-, Review- und Abbruchfälle.
- Nach Abschluss existiert eine einzige, konsistente Betriebsanleitung.
