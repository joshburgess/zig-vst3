#!/bin/sh
set -eu

destination=${1:?missing destination path}
fixture_url=https://raw.githubusercontent.com/androidx/media/3eb36d67bd90d6d962df26dfdf29701a45902b4a/libraries/test_data/src/test/assets/media/mp3/bear-vbr-vbri-header.mp3
fixture_sha256=efcb9b44bae21958c96b8d2601e75ba313154cb4170e3a9a3df4f6f0ec1e9a7c

# AndroidX Media test asset, Apache 2.0, commit 3eb36d67bd90d6d962df26dfdf29701a45902b4a.
verify_fixture() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s  %s\n' "$fixture_sha256" "$1" | sha256sum -c -
    else
        actual=$(shasum -a 256 "$1" | awk '{print $1}')
        test "$actual" = "$fixture_sha256"
    fi
}

if test -e "$destination"; then
    verify_fixture "$destination"
    exit 0
fi

partial=$(mktemp "${destination}.partial.XXXXXX")
cleanup() {
    if [ -n "$partial" ]; then
        rm -f -- "$partial"
    fi
}
on_hup() { exit 129; }
on_int() { exit 130; }
on_term() { exit 143; }
trap cleanup EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$partial" "$fixture_url"
verify_fixture "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
