#!/bin/sh
set -eu

root=${TMPDIR:-/tmp}/zig-vst3-installed-consumer-$$
package=$root/package
consumer=$root/consumer
preserve=0

cleanup() {
    if [ "$preserve" -eq 0 ]; then
        rm -rf "$root"
    fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$package" "$consumer"
cp build.zig build.zig.zon LICENSE README.md CHANGELOG.md "$package/"
cp -R zig-vst3 zig-vst3-plugin "$package/"
cp tests/installed-consumer/build.zig tests/installed-consumer/build.zig.zon tests/installed-consumer/editors.zig tests/installed-consumer/kernel_plugin.zig "$consumer/"
cp -R tests/installed-consumer/kernel "$consumer/"

if ! (
    cd "$consumer"
    ZIG_GLOBAL_CACHE_DIR="$root/zig-global-cache" zig build test --summary all
); then
    preserve=1
    printf 'installed-package consumer failed; preserved staged package at %s\n' "$root" >&2
    exit 1
fi

printf 'installed-package effect, instrument, and C kernel consumers passed\n'
