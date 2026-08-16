#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-xiph-vorbis-source.XXXXXX")
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
fake_bin=$root/bin
mkdir "$fake_bin"

cat >"$fake_bin/curl" <<'SCRIPT'
#!/bin/sh
set -eu
for argument do
    previous=${current-}
    current=$argument
    if [ "$previous" = -o ]; then destination=$current; fi
done
printf 'archive\n' >"$destination"
printf 'download\n' >>"$FAKE_CURL_LOG"
case "${FAKE_CURL_MODE:-success}" in
    success) exit 0 ;;
    fail) exit 7 ;;
    interrupt) kill -TERM "$PPID"; exit 9 ;;
    *) exit 2 ;;
esac
SCRIPT
cat >"$fake_bin/sha256sum" <<'SCRIPT'
#!/bin/sh
cat >/dev/null
exit "${FAKE_HASH_STATUS:-0}"
SCRIPT
cat >"$fake_bin/tar" <<'SCRIPT'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    if [ "$1" = -C ]; then shift; target=$1; fi
    shift
done
mkdir -p "$target/libogg-1.3.5" "$target/libvorbis-1.3.7"
SCRIPT
cat >"$fake_bin/cmake" <<'SCRIPT'
#!/bin/sh
set -eu
[ "${FAKE_CMAKE_STATUS:-0}" -eq 0 ] || exit "$FAKE_CMAKE_STATUS"
for argument do
    case "$argument" in
        -DCMAKE_INSTALL_PREFIX=*)
            printf '%s\n' "${argument#*=}" >"$FAKE_CMAKE_PREFIX"
            ;;
    esac
done
if [ "${1-}" = --install ]; then
    prefix=$(cat "$FAKE_CMAKE_PREFIX")
    mkdir -p "$prefix/include/ogg" "$prefix/include/vorbis" "$prefix/lib"
    : >"$prefix/include/ogg/ogg.h"
    : >"$prefix/include/vorbis/codec.h"
    : >"$prefix/include/vorbis/vorbisenc.h"
    : >"$prefix/lib/libogg.a"
    : >"$prefix/lib/libvorbis.a"
    : >"$prefix/lib/libvorbisenc.a"
fi
SCRIPT
chmod +x "$fake_bin"/*

script=$repo/scripts/prepare_xiph_vorbis_reference.sh
destination=$root/xiph
curl_log=$root/curl.log
cmake_prefix=$root/cmake-prefix

assert_no_partial() {
    if find "$(dirname -- "$destination")" -maxdepth 1 \
        -name "$(basename -- "$destination").partial.*" | grep -q .; then
        printf 'Xiph Vorbis preparation left a partial directory\n' >&2
        exit 1
    fi
}

if PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" "$script" >/dev/null 2>&1; then
    printf 'Xiph Vorbis preparation accepted a missing destination\n' >&2
    exit 1
fi

PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" "$script" "$destination"
test -d "$destination"
assert_no_partial
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" "$script" "$destination"
test "$(wc -l <"$curl_log" | tr -d ' ')" -eq 2
rm -rf -- "$destination"

set +e
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" FAKE_CURL_MODE=fail \
    "$script" "$destination" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 7
test ! -e "$destination"
assert_no_partial

set +e
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" FAKE_HASH_STATUS=1 \
    "$script" "$destination" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 1
test ! -e "$destination"
assert_no_partial

set +e
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" FAKE_CMAKE_STATUS=6 \
    "$script" "$destination" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 6
test ! -e "$destination"
assert_no_partial

set +e
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    FAKE_CMAKE_PREFIX="$cmake_prefix" FAKE_CURL_MODE=interrupt \
    "$script" "$destination" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 143
test ! -e "$destination"
assert_no_partial

printf 'Xiph Vorbis source preparation runner passed\n'
