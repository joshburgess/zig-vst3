#!/bin/sh
set -eu

fixture=${1:?missing MP3 fixture path}
decode_probe=${2-}
reference_probe=${3-}
vbri_fixture=${4-}
external_vbri_fixture=${5-}
mpeg2_mono_fixture=${6-}
mpeg2_intensity_fixture=${7-}
mpeg25_intensity_fixture=${8-}
adaptive_gapless_fixture=${9-}
adaptive_gapless_vbr_fixture=${10-}
mpeg2_protected_fixture=${11-}
mpeg25_protected_fixture=${12-}
androidx_vbri_fixture=${ZIG_VST3_EXTERNAL_VBRI_TEST_FILE-}
helix_encoder=${ZIG_VST3_HELIX_MP3_ENCODER-}
require_extended=${MP3_INTEROP_REQUIRE_EXTENDED-0}
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
    reference_mode=${5-}
    ffmpeg -v error -y \
        -i "$encoded_path" \
        -map 0:a:0 \
        -f f32le \
        -acodec pcm_f32le \
        "$reference_path"
    if [ -n "$reference_mode" ]; then
        "$reference_probe" \
            "$encoded_path" \
            "$reference_path" \
            "$channels" \
            "$reference_mode"
    else
        "$reference_probe" \
            "$encoded_path" \
            "$reference_path" \
            "$channels"
    fi
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
    if [ -n "$vbri_fixture" ]; then
        test -f "$vbri_fixture"
        "$decode_probe" "$vbri_fixture" 44100 2 --require-vbri
        printf 'MP3 project VBRI decoder probe passed\n'
    fi
    if [ -n "$mpeg2_mono_fixture" ]; then
        test -f "$mpeg2_mono_fixture"
        "$decode_probe" "$mpeg2_mono_fixture" 22050 1
        printf 'MP3 project MPEG-2 mono decoder probe passed\n'
    fi
    if [ -n "$mpeg2_intensity_fixture" ]; then
        test -f "$mpeg2_intensity_fixture"
        "$decode_probe" "$mpeg2_intensity_fixture" 22050 2 \
            --require-joint-stereo
        printf 'MP3 project MPEG-2 intensity-stereo decoder probe passed\n'
    fi
    if [ -n "$mpeg25_intensity_fixture" ]; then
        test -f "$mpeg25_intensity_fixture"
        "$decode_probe" "$mpeg25_intensity_fixture" 11025 2 \
            --require-joint-stereo
        printf 'MP3 project MPEG-2.5 intensity-stereo decoder probe passed\n'
    fi
    if [ -n "$adaptive_gapless_fixture" ]; then
        test -f "$adaptive_gapless_fixture"
        "$decode_probe" "$adaptive_gapless_fixture" 44100 2 \
            --require-gapless
        printf 'MP3 project adaptive gapless CBR decoder probe passed\n'
    fi
    if [ -n "$adaptive_gapless_vbr_fixture" ]; then
        test -f "$adaptive_gapless_vbr_fixture"
        "$decode_probe" "$adaptive_gapless_vbr_fixture" 44100 2 \
            --require-gapless
        printf 'MP3 project adaptive gapless VBR decoder probe passed\n'
    fi
    if [ -n "$mpeg2_protected_fixture" ]; then
        test -f "$mpeg2_protected_fixture"
        "$decode_probe" "$mpeg2_protected_fixture" 22050 1 \
            --require-protected
        printf 'MP3 project protected MPEG-2 decoder probe passed\n'
    fi
    if [ -n "$mpeg25_protected_fixture" ]; then
        test -f "$mpeg25_protected_fixture"
        "$decode_probe" "$mpeg25_protected_fixture" 11025 2 \
            --require-protected
        printf 'MP3 project protected MPEG-2.5 decoder probe passed\n'
    fi
    if [ -n "$androidx_vbri_fixture" ]; then
        test -f "$androidx_vbri_fixture"
        "$decode_probe" "$androidx_vbri_fixture" 48000 2 \
            --require-vbri
        printf 'MP3 AndroidX VBRI decoder and seek probe passed\n'
    elif [ "$require_extended" = 1 ]; then
        fail "required AndroidX VBRI fixture is unavailable"
    else
        printf 'MP3 AndroidX VBRI fixture unavailable; test skipped\n'
    fi
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

    if [ -n "$mpeg2_mono_fixture" ]; then
        compare_reference_pcm \
            "$mpeg2_mono_fixture" \
            1 \
            "$temporary/project-mpeg2-mono-reference.f32le" \
            'MP3 project MPEG-2 mono FFmpeg reference passed'
    fi
    if [ -n "$mpeg2_intensity_fixture" ]; then
        compare_reference_pcm \
            "$mpeg2_intensity_fixture" \
            2 \
            "$temporary/project-mpeg2-intensity-reference.f32le" \
            'MP3 project MPEG-2 intensity FFmpeg reference passed'
    fi
    if [ -n "$mpeg25_intensity_fixture" ]; then
        compare_reference_pcm \
            "$mpeg25_intensity_fixture" \
            2 \
            "$temporary/project-mpeg25-intensity-reference.f32le" \
            'MP3 project MPEG-2.5 intensity FFmpeg reference passed'
    fi
    if [ -n "$adaptive_gapless_fixture" ]; then
        compare_reference_pcm \
            "$adaptive_gapless_fixture" \
            2 \
            "$temporary/project-adaptive-gapless-reference.f32le" \
            'MP3 project adaptive gapless CBR FFmpeg reference passed' \
            --accept-full-gapless-reference
    fi
    if [ -n "$adaptive_gapless_vbr_fixture" ]; then
        compare_reference_pcm \
            "$adaptive_gapless_vbr_fixture" \
            2 \
            "$temporary/project-adaptive-gapless-vbr-reference.f32le" \
            'MP3 project adaptive gapless VBR FFmpeg reference passed' \
            --accept-full-gapless-reference
    fi
    if [ -n "$mpeg2_protected_fixture" ]; then
        compare_reference_pcm \
            "$mpeg2_protected_fixture" \
            1 \
            "$temporary/project-mpeg2-protected-reference.f32le" \
            'MP3 project protected MPEG-2 FFmpeg reference passed'
    fi
    if [ -n "$mpeg25_protected_fixture" ]; then
        compare_reference_pcm \
            "$mpeg25_protected_fixture" \
            2 \
            "$temporary/project-mpeg25-protected-reference.f32le" \
            'MP3 project protected MPEG-2.5 FFmpeg reference passed'
    fi
    if [ -n "$androidx_vbri_fixture" ] && [ -n "$reference_probe" ]; then
        compare_reference_pcm \
            "$androidx_vbri_fixture" \
            2 \
            "$temporary/androidx-vbri-reference.f32le" \
            'MP3 AndroidX VBRI FFmpeg decoded-PCM reference passed'
    fi

    if [ -n "$vbri_fixture" ]; then
        vbri_decoded="$temporary/ffmpeg-vbri-decoded.pcm"
        ffmpeg -v error -y -i "$vbri_fixture" \
            -map 0:a:0 \
            -f s16le \
            -acodec pcm_s16le \
            "$vbri_decoded"
        assert_nonsilent "$vbri_decoded" 0 "$(wc -c <"$vbri_decoded")"
        printf 'MP3 VBRI FFmpeg interoperability test passed\n'
    fi

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
            if [ -n "$external_vbri_fixture" ]; then
                external_vbri="$temporary/ffmpeg-mpeg1-vbri.mp3"
                "$external_vbri_fixture" \
                    "$external_mpeg1" \
                    "$external_vbri"
                "$decode_probe" "$external_vbri" 44100 2 \
                    --require-vbri
                printf 'MP3 external-audio VBRI decoder probe passed\n'
                external_vbri_decoded="$temporary/ffmpeg-mpeg1-vbri-decoded.pcm"
                ffmpeg -v error -y -i "$external_vbri" \
                    -map 0:a:0 \
                    -f s16le \
                    -acodec pcm_s16le \
                    "$external_vbri_decoded"
                assert_nonsilent \
                    "$external_vbri_decoded" \
                    0 \
                    "$(wc -c <"$external_vbri_decoded")"
                printf 'MP3 external-audio VBRI FFmpeg decode passed\n'
            fi
            "$decode_probe" "$external_mpeg1" 44100 2 \
                --require-junk-resync
            printf 'MP3 FFmpeg bounded junk resynchronization probe passed\n'

            external_trailing_junk="$temporary/ffmpeg-mpeg1-trailing-junk.mp3"
            cp "$external_mpeg1" "$external_trailing_junk"
            printf '\000\111\104\063\177' >>"$external_trailing_junk"
            "$decode_probe" "$external_trailing_junk" 44100 2 \
                --require-trailing-junk-rejection
            printf 'MP3 FFmpeg trailing-junk rejection probe passed\n'

            if [ -n "$reference_probe" ]; then
                compare_reference_pcm \
                    "$external_mpeg1" \
                    2 \
                    "$temporary/ffmpeg-mpeg1-reference.f32le" \
                    'MP3 FFmpeg MPEG-1 decoded-PCM reference probe passed'
            fi

            if [ -n "$helix_encoder" ]; then
                test -x "$helix_encoder"
                helix_wav="$temporary/helix-source.wav"
                helix_mp3="$temporary/helix-vbr.mp3"
                ffmpeg -v error -y \
                    -f lavfi \
                    -i 'aevalsrc=0.21*sin(2*PI*347*t)|0.16*sin(2*PI*911*t):s=44100' \
                    -t 1.2 \
                    -c:a pcm_s16le \
                    "$helix_wav"
                "$helix_encoder" "$helix_wav" "$helix_mp3" -V80
                "$decode_probe" "$helix_mp3" 44100 2 --require-helix
                printf 'MP3 Helix VBR decoder and metadata probe passed\n'
                if [ -n "$reference_probe" ]; then
                    compare_reference_pcm \
                        "$helix_mp3" \
                        2 \
                        "$temporary/helix-vbr-reference.f32le" \
                        'MP3 Helix VBR FFmpeg decoded-PCM reference passed' \
                        --accept-full-gapless-reference
                fi
            elif [ "$require_extended" = 1 ]; then
                fail "required Helix MP3 encoder is unavailable"
            else
                printf 'MP3 Helix encoder unavailable; test skipped\n'
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

            if command -v lame >/dev/null 2>&1; then
                external_mpeg2_stereo_wav="$temporary/lame-mpeg2-joint-stereo-source.wav"
                external_mpeg2_stereo="$temporary/lame-mpeg2-joint-stereo.mp3"
                ffmpeg -v error -y \
                    -f lavfi \
                    -i 'aevalsrc=0.23*sin(2*PI*440*t)|0.14*sin(2*PI*990*t):s=22050' \
                    -t 0.35 \
                    -c:a pcm_s16le \
                    "$external_mpeg2_stereo_wav"
                lame --silent --cbr -m j --resample 22.05 -b 32 \
                    "$external_mpeg2_stereo_wav" \
                    "$external_mpeg2_stereo"
                "$decode_probe" "$external_mpeg2_stereo" 22050 2 \
                    --require-joint-stereo
                printf 'MP3 LAME MPEG-2 joint-stereo decoder probe passed\n'
                if [ -n "$reference_probe" ]; then
                    compare_reference_pcm \
                        "$external_mpeg2_stereo" \
                        2 \
                        "$temporary/lame-mpeg2-joint-stereo-reference.f32le" \
                        'MP3 LAME MPEG-2 joint-stereo decoded-PCM reference probe passed'
                fi
            else
                printf 'MP3 LAME MPEG-2 joint-stereo test skipped\n'
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

            if command -v lame >/dev/null 2>&1; then
                external_mpeg25_stereo_wav="$temporary/lame-mpeg25-joint-stereo-source.wav"
                external_mpeg25_stereo="$temporary/lame-mpeg25-joint-stereo.mp3"
                ffmpeg -v error -y \
                    -f lavfi \
                    -i 'aevalsrc=0.18*sin(2*PI*510*t)|0.12*sin(2*PI*1370*t):s=11025' \
                    -t 0.35 \
                    -c:a pcm_s16le \
                    "$external_mpeg25_stereo_wav"
                lame --silent --cbr -m j --resample 11.025 -b 16 \
                    "$external_mpeg25_stereo_wav" \
                    "$external_mpeg25_stereo"
                "$decode_probe" "$external_mpeg25_stereo" 11025 2 \
                    --require-joint-stereo
                printf 'MP3 LAME MPEG-2.5 joint-stereo decoder probe passed\n'
                if [ -n "$reference_probe" ]; then
                    compare_reference_pcm \
                        "$external_mpeg25_stereo" \
                        2 \
                        "$temporary/lame-mpeg25-joint-stereo-reference.f32le" \
                        'MP3 LAME MPEG-2.5 joint-stereo decoded-PCM reference probe passed'
                fi
            else
                printf 'MP3 LAME MPEG-2.5 joint-stereo test skipped\n'
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
