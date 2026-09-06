#!/usr/bin/env bash
# Der PreToolUse-Hook blockiert gefährliche Befehle und lässt harmlose durch.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"

guard="$project_dir/scripts/bash-guard.sh"

begin_suite bash-guard

expect_success "Bash-Guard lässt Statusprüfung zu" sh -c "printf '%s' '{\"command\":\"git status\"}' | '$guard'"
expect_failure "Bash-Guard blockiert Push" sh -c "printf '%s' '{\"command\":\"git push origin main\"}' | '$guard'"
expect_failure "Bash-Guard blockiert rekursives Löschen" sh -c "printf '%s' '{\"command\":\"rm -rf build\"}' | '$guard'"
expect_failure "Bash-Guard blockiert Push mit JSON-Tabulator" sh -c "printf '%s' '{\"command\":\"git\\\\tpush origin main\"}' | '$guard'"
expect_failure "Bash-Guard blockiert rekursives Löschen mit JSON-Tabulator" sh -c "printf '%s' '{\"command\":\"rm\\\\t-rf build\"}' | '$guard'"
expect_failure "Bash-Guard blockiert --no-verify" sh -c "printf '%s' '{\"command\":\"git commit --no-verify -m x\"}' | '$guard'"
expect_success "Bash-Guard lässt normalen Commit zu" sh -c "printf '%s' '{\"command\":\"git commit -m x\"}' | '$guard'"

# Verwerfen ungespeicherter Arbeit und Netzzugriff: die Gruppe, die README und
# ARCHITECTURE am lautesten bewerben und die bis hierher kein Test beruehrt hat.
# Der letzte Fall ist der zusammengesetzte Befehl — die Doku verspricht, dass
# eine Sperre auch versteckt hinter `&&` greift.
for blocked in 'git reset --hard HEAD' \
  'git clean -fd' \
  'git checkout -- src/app.txt' \
  'git restore src/app.txt' \
  'curl https://example.com' \
  'wget https://example.com' \
  'echo x && curl https://example.com'; do
  expect_failure "Bash-Guard blockiert $blocked" sh -c "printf '%s' '{\"command\":\"$blocked\"}' | '$guard'"
done
for allowed in 'git reset --soft HEAD~1' 'git checkout feature'; do
  expect_success "Bash-Guard lässt $allowed zu" sh -c "printf '%s' '{\"command\":\"$allowed\"}' | '$guard'"
done

# Zusätze im Headless-Lauf: Historie und Zweige führt der Orchestrator, nicht
# der Agent. Interaktiv bleiben dieselben Befehle erlaubt — dort steht ein
# Mensch daneben.
headless() { printf '%s' "{\"command\":\"$1\"}" | AGENT_HEADLESS=1 "$guard"; }
for blocked in 'git commit -m x' 'git merge main' 'git rebase main' 'git stash' \
  'git worktree add ../zweit' 'git branch -D feature' 'pip install requests' \
  'pip3 install requests' 'npm publish'; do
  expect_failure "Headless-Guard blockiert $blocked" headless "$blocked"
done
for allowed in 'git status' 'git add src/app.txt' 'git branch feature' 'npm install' \
  './scripts/verify.sh'; do
  expect_success "Headless-Guard lässt $allowed zu" headless "$allowed"
done
expect_success "Interaktiv bleibt git merge erlaubt" sh -c "printf '%s' '{\"command\":\"git merge main\"}' | '$guard'"

finish_suite
