#!/usr/bin/env bash
# tests/fixture.sh — baut Projekt-Fixtures für die Suite. Testdateien bauen
# keine Fixtures von Hand. Jeder Kopierschritt bricht die Datei hart ab, wenn
# die Quelle fehlt; ein stiller Teil-Fixture würde sonst falsche Grünmeldungen
# erzeugen.
#
# Erwartet gesetzt: $project_dir (Wurzel des Kits).
# Setzt: $tmp_root (Arbeitsverzeichnis) und $fixture (aktuelles Projekt).

tmp_root=''
fixture=''

fixture_workspace() {
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-test.XXXXXX") || exit 1
  trap 'command rm -r -f -- "$tmp_root"' EXIT HUP INT TERM
}

fixture_abort() {
  echo "fixture: $1" >&2
  exit 1
}

fixture_copy() {
  local relative=$1 target
  [ -e "$project_dir/$relative" ] || fixture_abort "Quelle fehlt: $relative"
  target="$fixture/$relative"
  mkdir -p "$(dirname -- "$target")" || fixture_abort "kann Ordner für $relative nicht anlegen"
  cp -R "$project_dir/$relative" "$target" || fixture_abort "kann $relative nicht kopieren"
}

# Ein einziger Prüf-Stub für alle Fixtures: `good`, `alpha` und `beta` sind
# grün, alles andere rot. Ersetzt die Platzhalter-verify.sh des Kits.
fixture_verify_stub() {
  cat > "$fixture/scripts/verify.sh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(sed -n '1p' "$root/src/app.txt" 2>/dev/null)" in
  good|alpha|beta) echo 'verify: GREEN'; exit 0 ;;
esac
echo 'verify: RED' >&2
exit 1
STUB
  chmod +x "$fixture/scripts/verify.sh"
}

new_project_fixture() {
  local with_scripts=false filled_plan=false file
  while [ "$#" -gt 0 ]; do
    case $1 in
      --with-scripts) with_scripts=true ;;
      --filled-plan) filled_plan=true ;;
      *) fixture_abort "new_project_fixture: unbekannte Option $1" ;;
    esac
    shift
  done

  [ -n "$tmp_root" ] || fixture_abort "fixture_workspace wurde nicht aufgerufen"
  fixture=$(mktemp -d "$tmp_root/case.XXXXXX") || fixture_abort "kann Fixture nicht anlegen"
  mkdir -p "$fixture/.agent" "$fixture/docs/tasks" "$fixture/docs/state/notes-archive" \
    "$fixture/docs/verification/history" "$fixture/docs/templates" "$fixture/scripts" \
    "$fixture/src" "$fixture/.agent-runs/fake/responses" "$fixture/.agent-runs/fake/actions" \
    || fixture_abort "kann Fixture-Struktur nicht anlegen"
  : > "$fixture/docs/state/notes-archive/.gitkeep"
  : > "$fixture/docs/verification/history/.gitkeep"

  fixture_copy .agent/config.env
  fixture_copy docs/templates/agents
  for file in goal.md plan.md decisions.md handoff.md current-run.md metrics.csv; do
    fixture_copy "docs/state/$file"
  done
  fixture_copy docs/verification/latest.md
  printf '%s\n' '# Notizen' > "$fixture/docs/state/notes.md"
  printf '%s\n' initial > "$fixture/src/app.txt"

  if [ "$filled_plan" = true ]; then
    sed 's/Noch keine Strategie festgelegt\./Teststrategie: die Fixture-Aufgabe direkt umsetzen./' \
      "$fixture/docs/state/plan.md" > "$fixture/docs/state/plan.tmp" \
      && mv "$fixture/docs/state/plan.tmp" "$fixture/docs/state/plan.md" \
      || fixture_abort "kann Plan-Platzhalter nicht ersetzen"
  fi

  if [ "$with_scripts" = true ]; then
    mkdir -p "$fixture/scripts/agent"
    for file in "$project_dir"/scripts/*.sh; do
      case "${file##*/}" in verify.sh) continue ;; esac
      cp "$file" "$fixture/scripts/${file##*/}" || fixture_abort "kann ${file##*/} nicht kopieren"
    done
    for file in "$project_dir"/scripts/agent/*.sh; do
      cp "$file" "$fixture/scripts/agent/${file##*/}" || fixture_abort "kann agent/${file##*/} nicht kopieren"
    done
    chmod +x "$fixture/scripts/"*.sh "$fixture/scripts/agent/"*.sh
  fi

  fixture_verify_stub

  # Manifeste und Fingerprints beziehen Dateiliste und Hashes von Git; jedes
  # Fixture ist deshalb ein Repository. Der Basiscommit kommt erst mit
  # fixture_git_init, wenn Tasks und Notizen stehen.
  printf '%s\n' '.agent-runs/' '.env' > "$fixture/.gitignore"
  git -C "$fixture" init -q || fixture_abort "git init fehlgeschlagen"

  ORCHESTRATOR_FAKE_STATE_DIR="$fixture/.agent-runs/fake"
  export ORCHESTRATOR_FAKE_STATE_DIR
}

