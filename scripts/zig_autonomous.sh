#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$#" -eq 0 ]; then
    printf 'usage: %s zig-arguments...\n' "$0" >&2
    exit 2
fi

"$root/scripts/check_zig_cache_budget.sh" --autonomous

zig_status=0
ZIG_GLOBAL_CACHE_DIR="$root/.zig-cache-autonomous/global" \
ZIG_LOCAL_CACHE_DIR="$root/.zig-cache-autonomous/local" \
    "${ZIG:-zig}" "$@" || zig_status=$?

budget_status=0
"$root/scripts/check_zig_cache_budget.sh" --autonomous || budget_status=$?

if [ "$zig_status" -ne 0 ]; then
    exit "$zig_status"
fi
exit "$budget_status"
