#!/usr/bin/env sh
set -eu

zig build test
zig build layer1-abi

case "$(uname -s)" in
    Darwin)
        zig build validator
        zig build validate-examples
        ;;
    *)
        printf 'Skipping validator: Steinberg validator gate is currently run on macOS.\n'
        ;;
esac
