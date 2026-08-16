#!/bin/sh
set -eu

expected_zig=0.16.0
expected_package_version=0.3.0
expected_raw_version=0.3.0
expected_framework_version=0.3.0

zig_version=$(zig version)
if [ "$zig_version" != "$expected_zig" ]; then
    printf 'framework release candidate requires Zig %s, found %s\n' "$expected_zig" "$zig_version" >&2
    exit 1
fi

package_version=$(sed -n 's/^    \.version = "\([^"]*\)",$/\1/p' build.zig.zon)
if [ "$package_version" != "$expected_package_version" ]; then
    printf 'expected package version %s, found %s\n' "$expected_package_version" "$package_version" >&2
    exit 1
fi

framework_version=$(sed -n 's/^pub const version = "\([^"]*\)";$/\1/p' zig-vst3-plugin/src/root.zig)
if [ "$framework_version" != "$expected_framework_version" ]; then
    printf 'expected framework version %s, found %s\n' "$expected_framework_version" "$framework_version" >&2
    exit 1
fi

raw_version=$(sed -n 's/^pub const version = "\([^"]*\)";$/\1/p' zig-vst3/src/root.zig)
if [ "$raw_version" != "$expected_raw_version" ]; then
    printf 'expected raw API version %s, found %s\n' "$expected_raw_version" "$raw_version" >&2
    exit 1
fi

for required_path in \
    docs/framework/api-compatibility.md \
    docs/framework/compatibility-policy.md \
    docs/release-checklist.md \
    docs/stability.md \
    docs/toolchain.md
do
    if [ ! -f "$required_path" ]; then
        printf 'release archive is missing %s\n' "$required_path" >&2
        exit 1
    fi
done

scripts/test_installed_package.sh --optimize=Debug
scripts/test_installed_package.sh --optimize=ReleaseSafe
scripts/test_downstream_adoption.sh --optimize=Debug
scripts/test_downstream_adoption.sh --optimize=ReleaseSafe --validate
zig build test -Doptimize=ReleaseSafe --summary all
zig build test-plugin-core-builds test-lv2 test-audio-unit test-ara --summary all
zig build test-dsp-thread-sanitizer --summary all
zig build test-resource-thread-sanitizer test-vstgui-sanitizers test-vstgui-thread-sanitizer --summary all
zig build raw-api-abi validator validate-examples --summary all
zig build benchmark --summary all
