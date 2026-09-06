#!/usr/bin/env bash
# Rollenausgaben werden gegen einen festen Feldvertrag geprüft und grosse
# Rohausgaben lokal redigiert zusammengefasst.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

output_tool="$project_dir/scripts/agent/output.sh"
roles='manager-plan worker-brainstorm manager-manage worker-task worker-fresh reviewer finalizer'

begin_suite output-contract
fixture_workspace
new_project_fixture

valid_manage="$tmp_root/valid-manage.txt"
cat > "$valid_manage" <<'EOF'
---
action: dispatch
task_id: 017
worker_kind: normal
reason_code: NEXT_HIGHEST_VALUE
---
EOF
expect_success "gueltiger Manager-Output" "$output_tool" validate manager-manage "$valid_manage"

invalid_manage="$tmp_root/invalid-manage.txt"
cat > "$invalid_manage" <<'EOF'
---
action: dispatch
task_id: 017,018
worker_kind: normal
reason_code: NEXT
---
---
action: done
---
EOF
expect_failure "mehrfacher oder mehrdeutiger Manager-Output" "$output_tool" validate manager-manage "$invalid_manage"

valid_plan="$tmp_root/valid-plan.txt"
cat > "$valid_plan" <<'EOF'
PLAN_UPDATED=yes
TASKS_CREATED=017
OPEN_RISK=-
EOF
expect_success "gueltiger Plan-Manager-Output" "$output_tool" validate manager-plan "$valid_plan"

valid_brainstorm="$tmp_root/valid-brainstorm.txt"
cat > "$valid_brainstorm" <<'EOF'
NOTES_ADDED=N-0004
RISKS=Kontextlimit
TEST_IDEAS=Grenzfall testen
EOF
expect_success "gueltiger Brainstorm-Output" "$output_tool" validate worker-brainstorm "$valid_brainstorm"

valid_worker="$tmp_root/valid-worker.txt"
cat > "$valid_worker" <<'EOF'
RESULT=implemented
CHANGED_PATHS=src/app.txt
TESTS_RUN=./scripts/verify.sh
NOTES_ADDED=-
EOF
expect_success "gueltiger Worker-Output" "$output_tool" validate worker-task "$valid_worker"
expect_success "gueltiger Fresh-Worker-Output" "$output_tool" validate worker-fresh "$valid_worker"
printf '%s\n' 'ROLE=manager' >> "$valid_worker"
expect_failure "manipuliertes Outputfeld kann Rolle nicht aendern" "$output_tool" validate worker-task "$valid_worker"

invalid_fresh="$tmp_root/invalid-fresh.txt"
cat > "$invalid_fresh" <<'EOF'
RESULT=implemented
CHANGED_PATHS=src/app.txt
TESTS_RUN=tests
NOTES_ADDED=N-9999
EOF
expect_failure "Fresh Worker darf keine historischen Notes fortschreiben" "$output_tool" validate worker-fresh "$invalid_fresh"

valid_reviewer="$tmp_root/valid-reviewer.txt"
cat > "$valid_reviewer" <<'EOF'
RECOMMENDATION=neither
REASON_CODE=NO_GREEN_CANDIDATE
REPORTS=report-a,report-b
EOF
expect_success "gueltiger Reviewer-Output" "$output_tool" validate reviewer "$valid_reviewer"

valid_finalizer="$tmp_root/valid-finalizer.txt"
cat > "$valid_finalizer" <<'EOF'
OUTCOME=blocked
BEST_GREEN_REF=-
OPEN_ERROR=Pruefung rot
HUMAN_DECISION=Umfang klaeren
EOF
expect_success "gueltiger Finalizer-Output" "$output_tool" validate finalizer "$valid_finalizer"

for role in $roles; do
  schema=$("$output_tool" schema "$role") || { bad "Schema fuer $role fehlt"; continue; }
  fields=$("$output_tool" fields "$role") || { bad "Feldliste fuer $role fehlt"; continue; }
  printf '%s' "$schema" | perl -MJSON::PP -e '
    local $/; my $s = JSON::PP->new->decode(<STDIN>);
    my @fields = split / /, $ARGV[0];
    exit 1 unless $s->{type} eq "object" && !$s->{additionalProperties};
    exit 1 unless join(" ", @{ $s->{required} }) eq join(" ", @fields);
    for (@fields) { exit 1 unless ref $s->{properties}{$_} eq "HASH" && $s->{properties}{$_}{type} eq "string" }
    exit 0
  ' "$fields" && ok || bad "Schema fuer $role ist gueltiges JSON mit exakt den Vertragsfeldern"
done

raw="$fixture/.agent-runs/large/raw.txt"
summary="$fixture/.agent-runs/large/summary.md"
mkdir -p "$(dirname "$raw")"
printf '%s\n\n' 'password=should-not-leak' >> "$raw"
for index in $(seq 1 100); do printf 'Block %s mit Details.\n\n' "$index" >> "$raw"; done
raw_hash=$(shasum -a 256 "$raw" | awk '{print $1}')
expect_success "grosser Output wird lokal zusammengefasst" "$output_tool" summarize worker-task "$raw" "$summary" 900
[ "$(wc -c < "$summary" | tr -d ' ')" -le 900 ] && grep -Fq '[GEKUERZT:' "$summary" && ok || bad "Output-Zusammenfassung haelt Limit und markiert Kuerzung"
! grep -Fq 'should-not-leak' "$summary" && [ "$(shasum -a 256 "$raw" | awk '{print $1}')" = "$raw_hash" ] && ok || bad "Zusammenfassung redigiert und bewahrt Rohoutput"
expect_failure "Zusammenfassung kann .agent-runs nicht per Traversal verlassen" "$output_tool" summarize worker-task "$raw" "$fixture/.agent-runs/../escaped.md" 900
outside_raw="$fixture/src/raw.txt"
cp "$raw" "$outside_raw"
expect_failure "Rohoutput ausserhalb des Laufordners wird abgewiesen" "$output_tool" summarize worker-task "$outside_raw" "$fixture/.agent-runs/large/outside-summary.md" 900
ln -s "$raw" "$fixture/.agent-runs/large/raw-link.txt"
expect_failure "Symlink-Rohoutput wird abgewiesen" "$output_tool" summarize worker-task "$fixture/.agent-runs/large/raw-link.txt" "$fixture/.agent-runs/large/link-summary.md" 900

finish_suite
