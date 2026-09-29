#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

fixture=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-realtime-fixture.XXXXXX")
contract_fixture=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-realtime-contract.XXXXXX")
output=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-realtime-output.XXXXXX")
trap 'rm -f "$fixture" "$contract_fixture" "$output"' EXIT

scripts/check_realtime_source_inventory.sh

awk '
    !removed && /\.path = "[^"]+"/ { removed = 1; next }
    { print }
' examples/realtime_source_audit.zig > "$fixture"
if REALTIME_SOURCE_AUDIT="$fixture" \
    scripts/check_realtime_source_inventory.sh > "$output" 2>&1; then
    printf 'realtime source inventory accepted a missing processor\n' >&2
    exit 1
fi
grep -q 'realtime source inventory differs from production processors:' "$output"

awk '
    !removed && /^- `examples\/[^`]+`$/ { removed = 1; next }
    { print }
' docs/quality/realtime.md > "$contract_fixture"
if REALTIME_CONTRACT_DOC="$contract_fixture" \
    scripts/check_realtime_source_inventory.sh > "$output" 2>&1; then
    printf 'realtime source inventory accepted a missing contract path\n' >&2
    exit 1
fi
grep -q 'realtime contract differs from production processors:' "$output"

printf 'realtime source inventory fixture checks passed\n'
