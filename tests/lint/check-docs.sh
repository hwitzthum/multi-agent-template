#!/usr/bin/env bash
# Doku gegen Code: jeder dokumentierte Pfad existiert, jedes Einstiegsskript
# hat eine Hilfe, und der Auslieferungsstand trägt keine fremde Historie.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

begin_suite check-docs

for path in \
  README.md CLAUDE.md docs/KURSANLEITUNG.md \
  docs/templates/task-template.md docs/templates/handoff-template.md \
  docs/templates/initializer-prompt.md docs/state/decisions.md \
  docs/state/goal.md docs/state/plan.md docs/state/notes.md \
  docs/state/current-run.md docs/state/metrics.csv docs/verification/latest.md; do
  assert_file "dokumentierter Pfad existiert: $path" "$project_dir/$path"
done

for role in manager-plan manager-manage worker-brainstorm worker-task worker-fresh reviewer finalizer; do
  assert_file "Rollen-Prompt existiert: $role" "$project_dir/docs/templates/agents/$role.md"
done

assert_file_has "README beschreibt adaptives System" "$project_dir/README.md" 'Adaptives Agentensystem'
assert_file_has "README zeigt nächste Tasks" "$project_dir/README.md" './scripts/next-tasks.sh'
assert_file_has "README zeigt kontrollierte Bearbeitung" "$project_dir/README.md" './scripts/orchestrate.sh --next'
assert_file_has "README zeigt Projektstand" "$project_dir/README.md" './scripts/state-summary.sh'
assert_file_has "README begrenzt Multi-Agent" "$project_dir/README.md" 'nicht der Standard für'
assert_file_has "README erklärt Router-Entscheidung" "$project_dir/README.md" 'Router'

assert_file_has "CLAUDE kennt die Ledger-Quelle" "$project_dir/CLAUDE.md" '`docs/tasks/*.md` ist die einzige Aufgabenquelle'
assert_file_has "CLAUDE bindet done ans Gate" "$project_dir/CLAUDE.md" '`done` oder'
assert_file_has "CLAUDE trennt Rollenzuständigkeiten" "$project_dir/CLAUDE.md" 'Manager ändern Plan und Task-Inhalt'
assert_file_has "CLAUDE nennt harte Limits" "$project_dir/CLAUDE.md" 'No-Progress-'
assert_file_has "CLAUDE verlangt Handoff" "$project_dir/CLAUDE.md" 'braucht ein Handoff'
assert_file_has "CLAUDE hat einen Orchestrierungseinstieg" "$project_dir/CLAUDE.md" '`./scripts/orchestrate.sh`'
assert_file_lacks "CLAUDE behauptet nicht mehr, Orchestrierung fehle" "$project_dir/CLAUDE.md" 'Orchestrierung ist noch nicht implementiert'

for term in 'Ledger' 'Router' 'Fresh Worker' '`GREEN`' '`RED`' '`review`' '`blocked`' '--resume' 'No-Progress' 'agent-metrics.sh summary'; do
  assert_file_has "Kursanleitung erklärt $term" "$project_dir/docs/KURSANLEITUNG.md" "$term"
done
for flow in 'Normal:' 'Prüfung rot:' 'Menschlich:' 'Blockade:' 'Unterbruch:'; do
  assert_file_has "Kursanleitung dokumentiert Bedienfall $flow" "$project_dir/docs/KURSANLEITUNG.md" "$flow"
done

for field in 'orchestration: auto' 'fresh_perspective: auto' 'touches: []' 'risk_flags: []' 'max_attempts: 3' 'human_review: false'; do
  assert_file_has "Task-Vorlage enthält $field" "$project_dir/docs/templates/task-template.md" "$field"
done
assert_file_has "Task-Vorlage erklärt Single" "$project_dir/docs/templates/task-template.md" 'empfohlen wird `single`'
assert_file_has "Task-Vorlage erklärt Fresh" "$project_dir/docs/templates/task-template.md" 'empfohlen wird `managed-fresh`'

for field in 'Run-ID:' 'Verifierstatus:' 'Letzter grüner Stand:' 'Entscheidung:' 'Erster offener Fehler:'; do
  assert_file_has "Handoff-Vorlage enthält $field" "$project_dir/docs/templates/handoff-template.md" "$field"
done

assert_file_has "Initializer legt Goal an" "$project_dir/docs/templates/initializer-prompt.md" '`docs/state/goal.md`'
assert_file_has "Initializer legt Run-Ledger an" "$project_dir/docs/templates/initializer-prompt.md" '`docs/state/current-run.md`'
assert_file_has "Initializer fragt nur zerlegungsrelevante Fragen" "$project_dir/docs/templates/initializer-prompt.md" 'Zerlegung tatsächlich ändern würde'
assert_file_has "Initializer verbietet zweite Taskquelle" "$project_dir/docs/templates/initializer-prompt.md" 'paralleles `tasks.json`'

# docs/state/ ist Projektzustand, kein Vorlageninhalt. Solange docs/tasks/ leer
# ist, gilt der Auslieferungsstand: Ein neues Projekt darf keine fremden
# Einträge erben. Nach der Initialisierung entfällt die Prüfung, weil dann
# echter Projektzustand in diesen Dateien steht.
if [ -z "$(find "$project_dir/docs/tasks" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]; then
  assert_file_has "Startzustand: decisions.md ohne Einträge" "$project_dir/docs/state/decisions.md" 'Noch keine Entscheidungen festgehalten.'
  assert_file_has "Startzustand: goal.md ohne Projektziel" "$project_dir/docs/state/goal.md" 'Noch kein Projektziel festgelegt.'
  assert_file_has "Startzustand: plan.md ohne Strategie" "$project_dir/docs/state/plan.md" 'Noch keine Strategie festgelegt.'
  assert_file_has "Startzustand: handoff.md verweist auf die Initialisierung" "$project_dir/docs/state/handoff.md" 'noch nicht initialisiert'
  for state_file in decisions.md goal.md plan.md handoff.md; do
    assert_file_lacks "Startzustand: keine Bau-Historie in $state_file" "$project_dir/docs/state/$state_file" '2026-09-04'
  done
fi

expect_contains "orchestrate --help" 'Verwendung:' "$project_dir/scripts/orchestrate.sh" --help
expect_contains "next-tasks --help" 'Verwendung:' "$project_dir/scripts/next-tasks.sh" --help
expect_contains "state-summary --help" 'Verwendung:' "$project_dir/scripts/state-summary.sh" --help
expect_contains "verify --help" 'Verwendung:' "$project_dir/scripts/verify.sh" --help
expect_contains "agent-metrics --help" 'Verwendung:' "$project_dir/scripts/agent-metrics.sh" --help
expect_contains "route-task --help" 'Verwendung:' "$project_dir/scripts/route-task.sh" --help
expect_contains "verify-task --help" 'Verwendung:' "$project_dir/scripts/verify-task.sh" --help
expect_contains "validate-ledger --help" 'Verwendung:' "$project_dir/scripts/validate-ledger.sh" --help
expect_contains "tests/run --help" 'Verwendung:' "$tests_dir/run.sh" --help

if grep -rEq --include='*.md' '(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' "$project_dir/README.md" "$project_dir/CLAUDE.md" "$project_dir/docs"; then
  bad "Dokumentationsbeispiele enthalten keine offensichtlichen Secrets"
else
  ok
fi

finish_suite
