#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cache_name=.zig-cache
mode=inspect

usage() {
    printf 'usage: %s [--autonomous] [inspect|--apply]\n' "$0" >&2
    exit 2
}

case "$#" in
    0) ;;
    1)
        case "$1" in
            --autonomous) cache_name=.zig-cache-autonomous ;;
            inspect|--apply) mode="$1" ;;
            *) usage ;;
        esac
        ;;
    2)
        if [ "$1" != --autonomous ]; then
            usage
        fi
        cache_name=.zig-cache-autonomous
        case "$2" in
            inspect|--apply) mode="$2" ;;
            *) usage ;;
        esac
        ;;
    *) usage ;;
esac

cache_dir="$root/$cache_name"

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
    if [ "$cache_name" = .zig-cache-autonomous ]; then
        printf 'run %s --autonomous --apply to remove this rebuildable cache\n' "$0"
    else
        printf 'run %s --apply to remove this rebuildable cache\n' "$0"
    fi
    exit 0
fi

rm -rf -- "$cache_dir"
printf 'removed rebuildable cache: %s\n' "$cache_dir"
