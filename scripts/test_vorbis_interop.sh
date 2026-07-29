#!/bin/sh
set -eu

fixture=${1:?missing Vorbis fixture path}
test -f "$fixture"

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-interop.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

tested=0

if [ "${VORBIS_INTEROP_SKIP_FFMPEG-0}" != "1" ] &&
    command -v ffmpeg >/dev/null 2>&1 &&
    command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$fixture" >"$temporary/ffprobe.txt"
    grep -q '^vorbis$' "$temporary/ffprobe.txt"
    grep -q '^48000$' "$temporary/ffprobe.txt"

    ffmpeg_decoded="$temporary/ffmpeg-decoded.pcm"
    ffmpeg -v error -y -i "$fixture" \
        -map 0:a:0 \
        -f s16le \
        -acodec pcm_s16le \
        "$ffmpeg_decoded"
    test "$(wc -c <"$ffmpeg_decoded")" -gt 0
    od -An -tu1 "$ffmpeg_decoded" |
        grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'
    printf 'Vorbis FFmpeg interoperability test passed\n'
    tested=1
fi

if [ "${VORBIS_INTEROP_ONLY_FFMPEG-0}" != "1" ] &&
    [ "$(uname -s)" = "Darwin" ] &&
    command -v afconvert >/dev/null 2>&1 &&
    command -v afinfo >/dev/null 2>&1; then
    if afinfo "$fixture" >"$temporary/source.txt" 2>"$temporary/source-error.txt"; then
        decoded="$temporary/decoded.wav"
        if afconvert "$fixture" "$decoded" -f WAVE -d LEI16; then
            test "$(wc -c <"$decoded")" -gt 44
            if command -v ffmpeg >/dev/null 2>&1 &&
                command -v ffprobe >/dev/null 2>&1; then
                ffprobe -v error \
                    -select_streams a:0 \
                    -show_entries stream=codec_name,sample_rate \
                    -of default=noprint_wrappers=1:nokey=1 \
                    "$decoded" >"$temporary/decoded-probe.txt"
                grep -q '^pcm_s16le$' "$temporary/decoded-probe.txt"
                grep -q '^48000$' "$temporary/decoded-probe.txt"
                decoded_pcm="$temporary/audio-toolbox-decoded.pcm"
                ffmpeg -v error -y -i "$decoded" \
                    -map 0:a:0 \
                    -f s16le \
                    -acodec pcm_s16le \
                    "$decoded_pcm"
                test "$(wc -c <"$decoded_pcm")" -gt 0
                od -An -tu1 "$decoded_pcm" |
                    grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'
            else
                afinfo "$decoded" >"$temporary/decoded.txt"
                grep -q "WAVE" "$temporary/decoded.txt"
                grep -q "48000" "$temporary/decoded.txt"
                data_offset=$(awk '/audio data file offset:/ { print $5 }' "$temporary/decoded.txt")
                audio_bytes=$(awk '/audio bytes:/ { print $3 }' "$temporary/decoded.txt")
                case "$data_offset:$audio_bytes" in
                    *[!0-9:]* | :* | *:)
                        printf 'AudioToolbox did not report a usable PCM data range\n' >&2
                        exit 1
                        ;;
                esac
                test "$audio_bytes" -gt 0
                dd if="$decoded" bs=1 skip="$data_offset" count="$audio_bytes" 2>/dev/null |
                    od -An -tu1 |
                    grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'
            fi
            printf 'Vorbis AudioToolbox interoperability test passed\n'
            tested=1
        else
            printf 'Vorbis AudioToolbox decoder unavailable; test skipped\n'
        fi
    else
        printf 'Vorbis AudioToolbox decoder unavailable; test skipped\n'
    fi
fi

if [ "$tested" -eq 0 ]; then
    printf 'Vorbis decoder interoperability tests skipped\n'
fi
