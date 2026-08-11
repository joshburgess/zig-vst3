#!/bin/sh
set -eu

destination=${1:?missing destination path}
source_url=https://github.com/hoene/libmysofa/archive/6cc5b15a73e9bd97810d03767082edda7f315881.tar.gz
source_sha256=cf047bd684d28dca23d7d5b662c538b24392c620719f15d642594fc1405e24f6
source_directory=libmysofa-6cc5b15a73e9bd97810d03767082edda7f315881
identity='libmysofa 1.3.5 commit 6cc5b15a73e9bd97810d03767082edda7f315881'

verify_installation() {
    test -f "$1/include/mysofa.h"
    test -f "$1/lib/libmysofa.a"
    test "$(cat "$1/zig-vst3-renderer-version")" = "$identity"
}

if test -e "$destination"; then
    verify_installation "$destination"
    exit 0
fi

mkdir -p "$(dirname "$destination")"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-libmysofa.XXXXXX")
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

archive=$temporary/libmysofa.tar.gz
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$archive" "$source_url"
if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$source_sha256" "$archive" | sha256sum -c -
else
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    test "$actual" = "$source_sha256"
fi
tar -xzf "$archive" -C "$temporary"
cmake -S "$temporary/$source_directory" -B "$temporary/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$partial" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_TESTS=OFF
cmake --build "$temporary/build" --config Release --parallel 2
cmake --install "$temporary/build" --config Release
printf '%s\n' "$identity" > "$partial/zig-vst3-renderer-version"
verify_installation "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
