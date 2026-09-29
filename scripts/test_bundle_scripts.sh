#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-bundle-script-test.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

library="$temporary/plugin-library"
printf 'fixture\n' >"$library"

macos_bundle="$temporary/macos.vst3"
"$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$macos_bundle" "com.example.fixture" "1.0.0" "Fixture"
test -f "$macos_bundle/Contents/MacOS/Fixture"
test -f "$macos_bundle/Contents/Info.plist"
test -f "$macos_bundle/Contents/PkgInfo"

audio_unit_bundle="$temporary/mono-gain.component"
"$root/scripts/bundle_macos_auv2.sh" \
    "$library" "$audio_unit_bundle" "com.example.mono-gain" "1.0.0" \
    "MonoGain" "aufx" "ZMGn" "Zig3" "Example: Mono Gain" \
    "ZigVst3MonoGainFactory" "65536"
test -f "$audio_unit_bundle/Contents/MacOS/MonoGain"
test -f "$audio_unit_bundle/Contents/Info.plist"
test -f "$audio_unit_bundle/Contents/PkgInfo"
grep -q '<key>AudioComponents</key>' \
    "$audio_unit_bundle/Contents/Info.plist"
grep -q '<string>ZigVst3MonoGainFactory</string>' \
    "$audio_unit_bundle/Contents/Info.plist"

linux_bundle="$temporary/linux.vst3"
"$root/scripts/bundle_linux_vst3.sh" \
    "$library" "$linux_bundle" "x86_64-linux" "Fixture"
test -f "$linux_bundle/Contents/x86_64-linux/Fixture.so"

windows_bundle="$temporary/windows.vst3"
"$root/scripts/bundle_windows_vst3.sh" \
    "$library" "$windows_bundle" "x86_64-win" "Fixture"
test -f "$windows_bundle/Contents/x86_64-win/Fixture.vst3"

"$root/scripts/bundle_linux_vst3.sh" \
    "$library" "$linux_bundle" "x86_64-linux" "Fixture"
test -f "$linux_bundle/Contents/x86_64-linux/Fixture.so"
"$root/scripts/bundle_windows_vst3.sh" \
    "$library" "$windows_bundle" "x86_64-win" "Fixture"
test -f "$windows_bundle/Contents/x86_64-win/Fixture.vst3"
"$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$macos_bundle" "com.example.fixture" "1.0.0" "Fixture"
test -f "$macos_bundle/Contents/MacOS/Fixture"
"$root/scripts/bundle_macos_auv2.sh" \
    "$library" "$audio_unit_bundle" "com.example.mono-gain" "1.0.0" \
    "MonoGain" "aufx" "ZMGn" "Zig3" "Example: Mono Gain" \
    "ZigVst3MonoGainFactory" "65536"
test -f "$audio_unit_bundle/Contents/MacOS/MonoGain"
test "$(find "$temporary" -maxdepth 1 -name '*.backup.*' -type d | \
    wc -l | tr -d ' ')" = 0

preserved="$temporary/preserved"
mkdir -p "$preserved"
printf 'keep\n' >"$preserved/marker"
if "$root/scripts/bundle_linux_vst3.sh" \
    "$library" "$preserved" "x86_64-linux" "Fixture" >/dev/null 2>&1; then
    printf 'Linux bundler accepted a non-VST3 deletion target\n' >&2
    exit 1
fi
test -f "$preserved/marker"

guarded_bundle="$temporary/guarded.vst3"
mkdir -p "$guarded_bundle"
printf 'keep\n' >"$guarded_bundle/marker"
if "$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$guarded_bundle" "com.example.fixture" "1.0.0" "../Fixture" >/dev/null 2>&1; then
    printf 'macOS bundler accepted a nested executable name\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if "$root/scripts/bundle_macos_auv2.sh" \
    "$library" "$guarded_bundle" "com.example.fixture" "1.0.0" \
    "../Fixture" "aufx" "ZMGn" "Zig3" "Fixture" \
    "FixtureFactory" "65536" >/dev/null 2>&1; then
    printf 'AUv2 bundler accepted a non-component target or nested executable\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if "$root/scripts/bundle_windows_vst3.sh" \
    "$library" "$guarded_bundle" "../x86_64-win" "Fixture" >/dev/null 2>&1; then
    printf 'Windows bundler accepted a nested platform directory\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if "$root/scripts/bundle_windows_vst3.sh" \
    "$library" "$guarded_bundle" 'x86_64\win' "Fixture" >/dev/null 2>&1; then
    printf 'Windows bundler accepted a backslash in the platform directory\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if "$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$guarded_bundle" 'com.example.<fixture>' "1.0.0" "Fixture" >/dev/null 2>&1; then
    printf 'macOS bundler accepted XML metacharacters in the bundle identifier\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if "$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$guarded_bundle" "com.example.fixture" '1.0&bad' "Fixture" >/dev/null 2>&1; then
    printf 'macOS bundler accepted XML metacharacters in the version\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if "$root/scripts/bundle_linux_vst3.sh" \
    "$temporary/missing-library" "$guarded_bundle" "x86_64-linux" "Fixture" >/dev/null 2>&1; then
    printf 'Linux bundler accepted a missing library\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

fake_tools="$temporary/fake-tools"
mkdir -p "$fake_tools"
printf '#!/bin/sh\nexit 9\n' >"$fake_tools/cp"
chmod +x "$fake_tools/cp"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_linux_vst3.sh" \
    "$library" "$guarded_bundle" "x86_64-linux" "Fixture" >/dev/null 2>&1; then
    printf 'Linux bundler replaced the existing bundle after a copy failure\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$guarded_bundle" "com.example.fixture" "1.0.0" "Fixture" >/dev/null 2>&1; then
    printf 'macOS bundler replaced the existing bundle after a copy failure\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

