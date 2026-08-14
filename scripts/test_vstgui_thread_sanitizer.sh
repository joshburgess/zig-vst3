#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/gui-adapters/vstgui"
repetitions="${VSTGUI_THREAD_SANITIZER_REPETITIONS:-4}"

case "$repetitions" in
  ''|*[!0-9]*|0)
    printf 'VSTGUI_THREAD_SANITIZER_REPETITIONS must be a positive integer.\n' >&2
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

if [ -n "${VSTGUI_THREAD_SANITIZER_BUILD_DIR:-}" ]; then
  build_dir="$VSTGUI_THREAD_SANITIZER_BUILD_DIR"
else
  temporary_build=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vstgui-thread-sanitizer-build.XXXXXX")
  build_dir="$temporary_build/build"
fi

output_root="${VSTGUI_THREAD_SANITIZER_OUTPUT_DIR:-${TMPDIR:-/tmp}/zig-vst3-vstgui-thread-sanitizer}"
timestamp=$(date +%Y%m%d-%H%M%S)
output_dir="$output_root/$timestamp-$$"
mkdir -p "$output_dir"
export TSAN_OPTIONS="halt_on_error=1:history_size=7:second_deadlock_stack=1"

{
  printf 'started_at=%s\n' "$timestamp"
  printf 'repetitions=%s\n' "$repetitions"
  printf 'working_directory=%s\n' "$root"
  printf 'build_directory=%s\n' "$build_dir"
  printf 'system=%s\n' "$(uname -a)"
  printf 'git_commit=%s\n' "$(git -C "$root" rev-parse HEAD 2>/dev/null || printf unknown)"
  printf 'tsan_options=%s\n' "$TSAN_OPTIONS"
} > "$output_dir/run-metadata.txt" || {
  printf 'failed to write VSTGUI thread sanitizer metadata\n' >&2
  exit 1
}
printf 'VSTGUI thread sanitizer artifacts: %s\n' "$output_dir"

if [ "${VSTGUI_THREAD_SANITIZER_SKIP_BUILD:-0}" != 1 ]; then
  build_stdout="$output_dir/build.stdout"
  build_stderr="$output_dir/build.stderr"
  set +e
  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_C_FLAGS_RELEASE=-O2 -g -DNDEBUG" \
    "-DCMAKE_CXX_FLAGS_RELEASE=-O2 -g -DNDEBUG" \
    "-DCMAKE_OBJCXX_FLAGS_RELEASE=-O2 -g -DNDEBUG" \
    -DZIG_VSTGUI_ENABLE_SANITIZERS=OFF \
    -DZIG_VSTGUI_ENABLE_THREAD_SANITIZER=ON \
    -DVSTGUI_STANDALONE=OFF \
    -DVSTGUI_STANDALONE_EXAMPLES=OFF \
    -DVSTGUI_TOOLS=OFF \
    -DVSTGUI_DISABLE_UNITTESTS=ON \
    -DVSTGUI_UISCRIPTING=OFF \
    -DVSTGUI_ENABLE_OPENGL_SUPPORT=OFF \
    -DVSTGUI_ENABLE_XMLPARSER=OFF > "$build_stdout" 2> "$build_stderr"
  build_status=$?
  if [ "$build_status" -eq 0 ]; then
    cmake --build "$build_dir" --target zig_vstgui_adapter_tests --parallel >> "$build_stdout" 2>> "$build_stderr"
    build_status=$?
  fi
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

iteration=0
started_epoch=0
write_interrupted_status() {
  signal_name="$1"
  status="$2"
  {
    printf 'classification=interrupted\n'
    printf 'signal=%s\n' "$signal_name"
    printf 'status=%s\n' "$status"
    printf 'iteration=%s\n' "$iteration"
    printf 'phase=adapter-thread-safety\n'
    printf 'started_epoch=%s\n' "$started_epoch"
    printf 'finished_epoch=%s\n' "$(date +%s)"
  } > "$output_dir/runner-status.txt"
  trap - HUP INT TERM
  exit "$status"
}
trap 'write_interrupted_status HUP 129' HUP
trap 'write_interrupted_status INT 130' INT
trap 'write_interrupted_status TERM 143' TERM

iteration=1
while [ "$iteration" -le "$repetitions" ]; do
  stdout_path="$output_dir/$iteration.stdout"
  stderr_path="$output_dir/$iteration.stderr"
  command_path="$output_dir/$iteration.command-arguments.txt"
  started_epoch=$(date +%s)
  printf '0=%s\n' "$build_dir/zig_vstgui_adapter_tests" > "$command_path" || {
    printf 'failed to write VSTGUI thread sanitizer command record\n' >&2
    exit 1
  }
  printf 'iteration=%s/%s phase=adapter-thread-safety\n' "$iteration" "$repetitions"
  set +e
  "$build_dir/zig_vstgui_adapter_tests" > "$stdout_path" 2> "$stderr_path"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    if [ "$status" -ge 128 ]; then classification=signaled; else classification=failed; fi
    {
      printf 'classification=%s\n' "$classification"
      printf 'status=%s\n' "$status"
      if [ "$status" -ge 128 ]; then printf 'signal=%s\n' "$((status - 128))"; fi
      printf 'iteration=%s\n' "$iteration"
      printf 'phase=adapter-thread-safety\n'
      printf 'started_epoch=%s\n' "$started_epoch"
      printf 'finished_epoch=%s\n' "$(date +%s)"
      printf 'command_arguments=%s\n' "$command_path"
      printf 'stdout=%s\n' "$stdout_path"
      printf 'stderr=%s\n' "$stderr_path"
    } > "$output_dir/runner-status.txt" || {
      printf 'failed to write VSTGUI thread sanitizer failure status\n' >&2
      exit 1
    }
    cat "$stdout_path"
    cat "$stderr_path" >&2
    exit "$status"
  fi
  {
    printf 'classification=succeeded\n'
    printf 'status=0\n'
    printf 'iteration=%s\n' "$iteration"
    printf 'phase=adapter-thread-safety\n'
    printf 'started_epoch=%s\n' "$started_epoch"
    printf 'finished_epoch=%s\n' "$(date +%s)"
    printf 'command_arguments=%s\n' "$command_path"
    printf 'stdout=%s\n' "$stdout_path"
    printf 'stderr=%s\n' "$stderr_path"
  } > "$output_dir/$iteration.status" || {
    printf 'failed to write VSTGUI thread sanitizer iteration status\n' >&2
    exit 1
  }
  iteration=$((iteration + 1))
done

{
  printf 'classification=succeeded\n'
  printf 'status=0\n'
  printf 'repetitions=%s\n' "$repetitions"
  printf 'phase=complete\n'
} > "$output_dir/runner-status.txt" || {
  printf 'failed to write VSTGUI thread sanitizer completion status\n' >&2
  exit 1
}
printf 'VSTGUI thread sanitizer completed: %s process runs\n' "$repetitions"
