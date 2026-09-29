#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-mp3-sources.XXXXXX")
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
fake_bin=$root/bin
mkdir "$fake_bin"

cat >"$fake_bin/curl" <<'SCRIPT'
#!/bin/sh
set -eu
for output do
    previous=${current-}
    current=$output
    if [ "$previous" = -o ]; then
        destination=$current
    fi
done
printf 'archive\n' >"$destination"
case "${FAKE_CURL_MODE:-success}" in
    success) exit 0 ;;
    fail) exit 7 ;;
    interrupt) kill -TERM "$PPID"; exit 9 ;;
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
mkdir -p "$target/hmp3-7f7dfc7680db3c05f8e4a8fbd9861cbb06427d92"
SCRIPT
cat >"$fake_bin/make" <<'SCRIPT'
#!/bin/sh
set -eu
[ "${FAKE_MAKE_STATUS:-0}" -eq 0 ] || exit "$FAKE_MAKE_STATUS"
[ "$1" = -C ]
output=$2/builds/release/hmp3
mkdir -p "$(dirname -- "$output")"
cat >"$output" <<'ENCODER'
#!/bin/sh
printf 'hmp3 MPEG Layer III audio encoder 5.2.4\n' >&2
ENCODER
chmod +x "$output"
SCRIPT
chmod +x "$fake_bin"/*

assert_no_partial() {
    if find "$(dirname -- "$1")" -maxdepth 1 \
        -name "$(basename -- "$1").partial.*" | grep -q .; then
        printf 'MP3 external source preparation left a partial file\n' >&2
        exit 1
    fi
}

exercise() {
    script=$1
    destination=$2
    if PATH="$fake_bin:$PATH" "$script" >/dev/null 2>&1; then
        printf 'MP3 external source script accepted a missing destination\n' >&2
        exit 1
    fi
    PATH="$fake_bin:$PATH" "$script" "$destination"
    test -e "$destination"
    assert_no_partial "$destination"
    rm "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_CURL_MODE=fail \
        "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 7
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_HASH_STATUS=1 \
        "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 1
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_CURL_MODE=interrupt \
        "$script" "$destination" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 143
    test ! -e "$destination"
    assert_no_partial "$destination"
}

exercise "$repo/scripts/fetch_androidx_vbri_fixture.sh" "$root/androidx.mp3"
exercise "$repo/scripts/prepare_helix_mp3_encoder.sh" "$root/hmp3"
set +e
PATH="$fake_bin:$PATH" FAKE_MAKE_STATUS=6 \
    "$repo/scripts/prepare_helix_mp3_encoder.sh" \
    "$root/hmp3-build-failure" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 6
test ! -e "$root/hmp3-build-failure"
assert_no_partial "$root/hmp3-build-failure"
printf 'MP3 external source preparation runner passed\n'
