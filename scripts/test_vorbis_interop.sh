#!/bin/sh
set -eu

fixture=${1:?missing Vorbis fixture path}
test -f "$fixture"

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-interop.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

tested=0

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

if [ "${VORBIS_INTEROP_SKIP_FFMPEG-0}" != "1" ] &&
    command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg_decoded="$temporary/ffmpeg-decoded.pcm"
    ffmpeg -v error -y -i "$fixture" \
        -map 0:a:0 \
        -f s16le \
        -acodec pcm_s16le \
        "$ffmpeg_decoded"
    [ "$(wc -c <"$ffmpeg_decoded")" -gt 0 ] ||
        fail "FFmpeg produced empty Vorbis PCM"
    if ! od -An -tu1 "$ffmpeg_decoded" |
        grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'; then
        fail "FFmpeg produced silent Vorbis PCM"
    fi
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
            [ "$(wc -c <"$decoded")" -gt 44 ] ||
                fail "AudioToolbox produced an empty WAV"
            if command -v ffmpeg >/dev/null 2>&1; then
                decoded_pcm="$temporary/audio-toolbox-decoded.pcm"
                ffmpeg -v error -y -i "$decoded" \
                    -map 0:a:0 \
                    -f s16le \
                    -acodec pcm_s16le \
                    "$decoded_pcm"
                [ "$(wc -c <"$decoded_pcm")" -gt 0 ] ||
                    fail "AudioToolbox WAV contains no decodable PCM"
                if ! od -An -tu1 "$decoded_pcm" |
                    grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'; then
                    fail "AudioToolbox produced silent Vorbis PCM"
                fi
            else
                afinfo "$decoded" >"$temporary/decoded.txt"
                if ! grep -q "WAVE" "$temporary/decoded.txt" ||
                    ! grep -q "48000" "$temporary/decoded.txt"; then
                    sed -n '1,120p' "$temporary/decoded.txt" >&2
                    fail "AudioToolbox reported unexpected WAV metadata"
                fi
                data_offset=$(awk '/audio data file offset:/ { print $5 }' "$temporary/decoded.txt")
                audio_bytes=$(awk '/audio bytes:/ { print $3 }' "$temporary/decoded.txt")
                case "$data_offset:$audio_bytes" in
                    *[!0-9:]* | :* | *:)
                        sed -n '1,120p' "$temporary/decoded.txt" >&2
                        fail "AudioToolbox did not report a usable PCM data range"
                        ;;
                esac
                [ "$audio_bytes" -gt 0 ] ||
                    fail "AudioToolbox reported an empty PCM data range"
                if ! dd if="$decoded" bs=1 skip="$data_offset" count="$audio_bytes" 2>/dev/null |
                    od -An -tu1 |
                    grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'; then
                    sed -n '1,120p' "$temporary/decoded.txt" >&2
                    fail "AudioToolbox produced silent Vorbis PCM"
                fi
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
