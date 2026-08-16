#!/usr/bin/env sh
set -eu

iterations="${GUI_LIFECYCLE_SOAK_REPETITIONS:-3}"
case "$iterations" in
    ''|*[!0-9]*|0)
        printf 'GUI_LIFECYCLE_SOAK_REPETITIONS must be a positive integer.\n' >&2
        exit 2
        ;;
esac

output_root="${GUI_LIFECYCLE_SOAK_OUTPUT_DIR:-${TMPDIR:-/tmp}/zig-vst3-gui-lifecycle}"
timestamp="$(date +%Y%m%d-%H%M%S)"
output_dir="$output_root/$timestamp-$$"
mkdir -p "$output_dir"

zig_command="${ZIG:-zig}"
cache_dir="${ZIG_GLOBAL_CACHE_DIR:-.zig-global-cache}"
plugins="gain bypass mode-gain voice-mix sine-synth editor-smoke channel-strip parametric-eq resonant-filter ir-loader sample-player"

{
    printf 'started_at=%s\n' "$timestamp"
    printf 'repetitions=%s\n' "$iterations"
    printf 'plugins=%s\n' "$plugins"
    printf 'zig=%s\n' "$zig_command"
    printf 'zig_version=%s\n' "$($zig_command version)"
    printf 'working_directory=%s\n' "$(pwd)"
    printf 'cache_directory=%s\n' "$cache_dir"
    printf 'system=%s\n' "$(uname -a)"
    printf 'git_commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
} > "$output_dir/run-metadata.txt"
printf 'gui lifecycle soak artifacts: %s\n' "$output_dir"

current_plugin=none
current_iteration=0
current_started_epoch=0
write_interrupted_status() {
    signal_name="$1"
    status="$2"
    {
        printf 'classification=interrupted\n'
        printf 'signal=%s\n' "$signal_name"
        printf 'status=%s\n' "$status"
        printf 'plugin=%s\n' "$current_plugin"
        printf 'iteration=%s\n' "$current_iteration"
        printf 'phase=headless-lifecycle-test\n'
        printf 'started_epoch=%s\n' "$current_started_epoch"
        printf 'finished_epoch=%s\n' "$(date +%s)"
    } > "$output_dir/runner-status.txt"
    trap - HUP INT TERM
    exit "$status"
}
trap 'write_interrupted_status HUP 129' HUP
trap 'write_interrupted_status INT 130' INT
trap 'write_interrupted_status TERM 143' TERM

for current_plugin in $plugins; do
    current_iteration=1
    while [ "$current_iteration" -le "$iterations" ]; do
        run_id="$current_plugin-$current_iteration"
        stdout_path="$output_dir/$run_id.stdout"
        stderr_path="$output_dir/$run_id.stderr"
        command_path="$output_dir/$run_id.command-arguments.txt"
        current_started_epoch="$(date +%s)"
        {
            printf 'environment:ZIG_GLOBAL_CACHE_DIR=%s\n' "$cache_dir"
            printf '0=%s\n' "$zig_command"
            printf '1=build\n'
            printf '2=test-gui-lifecycle-%s\n' "$current_plugin"
            printf '3=--summary\n'
            printf '4=all\n'
        } > "$command_path"
        printf 'plugin=%s iteration=%s/%s phase=headless-lifecycle-test\n' "$current_plugin" "$current_iteration" "$iterations"
        set +e
        ZIG_GLOBAL_CACHE_DIR="$cache_dir" "$zig_command" build "test-gui-lifecycle-$current_plugin" --summary all > "$stdout_path" 2> "$stderr_path"
        status=$?
        set -e
        if [ "$status" -ne 0 ]; then
            if [ "$status" -ge 128 ]; then classification=signaled; else classification=failed; fi
            {
                printf 'classification=%s\n' "$classification"
                printf 'status=%s\n' "$status"
                if [ "$status" -ge 128 ]; then printf 'signal=%s\n' "$((status - 128))"; fi
                printf 'plugin=%s\n' "$current_plugin"
                printf 'iteration=%s\n' "$current_iteration"
                printf 'phase=headless-lifecycle-test\n'
                printf 'started_epoch=%s\n' "$current_started_epoch"
                printf 'finished_epoch=%s\n' "$(date +%s)"
                printf 'command_arguments=%s\n' "$command_path"
                printf 'stdout=%s\n' "$stdout_path"
                printf 'stderr=%s\n' "$stderr_path"
            } > "$output_dir/runner-status.txt"
            cat "$stdout_path"
            cat "$stderr_path" >&2
            exit "$status"
        fi
        {
            printf 'classification=succeeded\n'
            printf 'status=0\n'
            printf 'plugin=%s\n' "$current_plugin"
            printf 'iteration=%s\n' "$current_iteration"
            printf 'phase=headless-lifecycle-test\n'
            printf 'started_epoch=%s\n' "$current_started_epoch"
            printf 'finished_epoch=%s\n' "$(date +%s)"
            printf 'command_arguments=%s\n' "$command_path"
            printf 'stdout=%s\n' "$stdout_path"
            printf 'stderr=%s\n' "$stderr_path"
        } > "$output_dir/$run_id.status"
        current_iteration=$((current_iteration + 1))
    done
done

{
    printf 'classification=succeeded\n'
    printf 'status=0\n'
    printf 'plugin_count=11\n'
    printf 'repetitions=%s\n' "$iterations"
    printf 'editor_lifecycles=%s\n' "$((11 * iterations * 12))"
    printf 'phase=complete\n'
} > "$output_dir/runner-status.txt"
printf 'gui lifecycle soak completed: %s editor lifecycles\n' "$((11 * iterations * 12))"
