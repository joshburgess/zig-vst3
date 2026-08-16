#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

document=${QUALITY_CONCURRENCY_DOCUMENT:-docs/quality/concurrency.md}
if [[ ! -f "$document" ]]; then
    printf 'missing concurrency inventory: %s\n' "$document" >&2
    exit 1
fi

if [[ $(grep -c '^<!-- concurrency-files:start -->$' "$document") -ne 1 ||
      $(grep -c '^<!-- concurrency-files:end -->$' "$document") -ne 1 ]]; then
    printf 'concurrency inventory requires one start marker and one end marker\n' >&2
    exit 1
fi

expected_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-concurrency-expected.XXXXXX")
actual_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-concurrency-actual.XXXXXX")
trap 'rm -f "$expected_tmp" "$actual_tmp"' EXIT

awk '
    /^<!-- concurrency-files:start -->$/ { inside = 1; next }
    /^<!-- concurrency-files:end -->$/ { inside = 0; next }
    inside && /^- `[^`]+`$/ {
        line = $0
        sub(/^- `/, "", line)
        sub(/`$/, "", line)
        print line
    }
' "$document" | LC_ALL=C sort > "$expected_tmp"

if [[ ! -s "$expected_tmp" ]]; then
    printf 'concurrency inventory contains no source paths\n' >&2
    exit 1
fi
if [[ $(wc -l < "$expected_tmp") -ne $(LC_ALL=C sort -u "$expected_tmp" | wc -l) ]]; then
    printf 'concurrency inventory contains duplicate source paths\n' >&2
    exit 1
fi

pattern='std\.atomic|std\.Io\.Mutex|std\.Thread\.spawn|_Atomic|std::atomic|std::mutex|std::thread|AtomicReferenceCounted|pthread_(mutex|cond|create)|atomic_(load|store|fetch|exchange|compare)|Interlocked|CRITICAL_SECTION|CONDITION_VARIABLE|CreateThread|CreateEvent|WaitForSingleObject'
set +e
git grep -l -E "$pattern" -- \
    'zig-vst3/src/**' \
    'zig-vst3-plugin/src/**' \
    'gui-adapters/**' \
    'examples/**' > "$actual_tmp"
grep_status=$?
set -e
if [[ "$grep_status" -gt 1 ]]; then
    printf 'concurrency source scan failed with status %s\n' "$grep_status" >&2
    exit "$grep_status"
fi
LC_ALL=C sort -o "$actual_tmp" "$actual_tmp"

missing=$(comm -23 "$actual_tmp" "$expected_tmp")
stale=$(comm -13 "$actual_tmp" "$expected_tmp")
if [[ -n "$missing" || -n "$stale" ]]; then
    if [[ -n "$missing" ]]; then
        printf 'unrecorded concurrency source paths:\n%s\n' "$missing" >&2
    fi
    if [[ -n "$stale" ]]; then
        printf 'stale concurrency inventory paths:\n%s\n' "$stale" >&2
    fi
    exit 1
fi

printf 'concurrency inventory passed: %s source files classified\n' "$(wc -l < "$actual_tmp" | tr -d ' ')"
