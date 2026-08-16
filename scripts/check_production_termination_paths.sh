#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "--require-complete-allowlist" ]; then
    shift
fi
if [ "$#" -gt 1 ]; then
    printf 'usage: %s [--require-complete-allowlist] [repository]\n' "$0" >&2
    exit 2
fi
repository="$(CDPATH='' cd -- "${1:-$script_dir/..}" && pwd)"
runtime_sources="$repository/zig-vst3/src"
framework_sources="$repository/zig-vst3-plugin/src"
example_sources="$repository/examples"

findings=$(find "$runtime_sources" "$framework_sources" "$example_sources" -type f -name '*.zig' -exec awk -v root="$repository/" '
    function structure(source, output, cursor, current, following, quote, escaped) {
        if (source ~ /^[[:space:]]*\\\\/) return ""
        output = ""
        quote = 0
        escaped = 0
        for (cursor = 1; cursor <= length(source); cursor++) {
            current = substr(source, cursor, 1)
            following = substr(source, cursor + 1, 1)
            if (quote != 0) {
                if (escaped) {
                    escaped = 0
                } else if (current == sprintf("%c", 92)) {
                    escaped = 1
                } else if ((quote == 1 && current == "\"") ||
                    (quote == 2 && current == sprintf("%c", 39)))
                {
                    quote = 0
                }
                continue
            }
            if (current == "/" && following == "/") break
            if (current == "\"") {
                quote = 1
            } else if (current == sprintf("%c", 39)) {
                quote = 2
            } else {
                output = output current
            }
        }
        return output
    }

    FNR == 1 {
        in_test = 0
        test_opened = 0
        test_depth = 0
    }

    {
        structural_source = structure($0)
    }

    !in_test && $0 ~ /^[[:space:]]*test([[:space:]]|\")/ {
        in_test = 1
    }

    in_test {
        for (character = 1; character <= length(structural_source); character++) {
            token = substr(structural_source, character, 1)
            if (token == "{") {
                test_depth++
                test_opened = 1
            } else if (token == "}") {
                test_depth--
            }
        }
        if (test_opened && test_depth == 0) {
            in_test = 0
            test_opened = 0
        }
        next
    }

    structural_source ~ /(^|[^[:alnum:]_])unreachable([^[:alnum:]_]|$)/ ||
        structural_source ~ /std\.debug\.(assert|panic)/ ||
        structural_source ~ /@(panic|trap)/ {
        source = $0
        sub(/^[[:space:]]*/, "", source)
        sub(/[[:space:]]*$/, "", source)
        path = FILENAME
        sub("^" root, "", path)
        printf "%s:%d:%s\n", path, FNR, source
    }
' {} +)

if [ -n "$findings" ]; then
    printf '%s\n' "$findings" >&2
    printf 'production source adds an unreviewed termination path\n' >&2
    exit 1
fi

printf 'production termination path scan passed\n'
