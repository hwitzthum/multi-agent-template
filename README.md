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
