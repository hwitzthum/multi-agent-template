#!/usr/bin/env bash
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd) || exit 1

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAILED: $1" >&2; }
assert_file() { [ -f "$project_dir/$2" ] && ok || bad "$1"; }
assert_has() { grep -Fq -- "$3" "$project_dir/$2" && ok || bad "$1"; }
assert_lacks() { if grep -Fq -- "$3" "$project_dir/$2"; then bad "$1"; else ok; fi; }
expect_help() {
  name=$1
  shift
  if output=$("$@" --help 2>&1) && printf '%s\n' "$output" | grep -Fq 'Verwendung:'; then ok; else bad "$name"; fi
}

for path in \
  README.md CLAUDE.md docs/KURSANLEITUNG.md \
  docs/templates/task-template.md docs/templates/handoff-template.md \
  docs/templates/initializer-prompt.md docs/state/decisions.md \
  docs/state/goal.md docs/state/plan.md docs/state/notes.md \
  docs/state/current-run.md docs/state/metrics.csv docs/verification/latest.md; do
  assert_file "dokumentierter Pfad existiert: $path" "$path"
done

for role in manager-plan manager-manage worker-brainstorm worker-task worker-fresh reviewer finalizer; do
  assert_file "Rollen-Prompt existiert: $role" "docs/templates/agents/$role.md"
done

assert_has "README beschreibt adaptives System" README.md 'Adaptives Agentensystem'
assert_has "README zeigt nächste Tasks" README.md './scripts/next-tasks.sh'
assert_has "README zeigt kontrollierte Bearbeitung" README.md './scripts/orchestrate.sh --next'
assert_has "README zeigt Projektstand" README.md './scripts/state-summary.sh'
assert_has "README begrenzt Multi-Agent" README.md 'nicht der Standard für'
assert_has "README nennt ausgelieferte Rollout-Stufe" README.md '`shadow`'

assert_has "CLAUDE kennt die Ledger-Quelle" CLAUDE.md '`docs/tasks/*.md` ist die einzige Aufgabenquelle'
assert_has "CLAUDE bindet done ans Gate" CLAUDE.md '`done` oder'
assert_has "CLAUDE trennt Rollenzuständigkeiten" CLAUDE.md 'Manager ändern Plan und Task-Inhalt'
assert_has "CLAUDE nennt harte Limits" CLAUDE.md 'No-Progress-'
assert_has "CLAUDE verlangt Handoff" CLAUDE.md 'braucht ein Handoff'
assert_has "CLAUDE hat einen Orchestrierungseinstieg" CLAUDE.md '`./scripts/orchestrate.sh`'
assert_lacks "CLAUDE behauptet nicht mehr, Orchestrierung fehle" CLAUDE.md 'Orchestrierung ist noch nicht implementiert'

for term in 'Ledger' 'Router' 'Fresh Worker' '`GREEN`' '`RED`' '`review`' '`blocked`' '--resume' 'No-Progress' 'agent-metrics.sh summary'; do
  assert_has "Kursanleitung erklärt $term" docs/KURSANLEITUNG.md "$term"
done
for flow in 'Normal:' 'Prüfung rot:' 'Menschlich:' 'Blockade:' 'Unterbruch:'; do
  assert_has "Kursanleitung dokumentiert Bedienfall $flow" docs/KURSANLEITUNG.md "$flow"
done

for field in 'orchestration: auto' 'fresh_perspective: auto' 'touches: []' 'risk_flags: []' 'max_attempts: 3' 'human_review: false'; do
  assert_has "Task-Vorlage enthält $field" docs/templates/task-template.md "$field"
done
assert_has "Task-Vorlage erklärt Single" docs/templates/task-template.md 'empfohlen wird `single`'
assert_has "Task-Vorlage erklärt Fresh" docs/templates/task-template.md 'empfohlen wird `managed-fresh`'

for field in 'Run-ID:' 'Verifierstatus:' 'Letzter grüner Stand:' 'Entscheidung:' 'Erster offener Fehler:'; do
  assert_has "Handoff-Vorlage enthält $field" docs/templates/handoff-template.md "$field"
done

assert_has "Initializer legt Goal an" docs/templates/initializer-prompt.md '`docs/state/goal.md`'
assert_has "Initializer legt Run-Ledger an" docs/templates/initializer-prompt.md '`docs/state/current-run.md`'
assert_has "Initializer fragt nur zerlegungsrelevante Fragen" docs/templates/initializer-prompt.md 'Zerlegung tatsächlich ändern würde'
assert_has "Initializer verbietet zweite Taskquelle" docs/templates/initializer-prompt.md 'paralleles `tasks.json`'

for phrase in \
  'Das bestehende Task-System bleibt die einzige Aufgabenquelle' \
  'Statuswechsel brauchen einen überprüfbaren Beleg' \
  'Zusätzliche Agentenarbeit wird nach Risiko gewählt' \
  'Offene Aufgaben bleiben menschlich beaufsichtigt' \
  'Fresh Worker sieht bewusst weder frühere Notizen' \
  'Modellaufrufe und lokale Logs haben sichtbare Kostenfolgen'; do
  assert_has "Entscheidungen dokumentieren: $phrase" docs/state/decisions.md "$phrase"
done

expect_help "orchestrate --help" "$project_dir/scripts/orchestrate.sh"
expect_help "next-tasks --help" "$project_dir/scripts/next-tasks.sh"
expect_help "state-summary --help" "$project_dir/scripts/state-summary.sh"
expect_help "verify --help" "$project_dir/scripts/verify.sh"
expect_help "agent-metrics --help" "$project_dir/scripts/agent-metrics.sh"
expect_help "route-task --help" "$project_dir/scripts/route-task.sh"
expect_help "verify-task --help" "$project_dir/scripts/verify-task.sh"
expect_help "validate-ledger --help" "$project_dir/scripts/validate-ledger.sh"

if grep -rEq --include='*.md' '(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' "$project_dir/README.md" "$project_dir/CLAUDE.md" "$project_dir/docs"; then
  bad "Dokumentationsbeispiele enthalten keine offensichtlichen Secrets"
else
  ok
fi

if [ "$failed" -ne 0 ]; then
  echo "phase-09-tests: RED ($failed fehlgeschlagen, $passed bestanden)" >&2
  exit 1
fi
echo "phase-09-tests: GREEN ($passed bestanden)"
