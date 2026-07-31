#!/bin/sh
set -eu

fixture=${1:?missing MP3 fixture path}
decode_probe=${2-}
reference_probe=${3-}
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

compare_reference_pcm() {
    encoded_path=$1
    channels=$2
    reference_path=$3
    success_message=$4
    ffmpeg -v error -y \
        -i "$encoded_path" \
        -map 0:a:0 \
        -f f32le \
        -acodec pcm_f32le \
        "$reference_path"
    "$reference_probe" \
        "$encoded_path" \
        "$reference_path" \
        "$channels"
    printf '%s\n' "$success_message"
}

compare_lame_reference_pcm() {
    encoded_path=$1
    channels=$2
    decoded_wav=$3
    reference_path=$4
    success_message=$5
    lame --silent --decode "$encoded_path" "$decoded_wav"
    ffmpeg -v error -y \
        -i "$decoded_wav" \
        -map 0:a:0 \
        -f f32le \
        -acodec pcm_f32le \
        "$reference_path"
    "$reference_probe" \
        "$encoded_path" \
        "$reference_path" \
        "$channels"
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

            if [ -n "$reference_probe" ]; then
                compare_reference_pcm \
                    "$external_mpeg1" \
                    2 \
                    "$temporary/ffmpeg-mpeg1-reference.f32le" \
                    'MP3 FFmpeg MPEG-1 decoded-PCM reference probe passed'
            fi

            if ffmpeg -hide_banner -encoders 2>/dev/null |
                grep -q '[[:space:]]libshine[[:space:]]'; then
                external_shine="$temporary/shine-mpeg1-stereo.mp3"
                ffmpeg -v error -y \
                    -f lavfi \
                    -i 'aevalsrc=0.22*sin(2*PI*510*t)|0.17*sin(2*PI*730*t):s=44100' \
                    -t 0.35 \
                    -c:a libshine \
                    -b:a 128k \
                    -id3v2_version 0 \
                    -write_xing 0 \
                    "$external_shine"
                "$decode_probe" "$external_shine" 44100 2
                printf 'MP3 Shine MPEG-1 stereo decoder probe passed\n'
                if [ -n "$reference_probe" ]; then
                    compare_reference_pcm \
                        "$external_shine" \
                        2 \
                        "$temporary/shine-mpeg1-reference.f32le" \
                        'MP3 Shine MPEG-1 decoded-PCM reference probe passed'
                fi
            else
                printf 'MP3 Shine encoder unavailable; test skipped\n'
            fi

            if command -v lame >/dev/null 2>&1; then
                protected_wav="$temporary/lame-protected-source.wav"
                protected_mp3="$temporary/lame-protected.mp3"
                ffmpeg -v error -y \
                    -f lavfi \
                    -i 'aevalsrc=0.19*sin(2*PI*390*t)|0.14*sin(2*PI*810*t):s=44100' \
                    -t 0.35 \
                    -c:a pcm_s16le \
                    "$protected_wav"
                lame --silent --cbr -p -b 128 \
                    "$protected_wav" \
                    "$protected_mp3"
                "$decode_probe" "$protected_mp3" 44100 2 \
                    --require-protected
                printf 'MP3 LAME protected-frame decoder probe passed\n'
                if [ -n "$reference_probe" ]; then
                    compare_reference_pcm \
                        "$protected_mp3" \
                        2 \
                        "$temporary/lame-protected-reference.f32le" \
                        'MP3 LAME protected decoded-PCM reference probe passed'
                fi

                free_format_mp3="$temporary/lame-free-format.mp3"
                lame --silent --freeformat -b 320 \
                    "$protected_wav" \
                    "$free_format_mp3"
                "$decode_probe" "$free_format_mp3" 44100 2 \
                    --require-free-format
                printf 'MP3 LAME free-format decoder probe passed\n'
                if [ -n "$reference_probe" ]; then
                    compare_lame_reference_pcm \
                        "$free_format_mp3" \
                        2 \
                        "$temporary/lame-free-format-reference.wav" \
                        "$temporary/lame-free-format-reference.f32le" \
                        'MP3 LAME free-format decoded-PCM reference probe passed'
                fi
            else
                printf 'MP3 LAME executable unavailable; protected and free-format tests skipped\n'
            fi

            external_tagged_long="$temporary/ffmpeg-mpeg1-tagged-long.mp3"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.20*sin(2*PI*275*t)|0.15*sin(2*PI*715*t):s=44100' \
                -t 2.2 \
                -c:a libmp3lame \
                -b:a 128k \
                -id3v2_version 3 \
                -write_id3v1 1 \
                -metadata title='Interop seek fixture' \
                -metadata artist='zig-vst3' \
                "$external_tagged_long"
            "$decode_probe" "$external_tagged_long" 44100 2 \
                --require-tagged-multiple-seek-points
            printf 'MP3 FFmpeg tagged multi-point seek probe passed\n'

            external_id3v24="$temporary/ffmpeg-mpeg1-id3v24.mp3"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.18*sin(2*PI*330*t)|0.12*sin(2*PI*550*t):s=44100' \
                -t 0.35 \
                -c:a libmp3lame \
                -q:a 4 \
                -id3v2_version 4 \
                -metadata title='ID3v2.4 fixture' \
                "$external_id3v24"
            "$decode_probe" "$external_id3v24" 44100 2 \
                --require-id3v2.4
            printf 'MP3 FFmpeg ID3v2.4 decoder probe passed\n'

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
            if [ -n "$reference_probe" ]; then
                compare_reference_pcm \
                    "$external_mpeg2" \
                    1 \
                    "$temporary/ffmpeg-mpeg2-reference.f32le" \
                    'MP3 FFmpeg MPEG-2 decoded-PCM reference probe passed'
            fi

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
            if [ -n "$reference_probe" ]; then
                compare_reference_pcm \
                    "$external_mpeg25" \
                    1 \
                    "$temporary/ffmpeg-mpeg25-reference.f32le" \
                    'MP3 FFmpeg MPEG-2.5 decoded-PCM reference probe passed'
            fi

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
