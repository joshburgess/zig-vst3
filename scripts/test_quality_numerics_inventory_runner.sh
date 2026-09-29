#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-numerics-fixture.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT

expected="$fixture_dir/expected.tsv"
document="$fixture_dir/numerics.md"
output="$fixture_dir/output.txt"
printf 'Q13\talpha.zig\nQ14\tbeta.zig\nQ15\tgamma.zig\n' > "$expected"
printf '%s\n' \
    '<!-- numerical-files:start -->' \
    $'Q13\talpha.zig\tEVIDENCE\tN-ADM' \
    $'Q14\tbeta.zig\tREVIEW\tN-SPATIAL' \
    $'Q15\tgamma.zig\tEXCLUDED\tnon-numerical facade' \
    '<!-- numerical-files:end -->' > "$document"

run_check() {
    QUALITY_NUMERICS_DOCUMENT="$document" \
        QUALITY_NUMERICS_EXPECTED="$expected" \
        scripts/check_quality_numerics_inventory.sh > "$output" 2>&1
}

run_check
grep -q 'numerical inventory passed: 1 evidence, 1 review, 1 excluded sources' "$output"

sed -i.bak '/beta.zig/d' "$document"
if run_check; then
    printf 'numerical inventory accepted a missing source path\n' >&2
    exit 1
fi
grep -q 'unrecorded numerical source paths:' "$output"
mv "$document.bak" "$document"

sed -i.bak 's/Q14\tbeta.zig/Q15\tbeta.zig/' "$document"
if run_check; then
    printf 'numerical inventory accepted a wrong review unit\n' >&2
    exit 1
fi
grep -q 'numerical inventory review-unit mismatch' "$output"
mv "$document.bak" "$document"

sed -i.bak 's/REVIEW/UNKNOWN/' "$document"
if run_check; then
    printf 'numerical inventory accepted an invalid state\n' >&2
    exit 1
fi
grep -q 'invalid numerical inventory record:' "$output"
mv "$document.bak" "$document"

printf 'quality numerical inventory fixture checks passed\n'
