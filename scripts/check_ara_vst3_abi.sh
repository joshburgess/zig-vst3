#!/usr/bin/env sh
set -eu

sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
ara_dir="${ARA_API_DIR:-vendor/ARA_API}"
out_dir=".zig-cache/ara-vst3-abi"

if [ ! -d "$sdk_dir/pluginterfaces" ]; then
    printf 'SDK checkout not found at %s. Run scripts/fetch_sdk.sh first.\n' "$sdk_dir" >&2
    exit 1
fi
if [ ! -f "$ara_dir/ARAInterface.h" ] ||
    [ ! -f "$ara_dir/ARAVST3.h" ]; then
    printf 'ARA API headers not found at %s.\n' "$ara_dir" >&2
    exit 1
fi

mkdir -p "$out_dir"
repo_root=$(pwd)

c++ -std=c++17 \
    -I"$sdk_dir" \
    -I"$ara_dir" \
    tests/abi/ara_vst3_layout.cpp \
    -o "$out_dir/ara_vst3_layout_cpp"
"$out_dir/ara_vst3_layout_cpp" > "$out_dir/cpp.txt"

ZIG_GLOBAL_CACHE_DIR="$repo_root/.zig-global-cache" \
ZIG_LOCAL_CACHE_DIR="$repo_root/.zig-cache" \
"${ZIG:-zig}" translate-c \
    -I"$ara_dir" \
    "$ara_dir/ARAInterface.h" \
    > "$out_dir/ara_raw.zig"

ara_bindings="$out_dir/ara_raw.zig"
case "$(uname -m)" in
    x86_64|amd64|i386|i686)
        ara_bindings="$out_dir/ara_raw_packed.zig"
        ZIG_GLOBAL_CACHE_DIR="$repo_root/.zig-global-cache" \
        ZIG_LOCAL_CACHE_DIR="$repo_root/.zig-cache" \
        "${ZIG:-zig}" run tools/pack_ara_bindings.zig -- \
            "$out_dir/ara_raw.zig" \
            "$ara_bindings"
        ;;
esac

ZIG_GLOBAL_CACHE_DIR="$repo_root/.zig-global-cache" \
ZIG_LOCAL_CACHE_DIR="$repo_root/.zig-cache" \
"${ZIG:-zig}" run \
    --dep zig-vst3 \
    --dep zig-vst3-ara \
    -Mroot=tools/ara_vst3_layout.zig \
    --dep zig-vst3-ara \
    -Mzig-vst3=zig-vst3/src/root.zig \
    --dep ara-raw \
    -Mzig-vst3-ara=zig-vst3/src/ara_api.zig \
    -Mara-raw="$ara_bindings" \
    > "$out_dir/zig.txt"

diff -u "$out_dir/cpp.txt" "$out_dir/zig.txt"
