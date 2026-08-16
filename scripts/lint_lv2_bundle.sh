#!/usr/bin/env sh
set -eu

if [ "$#" -ne 2 ]; then
    printf 'usage: %s path/to/Plugin.lv2 plugin-uri\n' "$0" >&2
    exit 2
fi

bundle="$1"
plugin_uri="$2"
lv2_validate="${LV2_VALIDATE:-lv2_validate}"
lv2lint="${LV2LINT:-lv2lint}"

if [ ! -d "$bundle" ]; then
    printf 'LV2 bundle not found: %s\n' "$bundle" >&2
    exit 2
fi

for metadata_file in manifest.ttl plugin.ttl presets.ttl; do
    if [ ! -f "$bundle/$metadata_file" ]; then
        printf 'LV2 metadata file not found: %s/%s\n' "$bundle" "$metadata_file" >&2
        exit 2
    fi
done

if ! command -v "$lv2_validate" >/dev/null 2>&1; then
    printf 'lv2_validate not found. Install the LV2 validation tools or set LV2_VALIDATE=/path/to/lv2_validate.\n' >&2
    exit 1
fi
if ! command -v "$lv2lint" >/dev/null 2>&1; then
    printf 'lv2lint not found. Install lv2lint or set LV2LINT=/path/to/lv2lint.\n' >&2
    exit 1
fi

"$lv2_validate" \
    "$bundle/manifest.ttl" \
    "$bundle/plugin.ttl" \
    "$bundle/presets.ttl"
"$lv2lint" \
    -M nopack \
    -E warn \
    -I "$bundle" \
    "$plugin_uri"

printf 'LV2 schema and direct-distribution lint passed\n'
