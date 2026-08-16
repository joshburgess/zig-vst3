#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cache_name=.zig-cache
if [ "${ZIG_VST3_CACHE_LIMIT_KIB+x}" = x ]; then
    limit_kib=$ZIG_VST3_CACHE_LIMIT_KIB
else
    limit_kib=67108864
fi

usage() {
    printf 'usage: %s [--autonomous]\n' "$0" >&2
    exit 2
}

case "$#" in
    0) ;;
    1)
        if [ "$1" != --autonomous ]; then
            usage
        fi
        cache_name=.zig-cache-autonomous
        ;;
    *) usage ;;
esac

case "$limit_kib" in
    ''|*[!0-9]*)
        printf 'ZIG_VST3_CACHE_LIMIT_KIB must be a positive integer\n' >&2
        exit 2
        ;;
esac
if [ "${#limit_kib}" -gt 15 ] || [ "$limit_kib" -eq 0 ]; then
    printf 'ZIG_VST3_CACHE_LIMIT_KIB must be a positive integer\n' >&2
    exit 2
fi

cache_dir="$root/$cache_name"

if [ ! -f "$root/build.zig" ]; then
    printf 'repository marker is missing: %s\n' "$root/build.zig" >&2
    exit 1
fi
if [ -L "$cache_dir" ]; then
    printf 'refusing to inspect a symbolic link: %s\n' "$cache_dir" >&2
    exit 1
fi
if [ ! -e "$cache_dir" ]; then
    printf 'cache budget passed: cache is absent: %s\n' "$cache_dir"
    exit 0
fi
if [ ! -d "$cache_dir" ]; then
    printf 'cache path is not a directory: %s\n' "$cache_dir" >&2
    exit 1
fi

size_kib=$(du -sk "$cache_dir" | awk '{print $1}')
case "$size_kib" in
    ''|*[!0-9]*)
        printf 'could not measure cache size: %s\n' "$cache_dir" >&2
        exit 1
        ;;
esac

if [ "$size_kib" -gt "$limit_kib" ]; then
    printf 'cache budget exceeded: %s KiB exceeds %s KiB: %s\n' \
        "$size_kib" "$limit_kib" "$cache_dir" >&2
    if [ "$cache_name" = .zig-cache-autonomous ]; then
        printf 'inspect with %s --autonomous, then remove with %s --autonomous --apply\n' \
            "$root/scripts/clean_zig_cache.sh" \
            "$root/scripts/clean_zig_cache.sh" >&2
    else
        printf 'inspect with %s, then remove with %s --apply\n' \
            "$root/scripts/clean_zig_cache.sh" \
            "$root/scripts/clean_zig_cache.sh" >&2
    fi
    exit 1
fi

printf 'cache budget passed: %s KiB of %s KiB: %s\n' \
    "$size_kib" "$limit_kib" "$cache_dir"
