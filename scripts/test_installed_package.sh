#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-installed-consumer.XXXXXX")
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
mkdir -p "$package/tools"
cp tools/pack_ara_bindings.zig "$package/tools/"
mkdir -p "$package/vendor"
cp -R vendor/ARA_API "$package/vendor/"
cp tests/installed-consumer/build.zig tests/installed-consumer/build.zig.zon tests/installed-consumer/editors.zig tests/installed-consumer/dsp_fixture.zig tests/installed-consumer/core_consumer.zig tests/installed-consumer/kernel_plugin.zig "$consumer/"
cp -R tests/installed-consumer/kernel "$consumer/"

if ! (
    cd "$consumer"
    set -- test --summary all
    if [ -n "${ZIG_BUILD_JOBS:-}" ]; then
        jobs_argument="-j$ZIG_BUILD_JOBS"
        set -- "$@" "$jobs_argument"
    fi
    ZIG_GLOBAL_CACHE_DIR="$root/zig-global-cache" zig build "$@"
); then
    preserve=1
    printf 'installed-package consumer failed; preserved staged package at %s\n' "$root" >&2
    exit 1
fi

printf 'installed-package effect, instrument, core, DSP fixture, and C kernel consumers passed\n'
