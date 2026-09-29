#!/usr/bin/env sh
set -eu

if [ "$(uname -s)" != Linux ]; then
  printf 'VSTGUI Debug ABI test requires Linux\n'
  exit 0
fi

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vstgui-debug-abi.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
build_dir="$temporary/build"

cmake -S "$root/gui-adapters/vstgui" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DVSTGUI_STANDALONE=OFF \
  -DVSTGUI_STANDALONE_EXAMPLES=OFF \
  -DVSTGUI_TOOLS=OFF \
  -DVSTGUI_DISABLE_UNITTESTS=ON \
  -DVSTGUI_UISCRIPTING=OFF \
  -DVSTGUI_ENABLE_OPENGL_SUPPORT=OFF \
  -DVSTGUI_ENABLE_XMLPARSER=OFF
cmake --build "$build_dir" \
  --target zig_vstgui_accessibility_atspi_bridge_tests \
  --parallel
"$build_dir/zig_vstgui_accessibility_atspi_bridge_tests"
