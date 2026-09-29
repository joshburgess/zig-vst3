#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-hrtf-fetch.XXXXXX")
cleanup() {
    rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

fake_bin=$fixture/bin
mkdir -p "$fake_bin"

cat >"$fake_bin/curl" <<'SCRIPT'
#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        shift
        output=$1
    fi
    shift
done
if [ -z "$output" ]; then
    exit 2
fi
printf '%s\n' "$output" >>"$FAKE_CURL_OUTPUTS"
printf 'downloaded fixture\n' >"$output"
case "${FAKE_CURL_MODE:-success}" in
    success) exit 0 ;;
    fail) exit 7 ;;
    interrupt)
        kill -TERM "$PPID"
        exit 9
        ;;
    *) exit 2 ;;
esac
SCRIPT
chmod +x "$fake_bin/curl"

cat >"$fake_bin/sha256sum" <<'SCRIPT'
#!/bin/sh
set -eu
cat >/dev/null
exit "${FAKE_HASH_STATUS:-0}"
SCRIPT
chmod +x "$fake_bin/sha256sum"

assert_no_partial() {
    destination=$1
    parent=$(dirname -- "$destination")
    name=$(basename -- "$destination")
    if find "$parent" -maxdepth 1 -name "$name.partial.*" | grep -q .; then
        printf 'HRTF fixture fetch left a partial file\n' >&2
        exit 1
    fi
}

for fetcher in \
    fetch_hrtf_sofa_fixture.sh \
    fetch_hutubs_hrtf_sofa_fixture.sh
do
    output_log=$fixture/$fetcher.outputs
    destination=$fixture/$fetcher.sofa

    if PATH="$fake_bin:$PATH" FAKE_CURL_OUTPUTS="$output_log" \
        "$root/scripts/$fetcher" >/dev/null 2>&1; then
        printf '%s accepted a missing destination\n' "$fetcher" >&2
        exit 1
    fi

    printf 'existing fixture\n' >"$destination"
    PATH="$fake_bin:$PATH" FAKE_CURL_OUTPUTS="$output_log" \
        "$root/scripts/$fetcher" "$destination"
    grep -q '^existing fixture$' "$destination"
    if [ -e "$output_log" ]; then
        printf '%s downloaded over an accepted fixture\n' "$fetcher" >&2
        exit 1
    fi

    rm "$destination"
    PATH="$fake_bin:$PATH" FAKE_CURL_OUTPUTS="$output_log" \
        "$root/scripts/$fetcher" "$destination"
    grep -q '^downloaded fixture$' "$destination"
    test "$(wc -l <"$output_log" | tr -d ' ')" -eq 1
    assert_no_partial "$destination"

    rm "$destination"
    set +e
    PATH="$fake_bin:$PATH" FAKE_CURL_OUTPUTS="$output_log" \
    FAKE_CURL_MODE=fail \
        "$root/scripts/$fetcher" "$destination" >/dev/null 2>&1
    download_status=$?
    set -e
    if [ "$download_status" -ne 7 ]; then
        printf '%s changed the download failure status\n' "$fetcher" >&2
        exit 1
    fi
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_CURL_OUTPUTS="$output_log" \
    FAKE_HASH_STATUS=1 \
        "$root/scripts/$fetcher" "$destination" >/dev/null 2>&1
    hash_status=$?
    set -e
    if [ "$hash_status" -ne 1 ]; then
        printf '%s changed the hash failure status\n' "$fetcher" >&2
        exit 1
    fi
    test ! -e "$destination"
    assert_no_partial "$destination"

    set +e
    PATH="$fake_bin:$PATH" FAKE_CURL_OUTPUTS="$output_log" \
    FAKE_CURL_MODE=interrupt \
        "$root/scripts/$fetcher" "$destination" >/dev/null 2>&1
    interrupt_status=$?
    set -e
    if [ "$interrupt_status" -ne 143 ]; then
        printf '%s returned %s after TERM instead of 143\n' \
            "$fetcher" "$interrupt_status" >&2
        exit 1
    fi
    test ! -e "$destination"
    assert_no_partial "$destination"
done

printf 'HRTF fixture fetch runner passed\n'
