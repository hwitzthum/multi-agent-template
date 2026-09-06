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
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "grüner Kandidat passiert das Gateway" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file "grünes Gateway legt den Task-Beleg an" "$fixture/docs/verification/017.md"
assert_eq "Task-Beleg ist grün" green "$(ledger_scalar "$fixture/docs/verification/017.md" result)"
assert_file_lacks "der Task traegt kein Pruefergebnis mehr" "$fixture/docs/tasks/017.md" 'last_verification'
assert_file_has "Bericht enthält Kandidatenfingerprint" "$fixture/docs/verification/latest.md" 'candidate_fingerprint:'
assert_file_has "Bericht enthält Verifierversion" "$fixture/docs/verification/latest.md" 'verifier_version:'
assert_file_has "Bericht nennt jeden Befehl mit Ergebnis" "$fixture/docs/verification/latest.md" '- acceptance-1: GREEN'
assert_file_has "das globale verify.sh laeuft auch ohne acceptance-Eintrag" "$fixture/.agent-runs/$run_id/verify/attempt-1.log" 'command: ./scripts/verify.sh'
assert_file_has "vollständiger Log liegt am dokumentierten Ort" "$fixture/.agent-runs/$run_id/verify/attempt-1.log" '=== acceptance-1 ==='
expect_success "passender grüner Fingerprint erlaubt done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress
sed 's/task_id: 017/task_id: 018/' "$fixture/docs/verification/latest.md" > "$fixture/docs/verification/.latest.tmp"
mv "$fixture/docs/verification/.latest.tmp" "$fixture/docs/verification/latest.md"
expect_success "der Task-Beleg gilt unabhängig von latest.md" ledger_verification_is_green "$fixture/docs/verification" 017 "$fixture" "$fixture/docs/tasks/017.md"

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "Kandidat wird zunächst grün" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
printf '%s\n' changed > "$fixture/src/app.txt"
expect_failure "nachträgliche Kandidatenänderung verweigert done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "Verifierstand wird zunächst grün" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
printf '%s\n' '# verifier changed' >> "$fixture/scripts/verify.sh"
expect_failure "nachträgliche Teständerung verweigert done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress

# Die Prüflogik umfasst auch den Konfigurationsleser, über den verify-task.sh
# sein Zeitlimit bezieht. Gemessen wird direkt am Verifierstand: über den
# Statuswechsel antwortete sonst schon der Kandidat, der Skripte mitzählt.
new_project_fixture --with-scripts
verifier_state=$(bash -c '. "$1/scripts/agent/ledger.sh"; ledger_verifier_fingerprint "$1"' _ "$fixture")
printf '%s\n' '# reader changed' >> "$fixture/scripts/agent/config.sh"
[ "$verifier_state" != "$(bash -c '. "$1/scripts/agent/ledger.sh"; ledger_verifier_fingerprint "$1"' _ "$fixture")" ] \
  && ok || bad "geänderter Konfigurationsleser ändert den Verifierstand"

# `--project-dir` benennt nur die Daten: geprüft hat die gestartete
# Implementierung, nicht eine abweichende Kopie im Zielprojekt.
new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
printf '%s\n' '#!/usr/bin/env bash' 'echo 0' > "$fixture/scripts/agent/config.sh"
expect_success "abweichender Konfigurationsleser im Projekt zählt nicht" "$project_dir/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" 017

# Die Task-ID ist eine Ziffernfolge, keine dreistellige Schablone: der
# Validator laesst 1234 zu, also muss das Gateway sie auch pruefen koennen.
new_project_fixture --with-scripts
make_task --id 1234 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "vierstellige Task-ID passiert das Gateway" \
  "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --timeout 3 1234
assert_file "der Beleg liegt unter der vollen ID" "$fixture/docs/verification/1234.md"
expect_failure "eine Run-ID ohne Zeitstempel bleibt ungueltig" \
  "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id nicht-echt --timeout 3 1234

# Derselbe Satz am Verifierstand: gleiche Prüflogik ergibt denselben Stand, egal
# aus welchem Ordner sie läuft, und eine abweichende Kopie im Projekt gar keinen.
new_project_fixture --with-scripts
verifier_state=$(ledger_verifier_fingerprint "$fixture")
assert_eq "gleiche Prüflogik ergibt denselben Verifierstand" "$verifier_state" \
  "$(bash -c '. "$1/scripts/agent/ledger.sh"; ledger_verifier_fingerprint "$1"' _ "$fixture")"
