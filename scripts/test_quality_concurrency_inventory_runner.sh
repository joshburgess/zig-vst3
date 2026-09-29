#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

fixture=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-concurrency-fixture.XXXXXX")
output=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-concurrency-output.XXXXXX")
trap 'rm -f "$fixture" "$output"' EXIT

scripts/check_quality_concurrency_inventory.sh

awk '
    /^<!-- concurrency-files:start -->$/ { inside = 1; print; next }
    /^<!-- concurrency-files:end -->$/ { inside = 0; print; next }
    inside && !removed && /^- `[^`]+`$/ { removed = 1; next }
    { print }
' docs/quality/concurrency.md > "$fixture"
if QUALITY_CONCURRENCY_DOCUMENT="$fixture" \
    scripts/check_quality_concurrency_inventory.sh > "$output" 2>&1; then
    printf 'concurrency inventory accepted a missing source path\n' >&2
    exit 1
fi
grep -q 'unrecorded concurrency source paths:' "$output"

awk '
    /^<!-- concurrency-files:end -->$/ {
        print "- `zig-vst3-plugin/src/not-a-real-concurrency-source.zig`"
    }
    { print }
' docs/quality/concurrency.md > "$fixture"
if QUALITY_CONCURRENCY_DOCUMENT="$fixture" \
    scripts/check_quality_concurrency_inventory.sh > "$output" 2>&1; then
    printf 'concurrency inventory accepted a stale source path\n' >&2
    exit 1
fi
grep -q 'stale concurrency inventory paths:' "$output"

printf 'concurrency inventory fixture checks passed\n'
