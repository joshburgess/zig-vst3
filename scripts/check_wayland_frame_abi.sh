#!/usr/bin/env sh
set -eu

sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
out_dir="${ZIG_LOCAL_CACHE_DIR:-.zig-cache}/wayland-frame-abi"

if [ ! -d "$sdk_dir/pluginterfaces" ]; then
    printf 'SDK checkout not found at %s. Run scripts/fetch_sdk.sh first.\n' "$sdk_dir" >&2
    exit 1
fi

mkdir -p "$out_dir"

c++ -std=c++17 -I"$sdk_dir" tests/abi/wayland_frame_layout.cpp -o "$out_dir/wayland_frame_layout_cpp"
"$out_dir/wayland_frame_layout_cpp" > "$out_dir/cpp.txt"
"${ZIG:-zig}" run --dep zig-vst3 -Mroot=tools/wayland_frame_layout.zig -Mzig-vst3=zig-vst3/src/root.zig > "$out_dir/zig.txt"

diff -u "$out_dir/cpp.txt" "$out_dir/zig.txt"