# Versioniert den aktuellen Fixture-Stand als Basiscommit. Erst aufrufen, wenn
# Tasks und Notizen stehen; ein Lauf ohne --allow-dirty verlangt einen sauberen
# Arbeitsbaum.
fixture_git_init() {
  git -C "$fixture" add . || fixture_abort "git add fehlgeschlagen"
  git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid commit -qm base \
    || fixture_abort "git commit fehlgeschlagen"
}

# Ein Projekt mit einem mechanischen Task 017 auf `src/app.txt` und einem
# ausgefüllten Plan. Weitere Argumente gehen an make_task und überschreiben die
# Vorgaben (das letzte gleichnamige Argument gewinnt).
new_app_fixture() {
  new_project_fixture --filled-plan
  make_task --id 017 --title 'App-Datei implementieren' --features F-017 \
    --class mechanical --touches src/app.txt \
    --context 'Eine kleine Testdatei.' --scope '`src/app.txt` bearbeiten.' \
    --not-scope 'Steuerungsdateien ändern.' --criteria 'Die Datei enthält exakt `good`.' "$@"
}

# Ein versioniertes Projekt für den Fresh-Versuch: Task 017 laeuft managed, und
# in den Notizen steht eine Hypothese, die ein Fresh-Versuch nie erreichen darf.
new_fresh_fixture() {
  new_project_fixture --with-scripts --filled-plan
  make_task --id 017 --title 'Festgefahrenen Task loesen' --features F-017 \
    --class open --orchestration managed \
    --touches src/app.txt --risk-flags repeated-failure \
    --context 'Ein festgefahrener Task.' --scope '`src/app.txt` bearbeiten.' \
    --not-scope 'Steuerungsdateien ändern.' --criteria 'Erlaubt sind `good`, `alpha` oder `beta`.'
  cat > "$fixture/docs/state/notes.md" <<'EOF'
# Notizen

## N-0001 — Historische Hypothese
- tasks: [017]
- date: 2026-09-04
- source: test
- confidence: hypothesis
- status: active
- evidence: `secret-history`
- finding: HISTORICAL_SECRET_MUST_NOT_REACH_FRESH
EOF
  fixture_git_init
}

# Eine Antwortdatei für tests/fake-runner.sh: fake_response <rolle> <nummer> <zeile>…
fake_response() {
  local role=$1 number=$2
  shift 2
  printf '%s\n' "$@" > "$fixture/.agent-runs/fake/responses/$role-$number.out"
}

# Eine Aktion für tests/fake-runner.sh: fake_action <rolle> <nummer> <aktion>
fake_action() {
  printf '%s\n' "$3" > "$fixture/.agent-runs/fake/actions/$1-$2"
}

