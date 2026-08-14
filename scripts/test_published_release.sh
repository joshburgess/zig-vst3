#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf 'usage: %s ARCHIVE_URL [EXPECTED_SHA256]\n' "$0" >&2
    exit 2
fi

archive_url=$1
expected_sha256=${2:-}
expected_version=${ZIG_VST3_EXPECTED_VERSION:-0.3.0}
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-published-release.XXXXXX")
archive=$root/zig-vst3.tar.gz
unpacked=$root/unpacked

cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

mkdir "$unpacked"
curl --fail --location --silent --show-error "$archive_url" --output "$archive"

if command -v sha256sum >/dev/null 2>&1; then
    archive_sha256=$(sha256sum "$archive" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    archive_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
else
    printf 'sha256sum or shasum is required\n' >&2
    exit 1
fi

if [ -n "$expected_sha256" ] && [ "$archive_sha256" != "$expected_sha256" ]; then
    printf 'archive checksum mismatch: expected %s, found %s\n' "$expected_sha256" "$archive_sha256" >&2
    exit 1
fi

tar -xzf "$archive" -C "$unpacked"
set -- "$unpacked"/*
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    printf 'release archive must contain exactly one top-level directory\n' >&2
    exit 1
fi
package_source=$1

package_version=$(sed -n 's/^    \.version = "\([^"]*\)",$/\1/p' "$package_source/build.zig.zon")
raw_version=$(sed -n 's/^pub const version = "\([^"]*\)";$/\1/p' "$package_source/zig-vst3/src/root.zig")
framework_version=$(sed -n 's/^pub const version = "\([^"]*\)";$/\1/p' "$package_source/zig-vst3-plugin/src/root.zig")

for actual_version in "$package_version" "$raw_version" "$framework_version"; do
    if [ "$actual_version" != "$expected_version" ]; then
        printf 'expected published version %s, found %s\n' "$expected_version" "$actual_version" >&2
        exit 1
    fi
done

for required_path in \
    build.zig \
    build.zig.zon \
    zig-vst3/src/root.zig \
    zig-vst3-plugin/src/root.zig \
    docs/framework/api-compatibility.md \
    docs/framework/compatibility-policy.md \
    docs/release-checklist.md \
    docs/stability.md \
    docs/toolchain.md \
    tools/pack_ara_bindings.zig \
    vendor/ARA_API/ARAInterface.h
do
    if [ ! -f "$package_source/$required_path" ]; then
        printf 'published archive is missing %s\n' "$required_path" >&2
        exit 1
    fi
done

ZIG_VST3_PACKAGE_SOURCE="$package_source" scripts/test_installed_package.sh --optimize=ReleaseSafe
ZIG_VST3_PACKAGE_SOURCE="$package_source" scripts/test_downstream_adoption.sh --optimize=ReleaseSafe

printf 'published release archive passed\n'
printf 'archive URL: %s\n' "$archive_url"
printf 'archive SHA-256: %s\n' "$archive_sha256"
