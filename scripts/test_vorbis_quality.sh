#!/bin/sh
set -eu

q0_ogg=${1:?missing q0 fixture}
q0_source=${2:?missing q0 source}
q5_ogg=${3:?missing q5 fixture}
q5_source=${4:?missing q5 source}
q10_ogg=${5:?missing q10 fixture}
q10_source=${6:?missing q10 source}
probe=${7:?missing decoder probe}
pcm_quality_probe=${8:?missing external PCM quality probe}

if [ "${VORBIS_QUALITY_REQUIRE_EXTERNAL-0}" = "1" ]; then
    command -v ffmpeg >/dev/null 2>&1 || {
        printf 'FFmpeg is required for Vorbis objective quality validation\n' >&2
        exit 1
    }
    command -v oggdec >/dev/null 2>&1 || {
        printf 'oggdec is required for Vorbis objective quality validation\n' >&2
        exit 1
    }
fi

cmp "$q0_source" "$q5_source"
cmp "$q0_source" "$q10_source"

if cmp -s "$q0_ogg" "$q5_ogg" ||
    cmp -s "$q5_ogg" "$q10_ogg" ||
    cmp -s "$q0_ogg" "$q10_ogg"; then
    printf 'Vorbis quality presets produced identical encoded fixtures\n' >&2
    exit 1
fi

measure() {
    "$probe" "$1" --measure-source-f32le "$2" 2>&1
}

metric() {
    key=$1
    awk -v key="$key" '
        BEGIN {
            prefix = key "="
            count = 0
        }
        {
            for (field = 1; field <= NF; field += 1) {
                if (substr($field, 1, length(prefix)) != prefix) continue
                value = substr($field, length(prefix) + 1)
                count += 1
            }
        }
        END {
            if (count != 1 || value !~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/)
                exit 1
            print value
        }
    '
}

validate_external_report() {
    decoder=$1
    quality=$2
    report=$3
    error=$(printf '%s\n' "$report" | metric normalized_rms_error) || {
        printf 'Vorbis %s q%s quality probe returned invalid error metrics\n' \
            "$decoder" "$quality" >&2
        exit 1
    }
    snr=$(printf '%s\n' "$report" | metric signal_to_noise_db) || {
        printf 'Vorbis %s q%s quality probe returned invalid SNR metrics\n' \
            "$decoder" "$quality" >&2
        exit 1
    }
    awk -v error="$error" -v snr="$snr" '
        BEGIN {
            if (!(error >= 0 && error <= 0.75 &&
                  snr >= 3 && snr <= 1000)) exit 1
        }
    ' || {
        printf 'Vorbis %s q%s quality exceeded calibration bounds: error=%s snr=%s\n' \
            "$decoder" "$quality" "$error" "$snr" >&2
        exit 1
    }
    printf 'Vorbis %s q%s objective quality passed: error=%s snr=%s\n' \
        "$decoder" "$quality" "$error" "$snr"
}

q0_report=$(measure "$q0_ogg" "$q0_source")
q5_report=$(measure "$q5_ogg" "$q5_source")
q10_report=$(measure "$q10_ogg" "$q10_source")

q0_error=$(printf '%s\n' "$q0_report" | metric normalized_rms_error) || {
    printf 'Vorbis q0 quality probe returned invalid error metrics\n' >&2
    exit 1
}
q5_error=$(printf '%s\n' "$q5_report" | metric normalized_rms_error) || {
    printf 'Vorbis q5 quality probe returned invalid error metrics\n' >&2
    exit 1
}
q10_error=$(printf '%s\n' "$q10_report" | metric normalized_rms_error) || {
    printf 'Vorbis q10 quality probe returned invalid error metrics\n' >&2
    exit 1
}
q0_snr=$(printf '%s\n' "$q0_report" | metric signal_to_noise_db) || {
    printf 'Vorbis q0 quality probe returned invalid SNR metrics\n' >&2
    exit 1
}
q5_snr=$(printf '%s\n' "$q5_report" | metric signal_to_noise_db) || {
    printf 'Vorbis q5 quality probe returned invalid SNR metrics\n' >&2
    exit 1
}
q10_snr=$(printf '%s\n' "$q10_report" | metric signal_to_noise_db) || {
    printf 'Vorbis q10 quality probe returned invalid SNR metrics\n' >&2
    exit 1
}

awk -v q0="$q0_error" -v q5="$q5_error" -v q10="$q10_error" '
    BEGIN {
        if (!(q0 >= 0 && q0 <= 0.75 &&
              q5 >= 0 && q5 <= 0.75 &&
              q10 >= 0 && q10 <= 0.75)) exit 1
    }
' || {
    printf 'Vorbis quality error exceeded calibration bounds: q0=%s q5=%s q10=%s\n' \
        "$q0_error" "$q5_error" "$q10_error" >&2
    exit 1
}

awk -v q0="$q0_snr" -v q5="$q5_snr" -v q10="$q10_snr" '
    BEGIN {
        if (!(q0 >= 3 && q0 <= 1000 &&
              q5 >= 3 && q5 <= 1000 &&
              q10 >= 3 && q10 <= 1000)) exit 1
    }
' || {
    printf 'Vorbis quality SNR fell below calibration bounds: q0=%s q5=%s q10=%s\n' \
        "$q0_snr" "$q5_snr" "$q10_snr" >&2
    exit 1
}

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-quality.XXXXXX")
cleanup() {
    rm -rf "$temporary"
}
trap cleanup EXIT HUP INT TERM

for quality in 0 5 10; do
    case "$quality" in
        0)
            encoded=$q0_ogg
            source=$q0_source
            ;;
        5)
            encoded=$q5_ogg
            source=$q5_source
            ;;
        10)
            encoded=$q10_ogg
            source=$q10_source
            ;;
    esac
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg_pcm="$temporary/ffmpeg-q${quality}.f32le"
        ffmpeg -v error -y \
            -i "$encoded" \
            -map 0:a:0 \
            -f f32le \
            -acodec pcm_f32le \
            "$ffmpeg_pcm"
        ffmpeg_report=$(
            "$pcm_quality_probe" \
                --candidate-f32le \
                "$ffmpeg_pcm" \
                "$source" 2>&1
        )
        validate_external_report FFmpeg "$quality" "$ffmpeg_report"
    fi
    if command -v oggdec >/dev/null 2>&1; then
        xiph_pcm="$temporary/xiph-q${quality}.s16le"
        oggdec -Q -R -b 16 -e 0 -s 1 \
            -o "$xiph_pcm" \
            "$encoded"
        xiph_report=$(
            "$pcm_quality_probe" \
                --candidate-s16le \
                "$xiph_pcm" \
                "$source" 2>&1
        )
        validate_external_report Xiph "$quality" "$xiph_report"
    fi
done

printf 'Vorbis decoded quality calibration passed: q0_error=%s q5_error=%s q10_error=%s q0_snr=%s q5_snr=%s q10_snr=%s\n' \
    "$q0_error" "$q5_error" "$q10_error" \
    "$q0_snr" "$q5_snr" "$q10_snr"
