#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

script_dir="$repo_root/scripts"
document=${1:-docs/quality/parsers.md}
candidate_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-parser-candidates.XXXXXX")
document_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-parser-document.XXXXXX")
document_paths_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-parser-paths.XXXXXX")
trap 'rm -f "$candidate_tmp" "$document_tmp" "$document_paths_tmp"' EXIT

if [[ ! -f "$document" ]]; then
    printf 'parser inventory document is missing: %s\n' "$document" >&2
    exit 1
fi

"$script_dir/check_quality_inventory.sh" --files |
    awk -F '\t' '
        $1 ~ /^Q[0-9][0-9]$/ && $7 > 0 &&
        ($9 ~ /^zig-vst3-plugin\/src\// || $9 ~ /^zig-vst3\/src\//) {
            print $9
        }
    ' >> "$candidate_tmp"

while IFS= read -r source_path; do
    path_lower=$(printf '%s' "$source_path" | tr '[:upper:]' '[:lower:]')
    case "$path_lower" in
        */state/*|*/resource/*|*state*|*metadata*|*archive*|*preset*|*import*|*config*|*manifest*|*resource*|*file*|*codec*|*reader*|*json*|*xml*|*midi*|*ump*|*ara*)
            printf '%s\n' "$source_path" >> "$candidate_tmp"
            ;;
    esac
done < <(git ls-files 'zig-vst3-plugin/src/**' 'zig-vst3/src/**')

LC_ALL=C sort -u "$candidate_tmp" -o "$candidate_tmp"

awk '
    /<!-- parser-inventory-begin -->/ {
        if (inside || saw_begin) exit 20
        inside = 1
        saw_begin = 1
        next
    }
    /<!-- parser-inventory-end -->/ {
        if (!inside || saw_end) exit 21
        inside = 0
        saw_end = 1
        next
    }
    inside {
        if ($0 ~ /^[[:space:]]*```/ || $0 ~ /^[[:space:]]*$/) next
        if (NF != 2 || $1 !~ /^(P|N)-[A-Z0-9-]+$/) exit 22
        print $1 "\t" $2
    }
    END {
        if (!saw_begin || !saw_end || inside) exit 23
    }
' "$document" > "$document_tmp" || {
    status=$?
    printf 'invalid parser inventory block in %s (parser status %d)\n' \
        "$document" "$status" >&2
    exit 1
}

cut -f2 "$document_tmp" | LC_ALL=C sort > "$document_paths_tmp"
if [[ $(wc -l < "$document_paths_tmp") -ne $(LC_ALL=C sort -u "$document_paths_tmp" | wc -l) ]]; then
    printf 'parser inventory contains duplicate source paths\n' >&2
    comm -12 "$document_paths_tmp" <(uniq -d "$document_paths_tmp") >&2 || true
    exit 1
fi

invalid=0
while IFS=$'\t' read -r family source_path; do
    case "$family" in
        P-STATE|P-EDITOR|P-RESOURCE|P-ADAPTER|P-MIDI|P-MIDI-CI|P-AUDIO|P-ADM|P-SOFA|P-ARA|P-CONFIG|N-OUTPUT|N-TEST|N-DELEGATE|N-NONINPUT)
            ;;
        *)
            printf 'parser inventory uses an unknown family: %s (%s)\n' \
                "$family" "$source_path" >&2
            invalid=1
            ;;
    esac
    case "$source_path" in
        zig-vst3-plugin/src/*|zig-vst3/src/*) ;;
        *)
            printf 'parser inventory path is outside production roots: %s (%s)\n' \
                "$source_path" "$family" >&2
            invalid=1
            continue
            ;;
    esac
    if ! git ls-files --error-unmatch -- "$source_path" >/dev/null 2>&1; then
        printf 'parser inventory path is not tracked: %s (%s)\n' \
            "$source_path" "$family" >&2
        invalid=1
    fi
done < "$document_tmp"
if [[ "$invalid" -ne 0 ]]; then
    exit 1
fi

missing_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-parser-missing.XXXXXX")
stale_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-parser-stale.XXXXXX")
trap 'rm -f "$candidate_tmp" "$document_tmp" "$document_paths_tmp" "$missing_tmp" "$stale_tmp"' EXIT
comm -23 "$candidate_tmp" "$document_paths_tmp" > "$missing_tmp"
comm -13 "$candidate_tmp" "$document_paths_tmp" > "$stale_tmp"

if [[ -s "$missing_tmp" || -s "$stale_tmp" ]]; then
    if [[ -s "$missing_tmp" ]]; then
        printf 'parser inventory is missing candidate sources:\n' >&2
        sed 's/^/  /' "$missing_tmp" >&2
    fi
    if [[ -s "$stale_tmp" ]]; then
        printf 'parser inventory contains stale sources:\n' >&2
        sed 's/^/  /' "$stale_tmp" >&2
    fi
    exit 1
fi

printf 'parser inventory covers %d production sources\n' \
    "$(wc -l < "$candidate_tmp")"
