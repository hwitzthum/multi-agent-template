#!/usr/bin/env bash
# Doku gegen Code: jeder dokumentierte Pfad existiert, jedes Einstiegsskript
# hat eine Hilfe, und der Auslieferungsstand trägt keine fremde Historie.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

begin_suite check-docs

for path in \
  README.md CLAUDE.md docs/ARCHITECTURE.md \
  docs/templates/task.md docs/templates/handoff.md \
  docs/prompts/init.md docs/state/decisions.md \
  docs/state/goal.md docs/state/plan.md docs/state/notes.md \
  docs/verification/latest.md; do
  assert_file "dokumentierter Pfad existiert: $path" "$project_dir/$path"
done

for role in manager worker finalizer; do
  assert_file "Rollen-Prompt existiert: $role" "$project_dir/docs/prompts/$role.md"
  assert_file "Rollen-Schema existiert: $role" "$project_dir/scripts/agent/schemas/$role.json"
done
[ ! -d "$project_dir/docs/templates/agents" ] && ok || bad "keine zweite Sammlung von Rollenvorlagen"

assert_file_has "README beschreibt adaptives System" "$project_dir/README.md" 'Adaptives Agentensystem'
assert_file_has "README zeigt nächste Tasks" "$project_dir/README.md" './scripts/next-tasks.sh'
assert_file_has "README zeigt kontrollierte Bearbeitung" "$project_dir/README.md" './scripts/orchestrate.sh --next'
assert_file_has "README zeigt Projektstand" "$project_dir/README.md" './scripts/state-summary.sh'
assert_file_has "README begrenzt Multi-Agent" "$project_dir/README.md" 'nicht der Standard für'
assert_file_has "README erklärt Router-Entscheidung" "$project_dir/README.md" 'Router'
assert_file_has "README nennt die Umgebungsprüfung" "$project_dir/README.md" './scripts/doctor.sh'
assert_file_has "README nennt beide Runner" "$project_dir/README.md" 'AGENT_RUNNER=codex'

# Die zwei Runner unterscheiden sich in der Sicherheitshülle; das darf die
# Architektur nicht verschweigen.
for term in 'codex exec' '--sandbox workspace-write' '--restricted' 'AGENT_RUNNER' 'doctor.sh'; do
  assert_file_has "ARCHITECTURE benennt $term" "$project_dir/docs/ARCHITECTURE.md" "$term"
done

assert_file_has "CLAUDE kennt die Ledger-Quelle" "$project_dir/CLAUDE.md" '`docs/tasks/*.md` ist die einzige Aufgabenquelle'
assert_file_has "CLAUDE bindet done ans Gate" "$project_dir/CLAUDE.md" '`done` oder'
assert_file_has "CLAUDE trennt Rollenzuständigkeiten" "$project_dir/CLAUDE.md" 'Manager ändern Plan und Task-Inhalt'
assert_file_has "CLAUDE nennt harte Limits" "$project_dir/CLAUDE.md" 'No-Progress-'
assert_file_has "CLAUDE verlangt Handoff" "$project_dir/CLAUDE.md" 'braucht ein Handoff'
assert_file_has "CLAUDE hat einen Orchestrierungseinstieg" "$project_dir/CLAUDE.md" '`./scripts/orchestrate.sh`'
assert_file_lacks "CLAUDE behauptet nicht mehr, Orchestrierung fehle" "$project_dir/CLAUDE.md" 'Orchestrierung ist noch nicht implementiert'

for term in 'Ledger' 'Router' 'Fresh Worker' 'Status-Gate' 'Runner' 'Verifier'; do
  assert_file_has "ARCHITECTURE erklärt $term" "$project_dir/docs/ARCHITECTURE.md" "$term"
done

for field in 'orchestration: auto' 'touches: []' 'risk_flags: []' 'attempts: 0' 'human_review: false' 'blocked_reason: ""'; do
  assert_file_has "Task-Vorlage enthält $field" "$project_dir/docs/templates/task.md" "$field"
done
for field in 'features:' 'max_attempts:' 'last_verification:'; do
  assert_file_lacks "Task-Vorlage trägt kein $field mehr" "$project_dir/docs/templates/task.md" "$field"
done
for heading in '# Kontext' '# Umfang' '# Nicht Teil dieser Aufgabe' '# Akzeptanzkriterien'; do
  assert_file_has "Task-Vorlage hat den Pflichtabschnitt $heading" "$project_dir/docs/templates/task.md" "$heading"
