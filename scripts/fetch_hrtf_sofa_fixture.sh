#!/bin/sh
set -eu

destination=${1:?missing destination path}
fixture_url=https://sofacoustics.org/data/database/viking/subj_A.sofa
fixture_sha256=b7d8215a3bf35ddf216b98ac029c274c683ae38138abac5bff7a9c5afa4e2a4c

# Viking HRTF Dataset v2, CC BY 4.0, DOI 10.5281/zenodo.4160401
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
on_hup() {
    exit 129
}
on_int() {
    exit 130
}
on_term() {
    exit 143
}
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
