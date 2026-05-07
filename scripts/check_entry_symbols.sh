#!/usr/bin/env bash
set -euo pipefail

artifact="${1:?usage: scripts/check_entry_symbols.sh path/to/plugin-library}"

case "$(uname -s)" in
    Darwin)
        required_symbols=(GetPluginFactory bundleEntry bundleExit)
        ;;
    Linux)
        required_symbols=(GetPluginFactory ModuleEntry ModuleExit)
        ;;
    MINGW*|MSYS*|CYGWIN*)
        required_symbols=(GetPluginFactory InitDll ExitDll)
        ;;
    *)
        echo "unsupported host for entry symbol validation: $(uname -s)" >&2
        exit 1
        ;;
esac

if command -v nm >/dev/null 2>&1; then
    symbols="$(nm -g "$artifact")"
elif command -v llvm-nm >/dev/null 2>&1; then
    symbols="$(llvm-nm -g "$artifact")"
else
    echo "entry symbol validation requires nm or llvm-nm" >&2
    exit 1
fi

for symbol in "${required_symbols[@]}"; do
    if ! grep -Eq "(^|[[:space:]])_?${symbol}$" <<<"$symbols"; then
        echo "missing VST3 entry symbol: ${symbol}" >&2
        exit 1
    fi
done
