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

finish_suite
