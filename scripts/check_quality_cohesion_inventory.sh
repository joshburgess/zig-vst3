#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

document=${QUALITY_COHESION_DOCUMENT:-docs/quality/cohesion.md}
minimum_lines=2000

if [[ ! -f "$document" ]]; then
    printf 'missing cohesion inventory: %s\n' "$document" >&2
    exit 1
fi

if [[ $(grep -c '^<!-- cohesion-files:start -->$' "$document") -ne 1 ||
      $(grep -c '^<!-- cohesion-files:end -->$' "$document") -ne 1 ]]; then
    printf 'cohesion inventory requires one start marker and one end marker\n' >&2
    exit 1
fi

expected_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-expected.XXXXXX")
actual_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-actual.XXXXXX")
expected_paths_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-expected-paths.XXXXXX")
actual_paths_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-actual-paths.XXXXXX")
mismatch_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-cohesion-mismatch.XXXXXX")
trap 'rm -f "$expected_tmp" "$actual_tmp" "$expected_paths_tmp" "$actual_paths_tmp" "$mismatch_tmp"' EXIT

awk -F ' \\| ' '
    /^<!-- cohesion-files:start -->$/ { inside = 1; next }
    /^<!-- cohesion-files:end -->$/ { inside = 0; next }
    inside && NF > 0 {
        if (NF != 5 || $1 !~ /^- `[^`]+`$/ || $2 !~ /^[0-9]+$/ ||
            $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ ||
            ($5 != "KEEP" && $5 != "SPLIT")) {
            printf "invalid cohesion inventory record: %s\n", $0 > "/dev/stderr"
            invalid = 1
            next
        }
        source = $1
        sub(/^- `/, "", source)
        sub(/`$/, "", source)
        print source "|" $2 "|" $3 "|" $4 "|" $5
    }
    END { if (invalid) exit 1 }
' "$document" | LC_ALL=C sort > "$expected_tmp"

if [[ ! -s "$expected_tmp" ]]; then
    printf 'cohesion inventory contains no source records\n' >&2
    exit 1
fi

cut -d '|' -f 1 "$expected_tmp" > "$expected_paths_tmp"
if [[ $(wc -l < "$expected_paths_tmp") -ne $(LC_ALL=C sort -u "$expected_paths_tmp" | wc -l) ]]; then
    printf 'cohesion inventory contains duplicate source paths\n' >&2
    exit 1
fi

count_zig_test_lines() {
    awk '
        function brace_counts(line,    i, c, next_c, quote, escaped, opens, closes) {
            if (line ~ /^[[:space:]]*\\\\/) return "0 0"
            quote = ""
            escaped = 0
            opens = 0
            closes = 0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                next_c = substr(line, i + 1, 1)
                if (quote != "") {
                    if (escaped) {
                        escaped = 0
                    } else if (c == "\\") {
                        escaped = 1
                    } else if (c == quote) {
                        quote = ""
                    }
                    continue
                }
                if (c == "/" && next_c == "/") break
                if (c == "\"" || c == "\047") {
                    quote = c
                } else if (c == "{") {
                    opens++
                } else if (c == "}") {
                    closes++
                }
            }
            return opens " " closes
        }
        {
            if (!in_test && $0 ~ /^test([[:space:]]|$)/) {
                in_test = 1
                saw_open = 0
            }
            if (in_test) {
                test_lines++
                split(brace_counts($0), counts, " ")
                depth += counts[1] - counts[2]
                if (counts[1] > 0) saw_open = 1
                if (saw_open && depth == 0) in_test = 0
            }
        }
        END {
            if (in_test || depth != 0) exit 1
            print test_lines + 0
        }
    ' "$1"
}

while IFS= read -r -d '' source_file; do
    case "$source_file" in
        tests/*|*/tests/*|test-fixtures/*|*/test-fixtures/*|tools/*|*/tools/*|vendor/*|*/vendor/*)
            continue
            ;;
        *.zig|*.c|*.cc|*.cpp|*.h|*.hpp)
            ;;
        *)
            continue
            ;;
    esac

    source_name=${source_file##*/}
    case "$source_name" in
        test.*|tests.*|test_*|tests_*|*_test.*|*_tests.*)
            continue
            ;;
    esac

    total_lines=$(awk 'END { print NR + 0 }' "$source_file")
    if (( total_lines < minimum_lines )); then
        continue
    fi

    test_lines=0
    if [[ "$source_file" == *.zig ]]; then
        test_lines=$(count_zig_test_lines "$source_file")
    fi
    production_lines=$((total_lines - test_lines))
    printf '%s|%s|%s|%s\n' \
        "$source_file" "$total_lines" "$production_lines" "$test_lines" >> "$actual_tmp"
done < <(git ls-files -z)

LC_ALL=C sort -o "$actual_tmp" "$actual_tmp"
cut -d '|' -f 1 "$actual_tmp" > "$actual_paths_tmp"

missing=$(comm -23 "$actual_paths_tmp" "$expected_paths_tmp")
stale=$(comm -13 "$actual_paths_tmp" "$expected_paths_tmp")
if [[ -n "$missing" || -n "$stale" ]]; then
    if [[ -n "$missing" ]]; then
        printf 'unrecorded cohesion source paths:\n%s\n' "$missing" >&2
    fi
    if [[ -n "$stale" ]]; then
        printf 'stale cohesion inventory paths:\n%s\n' "$stale" >&2
    fi
    exit 1
fi

awk -F '|' '
    NR == FNR {
        expected[$1] = $2 "|" $3 "|" $4
        next
    }
    {
        actual = $2 "|" $3 "|" $4
        if (expected[$1] != actual) {
            printf "%s: recorded %s, actual %s\n", $1, expected[$1], actual
        }
    }
' "$expected_tmp" "$actual_tmp" > "$mismatch_tmp"

if [[ -s "$mismatch_tmp" ]]; then
    printf 'cohesion metric mismatch (total|production|test):\n' >&2
    cat "$mismatch_tmp" >&2
    exit 1
fi

printf 'cohesion inventory passed: %s large handwritten sources classified\n' \
    "$(wc -l < "$actual_tmp" | tr -d ' ')"
