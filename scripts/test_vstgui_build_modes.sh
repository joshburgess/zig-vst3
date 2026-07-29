#!/usr/bin/env sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vstgui-build-mode-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fake_bin="$temporary/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/cmake" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$VSTGUI_MODE_TEST_CMAKE_LOG"
exit 0
EOF
chmod +x "$fake_bin/cmake"

cat > "$fake_bin/zig" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$VSTGUI_MODE_TEST_ZIG_LOG"
exit 0
EOF
chmod +x "$fake_bin/zig"

build_cmake_log="$temporary/build-cmake.log"
build_zig_log="$temporary/build-zig.log"
PATH="$fake_bin:$PATH" \
VSTGUI_MODE_TEST_CMAKE_LOG="$build_cmake_log" \
VSTGUI_MODE_TEST_ZIG_LOG="$build_zig_log" \
  "$root/scripts/build_vstgui.sh" build

test "$(wc -l < "$build_cmake_log" | tr -d ' ')" = 2
grep -q -- '-DZIG_VSTGUI_RUN_VISUAL_TESTS=ON' "$build_cmake_log"
grep -q -- '--target zig_vstgui_adapter --parallel' "$build_cmake_log"
if grep -Eq 'tests_run|visual_tests|accessibility_tests' "$build_cmake_log"; then
  printf 'compile-only VSTGUI mode invoked a validation target\n' >&2
  exit 1
fi
test ! -e "$build_zig_log"

test_cmake_log="$temporary/test-cmake.log"
test_zig_log="$temporary/test-zig.log"
PATH="$fake_bin:$PATH" \
VSTGUI_RUN_VISUAL_TESTS=OFF \
VSTGUI_MODE_TEST_CMAKE_LOG="$test_cmake_log" \
VSTGUI_MODE_TEST_ZIG_LOG="$test_zig_log" \
  "$root/scripts/build_vstgui.sh" test

test "$(wc -l < "$test_cmake_log" | tr -d ' ')" = 3
grep -q -- '-DZIG_VSTGUI_RUN_VISUAL_TESTS=OFF' "$test_cmake_log"
grep -q -- '--target zig_vstgui_adapter --parallel' "$test_cmake_log"
grep -q -- 'zig_vstgui_adapter_tests_run zig_vstgui_accessibility_tests_run zig_vstgui_visual_tests_run' "$test_cmake_log"
test "$(wc -l < "$test_zig_log" | tr -d ' ')" = 1
grep -q -- '-target x86_64-windows-gnu' "$test_zig_log"

set +e
PATH="$fake_bin:$PATH" "$root/scripts/build_vstgui.sh" invalid > /dev/null 2> "$temporary/invalid.stderr"
invalid_status=$?
set -e
test "$invalid_status" = 2
grep -q 'usage:' "$temporary/invalid.stderr"

printf 'VSTGUI build mode tests passed\n'
