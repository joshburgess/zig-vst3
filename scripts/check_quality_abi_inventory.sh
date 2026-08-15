#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

document=${QUALITY_ABI_DOCUMENT:-docs/quality/abi.md}
if [[ ! -f "$document" ]]; then
    printf 'missing ABI inventory: %s\n' "$document" >&2
    exit 1
fi

if [[ $(grep -c '^<!-- abi-files:start -->$' "$document") -ne 1 ||
      $(grep -c '^<!-- abi-files:end -->$' "$document") -ne 1 ]]; then
    printf 'ABI inventory requires one start marker and one end marker\n' >&2
    exit 1
fi

expected_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-abi-expected.XXXXXX")
actual_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-abi-actual.XXXXXX")
expected_paths_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-abi-expected-paths.XXXXXX")
actual_paths_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-abi-actual-paths.XXXXXX")
trap 'rm -f "$expected_tmp" "$actual_tmp" "$expected_paths_tmp" "$actual_paths_tmp"' EXIT

awk -F '\t' '
    /^<!-- abi-files:start -->$/ { inside = 1; next }
    /^<!-- abi-files:end -->$/ { inside = 0; next }
    inside {
        valid_unit = $1 == "Q01" || $1 == "Q02" || $1 == "Q03" ||
            $1 == "Q04" || $1 == "Q06" || $1 == "Q17" ||
            $1 == "Q18" || $1 == "Q19"
        valid_state = $3 == "EVIDENCE" || $3 == "REVIEW" ||
            $3 == "EXCLUDED"
        if (NF != 4 || !valid_unit || !valid_state || $2 == "" || $4 == "") {
            printf "invalid ABI inventory record: %s\n", $0 > "/dev/stderr"
            invalid = 1
        } else {
            print $1 "\t" $2 "\t" $3 "\t" $4
        }
    }
    END { exit invalid }
' "$document" > "$actual_tmp"

if [[ ! -s "$actual_tmp" ]]; then
    printf 'ABI inventory contains no source records\n' >&2
    exit 1
fi

cut -f2 "$actual_tmp" | LC_ALL=C sort > "$actual_paths_tmp"
if [[ $(wc -l < "$actual_paths_tmp") -ne $(LC_ALL=C sort -u "$actual_paths_tmp" | wc -l) ]]; then
    printf 'ABI inventory contains duplicate source paths\n' >&2
    exit 1
fi

if [[ -n "${QUALITY_ABI_EXPECTED:-}" ]]; then
    cp "$QUALITY_ABI_EXPECTED" "$expected_tmp"
else
    scripts/check_quality_inventory.sh --files |
        awk -F '\t' '
            $1 == "unit" && $2 == "lines" { files = 1; next }
            files && ($1 == "Q01" || $1 == "Q02" || $1 == "Q03" ||
                $1 == "Q04" || $1 == "Q06" || $1 == "Q17" ||
                $1 == "Q18" || $1 == "Q19") {
                print $1 "\t" $9
            }
        ' > "$expected_tmp"
fi

cut -f2 "$expected_tmp" | LC_ALL=C sort > "$expected_paths_tmp"
missing=$(comm -23 "$expected_paths_tmp" "$actual_paths_tmp")
stale=$(comm -13 "$expected_paths_tmp" "$actual_paths_tmp")
if [[ -n "$missing" || -n "$stale" ]]; then
    if [[ -n "$missing" ]]; then
        printf 'unrecorded ABI source paths:\n%s\n' "$missing" >&2
    fi
    if [[ -n "$stale" ]]; then
        printf 'stale ABI inventory paths:\n%s\n' "$stale" >&2
    fi
    exit 1
fi

LC_ALL=C sort -k2,2 "$expected_tmp" -o "$expected_tmp"
awk -F '\t' '{ print $1 "\t" $2 }' "$actual_tmp" |
    LC_ALL=C sort -k2,2 > "$actual_paths_tmp"
if ! cmp -s "$expected_tmp" "$actual_paths_tmp"; then
    printf 'ABI inventory review-unit mismatch\n' >&2
    diff -u "$expected_tmp" "$actual_paths_tmp" >&2 || true
    exit 1
fi

evidence_count=$(awk -F '\t' '$3 == "EVIDENCE" { count += 1 } END { print count + 0 }' "$actual_tmp")
review_count=$(awk -F '\t' '$3 == "REVIEW" { count += 1 } END { print count + 0 }' "$actual_tmp")
excluded_count=$(awk -F '\t' '$3 == "EXCLUDED" { count += 1 } END { print count + 0 }' "$actual_tmp")
printf 'ABI inventory passed: %s evidence, %s review, %s excluded sources\n' \
    "$evidence_count" "$review_count" "$excluded_count"
