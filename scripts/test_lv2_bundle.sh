#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: %s <metadata-generator>\n' "$0" >&2
    exit 2
fi

metadata_generator=$1
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-lv2-bundle.XXXXXX")
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

library="$root/mono_gain.so"
bundle="$root/mono_gain.lv2"
printf 'fixture\n' > "$library"

scripts/bundle_lv2.sh \
    "$library" \
    "$bundle" \
    "$metadata_generator"

test -f "$bundle/mono_gain.so"
test -f "$bundle/manifest.ttl"
test -f "$bundle/plugin.ttl"
test -f "$bundle/presets.ttl"
grep -Fq 'lv2:binary <mono_gain.so>' "$bundle/manifest.ttl"
grep -Fq 'a pset:Preset' "$bundle/manifest.ttl"
grep -Fq 'lv2:index 3' "$bundle/plugin.ttl"
grep -Fq 'lv2:index 4' "$bundle/plugin.ttl"
grep -Fq 'lv2:symbol "freewheeling"' "$bundle/plugin.ttl"
grep -Fq 'lv2:designation lv2:freeWheeling' "$bundle/plugin.ttl"
grep -Fq 'lv2:portProperty lv2:toggled' "$bundle/plugin.ttl"
grep -Fq 'lv2:index 5' "$bundle/plugin.ttl"
grep -Fq 'lv2:designation lv2:latency' "$bundle/plugin.ttl"
grep -Fq 'rdfs:label "Unity"' "$bundle/presets.ttl"
grep -Fq 'rdfs:label "Muted"' "$bundle/presets.ttl"
grep -Fq 'lv2:symbol "gain"' "$bundle/presets.ttl"
grep -Fq 'pset:value 1' "$bundle/presets.ttl"
grep -Fq 'pset:value 0' "$bundle/presets.ttl"

nested_bundle="$root/generated/bundles/mono_gain.lv2"
scripts/bundle_lv2.sh \
    "$library" \
    "$nested_bundle" \
    "$metadata_generator"
test -f "$nested_bundle/mono_gain.so"
test -f "$nested_bundle/manifest.ttl"

ui_library="$root/mono_gain_ui.so"
ui_bundle="$root/mono_gain_ui.lv2"
printf 'ui fixture\n' > "$ui_library"
scripts/bundle_lv2.sh \
    "$library" \
    "$ui_bundle" \
    "$metadata_generator" \
    "$ui_library"
test -f "$ui_bundle/mono_gain.so"
test -f "$ui_bundle/mono_gain_ui.so"
grep -Fq 'ui:ui <https://zig-vst3.dev/plugins/mono-gain#vstgui-ui>' \
    "$ui_bundle/plugin.ttl"
grep -Fq 'lv2:binary <mono_gain_ui.so>' "$ui_bundle/manifest.ttl"
grep -Fq 'lv2:requiredFeature ui:parent' "$ui_bundle/plugin.ttl"
grep -Fq 'ui:portNotification [' "$ui_bundle/plugin.ttl"
grep -Fq 'lv2:symbol "gain"' "$ui_bundle/plugin.ttl"
grep -Fq 'ui:protocol ui:floatProtocol' "$ui_bundle/plugin.ttl"
grep -Fq 'lv2:symbol "input"' "$ui_bundle/plugin.ttl"
grep -Fq 'lv2:symbol "output"' "$ui_bundle/plugin.ttl"
test "$(grep -Fc 'ui:protocol ui:peakProtocol' "$ui_bundle/plugin.ttl")" -eq 2

printf 'preserve\n' > "$bundle/existing-marker"
failing_generator="$root/failing-generator"
printf '#!/bin/sh\nexit 1\n' > "$failing_generator"
chmod +x "$failing_generator"
if scripts/bundle_lv2.sh \
    "$library" \
    "$bundle" \
    "$failing_generator" \
    >/dev/null 2>&1; then
    printf 'bundle script accepted failed metadata generation\n' >&2
    exit 1
fi
test -f "$bundle/existing-marker"

interrupted_generator="$root/interrupted-generator"
printf '%s\n' \
    '#!/bin/sh' \
    "kill -TERM \"\$PPID\"" \
    'exit 9' \
    >"$interrupted_generator"
chmod +x "$interrupted_generator"
if scripts/bundle_lv2.sh \
    "$library" \
    "$bundle" \
    "$interrupted_generator" \
    >/dev/null 2>&1; then
    printf 'bundle script accepted interrupted metadata generation\n' >&2
    exit 1
fi
test -f "$bundle/existing-marker"
test "$(find "$root" -maxdepth 1 -name '.lv2-bundle.*' -type d | \
    wc -l | tr -d ' ')" -eq 0

fake_tools="$root/fake-tools"
mkdir -p "$fake_tools"
real_mv=$(command -v mv)
cat >"$fake_tools/mv" <<SCRIPT
#!/bin/sh
set -eu
count=0
if [ -f "\$LV2_MV_COUNT" ]; then
    count=\$(cat "\$LV2_MV_COUNT")
fi
count=\$((count + 1))
printf '%s\n' "\$count" >"\$LV2_MV_COUNT"
if [ "\$count" -eq 2 ]; then
    exit 9
fi
exec "$real_mv" "\$@"
SCRIPT
chmod +x "$fake_tools/mv"
if LV2_MV_COUNT="$root/mv-count" PATH="$fake_tools:$PATH" \
    scripts/bundle_lv2.sh \
        "$library" \
        "$bundle" \
        "$metadata_generator" \
        >/dev/null 2>&1; then
    printf 'bundle script accepted failed final publication\n' >&2
    exit 1
fi
test -f "$bundle/existing-marker"
test "$(find "$root" -maxdepth 1 \
    \( -name '.lv2-bundle.*' -o -name '.lv2-bundle-backup.*' \) \
    -type d | wc -l | tr -d ' ')" -eq 0

if scripts/bundle_lv2.sh \
    "$library" \
    "$root/not-a-bundle" \
    "$metadata_generator" \
    >/dev/null 2>&1; then
    printf 'bundle script accepted a path without the .lv2 suffix\n' >&2
    exit 1
fi

printf 'LV2 bundle script tests passed\n'
