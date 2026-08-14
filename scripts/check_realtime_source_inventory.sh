#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

audit=${REALTIME_SOURCE_AUDIT:-examples/realtime_source_audit.zig}
expected=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-realtime-expected.XXXXXX")
actual=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-realtime-actual.XXXXXX")
trap 'rm -f "$expected" "$actual"' EXIT

rg -l 'pub fn (process|process64|processWithParameters|process64WithParameters|processWithParameterView|process64WithParameterView)\(' \
    examples --glob '*.zig' | \
    LC_ALL=C sort | \
    sed '/^examples\/realtime_source_audit\.zig$/d' > "$actual"

sed -n 's/.*\.path = "\([^"]*\)".*/examples\/\1/p' "$audit" | \
    LC_ALL=C sort > "$expected"
if [[ $(wc -l < "$expected") -ne $(LC_ALL=C sort -u "$expected" | wc -l) ]]; then
    printf 'realtime source inventory contains duplicate paths\n' >&2
    exit 1
fi
if ! cmp -s "$expected" "$actual"; then
    printf 'realtime source inventory differs from production processors:\n' >&2
    diff -u "$expected" "$actual" >&2 || true
    exit 1
fi

printf 'realtime source inventory passed: %s processor files audited\n' \
    "$(wc -l < "$actual" | tr -d ' ')"
