#!/bin/sh
set -eu

project_fixture=${1:?missing project Vorbis fixture}
stb_probe=${2:?missing stb_vorbis probe}
project_probe=${3:?missing project decoder probe}
quality_probe=${4:?missing PCM quality probe}
tremor_probe=${5:?missing Tremor probe}
test -s "$project_fixture"
test -x "$stb_probe"
test -x "$project_probe"
test -x "$quality_probe"
test -x "$tremor_probe"

for tool in ffmpeg oggdec oggenc; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf '%s is required for the stb_vorbis comparison\n' "$tool" >&2
        exit 1
    }
done

temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-stb-vorbis.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
case_count=0
total_values=0
maximum_peak=0
maximum_normalized_rms=0
maximum_tremor_peak=0
maximum_tremor_normalized_rms=0

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

metric() {
    key=$1
    awk -v key="$key" '
        BEGIN { prefix = key "="; count = 0 }
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

validate_quality_report() {
    report=$1
    name=${2-}
    peak=$(printf '%s\n' "$report" | metric peak_error) || return 1
    normalized=$(printf '%s\n' "$report" | metric normalized_rms_error) || return 1
    case "$name" in
        fixed-low-level) normalized_limit=0.35 ;;
        fixed-clipping) normalized_limit=0.0005 ;;
        *) normalized_limit=0.00025 ;;
    esac
    awk -v peak="$peak" -v normalized="$normalized" \
        -v normalized_limit="$normalized_limit" '
        BEGIN {
            if (!(peak >= 0 && peak <= 0.000061 &&
                  normalized >= 0 && normalized <= normalized_limit)) exit 1
        }
    ' || return 1
    printf '%s %s\n' "$peak" "$normalized"
}

validate_tremor_report() {
    report=$1
    name=$2
    peak=$(printf '%s\n' "$report" | metric peak_error) || return 1
    normalized=$(printf '%s\n' "$report" | metric normalized_rms_error) || return 1
    case "$name" in
        fixed-low-level) peak_limit=0.000061; normalized_limit=0.35 ;;
        fixed-clipping) peak_limit=0.00025; normalized_limit=0.0005 ;;
        *) peak_limit=0.004; normalized_limit=0.02 ;;
    esac
    awk -v peak="$peak" -v normalized="$normalized" \
        -v peak_limit="$peak_limit" -v normalized_limit="$normalized_limit" '
        BEGIN {
            if (!(peak >= 0 && peak <= peak_limit &&
                  normalized >= 0 && normalized <= normalized_limit)) exit 1
        }
    ' || return 1
    printf '%s %s\n' "$peak" "$normalized"
}

for invalid_report in \
    'normalized_rms_error=0.00001' \
    'peak_error=0.00001 normalized_rms_error=NaN' \
    'peak_error=0.1 normalized_rms_error=0.00001' \
    'peak_error=0.00001 normalized_rms_error=0.1' \
    'peak_error=0.00001 peak_error=0.00002 normalized_rms_error=0.00001'; do
    if validate_quality_report "$invalid_report" >/dev/null 2>&1; then
        fail 'stb_vorbis comparison accepted invalid metrics'
    fi
done

