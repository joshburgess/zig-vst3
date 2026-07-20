#!/usr/bin/env sh

pluginval_timeout_attempts() {
    timeout_seconds="$1"
    case "$timeout_seconds" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ "$timeout_seconds" -lt 1 ] || [ "$timeout_seconds" -gt 3600 ]; then
        return 1
    fi
    printf '%s\n' "$((timeout_seconds * 10))"
}

pluginval_service_result() {
    service="$1"
    active_count="$(printf '%s\n' "$service" | sed -n 's/^[[:space:]]*active count = \([0-9][0-9]*\)$/\1/p' | tail -n 1)"
    exit_code="$(printf '%s\n' "$service" | sed -n 's/^[[:space:]]*last exit code = \([0-9][0-9]*\)$/\1/p' | tail -n 1)"
    terminating_signal="$(printf '%s\n' "$service" | sed -n 's/^[[:space:]]*last terminating signal = .*: \([0-9][0-9]*\)$/\1/p' | tail -n 1)"
    if [ "$active_count" != "0" ]; then
        printf 'running\n'
    elif [ -n "$terminating_signal" ]; then
        printf 'signal:%s\n' "$terminating_signal"
    elif [ -n "$exit_code" ]; then
        printf 'exit:%s\n' "$exit_code"
    else
        printf 'unknown\n'
    fi
}
