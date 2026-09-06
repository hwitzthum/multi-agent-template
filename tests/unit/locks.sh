#!/usr/bin/env bash
# Sperren: eine lebende Sperre hält, eine verwaiste wird übernommen.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"
. "$project_dir/scripts/agent/common.sh"

begin_suite locks
fixture_workspace

lock="$tmp_root/lock"
sleep 0 & dead_pid=$!; wait "$dead_pid"
mkdir "$lock" && printf '%s\n' "$dead_pid" > "$lock/pid"
expect_success "verwaiste Sperre mit toter PID wird uebernommen" agent_acquire_lock "$lock"
assert_eq "uebernommene Sperre traegt die eigene PID" "$$" "$(sed -n '1p' "$lock/pid")"
expect_failure "lebende Sperre bleibt bestehen" agent_acquire_lock "$lock"
agent_release_lock "$lock"
mkdir "$lock"
expect_failure "Sperre ohne PID-Datei gilt als gehalten" agent_acquire_lock "$lock"
rmdir "$lock"

finish_suite
