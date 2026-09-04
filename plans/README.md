---
plan_version: "1.1"
progress_schema: 1
overall_status: in_progress
current_phase: "08"
last_completed_phase: "07"
last_handoff: "plans/handoffs/07-handoff.md"
active_blocker: "none"
rollout_stage: implementation
pilot_status: not_started
next_action: "Phase 08 umsetzen"
last_updated: "2026-09-04"
---

# Umbauplan: Adaptiver Manager–Worker-Loop mit Datei-Ledger

## Zweck

Dieser Ordner beschreibt den schrittweisen Umbau von `multi-agent-template` zu
einem adaptiven, dateibasierten Agentensystem. Er enthält ausschließlich einen
Implementierungsplan; keine der beschriebenen Änderungen ist bereits umgesetzt.

Die Planung verbindet zwei Grundlagen:

1. Das bestehende Template besitzt bereits langlebigen Zustand in
   `docs/state/`, Markdown-Tasks mit Abhängigkeiten in `docs/tasks/`, eine
   zentrale Prüfung über `scripts/verify.sh`, Schutz-Hooks und Metriken.
2. Das Paper
   [Zero-Shot Self-Orchestration with Ledger-Based Control for Improved LLM Coding Performance](https://arxiv.org/html/2608.26480v1)
   koordiniert frische Modellaufrufe über ein gemeinsames Datei-Ledger. Sein
   aktuelles Scaffold verwendet Plan, Brainstorm, kuratierte Task-Liste,
   Einzel-Worker, Verifier, ein Budget von zehn Manager–Worker-Runden und einen
   No-Progress-Guard.

## Leitentscheidung

Es wird **kein zweites Task-System mit `tasks.json`** neben den vorhandenen
`docs/tasks/*.md` eingeführt. Die Task-Dateien bleiben die verbindliche Quelle
für Aufgaben, Abhängigkeiten, Status und Akzeptanz. Das Paper liefert das
Orchestrierungsmuster; das bestehende Repository liefert das Datenmodell.

Die Zielarchitektur lautet:

```text
Auftrag / Task
      |
      v
deterministischer Router
      |
      +--> single --------> Worker ------------------+
      +--> verified ------> Worker -> Verify --------+
      +--> managed -------> Manager -> Worker -------+--> Status-Gate
      +--> managed-fresh -> Manager -> Kandidaten ---+       |
                                                             v
                                             done | review | blocked
```

Alle Modi durchlaufen ein deterministisches Status-Gate. Ein Agent darf einen
Task nicht durch eine Behauptung auf `done` setzen.

## Zielstruktur

```text
.agent/
  config.env
docs/
  state/
    goal.md
    plan.md
    notes.md
    current-run.md
    notes-archive/
  tasks/
    <bestehende Task-Dateien>
  verification/
    latest.md
    history/
  templates/
    agents/
      manager-plan.md
      manager-manage.md
      worker-brainstorm.md
      worker-task.md
      worker-fresh.md
      reviewer.md
      finalizer.md
scripts/
  orchestrate.sh
  route-task.sh
  verify-task.sh
  validate-ledger.sh
  agent/
    common.sh
    context.sh
    ledger.sh
    runner.sh
    status.sh
    metrics.sh
tests/
  orchestrator/
.agent-runs/                 # lokal, nicht versioniert
```

Die endgültige Implementierung darf Namen zusammenlegen, wenn dadurch weniger
Skripte ohne Verlust klarer Zuständigkeiten entstehen.

## Phasenweise Nutzung

Jede Phase ist als eigenständiger Arbeitsauftrag geschrieben. Für eine neue
Sitzung genügt normalerweise:

1. die gewünschte Phasendatei;
2. der Abschnitt **Umsetzungsfortschritt** aus dieser Datei;
3. die dort genannten kompakten Handoffs aus `plans/handoffs/`;
4. die im Phasenvertrag ausdrücklich genannten Repository-Dateien.

Frühere Phasenpläne müssen nicht erneut vollständig in den Kontext geladen
werden. Der tatsächliche Code und die Phasen-Handoffs sind die Wahrheit über die
bereits erfolgte Umsetzung.

Ein sinnvoller Auftrag lautet beispielsweise:

> Setze Phase 01 aus `plans/01-zielarchitektur-und-leitplanken.md` um. Halte
> dich an den Ausführungsvertrag der Datei und aktualisiere anschließend das
> Fortschrittsboard in `plans/README.md`. Beginne keine weitere Phase.

## Statusmodell

| Status | Bedeutung |
|---|---|
| `WAITING` | Abhängigkeiten sind noch nicht abgeschlossen |
| `READY` | alle Abhängigkeiten sind `DONE`; Phase darf beginnen |
| `IN_PROGRESS` | Bearbeitung wurde begonnen, aber noch nicht abgenommen |
| `BLOCKED` | konkrete Blockade ist im Handoff dokumentiert |
| `DONE` | alle Abnahmekriterien grün, Handoff vorhanden |

`DONE` darf nur gesetzt werden, wenn die Phase ihre eigenen Tests und
Abnahmekriterien erfüllt. „Dateien wurden geändert“ reicht nicht.

## Umsetzungsfortschritt

<!-- PROGRESS:START -->

**Aktueller Stand:** Phase 07 ist grün abgeschlossen. Phase 08 ist als nächster
einzelner Arbeitsauftrag bereit.

| Phase | Status | Prüfung | Implementierungsstand | Handoff | Aktualisiert |
|---|---|---|---|---|---|
| 01 | `DONE` | `green` | `working-tree:5e04acd97d78f4cd62dddc16c001ea494ab5fb0d` | [01-handoff](handoffs/01-handoff.md) | 2026-09-04 |
| 02 | `DONE` | `green` | `working-tree:6c39757075a2fe07d35b8b0a03beeee38eabdf45787b1825d6e957d649ed8ba3` | [02-handoff](handoffs/02-handoff.md) | 2026-09-04 |
| 03 | `DONE` | `green` | `working-tree:3cb1beadc6830a17b7bb5d3c5ff99033f0abc91fa7f2090bb8e1032d81186fa0` | [03-handoff](handoffs/03-handoff.md) | 2026-09-04 |
| 04 | `DONE` | `green` | `working-tree:bea91e7cfc5a4c4aaf62c272aeb67a279b18a373c9925e73a1d5e3664f6e6f1d` | [04-handoff](handoffs/04-handoff.md) | 2026-09-04 |
| 05 | `DONE` | `green` | `working-tree:6287f9b24127d1aac57b983b18f8f9918c490a4c4cb6aaa3070b2a49a3df1a7b` | [05-handoff](handoffs/05-handoff.md) | 2026-09-04 |
| 06 | `DONE` | `green` | `working-tree:8c3a700a78dbb9db7fa272be1a026cf59d03deb7dea696bb50eb7d5a9fe4523f` | [06-handoff](handoffs/06-handoff.md) | 2026-09-04 |
| 07 | `DONE` | `green` | `working-tree:23f854bfd3b7573744eff76e6a2169009b9c379b8acadaee9ee51b780bf24a3c` | [07-handoff](handoffs/07-handoff.md) | 2026-09-04 |
| 08 | `READY` | `not_run` | `not_started` | `not_created` | 2026-09-04 |
| 09 | `WAITING` | `not_run` | `not_started` | `not_created` | 2026-09-04 |

**Nächster zulässiger Schritt:** Phase 08 umsetzen.

<!-- PROGRESS:END -->

## Regeln für Fortschrittsupdates

Das Board oben ist die einzige verbindliche Statusquelle für die Umbauphasen.
Die Phasendateien duplizieren keinen veränderlichen Status.

### Beim Start einer Phase

1. Abhängigkeiten im Board prüfen.
2. Zeile der Phase auf `IN_PROGRESS` setzen.
3. `Implementierungsstand` als `working-tree:<UTC-Zeit>` oder, falls bereits
   vorhanden, als Git-Referenz eintragen.
4. Frontmatter-Felder `overall_status`, `current_phase`, `next_action` und
   `last_updated` aktualisieren.
5. Erst danach Implementierungsdateien ändern.

### Beim erfolgreichen Abschluss

1. Alle phasenspezifischen Abnahmekriterien ausführen.
2. Kompaktes Handoff unter `plans/handoffs/<phase>-handoff.md` nach
   [Handoff-Vorlage](handoffs/README.md) anlegen.
3. Git-Commit oder eindeutigen Working-Tree-Fingerprint in
   `Implementierungsstand` eintragen.
4. `Prüfung` auf `green` und Phase auf `DONE` setzen.
5. Direkt abhängige nächste Phase auf `READY` setzen; andere bleiben
   `WAITING`.
6. Aktuellen Stand, `last_completed_phase`, `current_phase`, `next_action` und
   Datum aktualisieren.
7. Stoppen. Die nächste Phase wird niemals automatisch begonnen.

### Bei Blockade oder Sitzungsende

1. Phase bleibt `IN_PROGRESS` oder wird `BLOCKED`; niemals `DONE`.
2. Ein Handoff dokumentiert letzten grünen Stand, offene Arbeit, ersten Fehler
   und exakten Wiederaufnahmebefehl.
3. `Prüfung` wird `red`, `partial` oder `not_run`.
4. `next_action` beschreibt genau eine nächste Handlung.

### Konsistenzprüfung

Vor und nach jeder Phase muss gelten:

- jede `DONE`-Phase hat einen vorhandenen Handoff und `Prüfung: green`;
- jede `READY`-Phase hat ausschließlich `DONE`-Abhängigkeiten;
- höchstens eine Phase ist `IN_PROGRESS`;
- `current_phase` stimmt mit `IN_PROGRESS` oder der ersten `READY`-Phase
  überein;
- der Handoff nennt tatsächlich geänderte Dateien und ausgeführte Prüfungen;
- Statusupdates und Implementierungsänderungen werden gemeinsam übergeben.

## Phasen und Reihenfolge

| Phase | Ergebnis | Abhängigkeit |
|---|---|---|
| [01](01-zielarchitektur-und-leitplanken.md) | Grenzen, Verträge und sichere Ausgangslage | keine |
| [02](02-ledger-und-task-schema.md) | versioniertes Ledger und erweiterter Task-Status | 01 |
| [03](03-router-und-ausfuehrungsmodi.md) | adaptive Wahl von `single` bis `managed-fresh` | 02 |
| [04](04-rollenprompts-und-kontextpakete.md) | kleine, rollenbezogene und begrenzte Kontexte | 03 |
| [05](05-orchestrator-und-manager-worker-loop.md) | ausführbarer Manager–Worker-Loop | 04 |
| [06](06-verification-und-statusuebergaenge.md) | Verifikation als einziges Done-Gate | 05 |
| [07](07-fresh-worker-finalizer-und-fehlerbehandlung.md) | unabhängige Kandidaten und sichere Abbruchpfade | 06 |
| [08](08-metriken-evaluation-und-rollout.md) | messbarer Pilot und adaptiver Rollout | 07 |
| [09](09-dokumentation-und-betriebsuebergabe.md) | verständlicher Betrieb für Nicht-Entwickler | 08 |

Die Phasen werden jeweils als eigener Task oder kleines Task-Bündel umgesetzt.
Nach jeder Phase müssen die vorhandenen Schutzregeln weiter funktionieren und
`./scripts/verify.sh` grün sein.

## Was direkt aus dem Paper übernommen wird

- frischer Kontext pro Rolle;
- gemeinsamer Zustand auf der Festplatte;
- eigener Brainstorm-Schritt vor komplexer Implementierung;
- Manager wählt genau einen nächsten wertvollen Task;
- Worker führt genau einen begrenzten Task aus;
- maximal zehn Manager–Worker-Runden als Standard;
- No-Progress-Erkennung;
- kompakte, größenbegrenzte Kontextpakete;
- ein Verifier-Ergebnis überschreibt die Selbsteinschätzung des Workers.

## Bewusste Erweiterungen gegenüber dem Paper

- ein Router vermeidet teure Orchestrierung bei einfachen Aufgaben;
- pro Task gelten höchstens drei fehlgeschlagene Versuche;
- `review` trennt maschinell grüne Ergebnisse von ausstehender menschlicher
  Prüfung;
- Fresh Worker arbeiten isoliert, damit sie den besten Stand nicht ungeprüft
  überschreiben;
- der Finalizer dokumentiert bei Abbruch, setzt aber niemals eigenmächtig
  `done`;
- Verifikationsbefehle werden nicht ungeprüft aus LLM-beschriebenen Dateien
  ausgeführt;
- Metriken vergleichen Single- und Orchestrierungsmodus auf denselben Aufgaben.

Diese Erweiterungen sind Produktentscheidungen für dieses Repository, keine
Behauptungen des Papers. Das Paper selbst zeigt ausdrücklich, dass das Scaffold
modellabhängig helfen oder schaden kann und ungefähr ein Mehrfaches der Tokens
eines Single Calls kostet.

## Globale Definition of Done

Der Umbau ist erst abgeschlossen, wenn:

1. ein Task in jedem Ausführungsmodus kontrolliert gestartet werden kann;
2. Manager und Worker nur ihre erlaubten Artefakte verändern;
3. ungültige Ledger- oder Task-Daten vor einem Modellaufruf scheitern;
4. `done` nur nach grüner deterministischer Prüfung möglich ist;
5. `human_review: true` zu `review`, niemals automatisch zu `done`, führt;
6. Iterations- und Versuchslimits zuverlässig stoppen;
7. ein Fresh Worker keine vorhandene Lösung ungeprüft überschreibt;
8. sensible Dateien und `.env` nie in Prompts oder Logs gelangen;
9. alle Übergänge und Modellkosten in Metriken nachvollziehbar sind;
10. die Kursanleitung den neuen Ablauf in Alltagssprache erklärt;
11. ein reproduzierbarer Pilot vorbereitet ist; adaptive Standardausführung
    wird erst nach einem separat beauftragten und ausgewerteten Pilot aktiviert.

## Nicht Teil dieses Umbaus

- Training eines Managers oder Routers;
- dauerhafte Agentenpersönlichkeiten oder Agenten-Chats;
- automatische Veröffentlichung, `git push` oder externe Dienste;
- Umgehung der vorhandenen Sicherheits-Hooks;
- ungeprüfte parallele Bearbeitung derselben Arbeitskopie;
- eine Garantie, dass Multi-Agent-Ausführung immer besser ist.
