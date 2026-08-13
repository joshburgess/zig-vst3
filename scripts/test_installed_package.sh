#!/bin/sh
set -eu

keep_failed=${ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE:-0}

case "$keep_failed" in
    0|1) ;;
    *)
        printf 'ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE must be 0 or 1\n' >&2
        exit 2
        ;;
esac

optimize=ReleaseSafe

if [ "$#" -gt 1 ]; then
    printf 'usage: %s [--optimize=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall]\n' "$0" >&2
    exit 2
fi

if [ "$#" -eq 1 ]; then
    case "$1" in
        --optimize=Debug) optimize=Debug ;;
        --optimize=ReleaseSafe) optimize=ReleaseSafe ;;
        --optimize=ReleaseFast) optimize=ReleaseFast ;;
        --optimize=ReleaseSmall) optimize=ReleaseSmall ;;
        *)
            printf 'usage: %s [--optimize=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall]\n' "$0" >&2
            exit 2
            ;;
    esac
fi

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-installed-consumer-active.XXXXXX")
package=$root/package
consumer=$root/consumer
preserve=0
touch "$root/.active"

cleanup() {
    if [ "$preserve" -eq 0 ]; then
        rm -rf "$root"
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

mkdir -p "$package" "$consumer"
cp build.zig build.zig.zon LICENSE README.md CHANGELOG.md "$package/"
cp -R zig-vst3 zig-vst3-plugin "$package/"
mkdir -p "$package/tools"
cp tools/pack_ara_bindings.zig "$package/tools/"
mkdir -p "$package/vendor"
cp -R vendor/ARA_API "$package/vendor/"
cp tests/installed-consumer/build.zig tests/installed-consumer/build.zig.zon tests/installed-consumer/editors.zig tests/installed-consumer/dsp_fixture.zig tests/installed-consumer/core_consumer.zig tests/installed-consumer/public_api.zig tests/installed-consumer/kernel_plugin.zig "$consumer/"
cp tests/abi/lv2_log_capture.c "$consumer/"
cp -R tests/installed-consumer/kernel "$consumer/"

if ! (
    cd "$consumer"
    set -- test --summary all
    if [ -n "$optimize" ]; then
        optimize_argument="-Doptimize=$optimize"
        set -- "$@" "$optimize_argument"
    fi
    if [ -n "${ZIG_BUILD_JOBS:-}" ]; then
        jobs_argument="-j$ZIG_BUILD_JOBS"
        set -- "$@" "$jobs_argument"
    fi
    ZIG_GLOBAL_CACHE_DIR="$root/zig-global-cache" zig build "$@"
); then
    if [ "$keep_failed" -eq 1 ]; then
        rm "$root/.active"
        temporary_root=${root%/*}
        suffix=${root##*.}
        completed_root=$temporary_root/zig-vst3-installed-consumer.$suffix
        if [ -e "$completed_root" ] || [ -L "$completed_root" ]; then
            printf 'installed-package diagnostic path already exists: %s\n' "$completed_root" >&2
            exit 1
        fi
        mv "$root" "$completed_root"
        root=$completed_root
        preserve=1
        printf 'installed-package consumer failed; preserved staged package at %s\n' "$root" >&2
    else
        printf 'installed-package consumer failed; set ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE=1 to preserve a diagnostic staging tree\n' >&2
    fi
    exit 1
fi

printf 'installed-package effect, instrument, core, DSP fixture, and C kernel consumers passed\n'
