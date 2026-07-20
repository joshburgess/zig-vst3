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

tmp_root="${TMPDIR:-/tmp}/zig-vst3-pluginval-runner-test-$$"
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
mkdir -p "$tmp_root/fake.vst3" "$tmp_root/success" "$tmp_root/failure"
printf 'fixture\n' > "$tmp_root/fake.vst3/module.bin"
fake_pluginval="$tmp_root/fake-pluginval"
{
    printf '#!/bin/sh\n'
    printf 'printf "fake pluginval stdout\\n"\n'
    printf 'printf "fake pluginval stderr\\n" >&2\n'
    printf 'exit "${FAKE_PLUGINVAL_STATUS:-0}"\n'
} > "$fake_pluginval"
chmod +x "$fake_pluginval"

PLUGINVAL="$fake_pluginval" PLUGINVAL_OUTPUT_DIR="$tmp_root/success" \
    "$script_dir/pluginval.sh" "$tmp_root/fake.vst3" >/dev/null 2>/dev/null
success_dir="$(find "$tmp_root/success" -mindepth 1 -maxdepth 1 -type d | head -1)"
grep -q '^classification=succeeded$' "$success_dir/runner-status.txt"
grep -q '^phase=pluginval$' "$success_dir/runner-status.txt"
grep -q '^iteration=1$' "$success_dir/runner-status.txt"
grep -q '^bundle_hash=' "$success_dir/runner-status.txt"
grep -q '^0=' "$success_dir/command-arguments.txt"
grep -q 'fake pluginval stdout' "$success_dir/pluginval.stdout"
grep -q 'fake pluginval stderr' "$success_dir/pluginval.stderr"

set +e
FAKE_PLUGINVAL_STATUS=143 PLUGINVAL="$fake_pluginval" PLUGINVAL_OUTPUT_DIR="$tmp_root/failure" \
    "$script_dir/pluginval.sh" "$tmp_root/fake.vst3" >/dev/null 2>/dev/null
failure_status=$?
set -e
[ "$failure_status" -eq 143 ]
failure_dir="$(find "$tmp_root/failure" -mindepth 1 -maxdepth 1 -type d | head -1)"
grep -q '^classification=signaled$' "$failure_dir/runner-status.txt"
grep -q '^status=143$' "$failure_dir/runner-status.txt"
grep -q '^signal=15$' "$failure_dir/runner-status.txt"

printf 'pluginval runner parsing tests passed\n'
