#!/bin/sh
set -eu

fixture=${1:?missing Vorbis fixture path}
decode_probe=${2-}
reference_probe=${3-}
test -f "$fixture"

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-interop.XXXXXX")
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

compare_ffmpeg_reference_pcm() {
    encoded_path=$1
    reference_path=$2
    success_message=$3
    ffmpeg -v error -y \
        -i "$encoded_path" \
        -map 0:a:0 \
        -f f32le \
        -acodec pcm_f32le \
        "$reference_path"
    "$reference_probe" \
        "$encoded_path" \
        --reference-f32le \
        "$reference_path"
    printf '%s\n' "$success_message"
}

compare_xiph_reference_pcm() {
    encoded_path=$1
    reference_path=$2
    success_message=$3
    oggdec -Q -R -b 16 -e 0 -s 1 \
        -o "$reference_path" \
        "$encoded_path"
    "$reference_probe" \
        "$encoded_path" \
        --reference-s16le \
        "$reference_path"
    printf '%s\n' "$success_message"
}

wav_data_range() {
    wav_path=$1
    wav_bytes=$(wc -c <"$wav_path")
    chunk_offset=12
    empty_data_offset=
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
            if [ "$chunk_size" -gt 0 ]; then
                printf '%s %s\n' "$payload_offset" "$chunk_size"
                return 0
            fi
            empty_data_offset=$payload_offset
        fi
        chunk_offset=$((payload_end + chunk_size % 2))
    done
    if [ -n "$empty_data_offset" ]; then
        printf '%s 0\n' "$empty_data_offset"
        return 0
    fi
    return 1
}

if [ -n "$decode_probe" ]; then
    "$decode_probe" "$fixture"
    printf 'Vorbis project decoder and seek probe passed\n'
    project_chained_fixture="$temporary/project-chained.ogg"
    cat "$fixture" "$fixture" >"$project_chained_fixture"
    "$decode_probe" "$project_chained_fixture"
    printf 'Vorbis project chained decoder and seek probe passed\n'

    project_bytes=$(wc -c <"$fixture")
    [ "$project_bytes" -gt 26 ] ||
        fail "Vorbis project fixture is too short to damage"
    project_chained_corrupt_fixture="$temporary/project-chained-corrupt.ogg"
    cp "$project_chained_fixture" "$project_chained_corrupt_fixture"
    printf 'BAD!' |
        dd of="$project_chained_corrupt_fixture" bs=1 \
            seek=$((project_bytes + 22)) conv=notrunc 2>/dev/null
    require_probe_rejection \
        "$project_chained_corrupt_fixture" \
        "Project decoder accepted checksum damage in a later logical stream" \
        "Vorbis project chained checksum corruption rejection passed"

    project_corrupt_fixture="$temporary/project-corrupt.ogg"
    cp "$fixture" "$project_corrupt_fixture"
    printf 'BAD!' |
        dd of="$project_corrupt_fixture" bs=1 seek=22 conv=notrunc \
            2>/dev/null
    require_probe_rejection \
        "$project_corrupt_fixture" \
        "Project decoder accepted a corrupted Ogg checksum" \
        "Vorbis project checksum corruption rejection passed"

    [ "$project_bytes" -gt 1 ] ||
        fail "Vorbis project fixture is too short to truncate"
    project_truncated_fixture="$temporary/project-truncated.ogg"
    dd if="$fixture" of="$project_truncated_fixture" bs=1 \
        count=$((project_bytes - 1)) 2>/dev/null
    require_probe_rejection \
        "$project_truncated_fixture" \
        "Project decoder accepted a truncated Vorbis stream" \
        "Vorbis project truncation rejection passed"
