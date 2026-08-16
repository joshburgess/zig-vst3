#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-spatial-sources.XXXXXX")
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
mkdir -p "$target/libmysofa-6cc5b15a73e9bd97810d03767082edda7f315881"
mkdir -p "$target/libspatialaudio-0.4.1"
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
    mkdir -p "$prefix/lib"
    case "$FAKE_RENDERER_KIND" in
        mysofa)
            mkdir -p "$prefix/include"
            : >"$prefix/include/mysofa.h"
            : >"$prefix/lib/libmysofa.a"
            ;;
        spatialaudio)
            mkdir -p "$prefix/include/spatialaudio"
            : >"$prefix/include/spatialaudio/AmbisonicDecoder.h"
            : >"$prefix/lib/libspatialaudio.a"
            ;;
        *) exit 2 ;;
    esac
fi
SCRIPT
chmod +x "$fake_bin"/*

assert_no_partial() {
    if find "$(dirname -- "$1")" -maxdepth 1 \
        -name "$(basename -- "$1").partial.*" | grep -q .; then
        printf 'Spatial renderer preparation left a partial directory\n' >&2
        exit 1
    fi
}

exercise() {
    script=$1
    kind=$2
    destination=$root/$kind
    curl_log=$root/$kind-curl.log
    cmake_prefix=$root/$kind-cmake-prefix

    if PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        "$script" >/dev/null 2>&1; then
        printf '%s accepted a missing destination\n' "$script" >&2
        exit 1
    fi

    PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        "$script" "$destination"
    test -d "$destination"
    assert_no_partial "$destination"
    PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        "$script" "$destination"
    test "$(wc -l <"$curl_log" | tr -d ' ')" -eq 1
    rm -rf -- "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        FAKE_CURL_MODE=fail "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 7
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        FAKE_HASH_STATUS=1 "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 1
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        FAKE_CMAKE_STATUS=6 "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 6
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_RENDERER_KIND="$kind" \
        FAKE_CURL_LOG="$curl_log" FAKE_CMAKE_PREFIX="$cmake_prefix" \
        FAKE_CURL_MODE=interrupt "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 143
    test ! -e "$destination"
    assert_no_partial "$destination"
}

exercise "$repo/scripts/prepare_libmysofa_renderer.sh" mysofa
exercise "$repo/scripts/prepare_libspatialaudio_renderer.sh" spatialaudio
printf 'Spatial renderer source preparation runner passed\n'
