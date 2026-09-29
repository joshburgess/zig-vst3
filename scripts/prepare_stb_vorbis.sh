#!/bin/sh
set -eu

destination=${1:?missing destination path}
revision=2c980bb59875b0d32144a71867fbdebb2f77cd20
source_url=https://raw.githubusercontent.com/nothings/stb/$revision/stb_vorbis.c
source_sha256=4c7cb2ff1f7011e9d67950446b7eb9ca044f2e464d76bfbb0b84dd2e23e65636
identity="stb_vorbis 1.22 $revision"

verify_installation() {
    test -f "$1/stb_vorbis.c"
    test "$(cat "$1/zig-vst3-stb-vorbis-version")" = "$identity"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s  %s\n' "$source_sha256" "$1/stb_vorbis.c" |
            sha256sum -c -
    else
        actual=$(shasum -a 256 "$1/stb_vorbis.c" | awk '{print $1}')
        test "$actual" = "$source_sha256"
    fi
}

if test -e "$destination"; then
    verify_installation "$destination"
    exit 0
fi

mkdir -p "$(dirname "$destination")"
partial=$(mktemp -d "${destination}.partial.XXXXXX")
cleanup() {
    rm -rf -- "$partial"
}
on_hup() { exit 129; }
on_int() { exit 130; }
on_term() { exit 143; }
trap cleanup EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM

curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$partial/stb_vorbis.c" "$source_url"
printf '%s\n' "$identity" >"$partial/zig-vst3-stb-vorbis-version"
verify_installation "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
