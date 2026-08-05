#!/bin/sh
# shellcheck disable=SC2016
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-msvc-prerequisite.XXXXXX")
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

output="$root/missing-libc.txt"
if zig build \
    -Dtarget=x86_64-windows-msvc \
    --cache-dir "$root/missing-cache" \
    --global-cache-dir "$root/missing-global-cache" \
    -l >"$output" 2>&1
then
    printf 'MSVC cross-build configuration unexpectedly accepted a missing libc description\n' >&2
    exit 1
fi

grep -Fq 'Windows MSVC C-kernel cross-builds require an MSVC libc configuration.' "$output"
grep -Fq 'pass `--libc <path>`' "$output"
grep -Fq 'Use `-Dtarget=x86_64-windows-gnu`' "$output"

: >"$root/libc.txt"
zig build \
    -Dtarget=x86_64-windows-msvc \
    --libc "$root/libc.txt" \
    --cache-dir "$root/configured-cache" \
    --global-cache-dir "$root/configured-global-cache" \
    -l >/dev/null

zig build \
    -Dtarget=x86_64-windows-gnu \
    --cache-dir "$root/gnu-cache" \
    --global-cache-dir "$root/gnu-global-cache" \
    -l >/dev/null

printf 'MSVC prerequisite diagnostic tests passed\n'
