#!/usr/bin/env sh
# shellcheck disable=SC2016
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-sanitizer-soak-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fake_build="$temporary/build"
success_output="$temporary/success"
failure_output="$temporary/failure"
interrupt_output="$temporary/interrupt"
mkdir -p "$fake_build" "$success_output" "$failure_output" "$interrupt_output"

write_success() {
  path="$1"
  printf '#!/bin/sh\nexit 0\n' > "$path"
  chmod +x "$path"
}

write_success "$fake_build/zig_vstgui_adapter_tests"
write_success "$fake_build/zig_vstgui_visual_tests"
write_success "$fake_build/zig_vstgui_accessibility_macos_tests"

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
  '  for executable in zig_vstgui_adapter_tests zig_vstgui_visual_tests zig_vstgui_accessibility_macos_tests; do' \
  '    printf "#!/bin/sh\\nexit 0\\n" > "$build_dir/$executable"' \
  '    chmod +x "$build_dir/$executable"' \
  '  done' \
  'fi' \
  'exit 0' > "$fake_tools/cmake"
chmod +x "$fake_tools/cmake"

direct_record="$temporary/direct-build-dir"
PATH="$fake_tools:$PATH" \
CMAKE_BUILD_DIR_RECORD="$direct_record" \
  "$root/scripts/test_vstgui_sanitizers.sh" > "$temporary/direct.stdout"
direct_build=$(sed -n '1p' "$direct_record")
test -n "$direct_build"
test ! -e "$direct_build"

fake_project="$temporary/project"
mkdir -p "$fake_project/scripts" "$fake_project/gui-adapters/vstgui"
cp "$root/scripts/vstgui_sanitizer_soak.sh" "$fake_project/scripts/"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'build_dir="${VSTGUI_SANITIZER_BUILD_DIR:?}"' \
  'printf "%s\\n" "$build_dir" > "$BUILD_DIR_RECORD"' \
  'mkdir -p "$build_dir"' \
  'if [ "${BUILD_INTERRUPT_PARENT:-0}" = 1 ]; then kill -TERM "$PPID"; exit 0; fi' \
  'for executable in zig_vstgui_adapter_tests zig_vstgui_visual_tests zig_vstgui_accessibility_macos_tests; do' \
  '  printf "#!/bin/sh\\nexit 0\\n" > "$build_dir/$executable"' \
  '  chmod +x "$build_dir/$executable"' \
  'done' > "$fake_project/scripts/test_vstgui_sanitizers.sh"
chmod +x "$fake_project/scripts/test_vstgui_sanitizers.sh"
soak_record="$temporary/soak-build-dir"
soak_output="$temporary/owned-soak"
BUILD_DIR_RECORD="$soak_record" \
VSTGUI_SANITIZER_SOAK_REPETITIONS=1 \
VSTGUI_SANITIZER_SOAK_OUTPUT_DIR="$soak_output" \
  "$fake_project/scripts/vstgui_sanitizer_soak.sh" > "$temporary/owned-soak.stdout"
soak_build=$(sed -n '1p' "$soak_record")
test -n "$soak_build"
test ! -e "$soak_build"

interrupted_soak_record="$temporary/interrupted-soak-build-dir"
set +e
BUILD_DIR_RECORD="$interrupted_soak_record" \
BUILD_INTERRUPT_PARENT=1 \
VSTGUI_SANITIZER_SOAK_REPETITIONS=1 \
VSTGUI_SANITIZER_SOAK_OUTPUT_DIR="$temporary/interrupted-owned-soak" \
  "$fake_project/scripts/vstgui_sanitizer_soak.sh" > "$temporary/interrupted-owned-soak.stdout" 2> "$temporary/interrupted-owned-soak.stderr"
interrupted_soak_status=$?
set -e
test "$interrupted_soak_status" = 143
interrupted_soak_build=$(sed -n '1p' "$interrupted_soak_record")
test -n "$interrupted_soak_build"
test ! -e "$interrupted_soak_build"