done
assert_file_has "Task-Vorlage erklärt Single" "$project_dir/docs/templates/task.md" 'empfohlen wird `single`'
assert_file_has "Task-Vorlage erklärt den Fresh-Versuch" "$project_dir/docs/templates/task.md" 'Fresh-Versuch'
assert_file_has "Task-Vorlage nennt das Wiederöffnen" "$project_dir/docs/templates/task.md" './scripts/task.sh reopen'
assert_file_has "Task-Vorlage nennt die Freigabe" "$project_dir/docs/templates/task.md" './scripts/task.sh approve'

for field in 'Run-ID:' 'Modus:' 'Ergebnis:' 'Task:' 'Verifierstatus:' 'Letzter grüner Stand:' \
  'Entscheidung:' 'Erster offener Fehler:'; do
  assert_file_has "Handoff-Vorlage enthält $field" "$project_dir/docs/templates/handoff.md" "$field"
done

assert_file_has "Handoff-Vorlage hat den Abschnitt Laufbeleg" "$project_dir/docs/templates/handoff.md" '## Laufbeleg'
assert_file_has "Handoff-Vorlage kennt alle Laufergebnisse" "$project_dir/docs/templates/handoff.md" 'infrastructure_error'

assert_file_has "Initializer legt Goal an" "$project_dir/docs/prompts/init.md" '`docs/state/goal.md`'
assert_file_has "Initializer fragt nur zerlegungsrelevante Fragen" "$project_dir/docs/prompts/init.md" 'Zerlegung tatsächlich ändern würde'
assert_file_has "Initializer verbietet zweite Taskquelle" "$project_dir/docs/prompts/init.md" 'zweite Aufgabenquelle neben `docs/tasks/`'

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
expect_contains "verify-task --help" 'Verwendung:' "$project_dir/scripts/verify-task.sh" --help
expect_contains "validate-ledger --help" 'Verwendung:' "$project_dir/scripts/validate-ledger.sh" --help
expect_contains "task --help" 'Verwendung:' "$project_dir/scripts/task.sh" --help
expect_contains "doctor --help" 'Verwendung:' "$project_dir/scripts/doctor.sh" --help
expect_contains "orchestrate nennt den Laufbeleg" 'Laufbeleg' sed -n '1,12p' "$project_dir/scripts/orchestrate.sh"
expect_contains "tests/run --help" 'Verwendung:' "$tests_dir/run.sh" --help

# --- Doku gegen Code --------------------------------------------------------
# README und ARCHITECTURE sind die normativen Texte. Was sie nennen, muss es
# geben; was es gibt, muessen sie nennen. Beide Richtungen werden hier gefahren.

docs_text="$project_dir/README.md $project_dir/docs/ARCHITECTURE.md"

# Backtick-Spannen und Markdown-Ziele einsammeln, Klammergruppen wie
# `{manager,worker,finalizer}` in ihre Alternativen aufloesen.
documented_tokens() {
  # shellcheck disable=SC2086
  grep -ohE '`[^`]+`|\]\([^)]+\)' $docs_text \
    | sed 's/^`//; s/`$//; s/^](//; s/)$//' \
    | tr ' ' '\n' \
    | awk '{
        if (match($0, /\{[^{}]+\}/)) {
          pre = substr($0, 1, RSTART - 1)
          group = substr($0, RSTART + 1, RLENGTH - 2)
          post = substr($0, RSTART + RLENGTH)
          n = split(group, alt, ",")
          for (i = 1; i <= n; i++) print pre alt[i] post
        } else print
      }' \
    | sed 's/[.,;:]$//'
}

# Pfade, die im Auslieferungsstand absichtlich fehlen: das laufende Beispiel
# und eine Sperre, die nur waehrend eines Statuswechsels existiert.
documented_path_exception() {
  case "$1" in
    docs/tasks/017.md|docs/tasks/.status-lock) return 0 ;;
    *) return 1 ;;
  esac
}

