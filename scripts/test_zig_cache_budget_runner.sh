#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-cache-budget.XXXXXX")

cleanup() {
    rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$fixture/scripts"
cp "$root/scripts/check_zig_cache_budget.sh" "$fixture/scripts/"
touch "$fixture/build.zig"

ZIG_VST3_CACHE_LIMIT_KIB=1 \
    "$fixture/scripts/check_zig_cache_budget.sh" >/dev/null
ZIG_VST3_CACHE_LIMIT_KIB=1 \
    "$fixture/scripts/check_zig_cache_budget.sh" --autonomous >/dev/null

mkdir "$fixture/.zig-cache" "$fixture/.zig-cache-autonomous"
printf 'ordinary cache fixture\n' >"$fixture/.zig-cache/object"
printf 'autonomous cache fixture\n' >"$fixture/.zig-cache-autonomous/object"

ZIG_VST3_CACHE_LIMIT_KIB=1048576 \
    "$fixture/scripts/check_zig_cache_budget.sh" >/dev/null
ZIG_VST3_CACHE_LIMIT_KIB=1048576 \
    "$fixture/scripts/check_zig_cache_budget.sh" --autonomous >/dev/null

if ZIG_VST3_CACHE_LIMIT_KIB=1 \
    "$fixture/scripts/check_zig_cache_budget.sh" \
        >"$fixture/ordinary.txt" 2>&1
then
    printf 'cache budget accepted an oversized ordinary cache\n' >&2
    exit 1
fi
grep -q 'clean_zig_cache.sh --apply' "$fixture/ordinary.txt"

if ZIG_VST3_CACHE_LIMIT_KIB=1 \
    "$fixture/scripts/check_zig_cache_budget.sh" --autonomous \
        >"$fixture/autonomous.txt" 2>&1
then
    printf 'cache budget accepted an oversized autonomous cache\n' >&2
    exit 1
fi
grep -q 'clean_zig_cache.sh --autonomous --apply' \
    "$fixture/autonomous.txt"

for invalid_limit in '' 0 invalid 1.5 -1 9999999999999999; do
    if ZIG_VST3_CACHE_LIMIT_KIB=$invalid_limit \
        "$fixture/scripts/check_zig_cache_budget.sh" >/dev/null 2>&1
    then
        printf 'cache budget accepted invalid limit: %s\n' \
            "$invalid_limit" >&2
        exit 1
    fi
done

if "$fixture/scripts/check_zig_cache_budget.sh" invalid >/dev/null 2>&1; then
    printf 'cache budget accepted an invalid argument\n' >&2
    exit 1
fi

mv "$fixture/.zig-cache" "$fixture/cache-target"
ln -s "$fixture/cache-target" "$fixture/.zig-cache"
if "$fixture/scripts/check_zig_cache_budget.sh" >/dev/null 2>&1; then
    printf 'cache budget followed a symbolic link\n' >&2
    exit 1
fi
rm "$fixture/.zig-cache"

rm -rf "$fixture/.zig-cache-autonomous"
touch "$fixture/.zig-cache-autonomous"
if "$fixture/scripts/check_zig_cache_budget.sh" --autonomous \
    >/dev/null 2>&1
then
    printf 'cache budget accepted a non-directory cache\n' >&2
    exit 1
fi

rm "$fixture/build.zig"
if "$fixture/scripts/check_zig_cache_budget.sh" >/dev/null 2>&1; then
    printf 'cache budget accepted a repository without its build marker\n' >&2
    exit 1
fi

printf 'cache budget runner passed\n'
