#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

document=${QUALITY_ATOMIC_ORDER_DOCUMENT:-docs/quality/atomic-orders.md}
if [[ ! -f "$document" ]]; then
    printf 'missing atomic-order ledger: %s\n' "$document" >&2
    exit 1
fi

expected=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-atomic-expected.XXXXXX")
actual=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-atomic-actual.XXXXXX")
paths=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-atomic-paths.XXXXXX")
trap 'rm -f "$expected" "$actual" "$paths"' EXIT

awk '
    /^<!-- atomic-order-counts:start -->$/ { inside = 1; next }
    /^<!-- atomic-order-counts:end -->$/ { inside = 0; next }
    inside && /^\| `[^`]+` \| [0-9]+ \|/ { print }
' "$document" > "$expected"
if [[ ! -s "$expected" ]]; then
    printf 'atomic-order ledger contains no source rows\n' >&2
    exit 1
fi

awk '
    /^<!-- concurrency-files:start -->$/ { inside = 1; next }
    /^<!-- concurrency-files:end -->$/ { inside = 0; next }
    inside && /^- `[^`]+`$/ {
        line = $0
        sub(/^- `/, "", line)
        sub(/`$/, "", line)
        if (line ~ /\.zig$/) print line
    }
' docs/quality/concurrency.md > "$paths"

while IFS= read -r file; do
    counts=$(awk '
        BEGIN { unordered = monotonic = acquire = release = acq_rel = seq_cst = 0 }
        {
            line = $0
            while (match(line, /(^|[^[:alnum:]_])\.(unordered|monotonic|acquire|release|acq_rel|seq_cst)[),]/)) {
                token = substr(line, RSTART, RLENGTH)
                sub(/^.*\./, "", token)
                sub(/[),]$/, "", token)
                if (token == "unordered") unordered++
                else if (token == "monotonic") monotonic++
                else if (token == "acquire") acquire++
                else if (token == "release") release++
                else if (token == "acq_rel") acq_rel++
                else if (token == "seq_cst") seq_cst++
                line = substr(line, RSTART + RLENGTH)
            }
        }
        END { printf "%d %d %d %d %d %d", unordered, monotonic, acquire, release, acq_rel, seq_cst }
    ' "$file")
    if [[ "$counts" == "0 0 0 0 0 0" ]]; then
        continue
    fi
    read -r unordered monotonic acquire release acq_rel seq_cst <<< "$counts"
    printf '| `%s` | %s | %s | %s | %s | %s | %s |\n' \
        "$file" "$unordered" "$monotonic" "$acquire" "$release" \
        "$acq_rel" "$seq_cst" >> "$actual"
done < "$paths"

if ! cmp -s "$expected" "$actual"; then
    printf 'atomic-order ledger differs from tracked source:\n' >&2
    diff -u "$expected" "$actual" >&2 || true
    exit 1
fi

printf 'atomic-order ledger passed: %s source files tracked\n' \
    "$(wc -l < "$actual" | tr -d ' ')"
