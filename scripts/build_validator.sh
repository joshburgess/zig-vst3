#!/usr/bin/env sh
set -eu

sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
build_dir="${VST3_SDK_BUILD_DIR:-$sdk_dir/build}"
config="${VST3_SDK_CONFIG:-Release}"

if [ ! -d "$sdk_dir/.git" ]; then
    printf 'SDK checkout not found at %s. Run scripts/fetch_sdk.sh first.\n' "$sdk_dir" >&2
    exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
    if [ -z "${CC:-}" ]; then
        cc_path="$(xcrun --find clang 2>/dev/null || true)"
        if [ -n "$cc_path" ]; then
            export CC="$cc_path"
        fi
    fi

    if [ -z "${CXX:-}" ]; then
        cxx_path="$(xcrun --find clang++ 2>/dev/null || true)"
        if [ -n "$cxx_path" ]; then
            export CXX="$cxx_path"
        fi
    fi

    if [ -z "${XCODE_VERSION:-}" ] && ! xcodebuild -version >/dev/null 2>&1; then
        # Steinberg's CMake requires this cache value even when Command Line Tools can build the validator
        clang_version="$("${CXX:-clang++}" --version 2>/dev/null | sed -n 's/^Apple clang version \([0-9][0-9.]*\).*/\1/p' | sed -n '1p')"
        if [ -n "$clang_version" ]; then
            export XCODE_VERSION="$clang_version"
        fi
    fi
fi

if [ -n "${XCODE_VERSION:-}" ]; then
    cmake -S "$sdk_dir" -B "$build_dir" \
        -DXCODE_VERSION="$XCODE_VERSION" \
        -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF \
        -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
        -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON
else
    cmake -S "$sdk_dir" -B "$build_dir" \
        -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF \
        -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
        -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON
fi

cmake --build "$build_dir" --config "$config" --target validator
