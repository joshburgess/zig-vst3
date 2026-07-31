#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-clean-cache.XXXXXX")

cleanup() {
    rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$fixture/scripts" "$fixture/.zig-cache/o"
cp "$root/scripts/clean_zig_cache.sh" "$fixture/scripts/clean_zig_cache.sh"
touch "$fixture/build.zig" "$fixture/.zig-cache/o/object"

"$fixture/scripts/clean_zig_cache.sh" inspect >/dev/null
test -f "$fixture/.zig-cache/o/object"

if "$fixture/scripts/clean_zig_cache.sh" invalid >/dev/null 2>&1; then
    printf 'cache cleaner accepted an invalid mode\n' >&2
    exit 1
fi

"$fixture/scripts/clean_zig_cache.sh" --apply >/dev/null
test ! -e "$fixture/.zig-cache"
"$fixture/scripts/clean_zig_cache.sh" --apply >/dev/null

mkdir "$fixture/cache-target"
ln -s "$fixture/cache-target" "$fixture/.zig-cache"
if "$fixture/scripts/clean_zig_cache.sh" --apply >/dev/null 2>&1; then
    printf 'cache cleaner followed a symbolic link\n' >&2
    exit 1
fi
test -d "$fixture/cache-target"

rm "$fixture/.zig-cache"
touch "$fixture/.zig-cache"
if "$fixture/scripts/clean_zig_cache.sh" --apply >/dev/null 2>&1; then
    printf 'cache cleaner accepted a non-directory target\n' >&2
    exit 1
fi
test -f "$fixture/.zig-cache"

rm "$fixture/.zig-cache" "$fixture/build.zig"
mkdir "$fixture/.zig-cache"
if "$fixture/scripts/clean_zig_cache.sh" --apply >/dev/null 2>&1; then
    printf 'cache cleaner accepted a repository without its build marker\n' >&2
    exit 1
fi
test -d "$fixture/.zig-cache"

printf 'cache cleaner runner passed\n'
