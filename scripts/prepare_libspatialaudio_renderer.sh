#!/bin/sh
set -eu

destination=${1:?missing destination path}
source_url=https://github.com/videolan/libspatialaudio/releases/download/0.4.1/libspatialaudio-0.4.1.tar.xz
source_sha256=215980432e3980d7733caa7d5051887f0d604cb8a265adf1311087c0fe7d3892
source_directory=libspatialaudio-0.4.1
identity='libspatialaudio 0.4.1 commit d149ed9744fd399b835c6f2920511f8cbcfce5ea'

verify_installation() {
    test -f "$1/include/spatialaudio/AmbisonicDecoder.h"
    test -f "$1/lib/libspatialaudio.a"
    test "$(cat "$1/zig-vst3-renderer-version")" = "$identity"
}

if test -e "$destination"; then
    verify_installation "$destination"
    exit 0
fi

mkdir -p "$(dirname "$destination")"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-libspatialaudio.XXXXXX")
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

archive=$temporary/libspatialaudio.tar.xz
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$archive" "$source_url"
if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$source_sha256" "$archive" | sha256sum -c -
else
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    test "$actual" = "$source_sha256"
fi
tar -xJf "$archive" -C "$temporary"
cmake -S "$temporary/$source_directory" -B "$temporary/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$partial" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DHAVE_MIT_HRTF=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_MySofa=TRUE
cmake --build "$temporary/build" --config Release --parallel 2
cmake --install "$temporary/build" --config Release
printf '%s\n' "$identity" > "$partial/zig-vst3-renderer-version"
verify_installation "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