VSTGUI_SANITIZER_SOAK_REPETITIONS=2 \
VSTGUI_SANITIZER_SOAK_OUTPUT_DIR="$success_output" \
VSTGUI_SANITIZER_SOAK_BUILD_DIR="$fake_build" \
VSTGUI_SANITIZER_SOAK_SKIP_BUILD=1 \
  "$root/scripts/vstgui_sanitizer_soak.sh" > "$temporary/success.stdout"

success_run=$(find "$success_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$success_run"
grep -q '^classification=succeeded$' "$success_run/runner-status.txt"
grep -q '^repetitions=2$' "$success_run/runner-status.txt"
expected_runs=4
if [ "$(uname -s)" = Darwin ]; then expected_runs=6; fi
grep -q "^process_runs=$expected_runs$" "$success_run/runner-status.txt"
test "$(find "$success_run" -name '*.status' -type f | wc -l | tr -d ' ')" = "$expected_runs"

printf '#!/bin/sh\nexit 7\n' > "$fake_build/zig_vstgui_adapter_tests"
chmod +x "$fake_build/zig_vstgui_adapter_tests"
set +e
VSTGUI_SANITIZER_SOAK_REPETITIONS=2 \
VSTGUI_SANITIZER_SOAK_OUTPUT_DIR="$failure_output" \
VSTGUI_SANITIZER_SOAK_BUILD_DIR="$fake_build" \
VSTGUI_SANITIZER_SOAK_SKIP_BUILD=1 \
  "$root/scripts/vstgui_sanitizer_soak.sh" > "$temporary/failure.stdout" 2> "$temporary/failure.stderr"
failure_status=$?
set -e
test "$failure_status" = 7
failure_run=$(find "$failure_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$failure_run"
grep -q '^classification=failed$' "$failure_run/runner-status.txt"
grep -q '^status=7$' "$failure_run/runner-status.txt"
grep -q '^iteration=1$' "$failure_run/runner-status.txt"
grep -q '^phase=adapter$' "$failure_run/runner-status.txt"

printf '#!/bin/sh\nkill -TERM "$PPID"\nexit 0\n' > "$fake_build/zig_vstgui_adapter_tests"
chmod +x "$fake_build/zig_vstgui_adapter_tests"
set +e
VSTGUI_SANITIZER_SOAK_REPETITIONS=2 \
VSTGUI_SANITIZER_SOAK_OUTPUT_DIR="$interrupt_output" \
VSTGUI_SANITIZER_SOAK_BUILD_DIR="$fake_build" \
VSTGUI_SANITIZER_SOAK_SKIP_BUILD=1 \
  "$root/scripts/vstgui_sanitizer_soak.sh" > "$temporary/interrupt.stdout" 2> "$temporary/interrupt.stderr"
interrupt_status=$?
set -e
test "$interrupt_status" = 143
interrupt_run=$(find "$interrupt_output" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
test -n "$interrupt_run"
grep -q '^classification=interrupted$' "$interrupt_run/runner-status.txt"
grep -q '^signal=TERM$' "$interrupt_run/runner-status.txt"
grep -q '^status=143$' "$interrupt_run/runner-status.txt"
grep -q '^iteration=1$' "$interrupt_run/runner-status.txt"
grep -q '^phase=adapter$' "$interrupt_run/runner-status.txt"
test ! -e "$interrupt_run/1-adapter.status"

set +e
VSTGUI_SANITIZER_SOAK_REPETITIONS=0 "$root/scripts/vstgui_sanitizer_soak.sh" > /dev/null 2> "$temporary/invalid.stderr"
invalid_status=$?
set -e
test "$invalid_status" = 2
grep -q 'must be a positive integer' "$temporary/invalid.stderr"

printf 'VSTGUI sanitizer soak runner tests passed\n'
