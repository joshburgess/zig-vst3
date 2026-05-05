#!/usr/bin/env sh
set -eu

sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
build_dir="${VST3_SDK_BUILD_DIR:-$sdk_dir/build}"
config="${VST3_SDK_CONFIG:-Release}"

if [ ! -d "$sdk_dir/.git" ]; then
    printf 'SDK checkout not found at %s. Run scripts/fetch_sdk.sh first.\n' "$sdk_dir" >&2
    exit 1
fi

cmake -S "$sdk_dir" -B "$build_dir" \
    -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF \
    -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
    -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON

cmake --build "$build_dir" --config "$config" --target validator
