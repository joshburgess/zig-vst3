#!/bin/sh
set -eu

fixture=${1:?missing MP3 fixture path}
test -f "$fixture"

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-mp3-interop.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

tested=0

fail() {
    printf '%s\n' "$1" >&2
    exit 1
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
