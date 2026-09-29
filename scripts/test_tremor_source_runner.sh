#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-tremor-source.XXXXXX")
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
for file in COPYING ivorbiscodec.h ivorbisfile.h vorbisfile.c synthesis.c; do
    : >"$target/$file"
done
SCRIPT
chmod +x "$fake_bin"/*

script=$repo/scripts/prepare_tremor.sh
destination=$root/tremor
curl_log=$root/curl.log

assert_no_partial() {
    if find "$(dirname -- "$destination")" -maxdepth 1 \
        -name "$(basename -- "$destination").partial.*" | grep -q .; then
        printf 'Tremor preparation left a partial directory\n' >&2
        exit 1
    fi
}

if PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" >/dev/null 2>&1; then
    printf 'Tremor preparation accepted a missing destination\n' >&2
    exit 1
fi

PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" "$destination"
test -d "$destination"
assert_no_partial
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" "$destination"
test "$(wc -l <"$curl_log" | tr -d ' ')" -eq 1

printf 'wrong identity\n' >"$destination/zig-vst3-tremor-version"
if PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" "$destination" >/dev/null 2>&1; then
    printf 'Tremor preparation accepted a mismatched installation\n' >&2
    exit 1
fi
rm -rf -- "$destination"

expect_failure() {
    expected=$1
    shift
    set +e
    PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
        "$@" "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq "$expected"
    test ! -e "$destination"
    assert_no_partial
}

expect_failure 7 env FAKE_CURL_MODE=fail
expect_failure 1 env FAKE_HASH_STATUS=1
expect_failure 143 env FAKE_CURL_MODE=interrupt

printf 'Tremor source preparation runner passed\n'
