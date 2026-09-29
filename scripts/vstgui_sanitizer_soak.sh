#!/usr/bin/env sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/gui-adapters/vstgui"
repetitions="${VSTGUI_SANITIZER_SOAK_REPETITIONS:-8}"

case "$repetitions" in
  ''|*[!0-9]*|0)
    printf 'VSTGUI_SANITIZER_SOAK_REPETITIONS must be a positive integer.\n' >&2
    exit 2
    ;;
esac

temporary_build=""
cleanup_build() {
  if [ -n "$temporary_build" ]; then
    rm -rf -- "$temporary_build"
  fi
}
trap cleanup_build EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "${VSTGUI_SANITIZER_SOAK_BUILD_DIR:-}" ]; then
  build_dir="$VSTGUI_SANITIZER_SOAK_BUILD_DIR"
else
  temporary_build=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vstgui-sanitizer-soak-build.XXXXXX")
  build_dir="$temporary_build/build"
fi

output_root="${VSTGUI_SANITIZER_SOAK_OUTPUT_DIR:-${TMPDIR:-/tmp}/zig-vst3-vstgui-sanitizer}"
timestamp=$(date +%Y%m%d-%H%M%S)
output_dir="$output_root/$timestamp-$$"
mkdir -p "$output_dir"

platform=$(uname -s)
phases="adapter visual"
if [ "$platform" = Darwin ]; then
  phases="adapter accessibility visual"
  export ASAN_OPTIONS="halt_on_error=1:strict_string_checks=1"
else
  export ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:strict_string_checks=1"
fi
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"

{
  printf 'started_at=%s\n' "$timestamp"
  printf 'repetitions=%s\n' "$repetitions"
  printf 'phases=%s\n' "$phases"
  printf 'working_directory=%s\n' "$root"
  printf 'build_directory=%s\n' "$build_dir"
  printf 'system=%s\n' "$(uname -a)"
  printf 'cmake_version=%s\n' "$(cmake --version | sed -n '1p')"
  printf 'git_commit=%s\n' "$(git -C "$root" rev-parse HEAD 2>/dev/null || printf unknown)"
} > "$output_dir/run-metadata.txt"
printf 'VSTGUI sanitizer soak artifacts: %s\n' "$output_dir"

build_stdout="$output_dir/build.stdout"
build_stderr="$output_dir/build.stderr"
if [ "${VSTGUI_SANITIZER_SOAK_SKIP_BUILD:-0}" != 1 ]; then
  set +e
  VSTGUI_SANITIZER_BUILD_DIR="$build_dir" \
    ZIG_VSTGUI_SANITIZER_BUILD_ONLY=1 \
    "$root/scripts/test_vstgui_sanitizers.sh" > "$build_stdout" 2> "$build_stderr"
  build_status=$?
  set -e
  if [ "$build_status" -ne 0 ]; then
    {
      printf 'classification=failed\n'
      printf 'status=%s\n' "$build_status"
      printf 'phase=build\n'
      printf 'stdout=%s\n' "$build_stdout"
      printf 'stderr=%s\n' "$build_stderr"
    } > "$output_dir/runner-status.txt"
    cat "$build_stdout"
    cat "$build_stderr" >&2
    exit "$build_status"
  fi
fi

current_iteration=0
current_phase=none
current_started_epoch=0
write_interrupted_status() {
  signal_name="$1"
  status="$2"
  {
    printf 'classification=interrupted\n'
    printf 'signal=%s\n' "$signal_name"
    printf 'status=%s\n' "$status"
    printf 'iteration=%s\n' "$current_iteration"
    printf 'phase=%s\n' "$current_phase"
    printf 'started_epoch=%s\n' "$current_started_epoch"
    printf 'finished_epoch=%s\n' "$(date +%s)"
  } > "$output_dir/runner-status.txt"
  trap - HUP INT TERM
  exit "$status"
}
trap 'write_interrupted_status HUP 129' HUP
trap 'write_interrupted_status INT 130' INT
trap 'write_interrupted_status TERM 143' TERM

current_iteration=1
while [ "$current_iteration" -le "$repetitions" ]; do
  for current_phase in $phases; do
    run_id="$current_iteration-$current_phase"
    stdout_path="$output_dir/$run_id.stdout"
    stderr_path="$output_dir/$run_id.stderr"
    command_path="$output_dir/$run_id.command-arguments.txt"
    current_started_epoch=$(date +%s)
    case "$current_phase" in
      adapter)
        command="$build_dir/zig_vstgui_adapter_tests"
        ;;
      accessibility)
        command="$build_dir/zig_vstgui_accessibility_macos_tests"
        ;;
      visual)
        command="$build_dir/zig_vstgui_visual_tests"
        ;;
    esac
    {
      printf 'environment:ASAN_OPTIONS=%s\n' "$ASAN_OPTIONS"
      printf 'environment:UBSAN_OPTIONS=%s\n' "$UBSAN_OPTIONS"
      printf '0=%s\n' "$command"
      if [ "$current_phase" = visual ]; then
        printf '1=%s\n' "$source_dir/testdata/visual"
        printf '2=%s\n' "$output_dir/visual-$current_iteration"
        printf '3=--skip-performance\n'
      fi
    } > "$command_path"
    printf 'iteration=%s/%s phase=%s\n' "$current_iteration" "$repetitions" "$current_phase"
    set +e
    if [ "$current_phase" = visual ]; then
      "$command" "$source_dir/testdata/visual" "$output_dir/visual-$current_iteration" --skip-performance > "$stdout_path" 2> "$stderr_path"
    else
      "$command" > "$stdout_path" 2> "$stderr_path"
    fi
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
      if [ "$status" -ge 128 ]; then classification=signaled; else classification=failed; fi
      {
        printf 'classification=%s\n' "$classification"
        printf 'status=%s\n' "$status"
        if [ "$status" -ge 128 ]; then printf 'signal=%s\n' "$((status - 128))"; fi
        printf 'iteration=%s\n' "$current_iteration"
        printf 'phase=%s\n' "$current_phase"
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
      printf 'iteration=%s\n' "$current_iteration"
      printf 'phase=%s\n' "$current_phase"
      printf 'started_epoch=%s\n' "$current_started_epoch"
      printf 'finished_epoch=%s\n' "$(date +%s)"
      printf 'command_arguments=%s\n' "$command_path"
      printf 'stdout=%s\n' "$stdout_path"
      printf 'stderr=%s\n' "$stderr_path"
    } > "$output_dir/$run_id.status"
  done
  current_iteration=$((current_iteration + 1))
done

phase_count=2
if [ "$platform" = Darwin ]; then phase_count=3; fi
{
  printf 'classification=succeeded\n'
  printf 'status=0\n'
  printf 'repetitions=%s\n' "$repetitions"
  printf 'phase_count=%s\n' "$phase_count"
  printf 'process_runs=%s\n' "$((repetitions * phase_count))"
  printf 'phase=complete\n'
} > "$output_dir/runner-status.txt"
printf 'VSTGUI sanitizer soak completed: %s process runs\n' "$((repetitions * phase_count))"
