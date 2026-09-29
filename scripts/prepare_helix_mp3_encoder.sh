#!/bin/sh
set -eu

destination=${1:?missing destination path}
source_url=https://github.com/maikmerten/hmp3/archive/7f7dfc7680db3c05f8e4a8fbd9861cbb06427d92.tar.gz
source_sha256=7809b5eca0158ee4ec8ce4e6fabbf6e04c82396205e7e3283abd8114b810df47
source_directory=hmp3-7f7dfc7680db3c05f8e4a8fbd9861cbb06427d92

verify_encoder() {
    test -x "$1"
    "$1" 2>&1 | grep -q 'hmp3 MPEG Layer III audio encoder 5\.2\.4'
}

if test -e "$destination"; then
    verify_encoder "$destination"
    exit 0
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-hmp3.XXXXXX")
partial=$(mktemp "${destination}.partial.XXXXXX")
cleanup() {
    rm -rf -- "$temporary"
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

archive=$temporary/hmp3.tar.gz
curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    -o "$archive" "$source_url"
if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$source_sha256" "$archive" | sha256sum -c -
else
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    test "$actual" = "$source_sha256"
fi
tar -xzf "$archive" -C "$temporary"
make -C "$temporary/$source_directory"
cp "$temporary/$source_directory/builds/release/hmp3" "$partial"
chmod +x "$partial"
verify_encoder "$partial"
mv -- "$partial" "$destination"
partial=
trap - EXIT HUP INT TERM
