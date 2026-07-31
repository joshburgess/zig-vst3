#!/bin/sh
set -eu

fixture=${1:?missing MP3 fixture path}
decode_probe=${2-}
test -f "$fixture"

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-mp3-interop.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

tested=0

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

require_probe_rejection() {
    damaged_path=$1
    failure_message=$2
    success_message=$3
    if "$decode_probe" "$damaged_path" >/dev/null 2>&1; then
        fail "$failure_message"
    fi
    printf '%s\n' "$success_message"
}

wav_data_range() {
    wav_path=$1
    wav_bytes=$(wc -c <"$wav_path")
    chunk_offset=12
    while [ $((chunk_offset + 8)) -le "$wav_bytes" ]; do
        # shellcheck disable=SC2046
        set -- $(dd if="$wav_path" bs=1 skip="$chunk_offset" count=8 2>/dev/null |
            od -An -tu1 -v)
        [ "$#" -eq 8 ] || return 1
        chunk_size=$((
            $5 +
                $6 * 256 +
                $7 * 65536 +
                $8 * 16777216
        ))
        payload_offset=$((chunk_offset + 8))
        payload_end=$((payload_offset + chunk_size))
        [ "$payload_end" -le "$wav_bytes" ] || return 1
        if [ "$1" -eq 100 ] &&
            [ "$2" -eq 97 ] &&
            [ "$3" -eq 116 ] &&
            [ "$4" -eq 97 ]; then
            printf '%s %s\n' "$payload_offset" "$chunk_size"
            return 0
        fi
        chunk_offset=$((payload_end + chunk_size % 2))
    done
    return 1
}

assert_nonsilent() {
    path=$1
    offset=$2
    count=$3
    [ "$count" -gt 0 ] || fail "independent decoder produced empty MP3 PCM"
    if ! dd if="$path" bs=1 skip="$offset" count="$count" 2>/dev/null |
        od -An -tu1 |
        grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'; then
        fail "independent decoder produced silent MP3 PCM"
    fi
}

if [ -n "$decode_probe" ]; then
    "$decode_probe" "$fixture" 44100 2
    printf 'MP3 project decoder probe passed\n'
fi

if [ "${MP3_INTEROP_SKIP_FFMPEG-0}" != "1" ] &&
    command -v ffmpeg >/dev/null 2>&1; then
    decoded="$temporary/ffmpeg-decoded.pcm"
    ffmpeg -v error -y -i "$fixture" \
        -map 0:a:0 \
        -f s16le \
        -acodec pcm_s16le \
        "$decoded"
    assert_nonsilent "$decoded" 0 "$(wc -c <"$decoded")"
    if command -v ffprobe >/dev/null 2>&1; then
        ffprobe -v error \
            -select_streams a:0 \
            -show_entries stream=sample_rate,channels \
            -of default=noprint_wrappers=1 \
            "$fixture" >"$temporary/ffprobe.txt"
        grep -q '^sample_rate=44100$' "$temporary/ffprobe.txt" ||
            fail "FFprobe reported an unexpected MP3 sample rate"
        grep -q '^channels=2$' "$temporary/ffprobe.txt" ||
            fail "FFprobe reported an unexpected MP3 channel count"
    fi
    printf 'MP3 FFmpeg interoperability test passed\n'
    tested=1

    if [ -n "$decode_probe" ]; then
        external_mpeg1="$temporary/ffmpeg-mpeg1-stereo.mp3"
        if ffmpeg -v error -y \
            -f lavfi \
            -i 'aevalsrc=0.25*sin(2*PI*440*t)|0.2*sin(2*PI*660*t):s=44100' \
            -t 0.35 \
            -c:a libmp3lame \
            -q:a 4 \
            "$external_mpeg1"; then
            "$decode_probe" "$external_mpeg1" 44100 2
            printf 'MP3 FFmpeg MPEG-1 stereo decoder probe passed\n'

            external_mpeg2="$temporary/ffmpeg-mpeg2-mono.mp3"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.25*sin(2*PI*440*t):s=22050' \
                -t 0.35 \
                -c:a libmp3lame \
                -b:a 48k \
                -id3v2_version 0 \
                "$external_mpeg2"
            "$decode_probe" "$external_mpeg2" 22050 1
            printf 'MP3 FFmpeg MPEG-2 mono decoder probe passed\n'

            external_mpeg25="$temporary/ffmpeg-mpeg25-mono.mp3"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.20*sin(2*PI*880*t):s=8000' \
                -t 0.35 \
                -c:a libmp3lame \
                -b:a 24k \
                -id3v2_version 0 \
                "$external_mpeg25"
            "$decode_probe" "$external_mpeg25" 8000 1
            printf 'MP3 FFmpeg MPEG-2.5 mono decoder probe passed\n'

            external_truncated="$temporary/ffmpeg-mpeg1-truncated.mp3"
            external_bytes=$(wc -c <"$external_mpeg1")
            [ "$external_bytes" -gt 1 ] ||
                fail "External MP3 fixture is too short to truncate"
            dd if="$external_mpeg1" of="$external_truncated" bs=1 \
                count=$((external_bytes - 1)) 2>/dev/null
            require_probe_rejection \
                "$external_truncated" \
                "Project decoder accepted a truncated external MP3" \
                "MP3 FFmpeg truncation rejection passed"

            external_format_change="$temporary/ffmpeg-format-change.mp3"
            cat "$external_mpeg1" "$external_mpeg2" \
                >"$external_format_change"
            require_probe_rejection \
                "$external_format_change" \
                "Project decoder accepted an external MP3 format change" \
                "MP3 FFmpeg format-change rejection passed"
        else
            printf 'MP3 FFmpeg encoder unavailable; test skipped\n'
        fi
    fi
fi

if [ "${MP3_INTEROP_ONLY_FFMPEG-0}" != "1" ] &&
    [ "$(uname -s)" = "Darwin" ] &&
    command -v afconvert >/dev/null 2>&1 &&
    command -v afinfo >/dev/null 2>&1; then
    if afinfo "$fixture" >"$temporary/source.txt" &&
        grep -q '44100' "$temporary/source.txt"; then
        decoded="$temporary/audio-toolbox-decoded.wav"
        if afconvert "$fixture" "$decoded" -f WAVE -d LEI16; then
            afinfo "$decoded" >"$temporary/decoded.txt"
            grep -q '44100' "$temporary/decoded.txt" ||
                fail "AudioToolbox reported an unexpected decoded sample rate"
            data_range=$(wav_data_range "$decoded") ||
                fail "AudioToolbox produced malformed WAV output"
            # shellcheck disable=SC2086
            set -- $data_range
            assert_nonsilent "$decoded" "$1" "$2"
            printf 'MP3 AudioToolbox interoperability test passed\n'
            tested=1
        else
            printf 'MP3 AudioToolbox decoder unavailable; test skipped\n'
        fi
    else
        printf 'MP3 AudioToolbox decoder unavailable; test skipped\n'
    fi
fi

if [ "$tested" -eq 0 ]; then
    printf 'MP3 decoder interoperability tests skipped\n'
fi