fi

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

    if [ -n "$decode_probe" ]; then
        external_fixture="$temporary/ffmpeg-encoded.ogg"
        if ffmpeg -v error -y \
            -f lavfi \
            -i 'aevalsrc=0.25*sin(2*PI*440*t)|0.2*sin(2*PI*660*t):s=44100' \
            -t 0.12 \
            -c:a libvorbis \
            -q:a 4 \
            "$external_fixture"; then
            "$decode_probe" "$external_fixture"
            printf 'Vorbis FFmpeg stereo encoder decode and seek test passed\n'
            if [ -n "$reference_probe" ] &&
                command -v oggdec >/dev/null 2>&1; then
                compare_xiph_reference_pcm \
                    "$external_fixture" \
                    "$temporary/xiph-stereo-reference.s16le" \
                    'Vorbis Xiph stereo decoded-PCM reference passed'
            fi

            external_long_fixture="$temporary/ffmpeg-encoded-long.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.20*sin(2*PI*275*t)|0.15*sin(2*PI*715*t):s=44100' \
                -t 2.2 \
                -c:a libvorbis \
                -q:a 4 \
                "$external_long_fixture"
            "$decode_probe" "$external_long_fixture" \
                --require-midpoint-seek
            printf 'Vorbis FFmpeg multi-page encoder decode and seek test passed\n'
            if [ -n "$reference_probe" ]; then
                if command -v oggdec >/dev/null 2>&1; then
                    compare_xiph_reference_pcm \
                        "$external_long_fixture" \
                        "$temporary/xiph-long-reference.s16le" \
                        'Vorbis Xiph multi-page decoded-PCM reference passed'
                fi
                compare_ffmpeg_reference_pcm \
                    "$external_long_fixture" \
                    "$temporary/ffmpeg-long-reference.f32le" \
                    'Vorbis FFmpeg multi-page decoded-PCM reference passed'
            fi

            external_second_fixture="$temporary/ffmpeg-encoded-second.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.15*sin(2*PI*330*t)|0.1*sin(2*PI*550*t):s=44100' \
                -t 0.08 \
                -c:a libvorbis \
                -q:a 4 \
                "$external_second_fixture"
            external_chained_fixture="$temporary/ffmpeg-encoded-chained.ogg"
            cat "$external_fixture" "$external_second_fixture" \
                >"$external_chained_fixture"
            "$decode_probe" "$external_chained_fixture"
            printf 'Vorbis FFmpeg chained encoder decode and seek test passed\n'

            chained_bytes=$(wc -c <"$external_chained_fixture")
            [ "$chained_bytes" -gt 1 ] ||
                fail "Vorbis external chain is too short to truncate"
            external_truncated_fixture="$temporary/ffmpeg-encoded-chained-truncated.ogg"
            dd if="$external_chained_fixture" \
                of="$external_truncated_fixture" \
                bs=1 \
                count=$((chained_bytes - 1)) \
                2>/dev/null
            require_probe_rejection \
                "$external_truncated_fixture" \
                "Project decoder accepted a truncated external chain" \
                "Vorbis FFmpeg chained truncation rejection passed"

            external_mono_fixture="$temporary/ffmpeg-encoded-mono.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.25*sin(2*PI*440*t):s=44100' \
                -t 0.12 \
                -c:a libvorbis \
                -q:a 4 \
                "$external_mono_fixture"
            "$decode_probe" "$external_mono_fixture"
            printf 'Vorbis FFmpeg mono encoder decode and seek test passed\n'
            if [ -n "$reference_probe" ] &&
                command -v oggdec >/dev/null 2>&1; then
                compare_xiph_reference_pcm \
                    "$external_mono_fixture" \
                    "$temporary/xiph-mono-reference.s16le" \
                    'Vorbis Xiph mono decoded-PCM reference passed'
            fi

            external_8k_fixture="$temporary/ffmpeg-encoded-8k.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.20*sin(2*PI*440*t)|0.15*sin(2*PI*660*t):s=8000' \
                -t 0.35 \
                -c:a libvorbis \
                -q:a 4 \
                "$external_8k_fixture"
            "$decode_probe" "$external_8k_fixture"
            printf 'Vorbis FFmpeg 8 kHz stereo geometry test passed\n'
            if [ -n "$reference_probe" ] &&
                command -v oggdec >/dev/null 2>&1; then
                compare_xiph_reference_pcm \
                    "$external_8k_fixture" \
                    "$temporary/xiph-8k-reference.s16le" \
                    'Vorbis Xiph 8 kHz decoded-PCM reference passed'
            fi

            external_16k_fixture="$temporary/ffmpeg-encoded-16k.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.25*sin(2*PI*440*t):s=16000' \
                -t 0.35 \
                -c:a libvorbis \
                -q:a 4 \
                "$external_16k_fixture"
            "$decode_probe" "$external_16k_fixture"
            printf 'Vorbis FFmpeg 16 kHz mono geometry test passed\n'
            if [ -n "$reference_probe" ] &&
                command -v oggdec >/dev/null 2>&1; then
                compare_xiph_reference_pcm \
                    "$external_16k_fixture" \
                    "$temporary/xiph-16k-reference.s16le" \
                    'Vorbis Xiph 16 kHz decoded-PCM reference passed'
            fi

            external_geometry_change_fixture="$temporary/ffmpeg-encoded-geometry-change.ogg"
            cat "$external_8k_fixture" "$external_16k_fixture" \
                >"$external_geometry_change_fixture"
            require_probe_rejection \
                "$external_geometry_change_fixture" \
                "Project decoder accepted a chained Vorbis geometry change" \
                "Vorbis FFmpeg chained geometry-change rejection passed"

            external_low_quality_fixture="$temporary/ffmpeg-encoded-low-quality.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.20*sin(2*PI*440*t)|0.15*sin(2*PI*660*t):s=44100' \
                -t 0.35 \
                -c:a libvorbis \
                -q:a -1 \
                "$external_low_quality_fixture"
            "$decode_probe" "$external_low_quality_fixture"
            printf 'Vorbis FFmpeg low-quality 512/4096 geometry test passed\n'
            if [ -n "$reference_probe" ] &&
                command -v oggdec >/dev/null 2>&1; then
                compare_xiph_reference_pcm \
                    "$external_low_quality_fixture" \
                    "$temporary/xiph-low-quality-reference.s16le" \
                    'Vorbis Xiph low-quality decoded-PCM reference passed'
            fi

            external_surround_fixture="$temporary/ffmpeg-encoded-5.1.ogg"
            ffmpeg -v error -y \
                -f lavfi \
                -i 'aevalsrc=0.20*sin(2*PI*220*t)|0.18*sin(2*PI*330*t)|0.16*sin(2*PI*440*t)|0.14*sin(2*PI*110*t)|0.12*sin(2*PI*550*t)|0.10*sin(2*PI*660*t):s=44100:c=5.1' \
                -t 0.12 \
                -c:a libvorbis \
                -q:a 4 \
                "$external_surround_fixture"
            "$decode_probe" "$external_surround_fixture"
            printf 'Vorbis FFmpeg 5.1 encoder decode and seek test passed\n'
            tested=1
        else
            printf 'Vorbis FFmpeg encoder unavailable; test skipped\n'
        fi
    fi