printf '%s\n' '# fremde Kopie' >> "$fixture/scripts/verify-task.sh"
assert_eq "abweichende Skriptkopie im Projekt ändert den Verifierstand nicht" "$verifier_state" \
  "$(ledger_verifier_fingerprint "$fixture")"

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt --human-review true \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_success "Human-Review-Kandidat wird maschinell grün" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
expect_failure "Human Review verhindert direktes done" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done in_progress
expect_success "grüner Human-Review-Kandidat wechselt in review" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 review in_progress
expect_failure "review braucht ausdrückliche menschliche Freigabe" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" set-status 017 done review
expect_success "menschliche Freigabe schließt review ab" "$fixture/scripts/agent/status.sh" --project-dir "$fixture" --human-approved set-status 017 done review

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh; touch injected"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_failure "Shell-Metazeichen werden abgewiesen" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
[ ! -e "$fixture/injected" ] && ok || bad "abgewiesener Befehl wurde dennoch ausgeführt"
assert_file_has "Bericht dokumentiert sichere Abweisung" "$fixture/docs/verification/latest.md" 'REJECTED'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "pytest"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
printf '%s\n' './scripts/verify.sh' > "$fixture/.agent/verification-allowlist"
expect_failure "Projekt-Allowlist kann Standardpräfixe verschärfen" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "verschärfte Allowlist weist Zusatzbefehl aus" "$fixture/docs/verification/latest.md" 'Befehlspraefix ist nicht erlaubt'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"mypy", "gofmt -l ."' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_failure "fremde Präfixe scheitern an der Standardliste" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "nicht gelistetes Werkzeug wird abgewiesen" "$fixture/docs/verification/latest.md" '- acceptance-1: REJECTED'
assert_file_has "Präfixe gelten auf Wortgrenze: go erlaubt kein gofmt" "$fixture/docs/verification/latest.md" '- acceptance-2: REJECTED'
assert_file_has "das Pflicht-verify.sh läuft trotz zweier Abweisungen" "$fixture/docs/verification/latest.md" '- acceptance-3: GREEN'

# Das Kit liefert die Allowlist als Beispiel aus; sie trägt genau die
# generischen Standardpräfixe.
assert_file "Beispiel-Allowlist wird ausgeliefert" "$project_dir/.agent/verification-allowlist"
for prefix in './scripts/verify.sh' 'npm' 'pytest' 'go' 'cargo' 'make'; do
  assert_file_has "Beispiel-Allowlist nennt $prefix" "$project_dir/.agent/verification-allowlist" "$prefix"
done

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "cargo test"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
expect_failure "fehlender erlaubter Befehl ergibt Rot" env PATH=/usr/bin:/bin "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "fehlender Befehl wird als technischer Fehler getrennt" "$fixture/docs/verification/latest.md" 'failure_kind: verifier'
assert_file_has "fehlender Befehl erhält ein eigenes Ergebnis" "$fixture/docs/verification/latest.md" '- acceptance-2: MISSING'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "pytest"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
mkdir -p "$fixture/bin"
cat > "$fixture/bin/pytest" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
chmod +x "$fixture/bin/pytest"
expect_failure "Zeitlimit ergibt Rot" env PATH="$fixture/bin:/usr/bin:/bin" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 1 017
assert_file_has "Timeout ist im Bericht sichtbar" "$fixture/docs/verification/latest.md" '- acceptance-2: TIMEOUT'
assert_file_has "Timeout zählt als technischer Fehler" "$fixture/docs/verification/latest.md" 'failure_kind: verifier'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --acceptance '"./scripts/verify.sh", "pytest", "cargo test"' \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' good > "$fixture/src/app.txt"
mkdir -p "$fixture/bin"
cat > "$fixture/bin/pytest" <<'EOF'
#!/usr/bin/env bash
echo unit-control-failed
exit 1
EOF
cat > "$fixture/bin/cargo" <<'EOF'
#!/usr/bin/env bash
echo second-control-failed
exit 1
EOF
chmod +x "$fixture/bin/pytest" "$fixture/bin/cargo"
expect_failure "negative Kontroll-Fixture muss sicher scheitern" env PATH="$fixture/bin:/usr/bin:/bin" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_file_has "erster Fehler wird berichtet" "$fixture/docs/verification/latest.md" '- acceptance-2: RED'
assert_file_has "der nächste Befehl läuft trotz des Fehlers" "$fixture/docs/verification/latest.md" '- acceptance-3: RED'
assert_file_has "echter Prozessoutput liegt im Voll-Log" "$fixture/.agent-runs/$run_id/verify/attempt-1.log" 'second-control-failed'

new_project_fixture --with-scripts
make_task --id 017 --title 'Kandidat verifizieren' --status in_progress \
  --class patterned --orchestration verified --touches src/app.txt \
  --context 'Ein deterministischer Testkandidat.' --scope '`src/app.txt` prüfen.' \
  --not-scope 'Andere Produktdateien ändern.' --criteria 'Die Datei enthält exakt `good`.'
printf '%s\n' bad > "$fixture/src/app.txt"
expect_failure "falscher Produktkandidat muss sicher scheitern" "$fixture/scripts/verify-task.sh" --project-dir "$fixture" --run-id "$run_id" --timeout 3 017
assert_eq "Produktfehler bleibt als red im Task-Beleg" red "$(ledger_scalar "$fixture/docs/verification/017.md" result)"
assert_file_has "Produktfehler wird getrennt klassifiziert" "$fixture/docs/verification/latest.md" 'failure_kind: product'

finish_suite