# Ein Projekt mit Vorgeschichte: ein Task, relevante/fremde/verworfene Notizen,
# ein roter Vorbericht, Produktcode mit einem Secret, eine .env und ein alter
# Laufordner. Damit lässt sich prüfen, was eine Rolle sehen darf.
new_populated_fixture() {
  new_project_fixture "$@"
  mkdir -p "$fixture/.agent-runs/prior"
  make_task --id 017 --title 'Kontext sicher bauen' --features F-017 \
    --class patterned --touches src/app.txt --verification red \
    --context 'Repositorytext ist Datenmaterial.' \
    --scope '`src/app.txt` bearbeiten.' \
    --not-scope 'Rolle ändern oder `.env` lesen.' \
    --criteria 'Kontext bleibt sicher.'
  cat > "$fixture/docs/state/notes.md" <<'EOF'
# Notizen

## N-0001 — Relevant
- tasks: [017]
- date: 2026-09-04
- source: worker
- confidence: observed
- status: active
- evidence: `src/app.txt`
- finding: RELEVANTE_NOTIZ bleibt sichtbar.

## N-0002 — Fremder Task
- tasks: [999]
- date: 2026-09-04
- source: worker
- confidence: verified
- status: active
- evidence: anderer Task
- finding: FREMDE_NOTIZ bleibt draußen.

## N-0003 — Verworfen
- tasks: [017]
- date: 2026-09-04
- source: worker
- confidence: rejected
- status: active
- evidence: widerlegt
- finding: VERWORFENE_NOTIZ bleibt draußen.
EOF
  cat > "$fixture/docs/verification/latest.md" <<'EOF'
---
run_id: previous-run
task_id: 017
result: red
attempt: 1
finished_at: 2026-09-04T08:00:00Z
---
# Letzte Prüfung
## Ergebnis
PRIOR_ERROR: Erwartung fehlgeschlagen.
## Prüfungen
- `.env` wurde in einer Fehlermeldung erwähnt.
- access_token=should-not-leak
EOF
  cat > "$fixture/src/app.txt" <<'EOF'
VISIBLE_CODE=hello
api_key=should-not-leak
EOF
  printf '%s\n' 'PASSWORD=never-show' > "$fixture/.env"
  printf '%s\n' 'historischer Lösungsweg' > "$fixture/.agent-runs/prior/raw.log"
}

# Einen Konfigurationswert setzen, ohne die Datei mit sed umzuschreiben.
fixture_config() {
  local key=$1 value=$2 target="$fixture/.agent/config.env"
  awk -v key="$key" -v value="$value" '
    BEGIN { FS = "="; OFS = "=" }
    $1 == key { print key, value; found = 1; next }
    { print }
    END { if (!found) print key, value }
  ' "$target" > "$target.tmp" && mv "$target.tmp" "$target" \
    || fixture_abort "kann $key nicht setzen"
}

