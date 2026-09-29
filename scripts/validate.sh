#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: %s path/to/Plugin.vst3\n' "$0" >&2
    exit 2
fi

plugin_path="$1"
case "$plugin_path" in
    /*) ;;
    *) plugin_path="$(cd "$(dirname "$plugin_path")" && pwd)/$(basename "$plugin_path")" ;;
esac
sdk_dir="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"
validator="${VST3_VALIDATOR:-}"
output_root="${VALIDATOR_OUTPUT_DIR:-${TMPDIR:-/tmp}/zig-vst3-validator}"

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

timestamp="$(date +%Y%m%d-%H%M%S)"
plugin_name="$(basename "$plugin_path" .vst3)"
output_dir="$output_root/$plugin_name-$timestamp-$$"
stdout_path="$output_dir/validator.stdout"
stderr_path="$output_dir/validator.stderr"
marker_path="$output_dir/run-started.marker"
mkdir -p "$output_dir"
: > "$marker_path"
printf 'validator artifacts: %s\n' "$output_dir" >&2

bundle_hash() {
    if command -v shasum >/dev/null 2>&1; then
        find "$plugin_path" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort | shasum -a 256 | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        find "$plugin_path" -type f -exec sha256sum {} \; | LC_ALL=C sort | sha256sum | awk '{print $1}'
    else
        printf 'unavailable'
    fi
}

{
    printf '0=%s\n' "$validator"
    printf '1=%s\n' "$plugin_path"
} > "$output_dir/command-arguments.txt"
{
    printf 'started_at=%s\n' "$timestamp"
    printf 'phase=steinberg-validator\n'
    printf 'iteration=%s\n' "${VALIDATOR_ITERATION:-1}"
    printf 'plugin_path=%s\n' "$plugin_path"
    printf 'validator_path=%s\n' "$validator"
    printf 'bundle_hash=%s\n' "$(bundle_hash)"
    printf 'git_commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'system=%s\n' "$(uname -a)"
} > "$output_dir/run-metadata.txt"

set +e
"$validator" "$plugin_path" > "$stdout_path" 2> "$stderr_path"
status=$?
set -e
cat "$stdout_path"
cat "$stderr_path" >&2

if [ "$status" -eq 0 ]; then
    classification=succeeded
elif [ "$status" -ge 128 ]; then
    classification=signaled
else
    classification=failed
fi

if [ "$status" -ne 0 ] && [ "$(uname -s)" = Darwin ]; then
    reports="$HOME/Library/Logs/DiagnosticReports"
    if [ -d "$reports" ]; then
        mkdir -p "$output_dir/crash-reports"
        find "$reports" -type f -newer "$marker_path" \
            \( -name 'validator*.crash' -o -name 'validator*.ips' \) \
            -exec cp {} "$output_dir/crash-reports/" \; 2>/dev/null || true
    fi
fi

{
    printf 'classification=%s\n' "$classification"
    printf 'status=%s\n' "$status"
    if [ "$status" -ge 128 ]; then printf 'signal=%s\n' "$((status - 128))"; fi
    printf 'phase=steinberg-validator\n'
    printf 'iteration=%s\n' "${VALIDATOR_ITERATION:-1}"
    printf 'plugin=%s\n' "$plugin_path"
    printf 'bundle_hash=%s\n' "$(bundle_hash)"
    printf 'command_arguments=%s\n' "$output_dir/command-arguments.txt"
    printf 'stdout=%s\n' "$stdout_path"
    printf 'stderr=%s\n' "$stderr_path"
} > "$output_dir/runner-status.txt"
exit "$status"
