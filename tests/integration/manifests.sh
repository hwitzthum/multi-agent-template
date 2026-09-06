#!/usr/bin/env bash
# Manifeste kommen aus Git: .gitignore gilt, geloeschte und neue Pfade bleiben
# sichtbar, ignorierte Inhalte werden nie gelesen. Aus demselben Manifest laesst
# sich der Stand des Arbeitsbaums wiederherstellen.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/common.sh"
. "$project_dir/scripts/agent/ledger.sh"

begin_suite manifests
fixture_workspace

# --- Was ein Manifest sieht und was nicht ----------------------------------
new_project_fixture
printf '%s\n' 'PASSWORT=geheim' > "$fixture/.env"
printf '%s\n' 'node_modules/' >> "$fixture/.gitignore"
mkdir -p "$fixture/node_modules/paket"
printf '%s\n' 'abhaengigkeit' > "$fixture/node_modules/paket/index.js"
fixture_git_init

before="$tmp_root/repo.before"
after="$tmp_root/repo.after"
expect_success "Manifest laesst sich aus einem Git-Projekt bilden" agent_repo_manifest "$fixture" "$before"
assert_file_has "verfolgte Datei steht mit Blob-Hash im Manifest" "$before" '  src/app.txt'
assert_file_has "ignorierter Ordner steht nur mit Namen im Manifest" "$before" 'ignored  node_modules/'
assert_file_lacks "Inhalt eines ignorierten Ordners wird nie gehasht" "$before" 'node_modules/paket/index.js'
assert_file_has "ignorierte Datei steht nur mit Namen im Manifest" "$before" 'ignored  .env'
assert_file_has "Git-Steuerdateien zaehlen zum Manifest" "$before" '  .git/config'
assert_file_lacks "der Laufordner bleibt draussen" "$before" '.agent-runs'

# Aenderungen an ignorierten Inhalten bleiben unsichtbar, neue Namen nicht.
printf '%s\n' 'PASSWORT=anders' > "$fixture/.env"
printf '%s\n' 'noch eine Abhaengigkeit' > "$fixture/node_modules/paket/extra.js"
printf '%s\n' 'neu' > "$fixture/src/neu.txt"
rm -f "$fixture/src/app.txt"
printf '%s\n' 'exit 0' > "$fixture/.git/hooks/pre-commit"
agent_repo_manifest "$fixture" "$after"
changes=$(agent_manifest_changes "$before" "$after")
assert_eq "geaenderter ignorierter Inhalt bleibt unsichtbar" 0 "$(printf '%s\n' "$changes" | grep -c 'node_modules/paket')"
assert_eq "neue untracked Datei wird sichtbar" 1 "$(printf '%s\n' "$changes" | grep -c '^src/neu.txt$')"
assert_eq "geloeschte Datei wird sichtbar" 1 "$(printf '%s\n' "$changes" | grep -c '^src/app.txt$')"
assert_eq "geaenderter Git-Hook wird sichtbar" 1 "$(printf '%s\n' "$changes" | grep -c '^.git/hooks/pre-commit$')"
assert_file_has "geloeschte Datei ist im Manifest als missing vermerkt" "$after" 'missing  src/app.txt'

new_project_fixture
fixture_git_init
agent_repo_manifest "$fixture" "$tmp_root/ohne-env.before"
printf '%s\n' 'PASSWORT=geheim' > "$fixture/.env"
agent_repo_manifest "$fixture" "$tmp_root/ohne-env.after"
assert_eq "ein neu angelegter ignorierter Pfad wird mit Namen sichtbar" 1 \
  "$(agent_manifest_changes "$tmp_root/ohne-env.before" "$tmp_root/ohne-env.after" | grep -c '^.env$')"

# --- Wiederherstellung aus dem Snapshot ------------------------------------
new_project_fixture
fixture_git_init
# Der Besitzer hat vor dem Lauf etwas Unversioniertes in derselben Datei stehen.
printf '%s\n' 'besitzer-stand' > "$fixture/src/app.txt"
snapshot="$tmp_root/snapshot.manifest"
agent_repo_manifest "$fixture" "$snapshot"
printf '%s\n' 'agenten-stand' > "$fixture/src/app.txt"
printf '%s\n' 'nebenprodukt' > "$fixture/src/ausserhalb.txt"
quarantine="$tmp_root/quarantine"
expect_success "Snapshot stellt geaenderte und neue Pfade zurueck" \
  agent_snapshot_restore "$fixture" "$snapshot" "$quarantine" src/app.txt src/ausserhalb.txt
assert_eq "Besitzerstand in derselben Datei ueberlebt das Zuruecksetzen" 'besitzer-stand' "$(cat "$fixture/src/app.txt")"
assert_file "neue Datei liegt in der Quarantaene" "$quarantine/src/ausserhalb.txt"
[ -e "$fixture/src/ausserhalb.txt" ] && bad "neue Datei ist aus dem Arbeitsbaum verschwunden" || ok
agent_repo_manifest "$fixture" "$tmp_root/nach-restore.manifest"
assert_eq "nach dem Zuruecksetzen ist kein Unterschied mehr uebrig" '' \
  "$(agent_manifest_changes "$snapshot" "$tmp_root/nach-restore.manifest")"

# Eine geloeschte Datei kommt zurueck, eine im Snapshot fehlende verschwindet.
rm -f "$fixture/src/app.txt"
expect_success "geloeschte Datei kommt aus dem Snapshot zurueck" \
  agent_snapshot_restore "$fixture" "$snapshot" "$quarantine" src/app.txt
assert_eq "wiederhergestellte Datei traegt den Snapshot-Inhalt" 'besitzer-stand' "$(cat "$fixture/src/app.txt")"
expect_failure "ein Pfad ausserhalb des Projekts wird abgewiesen" \
  agent_snapshot_restore "$fixture" "$snapshot" "$quarantine" ../ausbruch.txt

# --- Ledger: der Dateiname ist der Schluessel ------------------------------
new_project_fixture
make_task --id 017 --title 'Namensregel'
expect_output "Task-Lookup findet die Datei ueber ihren Namen" "$fixture/docs/tasks/017.md" \
  ledger_task_path_by_id "$fixture/docs/tasks" 017
expect_failure "Task-Lookup scheitert bei unbekannter ID" ledger_task_path_by_id "$fixture/docs/tasks" 099
mv "$fixture/docs/tasks/017.md" "$fixture/docs/tasks/aufgabe.md"
expect_failure "Validator weist einen Dateinamen ungleich der ID ab" \
  "$project_dir/scripts/validate-ledger.sh" --project-dir "$fixture"

finish_suite
