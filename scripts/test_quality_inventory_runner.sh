#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/quality-inventory-check.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

mkdir -p \
    "$fixture_dir/scripts" \
    "$fixture_dir/zig-vst3/src" \
    "$fixture_dir/zig-vst3-plugin/src/dsp" \
    "$fixture_dir/zig-vst3-plugin/src/plugin"
cp "$script_dir/check_quality_inventory.sh" "$fixture_dir/scripts/"
printf '%s\n' 'const std = @import("std");' > "$fixture_dir/build.zig"
printf '%s\n' 'pub const value: u32 = 1;' > "$fixture_dir/zig-vst3/src/example.zig"
printf '%s\n' 'pub const value: u32 = 2;' > "$fixture_dir/zig-vst3-plugin/src/dsp/ogg.zig"
printf '%s\n' 'void backend_callback(void) {}' > "$fixture_dir/zig-vst3-plugin/src/plugin/example_shim.c"
printf '%s\n' 'struct state { std::atomic<unsigned> value; };' > "$fixture_dir/zig-vst3-plugin/src/plugin/example_ref_count.hpp"

git -C "$fixture_dir" init -q
git -C "$fixture_dir" add .
(cd "$fixture_dir" && scripts/check_quality_inventory.sh) > "$fixture_dir/output.txt"
grep -q '^Q01[[:space:]]' "$fixture_dir/output.txt"
grep -q '^Q10[[:space:]]' "$fixture_dir/output.txt"
grep -q '^Q18[[:space:]]' "$fixture_dir/output.txt"
awk '$1 == "Q18" && $2 == 2 && $6 == 1 { found = 1 } END { exit !found }' \
    "$fixture_dir/output.txt"

mkdir -p "$fixture_dir/unexpected"
printf '%s\n' 'pub const value: u32 = 3;' > "$fixture_dir/unexpected/source.zig"
git -C "$fixture_dir" add unexpected/source.zig
if (cd "$fixture_dir" && scripts/check_quality_inventory.sh) > "$fixture_dir/output.txt" 2>&1; then
    printf 'quality inventory accepted an unclassified source\n' >&2
    exit 1
fi
grep -q 'unclassified source: unexpected/source.zig' "$fixture_dir/output.txt"

printf 'quality inventory check tests passed\n'
