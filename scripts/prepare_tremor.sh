#!/bin/sh
set -eu

destination=${1:?missing destination path}
revision=820fb3237ea81af44c9cc468c8b4e20128e3e5ad
source_url=https://gitlab.xiph.org/xiph/tremor/-/archive/$revision/tremor-$revision.tar.gz
source_sha256=3974455fe776a41615f60e05c85733c1bb78bff310794cbb0236f8af4b44f583
identity="Tremor $revision generic C fixed-point decoder BSD-3-Clause"

verify_installation() {
    test -f "$1/COPYING"
    test -f "$1/ivorbiscodec.h"
    test -f "$1/ivorbisfile.h"
    test -f "$1/vorbisfile.c"
    test -f "$1/synthesis.c"
    test "$(cat "$1/zig-vst3-tremor-version")" = "$identity"
}

verify_archive() {
    archive=$1
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s  %s\n' "$source_sha256" "$archive" | sha256sum -c -
    else
        actual=$(shasum -a 256 "$archive" | awk '{print $1}')
        test "$actual" = "$source_sha256"
    fi
}

if test -e "$destination"; then
    verify_installation "$destination"
    exit 0
fi

mkdir -p "$(dirname "$destination")"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-tremor.XXXXXX")
partial=$(mktemp -d "${destination}.partial.XXXXXX")
cleanup() {
    rm -rf -- "$temporary" "$partial"
}
on_hup() { exit 129; }
on_int() { exit 130; }
on_term() { exit 143; }
trap cleanup EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM

archive=$temporary/tremor.tar.gz
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$archive" "$source_url"
verify_archive "$archive"
tar -xzf "$archive" -C "$partial" --strip-components=1
printf '%s\n' "$identity" >"$partial/zig-vst3-tremor-version"
verify_installation "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
