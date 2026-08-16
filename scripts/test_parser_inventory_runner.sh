#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/parser-inventory-check.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

mkdir -p \
    "$fixture_dir/docs/quality" \
    "$fixture_dir/scripts" \
    "$fixture_dir/zig-vst3/src" \
    "$fixture_dir/zig-vst3-plugin/src/state"
cp "$script_dir/check_quality_inventory.sh" "$fixture_dir/scripts/"
cp "$script_dir/check_parser_inventory.sh" "$fixture_dir/scripts/"
printf '%s\n' 'const std = @import("std");' > "$fixture_dir/build.zig"
printf '%s\n' 'pub fn parse(bytes: []const u8) void { _ = bytes; }' \
    > "$fixture_dir/zig-vst3/src/parser.zig"
printf '%s\n' 'pub const version: u16 = 1;' \
    > "$fixture_dir/zig-vst3-plugin/src/state/format.zig"
printf '%s\n' \
    '# Parser inventory' \
    '<!-- parser-inventory-begin -->' \
    '```text' \
    'P-STATE zig-vst3-plugin/src/state/format.zig' \
    'P-CONFIG zig-vst3/src/parser.zig' \
    '```' \
    '<!-- parser-inventory-end -->' \
    > "$fixture_dir/docs/quality/parsers.md"

git -C "$fixture_dir" init -q
git -C "$fixture_dir" add .
(cd "$fixture_dir" && scripts/check_parser_inventory.sh) > "$fixture_dir/output.txt"
grep -q 'parser inventory covers 2 production sources' "$fixture_dir/output.txt"

sed '/zig-vst3\/src\/parser.zig/d' "$fixture_dir/docs/quality/parsers.md" \
    > "$fixture_dir/docs/quality/parsers-missing.md"
if (cd "$fixture_dir" && scripts/check_parser_inventory.sh \
    docs/quality/parsers-missing.md) > "$fixture_dir/output.txt" 2>&1; then
    printf 'parser inventory accepted an omitted lexical candidate\n' >&2
    exit 1
fi
grep -q 'parser inventory is missing candidate sources' "$fixture_dir/output.txt"

sed '/zig-vst3-plugin\/src\/state\/format.zig/d' \
    "$fixture_dir/docs/quality/parsers.md" \
    > "$fixture_dir/docs/quality/parsers-missing.md"
if (cd "$fixture_dir" && scripts/check_parser_inventory.sh \
    docs/quality/parsers-missing.md) > "$fixture_dir/output.txt" 2>&1; then
    printf 'parser inventory accepted an omitted semantic filename candidate\n' >&2
    exit 1
fi
grep -q 'parser inventory is missing candidate sources' "$fixture_dir/output.txt"

sed 's/P-CONFIG zig-vst3\/src\/parser.zig/P-UNKNOWN zig-vst3\/src\/parser.zig/' \
    "$fixture_dir/docs/quality/parsers.md" \
    > "$fixture_dir/docs/quality/parsers-invalid.md"
if (cd "$fixture_dir" && scripts/check_parser_inventory.sh \
    docs/quality/parsers-invalid.md) > "$fixture_dir/output.txt" 2>&1; then
    printf 'parser inventory accepted an unknown family\n' >&2
    exit 1
fi
grep -q 'parser inventory uses an unknown family' "$fixture_dir/output.txt"

printf 'parser inventory check tests passed\n'
