#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/gui-adapters/vstgui"
build_dir="$root/.vst3-sdk/vstgui-adapter-sanitizer-build"

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

targets="zig_vstgui_adapter_tests zig_vstgui_visual_tests"
if [ "$(uname -s)" = Darwin ]; then
  targets="$targets zig_vstgui_accessibility_macos_tests"
fi

cmake --build "$build_dir" --target $targets --parallel

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
