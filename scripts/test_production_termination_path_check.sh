#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/termination-path-check.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/zig-vst3/src" "$fixture/zig-vst3-plugin/src" "$fixture/examples"
source="$fixture/zig-vst3/src/example.zig"
output="$fixture/output.txt"

printf '%s\n' 'pub fn value() u32 { return 1; }' >"$source"
"$script_dir/check_production_termination_paths.sh" "$fixture" >/dev/null
"$script_dir/check_production_termination_paths.sh" \
    --require-complete-allowlist "$fixture" >/dev/null

reject() {
    description="$1"
    if "$script_dir/check_production_termination_paths.sh" "$fixture" >"$output" 2>&1; then
        printf 'production termination path check accepted %s\n' "$description" >&2
        exit 1
    fi
    grep -q 'production source adds an unreviewed termination path' "$output"
}

printf '%s\n' 'pub fn value() u32 { unreachable; }' >"$source"
reject 'unreachable'

printf '%s\n' 'pub fn value() void { std.debug.assert(false); }' >"$source"
reject 'runtime assertion'

printf '%s\n' 'pub fn value() void { @panic("failure"); }' >"$source"
reject 'panic'

printf '%s\n' 'pub fn value() void { std.debug.panic("failure", .{}); }' >"$source"
reject 'debug panic'

printf '%s\n' 'pub fn value() void { @trap(); }' >"$source"
reject 'trap'

printf '%s\n' \
    'pub fn value() []const u8 {' \
    '    // unreachable, std.debug.assert, @panic, and @trap are policy terms.' \
    '    return "unreachable std.debug.panic @panic @trap";' \
    '}' \
    >"$source"
"$script_dir/check_production_termination_paths.sh" "$fixture" >/dev/null

printf '%s\n' \
    'pub fn value() u32 { return 1; }' \
    'test "fixture" {' \
    '    unreachable;' \
    '}' \
    >"$source"
"$script_dir/check_production_termination_paths.sh" "$fixture" >/dev/null

printf '%s\n' \
    'test "fixture" {' \
    '    const closing_brace = "}";' \
    '    _ = closing_brace;' \
    '    unreachable;' \
    '}' \
    'pub fn value() u32 { unreachable; }' \
    >"$source"
reject 'production unreachable after a test block'

printf 'production termination path check tests passed\n'
