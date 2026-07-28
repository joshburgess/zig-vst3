#!/usr/bin/env sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-thread-sanitizer-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fake_build="$temporary/build"
success_output="$temporary/success"
failure_output="$temporary/failure"
interrupt_output="$temporary/interrupt"
mkdir -p "$fake_build" "$success_output" "$failure_output" "$interrupt_output"

printf '#!/bin/sh\nexit 0\n' > "$fake_build/zig_vstgui_adapter_tests"
chmod +x "$fake_build/zig_vstgui_adapter_tests"

VSTGUI_THREAD_SANITIZER_REPETITIONS=3 \
VSTGUI_THREAD_SANITIZER_OUTPUT_DIR="$success_output" \
VSTGUI_THREAD_SANITIZER_BUILD_DIR="$fake_build" \
VSTGUI_THREAD_SANITIZER_SKIP_BUILD=1 \
  "$root/scripts/test_vstgui_thread_sanitizer.sh" > "$temporary/success.stdout"

success_run=$(find "$success_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$success_run"
grep -q '^classification=succeeded$' "$success_run/runner-status.txt"
grep -q '^repetitions=3$' "$success_run/runner-status.txt"
test "$(find "$success_run" -name '*.status' -type f | wc -l | tr -d ' ')" = 3
test "$(find "$success_run" -name '*.command-arguments.txt' -type f | wc -l | tr -d ' ')" = 3

printf '#!/bin/sh\nexit 9\n' > "$fake_build/zig_vstgui_adapter_tests"
chmod +x "$fake_build/zig_vstgui_adapter_tests"
set +e
VSTGUI_THREAD_SANITIZER_REPETITIONS=3 \
VSTGUI_THREAD_SANITIZER_OUTPUT_DIR="$failure_output" \
VSTGUI_THREAD_SANITIZER_BUILD_DIR="$fake_build" \
VSTGUI_THREAD_SANITIZER_SKIP_BUILD=1 \
  "$root/scripts/test_vstgui_thread_sanitizer.sh" > "$temporary/failure.stdout" 2> "$temporary/failure.stderr"
failure_status=$?
set -e
test "$failure_status" = 9
failure_run=$(find "$failure_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$failure_run"
grep -q '^classification=failed$' "$failure_run/runner-status.txt"
grep -q '^status=9$' "$failure_run/runner-status.txt"
grep -q '^iteration=1$' "$failure_run/runner-status.txt"
grep -q '^phase=adapter-thread-safety$' "$failure_run/runner-status.txt"
test ! -e "$failure_run/2.status"

printf '#!/bin/sh\nkill -TERM "$PPID"\nexit 0\n' > "$fake_build/zig_vstgui_adapter_tests"
chmod +x "$fake_build/zig_vstgui_adapter_tests"
set +e
VSTGUI_THREAD_SANITIZER_REPETITIONS=3 \
VSTGUI_THREAD_SANITIZER_OUTPUT_DIR="$interrupt_output" \
VSTGUI_THREAD_SANITIZER_BUILD_DIR="$fake_build" \
VSTGUI_THREAD_SANITIZER_SKIP_BUILD=1 \
  "$root/scripts/test_vstgui_thread_sanitizer.sh" > "$temporary/interrupt.stdout" 2> "$temporary/interrupt.stderr"
interrupt_status=$?
set -e
test "$interrupt_status" = 143
interrupt_run=$(find "$interrupt_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$interrupt_run"
grep -q '^classification=interrupted$' "$interrupt_run/runner-status.txt"
grep -q '^signal=TERM$' "$interrupt_run/runner-status.txt"
grep -q '^status=143$' "$interrupt_run/runner-status.txt"
grep -q '^iteration=1$' "$interrupt_run/runner-status.txt"
grep -q '^phase=adapter-thread-safety$' "$interrupt_run/runner-status.txt"
test ! -e "$interrupt_run/1.status"

set +e
VSTGUI_THREAD_SANITIZER_REPETITIONS=0 "$root/scripts/test_vstgui_thread_sanitizer.sh" > /dev/null 2> "$temporary/invalid.stderr"
invalid_status=$?
set -e
test "$invalid_status" = 2
grep -q 'must be a positive integer' "$temporary/invalid.stderr"

printf 'VSTGUI thread sanitizer runner tests passed\n'
