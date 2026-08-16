#!/usr/bin/env sh
# shellcheck disable=SC2016
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-thread-sanitizer-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fake_build="$temporary/build"
success_output="$temporary/success"
failure_output="$temporary/failure"
interrupt_output="$temporary/interrupt"
write_failure_output="$temporary/write-failure"
mkdir -p "$fake_build" "$success_output" "$failure_output" "$interrupt_output" "$write_failure_output"

fake_tools="$temporary/tools"
mkdir -p "$fake_tools"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'build_dir=""' \
  'previous=""' \
  'for argument in "$@"; do' \
  '  if [ "$previous" = -B ]; then build_dir="$argument"; break; fi' \
  '  previous="$argument"' \
  'done' \
  'if [ -n "$build_dir" ]; then' \
  '  printf "%s\\n" "$build_dir" > "$CMAKE_BUILD_DIR_RECORD"' \
  '  mkdir -p "$build_dir"' \
  '  if [ "${CMAKE_INTERRUPT_PARENT:-0}" = 1 ]; then kill -TERM "$PPID"; exit 0; fi' \
  '  printf "#!/bin/sh\\nexit 0\\n" > "$build_dir/zig_vstgui_adapter_tests"' \
  '  chmod +x "$build_dir/zig_vstgui_adapter_tests"' \
  'fi' \
  'exit 0' > "$fake_tools/cmake"
chmod +x "$fake_tools/cmake"

owned_output="$temporary/owned"
owned_record="$temporary/owned-build-dir"
PATH="$fake_tools:$PATH" \
CMAKE_BUILD_DIR_RECORD="$owned_record" \
VSTGUI_THREAD_SANITIZER_REPETITIONS=1 \
VSTGUI_THREAD_SANITIZER_OUTPUT_DIR="$owned_output" \
  "$root/scripts/test_vstgui_thread_sanitizer.sh" > "$temporary/owned.stdout"
owned_build=$(sed -n '1p' "$owned_record")
test -n "$owned_build"
test ! -e "$owned_build"

interrupted_build_record="$temporary/interrupted-build-dir"
set +e
PATH="$fake_tools:$PATH" \
CMAKE_BUILD_DIR_RECORD="$interrupted_build_record" \
CMAKE_INTERRUPT_PARENT=1 \
VSTGUI_THREAD_SANITIZER_REPETITIONS=1 \
VSTGUI_THREAD_SANITIZER_OUTPUT_DIR="$temporary/interrupted-build-output" \
  "$root/scripts/test_vstgui_thread_sanitizer.sh" > "$temporary/interrupted-build.stdout" 2> "$temporary/interrupted-build.stderr"
interrupted_build_status=$?
set -e
test "$interrupted_build_status" = 143
interrupted_build=$(sed -n '1p' "$interrupted_build_record")
test -n "$interrupted_build"
test ! -e "$interrupted_build"

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

printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'run=$(find "$VSTGUI_THREAD_SANITIZER_OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type d | sed -n "1p")' \
  'rm -rf "$run"' \
  'printf blocked > "$run"' \
  'exit 0' > "$fake_build/zig_vstgui_adapter_tests"
chmod +x "$fake_build/zig_vstgui_adapter_tests"
set +e
VSTGUI_THREAD_SANITIZER_REPETITIONS=1 \
VSTGUI_THREAD_SANITIZER_OUTPUT_DIR="$write_failure_output" \
VSTGUI_THREAD_SANITIZER_BUILD_DIR="$fake_build" \
VSTGUI_THREAD_SANITIZER_SKIP_BUILD=1 \
  "$root/scripts/test_vstgui_thread_sanitizer.sh" > "$temporary/write-failure.stdout" 2> "$temporary/write-failure.stderr"
write_failure_status=$?
set -e
test "$write_failure_status" != 0
grep -q 'failed to write VSTGUI thread sanitizer iteration status' "$temporary/write-failure.stderr"

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
