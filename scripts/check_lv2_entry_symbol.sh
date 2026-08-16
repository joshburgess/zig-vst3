#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf 'usage: %s <LV2 shared library> [entry-symbol]\n' "$0" >&2
    exit 2
fi

library=$1
entry_symbol=${2-lv2_descriptor}
case "$entry_symbol" in
    *[!A-Za-z0-9_]* | '')
        printf 'invalid LV2 entry symbol: %s\n' "$entry_symbol" >&2
        exit 2
        ;;
esac
if [ ! -f "$library" ]; then
    printf 'LV2 shared library is missing: %s\n' "$library" >&2
    exit 2
fi

if command -v nm >/dev/null 2>&1; then
    symbols=$(nm -g "$library")
elif command -v llvm-nm >/dev/null 2>&1; then
    symbols=$(llvm-nm -g "$library")
elif command -v objdump >/dev/null 2>&1; then
    symbols=$(objdump -t "$library")
else
    printf 'nm, llvm-nm, or objdump is required to inspect LV2 exports\n' >&2
    exit 2
fi

if ! printf '%s\n' "$symbols" |
    grep -Eq "(^|[[:space:]_])${entry_symbol}($|[[:space:]])"; then
    printf '%s entry symbol is missing from %s\n' "$entry_symbol" "$library" >&2
    exit 1
fi