guarded_component="$temporary/guarded.component"
mkdir -p "$guarded_component"
printf 'keep\n' >"$guarded_component/marker"
if PATH="$fake_tools:$PATH" "$root/scripts/bundle_macos_auv2.sh" \
    "$library" "$guarded_component" "com.example.fixture" "1.0.0" \
    "Fixture" "aufx" "ZMGn" "Zig3" "Fixture" \
    "FixtureFactory" "65536" >/dev/null 2>&1; then
    printf 'AUv2 bundler replaced the existing bundle after a copy failure\n' >&2
    exit 1
fi
test -f "$guarded_component/marker"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_windows_vst3.sh" \
    "$library" "$guarded_bundle" "x86_64-win" "Fixture" >/dev/null 2>&1; then
    printf 'Windows bundler replaced the existing bundle after a copy failure\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"
test "$(find "$temporary" -maxdepth 1 -name 'guarded.vst3.staging.*' -type d | wc -l | tr -d ' ')" = 0

rm "$fake_tools/cp"
real_mv="$(command -v mv)"
cat >"$fake_tools/mv" <<SCRIPT
#!/bin/sh
set -eu
count=0
if [ -f "\$BUNDLE_MV_COUNT" ]; then
    count=\$(cat "\$BUNDLE_MV_COUNT")
fi
count=\$((count + 1))
printf '%s\n' "\$count" >"\$BUNDLE_MV_COUNT"
if [ "\$count" -eq 2 ]; then
    exit 9
fi
exec "$real_mv" "\$@"
SCRIPT
chmod +x "$fake_tools/mv"

move_count="$temporary/linux-mv-count"
if BUNDLE_MV_COUNT="$move_count" PATH="$fake_tools:$PATH" \
    "$root/scripts/bundle_linux_vst3.sh" \
        "$library" "$guarded_bundle" "x86_64-linux" "Fixture" \
        >/dev/null 2>&1; then
    printf 'Linux bundler accepted a failed final publication\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

move_count="$temporary/macos-mv-count"
if BUNDLE_MV_COUNT="$move_count" PATH="$fake_tools:$PATH" \
    "$root/scripts/bundle_macos_vst3.sh" \
        "$library" "$guarded_bundle" "com.example.fixture" "1.0.0" \
        "Fixture" >/dev/null 2>&1; then
    printf 'macOS bundler accepted a failed final publication\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

move_count="$temporary/auv2-mv-count"
if BUNDLE_MV_COUNT="$move_count" PATH="$fake_tools:$PATH" \
    "$root/scripts/bundle_macos_auv2.sh" \
        "$library" "$guarded_component" "com.example.fixture" "1.0.0" \
        "Fixture" "aufx" "ZMGn" "Zig3" "Fixture" \
        "FixtureFactory" "65536" >/dev/null 2>&1; then
    printf 'AUv2 bundler accepted a failed final publication\n' >&2
    exit 1
fi
test -f "$guarded_component/marker"

move_count="$temporary/windows-mv-count"
if BUNDLE_MV_COUNT="$move_count" PATH="$fake_tools:$PATH" \
    "$root/scripts/bundle_windows_vst3.sh" \
        "$library" "$guarded_bundle" "x86_64-win" "Fixture" \
        >/dev/null 2>&1; then
    printf 'Windows bundler accepted a failed final publication\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"
test "$(find "$temporary" -maxdepth 1 \
    \( -name 'guarded.vst3.staging.*' -o \
       -name 'guarded.vst3.backup.*' -o \
       -name 'guarded.component.staging.*' -o \
       -name 'guarded.component.backup.*' \) \
    -type d | wc -l | tr -d ' ')" = 0
rm "$fake_tools/mv"

printf '%s\n' \
    '#!/bin/sh' \
    "kill -TERM \"\$PPID\"" \
    'exit 9' \
    >"$fake_tools/cp"
chmod +x "$fake_tools/cp"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_linux_vst3.sh" \
    "$library" "$guarded_bundle" "x86_64-linux" "Fixture" >/dev/null 2>&1; then
    printf 'Linux bundler accepted an interrupted copy\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_macos_vst3.sh" \
    "$library" "$guarded_bundle" "com.example.fixture" "1.0.0" "Fixture" >/dev/null 2>&1; then
    printf 'macOS bundler accepted an interrupted copy\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_macos_auv2.sh" \
    "$library" "$guarded_component" "com.example.fixture" "1.0.0" \
    "Fixture" "aufx" "ZMGn" "Zig3" "Fixture" \
    "FixtureFactory" "65536" >/dev/null 2>&1; then
    printf 'AUv2 bundler accepted an interrupted copy\n' >&2
    exit 1
fi
test -f "$guarded_component/marker"

if PATH="$fake_tools:$PATH" "$root/scripts/bundle_windows_vst3.sh" \
    "$library" "$guarded_bundle" "x86_64-win" "Fixture" >/dev/null 2>&1; then
    printf 'Windows bundler accepted an interrupted copy\n' >&2
    exit 1
fi
test -f "$guarded_bundle/marker"
test "$(find "$temporary" -maxdepth 1 \
    \( -name 'guarded.vst3.staging.*' -o \
       -name 'guarded.component.staging.*' \) \
    -type d | wc -l | tr -d ' ')" = 0

printf 'VST3 and AUv2 bundle script tests passed\n'
