#!/bin/sh
set -eu

if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
    printf 'usage: %s <library> <bundle.lv2> <metadata-generator> [ui-library]\n' "$0" >&2
    exit 2
fi

library=$1
bundle=$2
metadata_generator=$3
ui_library=${4-}

case "$bundle" in
    *.lv2) ;;
    *)
        printf 'LV2 bundle path must end in .lv2: %s\n' "$bundle" >&2
        exit 2
        ;;
esac

for source in "$library" "$metadata_generator" ${ui_library:+"$ui_library"}; do
    if [ ! -f "$source" ]; then
        printf 'required LV2 bundle input is missing: %s\n' "$source" >&2
        exit 2
    fi
done

binary_name=$(basename "$library")
case "$binary_name" in
    *[!A-Za-z0-9._-]*)
        printf 'unsupported LV2 binary filename: %s\n' "$binary_name" >&2
        exit 2
        ;;
esac
ui_binary_name=-
if [ -n "$ui_library" ]; then
    ui_binary_name=$(basename "$ui_library")
    case "$ui_binary_name" in
        *[!A-Za-z0-9._-]*)
            printf 'unsupported LV2 UI binary filename: %s\n' "$ui_binary_name" >&2
            exit 2
            ;;
    esac
    if [ "$ui_binary_name" = "$binary_name" ]; then
        printf 'LV2 core and UI binaries must have distinct filenames\n' >&2
        exit 2
    fi
fi

parent=$(dirname "$bundle")
mkdir -p "$parent"
staging=$(mktemp -d "$parent/.lv2-bundle.XXXXXX")
backup=
cleanup() {
    if [ -n "$staging" ]; then
        rm -rf "$staging"
    fi
    if [ -n "$backup" ]; then
        if [ -e "$bundle" ] || [ -L "$bundle" ]; then
            rm -rf "$backup"
        elif ! mv "$backup" "$bundle"; then
            printf 'failed to restore prior LV2 bundle: %s\n' "$bundle" >&2
        fi
    fi
}
on_hup() {
    exit 129
}
on_int() {
    exit 130
}
on_term() {
    exit 143
}
trap cleanup EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM

cp "$library" "$staging/$binary_name"
if [ -n "$ui_library" ]; then
    cp "$ui_library" "$staging/$ui_binary_name"
fi
"$metadata_generator" \
    "$binary_name" \
    "$staging/manifest.ttl" \
    "$staging/plugin.ttl" \
    "$staging/presets.ttl" \
    "$ui_binary_name"

if [ -e "$bundle" ] || [ -L "$bundle" ]; then
    backup=$(mktemp -d "$parent/.lv2-bundle-backup.XXXXXX")
    rmdir "$backup"
    mv "$bundle" "$backup"
fi
mv "$staging" "$bundle"
staging=
if [ -n "$backup" ]; then
    rm -rf "$backup"
    backup=
fi
trap - EXIT HUP INT TERM
