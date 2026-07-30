#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/gui-adapters/vstgui"
build_dir="$root/.vst3-sdk/vstgui-adapter-build"
mode="${1:-build}"

case "$mode" in
  build|test) ;;
  *)
    printf 'usage: %s [build|test]\n' "$0" >&2
    exit 2
    ;;
esac

cmake -S "$source_dir" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VSTGUI_VISUAL_TEST_ARGS="${VSTGUI_VISUAL_TEST_ARGS:-}" \
  -DZIG_VSTGUI_RUN_VISUAL_TESTS="${VSTGUI_RUN_VISUAL_TESTS:-ON}" \
  -DVSTGUI_STANDALONE=OFF \
  -DVSTGUI_STANDALONE_EXAMPLES=OFF \
  -DVSTGUI_TOOLS=OFF \
  -DVSTGUI_DISABLE_UNITTESTS=ON \
  -DVSTGUI_UISCRIPTING=OFF \
  -DVSTGUI_ENABLE_OPENGL_SUPPORT=OFF \
  -DVSTGUI_ENABLE_XMLPARSER=OFF
cmake --build "$build_dir" --target zig_vstgui_adapter --parallel

if [ "$mode" = test ]; then
  cmake --build "$build_dir" --target zig_vstgui_adapter_tests_run zig_vstgui_accessibility_tests_run zig_vstgui_visual_tests_run --parallel

  env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache \
      ZIG_LOCAL_CACHE_DIR=/tmp/zig-vst3-local-cache \
      zig c++ -target x86_64-windows-gnu -std=c++17 -Wno-nullability-completeness \
      -DVSTGUI_ENABLE_XML_PARSER=0 \
      -DVSTGUI_ENABLE_DEPRECATED_METHODS=1 \
      -DVSTGUI_OPENGL_SUPPORT=0 \
      -I"$root/.vst3-sdk/vst3sdk/vstgui4" \
      -I"$root/.vst3-sdk/vst3sdk" \
      -c "$root/gui-adapters/vstgui/zig_vstgui_accessibility_windows.cpp" \
      -o /tmp/zig_vstgui_accessibility_windows.o

  env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache \
      ZIG_LOCAL_CACHE_DIR=/tmp/zig-vst3-local-cache \
      zig c++ -target x86_64-linux-gnu -std=c++17 \
      -I"$root/gui-adapters/vstgui" \
      -c "$root/gui-adapters/vstgui/zig_vstgui_accessibility_atspi.cpp" \
      -o /tmp/zig_vstgui_accessibility_atspi_linux.o

  env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache \
      ZIG_LOCAL_CACHE_DIR=/tmp/zig-vst3-local-cache \
      zig c++ -target aarch64-linux-gnu -std=c++17 \
      -I"$root/gui-adapters/vstgui" \
      -c "$root/gui-adapters/vstgui/zig_vstgui_accessibility_atspi.cpp" \
      -o /tmp/zig_vstgui_accessibility_atspi_aarch64_linux.o

  env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache \
      ZIG_LOCAL_CACHE_DIR=/tmp/zig-vst3-local-cache \
      zig c++ -target x86_64-windows-gnu -std=c++17 -Wno-nullability-completeness \
      -DVSTGUI_ENABLE_XML_PARSER=0 \
      -DVSTGUI_ENABLE_DEPRECATED_METHODS=1 \
      -DVSTGUI_OPENGL_SUPPORT=0 \
      -I"$root/.vst3-sdk/vst3sdk/vstgui4" \
      -I"$root/.vst3-sdk/vst3sdk" \
      -c "$root/gui-adapters/vstgui/zig_vstgui_editor.cpp" \
      -o /tmp/zig_vstgui_editor_windows.o
fi
