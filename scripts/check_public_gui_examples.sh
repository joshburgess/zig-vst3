#!/usr/bin/env sh
set -eu

files='examples/channel_strip_plugin.zig
examples/parametric_eq_plugin.zig
examples/resonant_filter_plugin.zig
examples/ir_loader_plugin.zig
examples/sample_player_editor.zig'

for file in $files; do
    if [ ! -f "$file" ]; then
        printf 'missing public GUI example: %s\n' "$file" >&2
        exit 1
    fi
done

if rg -n 'gui-adapters|zig_vstgui_|@cImport' $files; then
    printf 'public GUI examples must not import adapter internals or native adapter symbols\n' >&2
    exit 1
fi

if ! rg -q '@import\("zig-vst3"\)' examples/sample_player_editor.zig; then
    printf 'sample_player_editor.zig must import the public zig-vst3 package\n' >&2
    exit 1
fi

printf 'public GUI example boundary checks passed\n'
