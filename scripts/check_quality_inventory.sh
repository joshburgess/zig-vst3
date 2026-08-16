#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

inventory_tmp=$(mktemp "${TMPDIR:-/tmp}/zig-vst3-quality-inventory.XXXXXX")
trap 'rm -f "$inventory_tmp"' EXIT

is_source() {
    case "$1" in
        build.zig|*.zig|*.zon|*.c|*.cc|*.cpp|*.cxx|*.h|*.hpp|*.m|*.mm|*.sh|*.ps1|*.lua|*.yml|*.yaml|*.plist)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

review_unit() {
    case "$1" in
        .github/*|build.zig|build.zig.zon|scripts/*)
            printf '%s\n' Q00
            ;;
        vendor/ARA_API/*|zig-vst3/src/ara*.zig)
            printf '%s\n' Q02
            ;;
        zig-vst3/src/pluginterfaces/*)
            printf '%s\n' Q01
            ;;
        zig-vst3/src/vstgui*.zig|zig-vst3/src/vst_wayland*.zig)
            printf '%s\n' Q03
            ;;
        zig-vst3/src/zig_vst3_plugin*.zig)
            printf '%s\n' Q04
            ;;
        zig-vst3/src/*_plugin.zig|zig-vst3/src/*_spec.zig)
            printf '%s\n' Q05
            ;;
        zig-vst3/src/*.zig)
            printf '%s\n' Q01
            ;;
        zig-vst3-plugin/src/process/midi*.zig|zig-vst3-plugin/src/process/mpe*.zig)
            printf '%s\n' Q09
            ;;
        zig-vst3-plugin/src/process/*.zig|zig-vst3-plugin/src/process.zig)
            printf '%s\n' Q08
            ;;
        zig-vst3-plugin/src/parameters/*|zig-vst3-plugin/src/state/*|zig-vst3-plugin/src/resource/*|zig-vst3-plugin/src/units/*|zig-vst3-plugin/src/parameters.zig|zig-vst3-plugin/src/state.zig|zig-vst3-plugin/src/resource.zig|zig-vst3-plugin/src/units.zig)
            printf '%s\n' Q07
            ;;
        zig-vst3-plugin/src/dsp/ogg.zig|zig-vst3-plugin/src/dsp/ogg/*.zig)
            printf '%s\n' Q10
            ;;
        zig-vst3-plugin/src/dsp/mp3*.zig|zig-vst3-plugin/src/dsp/mp3/*.zig)
            printf '%s\n' Q11
            ;;
        zig-vst3-plugin/src/dsp/flac.zig|zig-vst3-plugin/src/dsp/id3.zig|zig-vst3-plugin/src/dsp/audio_file_reader.zig|zig-vst3-plugin/src/dsp/audio_metadata.zig|zig-vst3-plugin/src/dsp/broadcast_metadata.zig|zig-vst3-plugin/src/dsp/ixml.zig|zig-vst3-plugin/src/dsp/xml.zig|zig-vst3-plugin/src/dsp/*writer*.zig|zig-vst3-plugin/src/dsp/file_*_io.zig|zig-vst3-plugin/src/dsp/pcm_encode.zig)
            printf '%s\n' Q12
            ;;
        zig-vst3-plugin/src/dsp/adm*.zig|zig-vst3-plugin/src/dsp/adm_render/*.zig|zig-vst3-plugin/src/dsp/adm_xml/*.zig)
            printf '%s\n' Q13
            ;;
        zig-vst3-plugin/src/dsp/hrtf*.zig|zig-vst3-plugin/src/dsp/hrtf/*.zig|zig-vst3-plugin/src/dsp/matrix.zig|zig-vst3-plugin/src/dsp/matrix/*.zig|zig-vst3-plugin/src/hoa_tests.zig|zig-vst3-plugin/src/hrtf_tests.zig|zig-vst3-plugin/src/hrtf_thread_sanitizer.zig)
            printf '%s\n' Q14
            ;;
        zig-vst3-plugin/src/dsp/*.zig|zig-vst3-plugin/src/dsp.zig|zig-vst3-plugin/src/gui_ir_convolution.zig)
            printf '%s\n' Q15
            ;;
        zig-vst3-plugin/src/gui*.zig|zig-vst3-plugin/src/editor_state.zig)
            printf '%s\n' Q16
            ;;
        zig-vst3-plugin/src/lv2*.zig|zig-vst3-plugin/src/audio_unit*)
            printf '%s\n' Q17
            ;;
        zig-vst3-plugin/src/alsa*.zig|zig-vst3-plugin/src/core_audio.zig|zig-vst3-plugin/src/core_midi.zig|zig-vst3-plugin/src/cocoa_window.zig|zig-vst3-plugin/src/pipewire.zig|zig-vst3-plugin/src/wasapi.zig|zig-vst3-plugin/src/wayland_window.zig|zig-vst3-plugin/src/win_midi.zig|zig-vst3-plugin/src/win_ump.zig|zig-vst3-plugin/src/win_window.zig|zig-vst3-plugin/src/x11_window.zig|zig-vst3-plugin/src/plugin/alsa*.zig|zig-vst3-plugin/src/plugin/core_audio.zig|zig-vst3-plugin/src/plugin/core_midi.zig|zig-vst3-plugin/src/plugin/cocoa_window.zig|zig-vst3-plugin/src/plugin/device_catalog.zig|zig-vst3-plugin/src/plugin/native_callback_gate.zig|zig-vst3-plugin/src/plugin/pipewire.zig|zig-vst3-plugin/src/plugin/standalone*.zig|zig-vst3-plugin/src/plugin/wasapi.zig|zig-vst3-plugin/src/plugin/wayland_window.zig|zig-vst3-plugin/src/plugin/win_midi.zig|zig-vst3-plugin/src/plugin/win_ump.zig|zig-vst3-plugin/src/plugin/win_window.zig|zig-vst3-plugin/src/plugin/x11_window.zig|zig-vst3-plugin/src/plugin/*_shim.c|zig-vst3-plugin/src/plugin/*_shim.cpp|zig-vst3-plugin/src/plugin/*_shim.h|zig-vst3-plugin/src/plugin/*_shim.m|zig-vst3-plugin/src/plugin/*_unavailable.c|zig-vst3-plugin/src/plugin/*_scheduler_queue.h|zig-vst3-plugin/src/plugin/*_ref_count.hpp)
            printf '%s\n' Q18
            ;;
        zig-vst3-plugin/src/plugin/*|zig-vst3-plugin/src/common.zig|zig-vst3-plugin/src/core.zig|zig-vst3-plugin/src/plugin.zig|zig-vst3-plugin/src/realtime_audit.zig|zig-vst3-plugin/src/root.zig|zig-vst3-plugin/src/serial_generation.zig)
            printf '%s\n' Q06
            ;;
        gui-adapters/*)
            printf '%s\n' Q19
            ;;
        examples/*)
            printf '%s\n' Q20
            ;;
        tests/*)
            printf '%s\n' Q21
            ;;
        tools/*)
            printf '%s\n' Q22
            ;;
        *)
            return 1
            ;;
    esac
}

source_metrics() {
    awk '
        /Allocator|alloc[[:space:]]*\(|create[[:space:]]*\(|dupe[[:space:]]*\(|free[[:space:]]*\(|destroy[[:space:]]*\(/ { allocation += 1 }
        /@ptrCast|@alignCast|@ptrFromInt|\[\*c\]|\*anyopaque|\?\*anyopaque/ { pointer += 1 }
        /std\.atomic|std::atomic|_Atomic|atomic_(load|store|fetch|exchange|compare|init)|Atomic[[:space:]]*\(|\.atomic/ { atomic += 1 }
        /callback|Callback|callconv/ { callback += 1 }
        /parse|Parse|decode|Decode|restore|Restore|deserialize|Deserialize/ { parser += 1 }
        /^[[:space:]]*pub[[:space:]]+(const|fn|var)/ { public_decl += 1 }
        END {
            printf "%d\t%d\t%d\t%d\t%d\t%d", allocation, pointer, atomic, callback, parser, public_decl
        }
    ' "$1"
}

unclassified=0
while IFS= read -r source_path; do
    if ! is_source "$source_path"; then
        continue
    fi
    if unit=$(review_unit "$source_path"); then
        lines=$(wc -l < "$source_path")
        metrics=$(source_metrics "$source_path")
        printf '%s\t%s\t%s\t%s\n' \
            "$unit" "$lines" "$metrics" "$source_path" >> "$inventory_tmp"
    else
        printf 'unclassified source: %s\n' "$source_path" >&2
        unclassified=1
    fi
done < <(git ls-files)

if [[ "$unclassified" -ne 0 ]]; then
    exit 1
fi

LC_ALL=C sort -k1,1 -k9,9 "$inventory_tmp" -o "$inventory_tmp"
awk -F '\t' '
    {
        files[$1] += 1
        lines[$1] += $2
        allocation[$1] += $3
        pointer[$1] += $4
        atomic[$1] += $5
        callback[$1] += $6
        parser[$1] += $7
        public_decl[$1] += $8
        total_files += 1
        total_lines += $2
    }
    END {
        print "unit\tfiles\tlines\tallocation\tpointer\tatomic\tcallback\tparser\tpublic"
        for (i = 0; i <= 22; i += 1) {
            unit = sprintf("Q%02d", i)
            printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", unit, files[unit], lines[unit], allocation[unit], pointer[unit], atomic[unit], callback[unit], parser[unit], public_decl[unit]
        }
        printf "total\t%d\t%d\n", total_files, total_lines
    }
' "$inventory_tmp"

if [[ "${1:-}" == "--files" ]]; then
    printf '\nunit\tlines\tallocation\tpointer\tatomic\tcallback\tparser\tpublic\tpath\n'
    cat "$inventory_tmp"
fi
