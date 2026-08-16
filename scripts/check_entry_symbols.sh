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

if grep -Eq '(^|[[:space:]])_?zig_vst3_dense4_(portable|neon|avx2)$' <<<"$symbols"; then
    echo "C kernel implementation symbols must remain private to the plugin bundle" >&2
    exit 1
fi

if [ "$(uname -s)" = Darwin ]; then
    if grep -Fq "OBJC_CLASS_\$_ZigVstguiAccessibilityElement" <<<"$symbols"; then
        echo "fixed Objective-C accessibility class name would collide across plugin bundles" >&2
        exit 1
    fi
    exports="$(xcrun dyld_info -exports "$artifact")"
    if grep -Eq '(_ZN6VSTGUI|_ZN9ZigVstgui)' <<<"$exports"; then
        echo "VSTGUI implementation symbols must remain private to each plugin bundle" >&2
        exit 1
    fi
fi