compare_case() {
    name=$1
    encoded=$2
    rate=$3
    channels=$4
    shift 4
    test -s "$encoded" || fail "stb_vorbis case $name is missing"
    stb_pcm=$temporary/$name.stb.f32le
    report=$(
        "$stb_probe" "$stb_pcm" "$rate" "$channels" "$@" 2>&1
    ) || fail "stb_vorbis failed case $name"
    printf '%s\n' "$report" | grep -Eq \
        '^stb_vorbis decoded links=[0-9]+ frames=[0-9]+ values=[0-9]+ peak=[0-9]' ||
        fail "stb_vorbis case $name returned an invalid decoder report"
    test -s "$stb_pcm" || fail "stb_vorbis case $name returned no PCM"
    bytes=$(wc -c <"$stb_pcm" | tr -d ' ')
    test $((bytes % (4 * channels))) -eq 0 ||
        fail "stb_vorbis case $name returned malformed PCM"
    if [ "$name" = fixed-5.1 ]; then
        "$project_probe" "$encoded"
    else
        "$project_probe" "$encoded" --reference-f32le "$stb_pcm"
    fi

    tremor_pcm=$temporary/$name.tremor.s16le
    tremor_report=$(
        "$tremor_probe" "$tremor_pcm" "$rate" "$channels" "$@" 2>&1
    ) || fail "Tremor failed case $name"
    printf '%s\n' "$tremor_report" | grep -Eq \
        '^Tremor decoded links=[0-9]+ frames=[0-9]+ values=[0-9]+ peak=[0-9]' ||
        fail "Tremor case $name returned an invalid decoder report"
    test -s "$tremor_pcm" || fail "Tremor case $name returned no PCM"
    tremor_bytes=$(wc -c <"$tremor_pcm" | tr -d ' ')
    test "$tremor_bytes" -eq $((bytes / 2)) ||
        fail "Tremor case $name returned malformed PCM"

    xiph_pcm=$temporary/$name.xiph.s16le
    : >"$xiph_pcm"
    for link; do
        link_pcm=$temporary/$name.$case_count.xiph-link.s16le
        oggdec -Q -R -b 16 -e 0 -s 1 -o "$link_pcm" "$link"
        test -s "$link_pcm" || fail "Xiph returned no PCM for $name"
        cat "$link_pcm" >>"$xiph_pcm"
    done

    tremor_mode=--candidate-s16le
    tremor_reference=$stb_pcm
    if [ "$name" = fixed-clipping ]; then
        stb_peak=$(printf '%s\n' "$report" | metric peak) ||
            fail 'stb_vorbis clipping case omitted its peak'
        awk -v peak="$stb_peak" 'BEGIN { if (!(peak > 1)) exit 1 }' ||
            fail 'fixed clipping case did not exceed the signed PCM range'
        tremor_mode=--candidate-s16le-clipped-reference
    elif [ "$name" = fixed-5.1 ]; then
        tremor_mode=--candidate-s16le-reference-s16le
        tremor_reference=$xiph_pcm
    fi
    tremor_quality_report=$(
        "$quality_probe" "$tremor_mode" "$tremor_pcm" "$tremor_reference" 2>&1
    ) || fail "Tremor comparison PCM shapes differ for $name"
    tremor_metrics=$(validate_tremor_report "$tremor_quality_report" "$name") ||
        fail "Tremor comparison metrics exceeded bounds for $name: $tremor_quality_report"
    tremor_peak=$(printf '%s\n' "$tremor_metrics" | awk '{ print $1 }')
    tremor_normalized=$(printf '%s\n' "$tremor_metrics" | awk '{ print $2 }')
    maximum_tremor_peak=$(awk \
        -v left="$maximum_tremor_peak" -v right="$tremor_peak" \
        'BEGIN { print (left > right ? left : right) }')
    maximum_tremor_normalized_rms=$(awk \
        -v left="$maximum_tremor_normalized_rms" -v right="$tremor_normalized" \
        'BEGIN { print (left > right ? left : right) }')

    xiph_mode=--candidate-s16le
    if [ "$name" = fixed-clipping ]; then
        xiph_mode=--candidate-s16le-clipped-reference
    fi
    if [ "$name" = fixed-5.1 ]; then
        quality_report=$tremor_quality_report
        metrics=$tremor_metrics
    else
        quality_report=$(
            "$quality_probe" "$xiph_mode" "$xiph_pcm" "$stb_pcm" 2>&1
        ) || fail "Xiph and stb_vorbis PCM shapes differ for $name"
        metrics=$(validate_quality_report "$quality_report" "$name") ||
            fail "Xiph and stb_vorbis metrics exceeded bounds for $name: $quality_report"
    fi
    # shellcheck disable=SC2086
    set -- $metrics
    peak=$1
    normalized=$2
    maximum_peak=$(awk -v left="$maximum_peak" -v right="$peak" \
        'BEGIN { print (left > right ? left : right) }')
    maximum_normalized_rms=$(awk \
        -v left="$maximum_normalized_rms" -v right="$normalized" \
        'BEGIN { print (left > right ? left : right) }')
    values=$((bytes / 4))
    total_values=$((total_values + values))
    case_count=$((case_count + 1))
    printf 'four-decoder Vorbis case %s passed: values=%s xiph_peak=%s xiph_normalized_rms=%s tremor_peak=%s tremor_normalized_rms=%s\n' \
        "$name" "$values" "$peak" "$normalized" "$tremor_peak" "$tremor_normalized"
}

