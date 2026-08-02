#!/bin/sh
set -eu

destination=${1:?missing destination path}
fixture_url=https://sofacoustics.org/data/database/hutubs/pp1_HRIRs_measured.sofa
fixture_sha256=f626d335c590db687608fff5992972725230d594067b2e6906893bddc85e5173

# HUTUBS participant 1 measured HRIRs, CC BY 4.0, DOI 10.14279/depositonce-8487
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

partial=${destination}.partial
trap 'rm -f "$partial"' EXIT HUP INT TERM
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$partial" "$fixture_url"
verify_fixture "$partial"
mv "$partial" "$destination"
trap - EXIT HUP INT TERM
