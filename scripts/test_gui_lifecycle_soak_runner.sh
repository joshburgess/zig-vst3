#!/usr/bin/env sh
# shellcheck disable=SC2016
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-gui-lifecycle-runner-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fake_zig="$temporary/zig"
success_output="$temporary/success"
failure_output="$temporary/failure"
interrupt_output="$temporary/interrupt"
success_log="$temporary/success.log"
failure_log="$temporary/failure.log"
interrupt_log="$temporary/interrupt.log"
mkdir -p "$success_output" "$failure_output" "$interrupt_output"

printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'if [ "${1:-}" = version ]; then' \
  '  printf "0.0.0-test\n"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-}" != build ] || [ "$#" -ne 4 ]; then' \
  '  exit 64' \
  'fi' \
  'target="$2"' \
  'printf "%s\n" "$target" >> "$FAKE_ZIG_LOG"' \
  'if [ "${FAKE_ZIG_SIGNAL_PARENT:-0}" = 1 ]; then' \
  '  kill -TERM "$PPID"' \
  '  exit 0' \
  'fi' \
  'if [ "$target" = "${FAKE_ZIG_FAIL_TARGET:-}" ]; then' \
  '  exit "${FAKE_ZIG_FAIL_STATUS:-7}"' \
  'fi' \
  'exit 0' > "$fake_zig"
chmod +x "$fake_zig"

FAKE_ZIG_LOG="$success_log" \
GUI_LIFECYCLE_SOAK_REPETITIONS=2 \
GUI_LIFECYCLE_SOAK_OUTPUT_DIR="$success_output" \
ZIG="$fake_zig" \
  "$root/scripts/gui_lifecycle_soak.sh" > "$temporary/success.stdout"

success_run=$(find "$success_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$success_run"
grep -q '^classification=succeeded$' "$success_run/runner-status.txt"
grep -q '^repetitions=2$' "$success_run/runner-status.txt"
grep -q '^plugin_count=11$' "$success_run/runner-status.txt"
grep -q '^editor_lifecycles=264$' "$success_run/runner-status.txt"
test "$(find "$success_run" -name '*.status' -type f | wc -l | tr -d ' ')" = 22
test "$(find "$success_run" -name '*.command-arguments.txt' -type f | wc -l | tr -d ' ')" = 22
test "$(wc -l < "$success_log" | tr -d ' ')" = 22
grep -q '^test-gui-lifecycle-gain$' "$success_log"
grep -q '^test-gui-lifecycle-sample-player$' "$success_log"

set +e
FAKE_ZIG_LOG="$failure_log" \
FAKE_ZIG_FAIL_TARGET=test-gui-lifecycle-mode-gain \
FAKE_ZIG_FAIL_STATUS=9 \
GUI_LIFECYCLE_SOAK_REPETITIONS=2 \
GUI_LIFECYCLE_SOAK_OUTPUT_DIR="$failure_output" \
ZIG="$fake_zig" \
  "$root/scripts/gui_lifecycle_soak.sh" > "$temporary/failure.stdout" 2> "$temporary/failure.stderr"
failure_status=$?
set -e
test "$failure_status" = 9
failure_run=$(find "$failure_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$failure_run"
grep -q '^classification=failed$' "$failure_run/runner-status.txt"
grep -q '^status=9$' "$failure_run/runner-status.txt"
grep -q '^plugin=mode-gain$' "$failure_run/runner-status.txt"
grep -q '^iteration=1$' "$failure_run/runner-status.txt"
grep -q '^phase=headless-lifecycle-test$' "$failure_run/runner-status.txt"
test "$(find "$failure_run" -name '*.status' -type f | wc -l | tr -d ' ')" = 4
test "$(wc -l < "$failure_log" | tr -d ' ')" = 5
test ! -e "$failure_run/mode-gain-2.command-arguments.txt"

set +e
FAKE_ZIG_LOG="$interrupt_log" \
FAKE_ZIG_SIGNAL_PARENT=1 \
GUI_LIFECYCLE_SOAK_REPETITIONS=2 \
GUI_LIFECYCLE_SOAK_OUTPUT_DIR="$interrupt_output" \
ZIG="$fake_zig" \
  "$root/scripts/gui_lifecycle_soak.sh" > "$temporary/interrupt.stdout" 2> "$temporary/interrupt.stderr"
interrupt_status=$?
set -e
test "$interrupt_status" = 143
interrupt_run=$(find "$interrupt_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$interrupt_run"
grep -q '^classification=interrupted$' "$interrupt_run/runner-status.txt"
grep -q '^signal=TERM$' "$interrupt_run/runner-status.txt"
grep -q '^status=143$' "$interrupt_run/runner-status.txt"
grep -q '^plugin=gain$' "$interrupt_run/runner-status.txt"
grep -q '^iteration=1$' "$interrupt_run/runner-status.txt"
grep -q '^phase=headless-lifecycle-test$' "$interrupt_run/runner-status.txt"
test ! -e "$interrupt_run/gain-1.status"

set +e
GUI_LIFECYCLE_SOAK_REPETITIONS=0 \
ZIG="$fake_zig" \
  "$root/scripts/gui_lifecycle_soak.sh" > /dev/null 2> "$temporary/invalid.stderr"
invalid_status=$?
set -e
test "$invalid_status" = 2
grep -q 'must be a positive integer' "$temporary/invalid.stderr"

printf 'GUI lifecycle soak runner tests passed\n'
