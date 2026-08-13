#!/bin/sh
set -eu

optimize=ReleaseSafe
validate=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --optimize=Debug) optimize=Debug ;;
        --optimize=ReleaseSafe) optimize=ReleaseSafe ;;
        --optimize=ReleaseFast) optimize=ReleaseFast ;;
        --optimize=ReleaseSmall) optimize=ReleaseSmall ;;
        --validate) validate=1 ;;
        *)
            printf 'usage: %s [--optimize=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall] [--validate]\n' "$0" >&2
            exit 2
            ;;
    esac
    shift
done

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-downstream-adoption.XXXXXX")
package=$root/zig-vst3-package
cache=$root/zig-global-cache
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$package/tools" "$package/vendor"
cp build.zig build.zig.zon LICENSE README.md CHANGELOG.md "$package/"
cp -R zig-vst3 zig-vst3-plugin docs "$package/"
cp tools/pack_ara_bindings.zig "$package/tools/"
cp -R vendor/ARA_API "$package/vendor/"

for project in effect instrument upgrade; do
    mkdir "$root/$project"
    cp -R "tests/downstream-adoption/$project/." "$root/$project/"
    if grep -R -F "$(pwd)" "$root/$project" >/dev/null 2>&1; then
        printf '%s consumer contains a repository-absolute source path\n' "$project" >&2
        exit 1
    fi
done

run_project() {
    project=$1
    (
        cd "$root/$project"
        set -- test --summary all "-Doptimize=$optimize"
        if [ -n "${ZIG_BUILD_JOBS:-}" ]; then
            set -- "$@" "-j$ZIG_BUILD_JOBS"
        fi
        ZIG_GLOBAL_CACHE_DIR="$cache" zig build "$@"
    )
}

run_project effect
run_project instrument
run_project upgrade

case "$(uname -s)" in
    Darwin)
        effect_bundle=$root/effect/zig-out/bundle/DownstreamEffect.vst3/Contents
        instrument_bundle=$root/instrument/zig-out/bundle/DownstreamInstrument.vst3/Contents
        test -x "$effect_bundle/MacOS/DownstreamEffect"
        test -x "$instrument_bundle/MacOS/DownstreamInstrument"
        test -f "$effect_bundle/Info.plist"
        test -f "$effect_bundle/PkgInfo"
        test -f "$instrument_bundle/Info.plist"
        test -f "$instrument_bundle/PkgInfo"
        ;;
    Linux)
        case "$(uname -m)" in
            x86_64|amd64) bundle_arch=x86_64 ;;
            aarch64|arm64) bundle_arch=aarch64 ;;
            *)
                printf 'unsupported downstream bundle architecture: %s\n' "$(uname -m)" >&2
                exit 1
                ;;
        esac
        effect_bundle=$root/effect/zig-out/bundle/DownstreamEffect.vst3/Contents/$bundle_arch-linux
        instrument_bundle=$root/instrument/zig-out/bundle/DownstreamInstrument.vst3/Contents/$bundle_arch-linux
        test -f "$effect_bundle/DownstreamEffect.so"
        test -f "$instrument_bundle/DownstreamInstrument.so"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        effect_bundle=$root/effect/zig-out/bundle/DownstreamEffect.vst3/Contents/x86_64-win
        instrument_bundle=$root/instrument/zig-out/bundle/DownstreamInstrument.vst3/Contents/x86_64-win
        test -f "$effect_bundle/DownstreamEffect.vst3"
        test -f "$instrument_bundle/DownstreamInstrument.vst3"
        ;;
    *)
        printf 'unsupported downstream bundle host: %s\n' "$(uname -s)" >&2
        exit 1
        ;;
esac

test -f "$root/effect/zig-out/bundle/DownstreamEffect.vst3/Contents/Resources/default-preset.txt"
test -f "$root/instrument/zig-out/bundle/DownstreamInstrument.vst3/Contents/Resources/wavetable.txt"

expect_legacy_failure() {
    step=$1
    expected=$2
    log=$root/$step.log
    if (
        cd "$root/upgrade"
        ZIG_GLOBAL_CACHE_DIR="$cache" zig build "$step" "-Doptimize=$optimize"
    ) >"$log" 2>&1; then
        printf 'retired source path unexpectedly compiled: %s\n' "$step" >&2
        exit 1
    fi
    if ! grep -F "$expected" "$log" >/dev/null 2>&1; then
        printf 'retired source path failed for an unexpected reason: %s\n' "$step" >&2
        sed -n '1,80p' "$log" >&2
        exit 1
    fi
}

expect_legacy_failure legacy-backend-version backendVersion
expect_legacy_failure legacy-lv2-metadata lv2_metadata

if [ "$validate" -eq 1 ]; then
    scripts/validate.sh "$root/effect/zig-out/bundle/DownstreamEffect.vst3"
    scripts/validate.sh "$root/instrument/zig-out/bundle/DownstreamInstrument.vst3"
fi

printf 'downstream effect, instrument, bundle, and upgrade consumers passed in %s\n' "$optimize"
