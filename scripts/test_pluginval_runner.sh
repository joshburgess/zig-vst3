#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$script_dir/pluginval_runner_lib.sh"

expect_result() {
    expected="$1"
    service="$2"
    actual="$(pluginval_service_result "$service")"
    if [ "$actual" != "$expected" ]; then
        printf 'expected %s, got %s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

[ "$(pluginval_timeout_attempts 1)" = "10" ]
[ "$(pluginval_timeout_attempts 180)" = "1800" ]
[ "$(pluginval_timeout_attempts 3600)" = "36000" ]
if pluginval_timeout_attempts 0 >/dev/null 2>&1; then exit 1; fi
if pluginval_timeout_attempts 3601 >/dev/null 2>&1; then exit 1; fi
if pluginval_timeout_attempts invalid >/dev/null 2>&1; then exit 1; fi

expect_result running 'active count = 1'
expect_result exit:0 'active count = 0
last exit code = 0'
expect_result exit:7 'active count = 0
last exit code = 7'
expect_result signal:6 'active count = 0
last terminating signal = Abort trap: 6'
expect_result signal:11 'active count = 0
last exit code = 0
last terminating signal = Segmentation fault: 11'
expect_result unknown 'active count = 0'

printf 'pluginval runner parsing tests passed\n'
