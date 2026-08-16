#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

fixture=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-fixture.XXXXXX")
output=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-output.XXXXXX")
trap 'rm -f "$fixture" "$output"' EXIT

scripts/check_quality_cohesion_inventory.sh

awk '
    /^<!-- cohesion-files:start -->$/ { inside = 1; print; next }
    /^<!-- cohesion-files:end -->$/ { inside = 0; print; next }
    inside && !removed && /^- `[^`]+`/ { removed = 1; next }
    { print }
' docs/quality/cohesion.md > "$fixture"
if QUALITY_COHESION_DOCUMENT="$fixture" \
    scripts/check_quality_cohesion_inventory.sh > "$output" 2>&1; then
    printf 'cohesion inventory accepted a missing source path\n' >&2
    exit 1
fi
grep -q 'unrecorded cohesion source paths:' "$output"

awk '
    /^<!-- cohesion-files:end -->$/ {
        print "- `zig-vst3-plugin/src/not-a-real-large-source.zig` | 2000 | 2000 | 0 | KEEP"
    }
    { print }
' docs/quality/cohesion.md > "$fixture"
if QUALITY_COHESION_DOCUMENT="$fixture" \
    scripts/check_quality_cohesion_inventory.sh > "$output" 2>&1; then
    printf 'cohesion inventory accepted a stale source path\n' >&2
    exit 1
fi
grep -q 'stale cohesion inventory paths:' "$output"

awk -F ' \\| ' '
    BEGIN { OFS = " | " }
    /^<!-- cohesion-files:start -->$/ { inside = 1 }
    /^<!-- cohesion-files:end -->$/ { inside = 0 }
    inside && !changed && /^- `[^`]+`/ { $2 = $2 + 1; changed = 1 }
    { print }
' docs/quality/cohesion.md > "$fixture"
if QUALITY_COHESION_DOCUMENT="$fixture" \
    scripts/check_quality_cohesion_inventory.sh > "$output" 2>&1; then
    printf 'cohesion inventory accepted stale line metrics\n' >&2
    exit 1
fi
grep -q 'cohesion metric mismatch' "$output"

awk -F ' \\| ' '
    BEGIN { OFS = " | " }
    /^<!-- cohesion-files:start -->$/ { inside = 1 }
    /^<!-- cohesion-files:end -->$/ { inside = 0 }
    inside && !changed && /^- `[^`]+`/ { $5 = "DEFER"; changed = 1 }
    { print }
' docs/quality/cohesion.md > "$fixture"
if QUALITY_COHESION_DOCUMENT="$fixture" \
    scripts/check_quality_cohesion_inventory.sh > "$output" 2>&1; then
    printf 'cohesion inventory accepted an unknown decision\n' >&2
    exit 1
fi
grep -q 'invalid cohesion inventory record:' "$output"

printf 'cohesion inventory fixture checks passed\n'
