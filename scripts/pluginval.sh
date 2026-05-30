#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: %s path/to/Plugin.vst3\n' "$0" >&2
    exit 2
fi

plugin_path="$1"
pluginval="${PLUGINVAL:-}"
strictness="${PLUGINVAL_STRICTNESS:-5}"

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

if [ -n "${PLUGINVAL_ARGS:-}" ]; then
    # Intentionally split PLUGINVAL_ARGS so callers can pass pluginval CLI flags.
    # shellcheck disable=SC2086
    exec "$pluginval" --strictness-level "$strictness" $PLUGINVAL_ARGS "$plugin_path"
fi

exec "$pluginval" --strictness-level "$strictness" "$plugin_path"
