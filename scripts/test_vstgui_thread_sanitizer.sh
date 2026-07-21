#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/gui-adapters/vstgui"
build_dir="$root/.vst3-sdk/vstgui-adapter-thread-sanitizer-build"
repetitions="${VSTGUI_THREAD_SANITIZER_REPETITIONS:-4}"

case "$repetitions" in
  ''|*[!0-9]*|0)
    printf 'VSTGUI_THREAD_SANITIZER_REPETITIONS must be a positive integer.\n' >&2
    exit 2
    ;;
esac

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
  -DVSTGUI_ENABLE_XMLPARSER=OFF

cmake --build "$build_dir" --target zig_vstgui_adapter_tests --parallel

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
} > "$output_dir/run-metadata.txt"
printf 'VSTGUI thread sanitizer artifacts: %s\n' "$output_dir"

iteration=1
while [ "$iteration" -le "$repetitions" ]; do
  stdout_path="$output_dir/$iteration.stdout"
  stderr_path="$output_dir/$iteration.stderr"
  started_epoch=$(date +%s)
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
    printf 'iteration=%s\n' "$iteration"
    printf 'phase=adapter-thread-safety\n'
    printf 'started_epoch=%s\n' "$started_epoch"
    printf 'finished_epoch=%s\n' "$(date +%s)"
    printf 'stdout=%s\n' "$stdout_path"
    printf 'stderr=%s\n' "$stderr_path"
  } > "$output_dir/$iteration.status"
  iteration=$((iteration + 1))
done

{
  printf 'classification=succeeded\n'
  printf 'status=0\n'
  printf 'repetitions=%s\n' "$repetitions"
  printf 'phase=complete\n'
} > "$output_dir/runner-status.txt"
printf 'VSTGUI thread sanitizer completed: %s process runs\n' "$repetitions"
