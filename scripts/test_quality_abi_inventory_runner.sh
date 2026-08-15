#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-abi-fixture.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT

expected="$fixture_dir/expected.tsv"
document="$fixture_dir/abi.md"
output="$fixture_dir/output.txt"
printf 'Q01\talpha.zig\nQ17\tbeta.zig\nQ19\tgamma.cpp\n' > "$expected"
printf '%s\n' \
    '<!-- abi-files:start -->' \
    $'Q01\talpha.zig\tEVIDENCE\tA-VST3' \
    $'Q17\tbeta.zig\tREVIEW\tA-PLUGIN-ABI' \
    $'Q19\tgamma.cpp\tEXCLUDED\ttest fixture' \
    '<!-- abi-files:end -->' > "$document"

run_check() {
    QUALITY_ABI_DOCUMENT="$document" \
        QUALITY_ABI_EXPECTED="$expected" \
        scripts/check_quality_abi_inventory.sh > "$output" 2>&1
}

run_check
grep -q 'ABI inventory passed: 1 evidence, 1 review, 1 excluded sources' "$output"

sed -i.bak '/beta.zig/d' "$document"
if run_check; then
    printf 'ABI inventory accepted a missing source path\n' >&2
    exit 1
fi
grep -q 'unrecorded ABI source paths:' "$output"
mv "$document.bak" "$document"

sed -i.bak 's/Q17\tbeta.zig/Q18\tbeta.zig/' "$document"
if run_check; then
    printf 'ABI inventory accepted a wrong review unit\n' >&2
    exit 1
fi
grep -q 'ABI inventory review-unit mismatch' "$output"
mv "$document.bak" "$document"

sed -i.bak 's/REVIEW/UNKNOWN/' "$document"
if run_check; then
    printf 'ABI inventory accepted an invalid state\n' >&2
    exit 1
fi
grep -q 'invalid ABI inventory record:' "$output"
mv "$document.bak" "$document"

printf 'quality ABI inventory fixture checks passed\n'
