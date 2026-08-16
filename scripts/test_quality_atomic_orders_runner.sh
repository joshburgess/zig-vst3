#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

fixture=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-atomic-fixture.XXXXXX")
output=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-atomic-output.XXXXXX")
trap 'rm -f "$fixture" "$output"' EXIT

scripts/check_quality_atomic_orders.sh

awk '
    /^<!-- atomic-order-counts:start -->$/ { inside = 1 }
    inside && !changed && /^\| `[^`]+` \| [0-9]+ \|/ {
        sub(/\| [0-9]+ \|$/, "| 999999 |")
        changed = 1
    }
    { print }
' docs/quality/atomic-orders.md > "$fixture"
if QUALITY_ATOMIC_ORDER_DOCUMENT="$fixture" \
    scripts/check_quality_atomic_orders.sh > "$output" 2>&1; then
    printf 'atomic-order ledger accepted a changed count\n' >&2
    exit 1
fi
grep -q 'atomic-order ledger differs from tracked source:' "$output"

awk '
    /^<!-- native-atomic-order-counts:start -->$/ { inside = 1 }
    inside && !changed && /^\| `[^`]+` \| [0-9]+ \|/ {
        sub(/\| [0-9]+ \|$/, "| 999999 |")
        changed = 1
    }
    { print }
' docs/quality/atomic-orders.md > "$fixture"
if QUALITY_ATOMIC_ORDER_DOCUMENT="$fixture" \
    scripts/check_quality_atomic_orders.sh > "$output" 2>&1; then
    printf 'atomic-order ledger accepted a changed native count\n' >&2
    exit 1
fi
grep -q 'native atomic-order ledger differs from tracked source:' "$output"

printf 'atomic-order ledger fixture checks passed\n'