expect_rejection() {
    name=$1
    shift
    output=$temporary/$name.rejected.f32le
    sentinel=$temporary/$name.sentinel
    printf 'preserve output\n' >"$output"
    cp "$output" "$sentinel"
    if "$stb_probe" "$output" "$@" >/dev/null 2>&1; then
        fail "stb_vorbis accepted $name"
    fi
    cmp "$output" "$sentinel" ||
        fail "stb_vorbis changed output after rejecting $name"
    printf 'stb_vorbis %s rejection passed\n' "$name"
    tremor_output=$temporary/$name.tremor-rejected.s16le
    tremor_sentinel=$temporary/$name.tremor-sentinel
    printf 'preserve Tremor output\n' >"$tremor_output"
    cp "$tremor_output" "$tremor_sentinel"
    if "$tremor_probe" "$tremor_output" "$@" >/dev/null 2>&1; then
        fail "Tremor accepted $name"
    fi
    cmp "$tremor_output" "$tremor_sentinel" ||
        fail "Tremor changed output after rejecting $name"
    printf 'Tremor %s rejection passed\n' "$name"
}

project_chain=$temporary/project-chain.ogg
cat "$project_fixture" "$project_fixture" >"$project_chain"
compare_case project "$project_fixture" 48000 1 "$project_fixture"
compare_case project-chain "$project_chain" 48000 1 \
    "$project_fixture" "$project_fixture"

stereo=$temporary/ffmpeg-stereo.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.25*sin(2*PI*440*t)|0.20*sin(2*PI*660*t):s=44100' \
    -t 0.35 -c:a libvorbis -q:a 4 "$stereo"
compare_case ffmpeg-stereo "$stereo" 44100 2 "$stereo"

mono=$temporary/ffmpeg-mono.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.22*sin(2*PI*510*t):s=44100' \
    -t 0.35 -c:a libvorbis -q:a 4 "$mono"
compare_case ffmpeg-mono "$mono" 44100 1 "$mono"

low_rate=$temporary/ffmpeg-8k.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.20*sin(2*PI*440*t)|0.15*sin(2*PI*660*t):s=8000' \
    -t 0.35 -c:a libvorbis -q:a 4 "$low_rate"
compare_case ffmpeg-8k "$low_rate" 8000 2 "$low_rate"

low_rate_mono=$temporary/ffmpeg-16k.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.20*sin(2*PI*440*t):s=16000' \
    -t 0.35 -c:a libvorbis -q:a 4 "$low_rate_mono"
compare_case ffmpeg-16k "$low_rate_mono" 16000 1 "$low_rate_mono"

low_quality=$temporary/ffmpeg-low-quality.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.20*sin(2*PI*330*t)|0.15*sin(2*PI*770*t):s=44100' \
    -t 0.35 -c:a libvorbis -q:a -1 "$low_quality"
compare_case ffmpeg-low-quality "$low_quality" 44100 2 "$low_quality"

long=$temporary/ffmpeg-long.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.20*sin(2*PI*275*t)|0.15*sin(2*PI*715*t):s=44100' \
    -t 2.2 -c:a libvorbis -q:a 4 "$long"
compare_case ffmpeg-multi-page "$long" 44100 2 "$long"

second=$temporary/ffmpeg-second.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.18*sin(2*PI*315*t)|0.12*sin(2*PI*615*t):s=44100' \
    -t 0.21 -c:a libvorbis -q:a 2 "$second"
chain=$temporary/ffmpeg-chain.ogg
cat "$stereo" "$second" >"$chain"
compare_case ffmpeg-chain "$chain" 44100 2 "$stereo" "$second"

xiph_source=$temporary/xiph-source.wav
xiph_stereo=$temporary/xiph-stereo.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.21*sin(2*PI*375*t)|0.16*sin(2*PI*825*t):s=48000' \
    -t 0.35 -c:a pcm_s16le "$xiph_source"
oggenc -Q -q 3 -o "$xiph_stereo" "$xiph_source"
compare_case xiph-stereo "$xiph_stereo" 48000 2 "$xiph_stereo"

