#!/usr/bin/env sh
set -eu

sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
out_dir=".zig-cache/test-plug-provider-abi"

if [ ! -d "$sdk_dir/pluginterfaces" ]; then
    printf 'SDK checkout not found at %s. Run scripts/fetch_sdk.sh first.\n' "$sdk_dir" >&2
    exit 1
fi

mkdir -p "$out_dir"

c++ -std=c++17 -I"$sdk_dir" tests/abi/test_plug_provider_layout.cpp -o "$out_dir/test_plug_provider_layout_cpp"
"$out_dir/test_plug_provider_layout_cpp" > "$out_dir/cpp.txt"
zig run --dep vst3-zig -Mroot=tools/test_plug_provider_layout.zig -Mvst3-zig=vst3-zig/src/root.zig > "$out_dir/zig.txt"

diff -u "$out_dir/cpp.txt" "$out_dir/zig.txt"