fi

if [ "${VORBIS_INTEROP_ONLY_FFMPEG-0}" != "1" ] &&
    [ "$(uname -s)" = "Darwin" ] &&
    command -v afconvert >/dev/null 2>&1 &&
    command -v afinfo >/dev/null 2>&1; then
    if afinfo "$fixture" >"$temporary/source.txt" 2>"$temporary/source-error.txt"; then
        decoded="$temporary/decoded.wav"
        if afconvert "$fixture" "$decoded" -f WAVE -d LEI16; then
            if [ "$(wc -c <"$decoded")" -le 44 ]; then
                printf 'Vorbis AudioToolbox decoder unavailable; test skipped\n'
            else
                if [ "${VORBIS_INTEROP_SKIP_FFMPEG-0}" != "1" ] &&
                    command -v ffmpeg >/dev/null 2>&1; then
                    decoded_pcm="$temporary/audio-toolbox-decoded.pcm"
                    ffmpeg -v error -y -i "$decoded" \
                        -map 0:a:0 \
                        -f s16le \
                        -acodec pcm_s16le \
                        "$decoded_pcm"
                    if [ "$(wc -c <"$decoded_pcm")" -eq 0 ]; then
                        printf 'Vorbis AudioToolbox decoder unavailable; test skipped\n'
                    elif ! od -An -tu1 "$decoded_pcm" |
                        grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'; then
                        fail "AudioToolbox produced silent Vorbis PCM"
                    else
                        printf 'Vorbis AudioToolbox interoperability test passed\n'
                        tested=1
                    fi
                else
                    afinfo "$decoded" >"$temporary/decoded.txt"
                    if ! grep -q "WAVE" "$temporary/decoded.txt" ||
                        ! grep -q "48000" "$temporary/decoded.txt"; then
                        sed -n '1,120p' "$temporary/decoded.txt" >&2
                        fail "AudioToolbox reported unexpected WAV metadata"
                    fi
                    data_range=$(wav_data_range "$decoded") || {
                        sed -n '1,120p' "$temporary/decoded.txt" >&2
                        fail "AudioToolbox produced a malformed WAV data range"
                    }
                    # shellcheck disable=SC2086
                    set -- $data_range
                    data_offset=$1
                    audio_bytes=$2
                    if [ "$audio_bytes" -eq 0 ]; then
                        printf 'Vorbis AudioToolbox decoder unavailable; test skipped\n'
                    elif ! dd if="$decoded" bs=1 skip="$data_offset" count="$audio_bytes" 2>/dev/null |
                        od -An -tu1 |
                        grep -Eq '(^|[[:space:]])[1-9][0-9]*([[:space:]]|$)'; then
                        sed -n '1,120p' "$temporary/decoded.txt" >&2
                        fail "AudioToolbox produced silent Vorbis PCM"
                    else
                        printf 'Vorbis AudioToolbox interoperability test passed\n'
                        tested=1
                    fi
                fi
            fi
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