xiph_mono_source=$temporary/xiph-mono-source.wav
xiph_mono=$temporary/xiph-mono.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.19*sin(2*PI*615*t):s=32000' \
    -t 0.35 -c:a pcm_s16le "$xiph_mono_source"
oggenc -Q -q 0 -o "$xiph_mono" "$xiph_mono_source"
compare_case xiph-mono "$xiph_mono" 32000 1 "$xiph_mono"

low_level=$temporary/fixed-low-level.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.0005*sin(2*PI*997*t):s=48000' \
    -t 0.35 -c:a libvorbis -q:a 6 "$low_level"
compare_case fixed-low-level "$low_level" 48000 1 "$low_level"

clipping=$temporary/fixed-clipping.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=1.25*sin(2*PI*701*t):s=48000' \
    -t 0.35 -c:a libvorbis -q:a 10 "$clipping"
compare_case fixed-clipping "$clipping" 48000 1 "$clipping"

multichannel=$temporary/fixed-5.1.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.0050*sin(2*PI*210*t)|0.0045*sin(2*PI*320*t)|0.0040*sin(2*PI*430*t)|0.0035*sin(2*PI*90*t)|0.0030*sin(2*PI*540*t)|0.0025*sin(2*PI*650*t):s=48000:c=5.1' \
    -t 0.35 -c:a libvorbis -q:a 4 "$multichannel"
compare_case fixed-5.1 "$multichannel" 48000 6 "$multichannel"

terminal=$temporary/fixed-terminal.ogg
ffmpeg -v error -y -f lavfi \
    -i 'aevalsrc=0.16*sin(2*PI*887*t):s=48000' \
    -af atrim=end_sample=1001 -c:a libvorbis -q:a 5 "$terminal"
compare_case fixed-terminal "$terminal" 48000 1 "$terminal"

checksum=$temporary/checksum.ogg
cp "$stereo" "$checksum"
printf 'BAD!' | dd of="$checksum" bs=1 seek=22 conv=notrunc 2>/dev/null
expect_rejection checksum-damage 44100 2 "$checksum"

truncated_header=$temporary/truncated-header.ogg
dd if="$stereo" of="$truncated_header" bs=1 count=20 2>/dev/null
expect_rejection truncated-header 44100 2 "$truncated_header"

stereo_bytes=$(wc -c <"$stereo" | tr -d ' ')
truncated_audio=$temporary/truncated-audio.ogg
dd if="$stereo" of="$truncated_audio" bs=1 \
    count=$((stereo_bytes - 1)) 2>/dev/null
expect_rejection truncated-audio 44100 2 "$truncated_audio"

invalid_packet=$temporary/invalid-packet.ogg
"$project_probe" "$long" --write-invalid-audio-packet "$invalid_packet"
expect_rejection invalid-audio-packet 44100 2 "$invalid_packet"
expect_rejection incompatible-chain 44100 2 "$stereo" "$low_rate_mono"

injected_output=$temporary/injected-chain.s16le
injected_sentinel=$temporary/injected-chain.sentinel
printf 'preserve injected output\n' >"$injected_output"
cp "$injected_output" "$injected_sentinel"
if ZIG_VST3_TREMOR_FAIL_LINK=1 ZIG_VST3_TREMOR_FAIL_AFTER_FRAMES=64 \
    "$tremor_probe" "$injected_output" 44100 2 "$stereo" "$second" \
    >/dev/null 2>&1; then
    fail 'Tremor accepted an injected second-link decoder failure'
fi
cmp "$injected_output" "$injected_sentinel" ||
    fail 'Tremor changed output after an injected second-link decoder failure'
printf 'Tremor injected second-link failure rejection passed\n'

test "$case_count" -eq 15 || fail 'four-decoder Vorbis comparison skipped a case'
test "$total_values" -gt 0 || fail 'stb_vorbis comparison returned no values'
printf 'four-decoder Vorbis comparison passed: cases=%s values=%s xiph_peak=%s xiph_normalized_rms=%s tremor_peak=%s tremor_normalized_rms=%s\n' \
    "$case_count" "$total_values" "$maximum_peak" "$maximum_normalized_rms" \
    "$maximum_tremor_peak" "$maximum_tremor_normalized_rms"
