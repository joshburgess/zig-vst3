#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-stb-vorbis-source.XXXXXX")
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
printf 'stb source\n' >"$destination"
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
chmod +x "$fake_bin"/*

script=$repo/scripts/prepare_stb_vorbis.sh
destination=$root/stb
curl_log=$root/curl.log

assert_no_partial() {
    if find "$(dirname -- "$destination")" -maxdepth 1 \
        -name "$(basename -- "$destination").partial.*" | grep -q .; then
        printf 'stb_vorbis preparation left a partial directory\n' >&2
        exit 1
    fi
}

if PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" >/dev/null 2>&1; then
    printf 'stb_vorbis preparation accepted a missing destination\n' >&2
    exit 1
fi

PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" "$destination"
test -d "$destination"
assert_no_partial
PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" "$destination"
test "$(wc -l <"$curl_log" | tr -d ' ')" -eq 1

printf 'wrong identity\n' >"$destination/zig-vst3-stb-vorbis-version"
if PATH="$fake_bin:$PATH" FAKE_CURL_LOG="$curl_log" \
    "$script" "$destination" >/dev/null 2>&1; then
    printf 'stb_vorbis preparation accepted a mismatched installation\n' >&2
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

printf 'stb_vorbis source preparation runner passed\n'