missing_paths=''
for token in $(documented_tokens | grep -E '^(scripts|docs|tests)/|^\.agent/' | grep -v '<' | sort -u); do
  candidate=${token%/}
  documented_path_exception "$candidate" && continue
  # Ein Glob wie `docs/tasks/*.md` meint den Ordner, nicht eine bestimmte Datei.
  case "$candidate" in *'*'*) candidate=${candidate%/*} ;; esac
  [ -e "$project_dir/$candidate" ] || missing_paths="$missing_paths $token"
done
if [ -z "$missing_paths" ]; then ok; else bad "jeder dokumentierte Pfad existiert (fehlt:$missing_paths)"; fi

# Ein Flag, das die Doku nennt, muss ein Skript des Kits auch verwenden — das
# faengt erfundene und umbenannte Optionen, auch die der beiden Anbieter-CLIs.
missing_flags=''
for flag in $(grep -ohE '(^|[^-[:alnum:]])--[a-z][A-Za-z0-9-]*' $docs_text | grep -oE '\-\-[a-z][A-Za-z0-9-]*' | sort -u); do
  grep -rqF -- "$flag" "$project_dir/scripts" "$project_dir/tests/run.sh" || missing_flags="$missing_flags $flag"
done
if [ -z "$missing_flags" ]; then ok; else bad "jedes dokumentierte Flag kommt im Code vor (fehlt:$missing_flags)"; fi

# Umgekehrte Richtung: kein Skript und kein Konfigurationsschluessel bleibt
# undokumentiert. Dass die Einstiegsskripte `--help` beantworten, prueft der
# Block darueber.
undocumented_scripts=''
for script in "$project_dir"/scripts/*.sh "$project_dir"/scripts/agent/*.sh "$project_dir/tests/run.sh"; do
  relative=${script#"$project_dir/"}
  # shellcheck disable=SC2086
  grep -qF "$relative" $docs_text || undocumented_scripts="$undocumented_scripts $relative"
done
if [ -z "$undocumented_scripts" ]; then ok; else bad "jedes Skript ist dokumentiert (fehlt:$undocumented_scripts)"; fi

# Die Metadaten eines Rollenaufrufs sind ein Vertrag fuer jeden kuenftigen
# Adapter. Ein Feld, das der Runner schreibt und die Architektur verschweigt,
# faellt sonst erst dem naechsten Adapterschreiber auf.
for field in $(grep -oE "printf '[a-z_]+=" "$project_dir/scripts/agent/runner.sh" | sed "s/printf '//; s/=$//" | sort -u); do
  assert_file_has "ARCHITECTURE nennt das Metadatenfeld $field" "$project_dir/docs/ARCHITECTURE.md" "\`$field\`"
done

undocumented_keys=''
while IFS='=' read -r key _; do
  case "$key" in ''|'#'*) continue ;; esac
  grep -qF "$key" "$project_dir/docs/ARCHITECTURE.md" || undocumented_keys="$undocumented_keys $key"
done < "$project_dir/.agent/config.env"
if [ -z "$undocumented_keys" ]; then ok; else bad "jeder Konfigurationsschluessel ist in ARCHITECTURE erklaert (fehlt:$undocumented_keys)"; fi

assert_file_lacks "ARCHITECTURE ist keine Rohfassung mehr" "$project_dir/docs/ARCHITECTURE.md" 'Rohfassung'
assert_file_has "ARCHITECTURE nennt die Sperren" "$project_dir/docs/ARCHITECTURE.md" '.orchestrator-lock'
assert_file_has "ARCHITECTURE nennt das Berichtsschema" "$project_dir/docs/ARCHITECTURE.md" 'candidate_fingerprint'
assert_file_has "README verweist auf den Vertrag" "$project_dir/README.md" 'docs/ARCHITECTURE.md'
assert_file_has "README nennt den Initialisierungsprompt" "$project_dir/README.md" 'docs/prompts/init.md'
assert_file_has "CLAUDE nennt den unversionierten Laufstand" "$project_dir/CLAUDE.md" '`.agent-runs/`'
assert_file_has "Init-Prompt nennt die Pflichtabschnitte eines Tasks" "$project_dir/docs/prompts/init.md" '# Nicht Teil dieser Aufgabe'
assert_file_has "Init-Prompt nennt die erlaubten Klassen" "$project_dir/docs/prompts/init.md" 'mechanical | patterned | open'
assert_file_has "Init-Prompt nennt die Allowlist" "$project_dir/docs/prompts/init.md" '.agent/verification-allowlist'
assert_file_lacks "Init-Prompt nennt keinen Testordner, den es nicht gibt" "$project_dir/docs/prompts/init.md" 'tests/orchestrator/'

if grep -rEq --include='*.md' '(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' "$project_dir/README.md" "$project_dir/CLAUDE.md" "$project_dir/docs"; then
  bad "Dokumentationsbeispiele enthalten keine offensichtlichen Secrets"
else
  ok
fi

finish_suite
