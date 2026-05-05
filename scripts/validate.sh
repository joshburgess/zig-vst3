#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: %s path/to/Plugin.vst3\n' "$0" >&2
    exit 2
fi

plugin_path="$1"
sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
validator="${VST3_VALIDATOR:-}"

if [ -z "$validator" ]; then
    for candidate in \
        "$sdk_dir/build/bin/validator" \
        "$sdk_dir/build/bin/Release/validator" \
        "$sdk_dir/build/bin/Debug/validator" \
        "$sdk_dir/build/bin/Release/validator.exe" \
        "$sdk_dir/build/bin/Debug/validator.exe"
    do
        if [ -x "$candidate" ]; then
            validator="$candidate"
            break
        fi
    done
fi

if [ -z "$validator" ] || [ ! -x "$validator" ]; then
    printf 'validator not found. Build the SDK validator or set VST3_VALIDATOR.\n' >&2
    printf 'expected SDK checkout: %s\n' "$sdk_dir" >&2
    exit 1
fi

exec "$validator" "$plugin_path"
