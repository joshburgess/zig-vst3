#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: %s <metadata-generator>\n' "$0" >&2
    exit 2
fi

metadata_generator=$1
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-lv2-topology-bundle.XXXXXX")
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

library="$root/dynamic_topology.so"
bundle="$root/dynamic_topology.lv2"
printf 'fixture\n' > "$library"

scripts/bundle_lv2.sh \
    "$library" \
    "$bundle" \
    "$metadata_generator"

test -f "$bundle/dynamic_topology.so"
test -f "$bundle/manifest.ttl"
test -f "$bundle/plugin.ttl"
test -f "$bundle/presets.ttl"
grep -Fq 'lv2:binary <dynamic_topology.so>' "$bundle/manifest.ttl"
grep -Fq 'pg:mainInput <https://zig-vst3.dev/tests/lv2-dynamic-topology#main_input_group>' "$bundle/plugin.ttl"
grep -Fq 'pg:mainOutput <https://zig-vst3.dev/tests/lv2-dynamic-topology#main_output_group>' "$bundle/plugin.ttl"
test "$(grep -Fc 'lv2:portProperty lv2:connectionOptional' "$bundle/plugin.ttl")" -eq 4
test "$(grep -Fc 'pg:sideChainOf <https://zig-vst3.dev/tests/lv2-dynamic-topology#main_input_group>' "$bundle/plugin.ttl")" -eq 1
test "$(grep -Fc 'pg:source <https://zig-vst3.dev/tests/lv2-dynamic-topology#main_input_group>' "$bundle/plugin.ttl")" -eq 1
grep -Fq 'lv2:symbol "input_3"' "$bundle/plugin.ttl"
grep -Fq 'lv2:symbol "input_4"' "$bundle/plugin.ttl"
grep -Fq 'lv2:symbol "output_3"' "$bundle/plugin.ttl"
grep -Fq 'lv2:symbol "output_4"' "$bundle/plugin.ttl"

printf 'LV2 dynamic topology bundle tests passed\n'
