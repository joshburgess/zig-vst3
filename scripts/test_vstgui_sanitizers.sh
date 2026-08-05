#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/gui-adapters/vstgui"
temporary_build=""

cleanup_build() {
  if [ -n "$temporary_build" ]; then
    rm -rf -- "$temporary_build"
  fi
}
trap cleanup_build EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "${VSTGUI_SANITIZER_BUILD_DIR:-}" ]; then
  build_dir="$VSTGUI_SANITIZER_BUILD_DIR"
else
  temporary_build=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vstgui-sanitizer-build.XXXXXX")
  build_dir="$temporary_build/build"
fi

cmake -S "$source_dir" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_C_FLAGS_RELEASE=-O2 -g -DNDEBUG" \
  "-DCMAKE_CXX_FLAGS_RELEASE=-O2 -g -DNDEBUG" \
  "-DCMAKE_OBJCXX_FLAGS_RELEASE=-O2 -g -DNDEBUG" \
  -DZIG_VSTGUI_ENABLE_SANITIZERS=ON \
  -DVSTGUI_STANDALONE=OFF \
  -DVSTGUI_STANDALONE_EXAMPLES=OFF \
  -DVSTGUI_TOOLS=OFF \
  -DVSTGUI_DISABLE_UNITTESTS=ON \
  -DVSTGUI_UISCRIPTING=OFF \
  -DVSTGUI_ENABLE_OPENGL_SUPPORT=OFF \
  -DVSTGUI_ENABLE_XMLPARSER=OFF

if [ "$(uname -s)" = Darwin ]; then
  cmake --build "$build_dir" --target \
    zig_vstgui_adapter_tests \
    zig_vstgui_visual_tests \
    zig_vstgui_accessibility_macos_tests \
    --parallel
else
  cmake --build "$build_dir" --target \
    zig_vstgui_adapter_tests \
    zig_vstgui_visual_tests \
    --parallel
fi

if [ "${ZIG_VSTGUI_SANITIZER_BUILD_ONLY:-0}" = 1 ]; then
  exit 0
fi

if [ "$(uname -s)" = Darwin ]; then
  export ASAN_OPTIONS="halt_on_error=1:strict_string_checks=1"
else
  export ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:strict_string_checks=1"
fi
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"

"$build_dir/zig_vstgui_adapter_tests"
if [ "$(uname -s)" = Darwin ]; then
  "$build_dir/zig_vstgui_accessibility_macos_tests"
fi
"$build_dir/zig_vstgui_visual_tests" \
  "$source_dir/testdata/visual" \
  "$build_dir/visual-regression" \
  --skip-performance
