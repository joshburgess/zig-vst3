#!/bin/sh
set -eu

mode=${1:-inspect}
case "$mode" in
    inspect|--apply) ;;
    *)
        printf 'usage: %s [inspect|--apply]\n' "$0" >&2
        exit 2
        ;;
esac

temporary_root=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd)
found=0
active=0

for path in "$temporary_root"/zig-vst3-installed-consumer.*; do
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        continue
    fi
    found=1
    if [ -L "$path" ]; then
        printf 'refusing symbolic-link staging tree: %s\n' "$path" >&2
        exit 1
    fi
    if [ ! -d "$path" ]; then
        printf 'refusing non-directory staging path: %s\n' "$path" >&2
        exit 1
    fi
done

for path in "$temporary_root"/zig-vst3-installed-consumer.*; do
    if [ ! -d "$path" ] || [ -L "$path" ]; then
        continue
    fi
    if [ -e "$path/.active" ] || [ -L "$path/.active" ]; then
        active=1
        printf 'active staging tree retained: %s\n' "$path"
        continue
    fi

    du -sh "$path"
    if [ "$mode" = --apply ]; then
        rm -rf -- "$path"
        printf 'removed completed staging tree: %s\n' "$path"
    fi
done

if [ "$found" -eq 0 ]; then
    printf 'no installed-package staging trees found under %s\n' "$temporary_root"
elif [ "$mode" = inspect ]; then
    printf 'run %s --apply to remove completed trees; active trees remain untouched\n' "$0"
elif [ "$active" -eq 1 ]; then
    printf 'completed staging trees removed; active trees remain\n'
else
    printf 'completed installed-package staging trees removed\n'
fi
