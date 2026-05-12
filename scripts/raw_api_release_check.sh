#!/usr/bin/env sh
set -eu

"${ZIG:-zig}" build test
"${ZIG:-zig}" build raw-api-abi

case "$(uname -s)" in
    Darwin)
        "${ZIG:-zig}" build validator
        "${ZIG:-zig}" build validate-examples
        ;;
    *)
        printf 'Skipping validator: Steinberg validator gate is currently run on macOS.\n'
        ;;
esac
