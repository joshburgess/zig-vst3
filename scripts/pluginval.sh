#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$script_dir/pluginval_runner_lib.sh"

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
timeout_seconds="${PLUGINVAL_TIMEOUT_SECONDS:-180}"
if ! timeout_attempts="$(pluginval_timeout_attempts "$timeout_seconds")"; then
    printf 'PLUGINVAL_TIMEOUT_SECONDS must be an integer from 1 to 3600.\n' >&2
    exit 2
fi

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

write_runner_status() {
    classification="$1"
    status="$2"
    {
        printf 'classification=%s\n' "$classification"
        printf 'status=%s\n' "$status"
        printf 'strictness=%s\n' "$strictness"
        printf 'timeout_seconds=%s\n' "$timeout_seconds"
    } > "$output_dir/runner-status.txt"
}

pluginval_app=""
case "$(uname -s):$pluginval" in
    Darwin:*.app/Contents/MacOS/*)
        pluginval_app="${pluginval%/Contents/MacOS/*}"
        ;;
esac

if [ -n "$pluginval_app" ]; then
    user_id="$(id -u)"
    label="dev.zig-vst3.pluginval.$$.${timestamp}"
    stdout_path="$output_dir/pluginval.stdout"
    stderr_path="$output_dir/pluginval.stderr"
    plist_path="$output_dir/pluginval-launch.plist"
    plist_buddy=/usr/libexec/PlistBuddy
    /usr/bin/plutil -create xml1 "$plist_path"
    "$plist_buddy" -c "Add :Label string $label" "$plist_path"
    "$plist_buddy" -c "Add :ProgramArguments array" "$plist_path"
    set -- "$pluginval" --strictness-level "$strictness" --output-dir "$output_dir"
    if [ -n "${PLUGINVAL_ARGS:-}" ]; then
        # Intentionally split PLUGINVAL_ARGS so callers can pass pluginval CLI flags.
        # shellcheck disable=SC2086
        set -- "$@" $PLUGINVAL_ARGS
    fi
    set -- "$@" "$plugin_path"
    argument_index=0
    for argument in "$@"; do
        "$plist_buddy" -c "Add :ProgramArguments:$argument_index string $argument" "$plist_path"
        argument_index=$((argument_index + 1))
    done
    "$plist_buddy" -c "Add :RunAtLoad bool true" "$plist_path"
    "$plist_buddy" -c "Add :KeepAlive bool false" "$plist_path"
    "$plist_buddy" -c "Add :StandardOutPath string $stdout_path" "$plist_path"
    "$plist_buddy" -c "Add :StandardErrorPath string $stderr_path" "$plist_path"

    cleanup_launch_job() {
        /bin/launchctl bootout "gui/$user_id/$label" >/dev/null 2>&1 || true
    }
    interrupt_launch_job() {
        signal_name="$1"
        interrupted_status="$2"
        cleanup_launch_job
        write_runner_status "interrupted:$signal_name" "$interrupted_status"
        trap - EXIT HUP INT TERM
        exit "$interrupted_status"
    }
    trap cleanup_launch_job EXIT
    trap 'interrupt_launch_job HUP 129' HUP
    trap 'interrupt_launch_job INT 130' INT
    trap 'interrupt_launch_job TERM 143' TERM
    set +e
    /bin/launchctl bootstrap "gui/$user_id" "$plist_path"
    status=$?
    classification=bootstrap_failed
    if [ "$status" -eq 0 ]; then
        attempts=0
        status=124
        classification=timed_out
        while [ "$attempts" -lt "$timeout_attempts" ]; do
            service="$(/bin/launchctl print "gui/$user_id/$label" 2>/dev/null)"
            printf '%s\n' "$service" > "$output_dir/launchctl-state.txt"
            result="$(pluginval_service_result "$service")"
            case "$result" in
                signal:*)
                    signal_number="${result#signal:}"
                    status=$((128 + signal_number))
                    classification=signaled
                    break
                    ;;
                exit:*)
                    status="${result#exit:}"
                    if [ "$status" -eq 0 ]; then classification=succeeded; else classification=failed; fi
                    break
                    ;;
            esac
            attempts=$((attempts + 1))
            sleep 0.1
        done
    fi
    cleanup_launch_job
    trap - EXIT HUP INT TERM
    if [ -f "$stdout_path" ]; then cat "$stdout_path"; fi
    if [ -f "$stderr_path" ]; then cat "$stderr_path" >&2; fi
    write_runner_status "$classification" "$status"
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
if [ "$status" -eq 0 ]; then
    classification=succeeded
elif [ "$status" -ge 128 ]; then
    classification=signaled
else
    classification=failed
fi
write_runner_status "$classification" "$status"
exit "$status"
