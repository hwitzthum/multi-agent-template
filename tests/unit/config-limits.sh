#!/usr/bin/env bash
# Die statischen Grenzen in .agent/config.env werden geprüft, nicht ausgeführt.
set -uo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
project_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
. "$tests_dir/lib.sh"
. "$tests_dir/fixture.sh"

config="$project_dir/scripts/agent/config.sh"

begin_suite config-limits
fixture_workspace

new_project_fixture
expect_success "Standardkonfiguration" "$config" --check
expect_success "Konfigurationswert lesen" "$config" --get MAX_TASK_ATTEMPTS

new_project_fixture
fixture_config UNKNOWN_KEY 1
expect_failure "unbekannter Schlüssel" "$config" --check "$fixture/.agent/config.env"

new_project_fixture
fixture_config MAX_TASK_ATTEMPTS -1
expect_failure "negatives Limit" "$config" --check "$fixture/.agent/config.env"

new_project_fixture
fixture_config MAX_NO_PROGRESS '1;touch_x'
expect_failure "Shellsyntax" "$config" --check "$fixture/.agent/config.env"

finish_suite
