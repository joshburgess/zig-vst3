#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cache_dir="$root/.zig-cache"
mode="${1:-inspect}"

if [ "$#" -gt 1 ]; then
    printf 'usage: %s [inspect|--apply]\n' "$0" >&2
    exit 2
fi

case "$mode" in
    inspect|--apply) ;;
    *)
        printf 'usage: %s [inspect|--apply]\n' "$0" >&2
        exit 2
        ;;
esac

if [ ! -f "$root/build.zig" ]; then
    printf 'repository marker is missing: %s\n' "$root/build.zig" >&2
    exit 1
fi

if [ -L "$cache_dir" ]; then
    printf 'refusing to operate on a symbolic link: %s\n' "$cache_dir" >&2
    exit 1
fi

if [ ! -e "$cache_dir" ]; then
    printf 'cache is absent: %s\n' "$cache_dir"
    exit 0
fi

if [ ! -d "$cache_dir" ]; then
    printf 'cache path is not a directory: %s\n' "$cache_dir" >&2
    exit 1
fi

du -sh "$cache_dir"

if [ "$mode" = inspect ]; then
    printf 'run %s --apply to remove this rebuildable cache\n' "$0"
    exit 0
fi

rm -rf -- "$cache_dir"
printf 'removed rebuildable cache: %s\n' "$cache_dir"