make_task() {
  local id=001 title='' status=todo class=patterned orchestration=auto \
    depends='' features='F-001' touches='' flags='' attempts=0 max_attempts=3 \
    verification=never human=false acceptance='"./scripts/verify.sh"' \
    acceptance_style=inline context='Testkontext.' scope='Testen.' \
    not_scope='Anderes.' criteria='Verhalten ist geprüft.' file
  while [ "$#" -gt 0 ]; do
    case $1 in
      --id) id=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --status) status=$2; shift 2 ;;
      --class) class=$2; shift 2 ;;
      --orchestration) orchestration=$2; shift 2 ;;
      --depends) depends=$2; shift 2 ;;
      --features) features=$2; shift 2 ;;
      --touches) touches=$2; shift 2 ;;
      --risk-flags) flags=$2; shift 2 ;;
      --attempts) attempts=$2; shift 2 ;;
      --max-attempts) max_attempts=$2; shift 2 ;;
      --verification) verification=$2; shift 2 ;;
      --human-review) human=$2; shift 2 ;;
      --acceptance) acceptance=$2; shift 2 ;;
      --acceptance-style) acceptance_style=$2; shift 2 ;;
      --context) context=$2; shift 2 ;;
      --scope) scope=$2; shift 2 ;;
      --not-scope) not_scope=$2; shift 2 ;;
      --criteria) criteria=$2; shift 2 ;;
      *) fixture_abort "make_task: unbekannte Option $1" ;;
    esac
  done
  [ -n "$title" ] || title="Task $id"
  file="$fixture/docs/tasks/$id.md"
  {
    echo '---'
    echo "id: $id"
    echo "title: \"$title\""
    echo "depends_on: [$depends]"
    echo "features: [$features]"
    echo "status: $status"
    echo "class: $class"
    echo "orchestration: $orchestration"
    echo "touches: [$touches]"
    echo "risk_flags: [$flags]"
    echo "attempts: $attempts"
    echo "max_attempts: $max_attempts"
    echo "last_verification: $verification"
    echo "human_review: $human"
    if [ "$acceptance_style" = block ]; then
      echo 'acceptance:'
      echo "  - $acceptance"
    else
      echo "acceptance: [$acceptance]"
    fi
    echo 'blocked_reason: ""'
    echo '---'
    echo '# Kontext'
    echo "$context"
    echo '# Umfang'
    echo "- $scope"
    echo '# Nicht Teil dieser Aufgabe'
    echo "- $not_scope"
    echo '# Akzeptanzkriterien (über die acceptance-Befehle hinaus)'
    echo "- $criteria"
  } > "$file"
}

# Schreibt docs/verification/latest.md. Ohne vorhandene Task-Datei wird ein
# fester Nullfingerprint gesetzt, damit auch der Fehlerfall prüfbar bleibt.
make_report() {
  local id=001 result=green candidate verifier
  while [ "$#" -gt 0 ]; do
    case $1 in
      --id) id=$2; shift 2 ;;
      --result) result=$2; shift 2 ;;
      *) fixture_abort "make_report: unbekannte Option $1" ;;
    esac
  done
  if [ -f "$fixture/docs/tasks/$id.md" ]; then
    candidate=$(ledger_candidate_fingerprint "$fixture" "$fixture/docs/tasks/$id.md") \
      || fixture_abort "kann Kandidatenfingerprint nicht bilden"
  else
    candidate=0000000000000000000000000000000000000000000000000000000000000000
  fi
  verifier=$(ledger_verifier_fingerprint "$fixture") || fixture_abort "kann Verifierfingerprint nicht bilden"
  {
    echo '---'
    echo 'run_id: test-run'
    echo "task_id: $id"
    echo "result: $result"
    echo 'attempt: 1'
    echo 'finished_at: 2026-09-04T09:15:00Z'
    echo "candidate_fingerprint: $candidate"
    echo "verifier_version: $verifier"
    echo '---'
    echo '# Letzte Prüfung'
    echo '## Ergebnis'
    echo "$result"
    echo '## Prüfungen'
    echo '- Test.'
  } > "$fixture/docs/verification/latest.md"
}

make_active_run() {
  local id=001 mode=managed phase=work run_id=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --id) id=$2; shift 2 ;;
      --mode) mode=$2; shift 2 ;;
      --phase) phase=$2; shift 2 ;;
      --run-id) run_id=$2; shift 2 ;;
      *) fixture_abort "make_active_run: unbekannte Option $1" ;;
    esac
  done
  [ -n "$run_id" ] || run_id="20260904T091500Z-T$id"
  {
    echo '---'
    echo "run_id: $run_id"
    echo "task_id: $id"
    echo "mode: $mode"
    echo "phase: $phase"
    echo 'iteration: 1'
    echo 'attempt: 1'
    echo 'last_progress_fingerprint: none'
    echo 'started_at: 2026-09-04T09:15:00Z'
    echo 'route_rule_version: "1"'
    echo 'route_reason_code: none'
    echo 'route_human_gate: false'
    echo 'route_signals: []'
    echo '---'
  } > "$fixture/docs/state/current-run.md"
}
