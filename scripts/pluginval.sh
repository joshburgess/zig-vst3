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
pluginval="${PLUGINVAL:-}"
strictness="${PLUGINVAL_STRICTNESS:-5}"
output_root="${PLUGINVAL_OUTPUT_DIR:-${TMPDIR:-/tmp}/zig-vst3-pluginval}"

if [ -z "$pluginval" ]; then
    for candidate in \
        pluginval \
        /Applications/pluginval.app/Contents/MacOS/pluginval \
        "$HOME/Applications/pluginval.app/Contents/MacOS/pluginval"
    do
        if command -v "$candidate" >/dev/null 2>&1; then
            pluginval="$candidate"
            break
        fi
        if [ -x "$candidate" ]; then
            pluginval="$candidate"
            break
        fi
    done
fi

if [ -z "$pluginval" ]; then
    printf 'pluginval not found. Install pluginval or set PLUGINVAL=/path/to/pluginval.\n' >&2
    exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
plugin_name="$(basename "$plugin_path" .vst3)"
output_dir="$output_root/$plugin_name-strictness-$strictness-$timestamp-$$"
mkdir -p "$output_dir"
printf 'pluginval artifacts: %s\n' "$output_dir" >&2

pluginval_app=""
case "$(uname -s):$pluginval" in
    Darwin:*.app/Contents/MacOS/*)
        pluginval_app="${pluginval%/Contents/MacOS/*}"
        ;;
esac

if [ -n "$pluginval_app" ]; then
    user_id="$(id -u)"
    set +e
    if [ -n "${PLUGINVAL_ARGS:-}" ]; then
        # Intentionally split PLUGINVAL_ARGS so callers can pass pluginval CLI flags.
        # shellcheck disable=SC2086
        /bin/launchctl asuser "$user_id" "$pluginval" --strictness-level "$strictness" --output-dir "$output_dir" $PLUGINVAL_ARGS "$plugin_path"
    else
        /bin/launchctl asuser "$user_id" "$pluginval" --strictness-level "$strictness" --output-dir "$output_dir" "$plugin_path"
    fi
    status=$?
    set -e
    exit "$status"
fi

set +e
if [ -n "${PLUGINVAL_ARGS:-}" ]; then
    # Intentionally split PLUGINVAL_ARGS so callers can pass pluginval CLI flags.
    # shellcheck disable=SC2086
    "$pluginval" --strictness-level "$strictness" --output-dir "$output_dir" $PLUGINVAL_ARGS "$plugin_path"
else
    "$pluginval" --strictness-level "$strictness" --output-dir "$output_dir" "$plugin_path"
fi
status=$?
set -e
exit "$status"
