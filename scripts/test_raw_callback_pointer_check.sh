#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/raw-callback-check.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/zig-vst3/src" "$fixture/zig-vst3-plugin/src"
source="$fixture/zig-vst3/src/example.zig"
output="$fixture/output.txt"

printf '%s\n' \
    'field: *const fn (*anyopaque, [*c]u8, ?*u32) callconv(.c) i32,' \
    >"$source"
"$script_dir/check_raw_callback_pointers.sh" "$fixture" >/dev/null

printf '%s\n' \
    'foreign_call: *const fn ([*:0]const u8, *u32) callconv(.c) i32,' \
    >"$source"
"$script_dir/check_raw_callback_pointers.sh" "$fixture" >/dev/null

printf '%s\n' \
    'field: *const fn (*anyopaque, *u32) i32,' \
    >"$source"
"$script_dir/check_raw_callback_pointers.sh" "$fixture" >/dev/null

for argument in '*u32' '[*]u8' '[*:0]const u8'; do
    printf '%s\n' \
        "field: *const fn (*anyopaque, $argument) callconv(.c) i32," \
        >"$source"
    if "$script_dir/check_raw_callback_pointers.sh" "$fixture" >"$output" 2>&1; then
        printf 'raw callback pointer check accepted %s\n' "$argument" >&2
        exit 1
    fi
    grep -q 'C callback uses a non-null raw pointer argument' "$output"
done

printf '%s\n' \
    'field: *const fn (*anyopaque, *u32) callconv(.c) i32,' \
    >"$fixture/zig-vst3-plugin/src/example.zig"
if "$script_dir/check_raw_callback_pointers.sh" "$fixture" >"$output" 2>&1; then
    printf 'raw callback pointer check skipped framework sources\n' >&2
    exit 1
fi
grep -q 'C callback uses a non-null raw pointer argument' "$output"

printf '%s\n' \
    'field: *const fn (self:*anyopaque,output:*u32) callconv(.c) i32,' \
    >"$fixture/zig-vst3-plugin/src/example.zig"
if "$script_dir/check_raw_callback_pointers.sh" "$fixture" >"$output" 2>&1; then
    printf 'raw callback pointer check accepted compact syntax\n' >&2
    exit 1
fi
grep -q 'C callback uses a non-null raw pointer argument' "$output"

printf '%s\n' \
    'field: *const fn (' \
    '    self: *anyopaque,' \
    '    output: [*]u8,' \
    ') callconv(.c) i32,' \
    >"$fixture/zig-vst3-plugin/src/example.zig"
if "$script_dir/check_raw_callback_pointers.sh" "$fixture" >"$output" 2>&1; then
    printf 'raw callback pointer check accepted a multiline declaration\n' >&2
    exit 1
fi
grep -q 'C callback uses a non-null raw pointer argument' "$output"

printf '%s\n' \
    'field: *const fn (self: *anyopaque, output: *u32) callconv(.c) i32,' \
    >"$fixture/zig-vst3-plugin/src/example.zig"
if "$script_dir/check_raw_callback_pointers.sh" "$fixture" >"$output" 2>&1; then
    printf 'raw callback pointer check accepted named arguments\n' >&2
    exit 1
fi
grep -q 'C callback uses a non-null raw pointer argument' "$output"

printf 'raw callback pointer check tests passed\n'
