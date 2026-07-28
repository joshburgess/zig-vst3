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

if scripts/bundle_lv2.sh \
    "$library" \
    "$root/not-a-bundle" \
    "$metadata_generator" \
    >/dev/null 2>&1; then
    printf 'bundle script accepted a path without the .lv2 suffix\n' >&2
    exit 1
fi

printf 'LV2 bundle script tests passed\n'
