#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
repository="${1:-$script_dir/..}"
runtime_sources="$repository/zig-vst3/src"
framework_sources="$repository/zig-vst3-plugin/src"

findings=$(find "$runtime_sources" "$framework_sources" -type f -name '*.zig' -exec awk '
    function inspect(signature, source, line, arguments) {
        if (signature !~ /callconv\(\.c\)/) return
        arguments = signature
        sub(/^.*\*const fn \(/, "", arguments)
        sub(/\)[[:space:]]*callconv\(\.c\).*$/, "", arguments)
        if (arguments !~ /,/) return
        if (arguments !~ /^[^,]*\*anyopaque[[:space:]]*,/) return
        sub(/^[^,]*,/, "", arguments)
        if (arguments ~ /(^|[,:])[[:space:]]*\*/ ||
            arguments ~ /(^|[,:])[[:space:]]*\[\*\]/ ||
            arguments ~ /(^|[,:])[[:space:]]*\[\*:[^]]*\]/)
        {
            printf "%s:%d:%s\n", source, line, signature
        }
    }

    BEGIN {
        collecting = 0
    }

    {
        if (FNR == 1) {
            collecting = 0
            signature = ""
        }
        if (!collecting && $0 ~ /^[[:space:]]*[A-Za-z][A-Za-z0-9_]*: \*const fn \(/) {
            signature = $0
            signature_line = FNR
            collecting = 1
        } else if (collecting) {
            signature = signature " " $0
        }

        if (collecting && signature ~ /callconv\(\.c\)/) {
            inspect(signature, FILENAME, signature_line)
            collecting = 0
            signature = ""
        } else if (collecting && $0 ~ /\)[[:space:]]+[^,]+,[[:space:]]*$/) {
            collecting = 0
            signature = ""
        }
    }

' {} +)
if [ -n "$findings" ]; then
    printf '%s\n' "$findings" >&2
    printf 'C callback uses a non-null raw pointer argument\n' >&2
    exit 1
fi

printf 'raw callback pointer scan passed\n'
