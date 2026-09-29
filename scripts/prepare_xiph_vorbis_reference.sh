#!/bin/sh
set -eu

destination=${1:?missing destination path}
ogg_url=https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz
ogg_sha256=c4d91be36fc8e54deae7575241e03f4211eb102afb3fc0775fbbc1b740016705
vorbis_url=https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz
vorbis_sha256=b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b
identity='libogg 1.3.5 and libvorbis 1.3.7'

verify_installation() {
    test -f "$1/include/ogg/ogg.h"
    test -f "$1/include/vorbis/codec.h"
    test -f "$1/include/vorbis/vorbisenc.h"
    test -f "$1/lib/libogg.a"
    test -f "$1/lib/libvorbis.a"
    test -f "$1/lib/libvorbisenc.a"
    test "$(cat "$1/zig-vst3-xiph-version")" = "$identity"
}

verify_archive() {
    expected=$1
    archive=$2
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s  %s\n' "$expected" "$archive" | sha256sum -c -
    else
        actual=$(shasum -a 256 "$archive" | awk '{print $1}')
        test "$actual" = "$expected"
    fi
}

if test -e "$destination"; then
    verify_installation "$destination"
    exit 0
fi

mkdir -p "$(dirname "$destination")"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-xiph-vorbis.XXXXXX")
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

ogg_archive=$temporary/libogg.tar.xz
vorbis_archive=$temporary/libvorbis.tar.xz
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$ogg_archive" "$ogg_url"
verify_archive "$ogg_sha256" "$ogg_archive"
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$vorbis_archive" "$vorbis_url"
verify_archive "$vorbis_sha256" "$vorbis_archive"
tar -xJf "$ogg_archive" -C "$temporary"
tar -xJf "$vorbis_archive" -C "$temporary"

CC='zig cc' cmake \
    -S "$temporary/libogg-1.3.5" \
    -B "$temporary/ogg-build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$partial" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DINSTALL_DOCS=OFF
cmake --build "$temporary/ogg-build" --config Release --parallel 2
cmake --install "$temporary/ogg-build" --config Release

CC='zig cc' cmake \
    -S "$temporary/libvorbis-1.3.7" \
    -B "$temporary/vorbis-build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$partial" \
    -DCMAKE_PREFIX_PATH="$partial" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_SHARED_LIBS=OFF
cmake --build "$temporary/vorbis-build" --config Release --parallel 2
cmake --install "$temporary/vorbis-build" --config Release

printf '%s\n' "$identity" >"$partial/zig-vst3-xiph-version"
verify_installation "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
