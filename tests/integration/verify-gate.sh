#!/usr/bin/env bash
# Das Prüftor führt nur erlaubte Befehle aus, trennt Produkt- von
# Verifierfehlern und bindet `done` an einen aktuellen Fingerprint.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/ledger.sh"

run_id=20260904T120000Z-T017

begin_suite verify-gate
fixture_workspace

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "grüner Kandidat passiert das Gateway" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_eq "grünes Gateway aktualisiert last_verification" green "$(ledger_scalar "$fixture/docs/tasks/017.md" last_verification)"
assert_file_has "Bericht enthält Kandidatenfingerprint" "$fixture/docs/verification/latest.md" 'candidate_fingerprint:'
assert_file_has "Bericht enthält Verifierversion" "$fixture/docs/verification/latest.md" 'verifier_version:'
assert_file_has "Bericht nennt alle Stufen" "$fixture/docs/verification/latest.md" '- integration: SKIPPED'
assert_file_has "vollständiger Log liegt am dokumentierten Ort" "$fixture/.agent-runs/$run_id/verify/attempt-1.log" 'acceptance: acceptance-1'
expect_success "passender grüner Fingerprint erlaubt done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress
sed 's/task_id: 017/task_id: 018/' "$fixture/docs/verification/latest.md" > "$fixture/docs/verification/.latest.tmp"
mv "$fixture/docs/verification/.latest.tmp" "$fixture/docs/verification/latest.md"
expect_success "historischer Task-Beleg bleibt nach anderer Latest-Prüfung auffindbar" ledger_verification_is_green "$fixture/docs/verification" 017 "$fixture" "$fixture/docs/tasks/017.md"

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "Kandidat wird zunächst grün" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
printf '%s\n' changed > "$fixture/src/app.txt"
expect_failure "nachträgliche Kandidatenänderung verweigert done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "Verifierstand wird zunächst grün" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
printf '%s\n' '# verifier changed' >> "$fixture/scripts/verify.sh"
expect_failure "nachträgliche Teständerung verweigert done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt --human-review true \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "Human-Review-Kandidat wird maschinell grün" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
expect_failure "Human Review verhindert direktes done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress
expect_success "grüner Human-Review-Kandidat wechselt in review" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 review in_progress
expect_failure "review braucht ausdrückliche menschliche Freigabe" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done review
expect_success "menschliche Freigabe schließt review ab" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" --human-approved set-status 017 done review

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh; touch injected"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
expect_failure "Shell-Metazeichen werden abgewiesen" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
[ ! -e "$fixture/injected" ] && ok || bad "abgewiesener Befehl wurde dennoch ausgeführt"
assert_file_has "Bericht dokumentiert sichere Abweisung" "$fixture/docs/verification/latest.md" 'REJECTED'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "pytest"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
printf '%s\n' './scripts/verify.sh' > "$fixture/.agent/verification-allowlist"
expect_failure "Projekt-Allowlist kann Standardpräfixe verschärfen" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "verschärfte Allowlist weist Zusatzbefehl aus" "$fixture/docs/verification/latest.md" 'Befehlspraefix ist nicht erlaubt'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "runner:release"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
cat > "$fixture/scripts/named-check" <<'EOF'
#!/usr/bin/env bash
echo named-runner-ok
EOF
chmod +x "$fixture/scripts/named-check"
printf '%s\n' 'release|build|./scripts/named-check' > "$fixture/.agent/verification-runners"
expect_success "Projektkonfiguration ergänzt einen benannten Runner" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "benannter Runner wird seiner Stufe zugeordnet" "$fixture/docs/verification/latest.md" '- build: GREEN'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "mypy"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
expect_failure "fehlender erlaubter Befehl ergibt Rot" env PATH=/usr/bin:/bin "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "fehlender Befehl wird als technischer Fehler getrennt" "$fixture/docs/verification/latest.md" 'failure_kind: verifier'
assert_file_has "fehlender Befehl erhält Stufenstatus" "$fixture/docs/verification/latest.md" '- lint: MISSING'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "pytest"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
mkdir -p "$fixture/bin"
cat > "$fixture/bin/pytest" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
chmod +x "$fixture/bin/pytest"
expect_failure "Zeitlimit ergibt Rot" env PATH="$fixture/bin:/usr/bin:/bin" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 1 017
assert_file_has "Timeout ist im Bericht sichtbar" "$fixture/docs/verification/latest.md" '- unit: TIMEOUT'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "pytest", "ruff"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' good > "$fixture/src/app.txt"
mkdir -p "$fixture/bin"
cat > "$fixture/bin/pytest" <<'EOF'
#!/usr/bin/env bash
echo unit-control-failed
exit 1
EOF
cat > "$fixture/bin/ruff" <<'EOF'
#!/usr/bin/env bash
echo lint-control-failed
exit 1
EOF
chmod +x "$fixture/bin/pytest" "$fixture/bin/ruff"
expect_failure "negative Kontroll-Fixture muss sicher scheitern" env PATH="$fixture/bin:/usr/bin:/bin" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "Unit-Fehler wird berichtet" "$fixture/docs/verification/latest.md" '- unit: RED'
assert_file_has "spätere Lint-Stufe läuft trotz Unit-Fehler" "$fixture/docs/verification/latest.md" '- lint: RED'
assert_file_has "echter Prozessoutput liegt im Voll-Log" "$fixture/.agent-runs/$run_id/verify/attempt-1.log" 'lint-control-failed'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --features F-017 --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
make_active_run --id 017 --mode verified --phase verify --run-id "$run_id"
printf '%s\n' bad > "$fixture/src/app.txt"
expect_failure "falscher Produktkandidat muss sicher scheitern" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_eq "Produktfehler bleibt als red im Task" red "$(ledger_scalar "$fixture/docs/tasks/017.md" last_verification)"
assert_file_has "Produktfehler wird getrennt klassifiziert" "$fixture/docs/verification/latest.md" 'failure_kind: product'

finish_suite
