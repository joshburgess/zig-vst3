#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-quality.XXXXXX")
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

printf 'source pcm\n' >"$root/q0.f32le"
cp "$root/q0.f32le" "$root/q5.f32le"
cp "$root/q0.f32le" "$root/q10.f32le"
printf 'q0 encoded\n' >"$root/q0.ogg"
printf 'q5 encoded\n' >"$root/q5.ogg"
printf 'q10 encoded\n' >"$root/q10.ogg"

probe="$root/probe"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'case "${VORBIS_QUALITY_RUNNER_MODE:-pass}:$1" in' \
    '    missing:*) printf "normalized_rms_error=0.5\n" ;;' \
    '    duplicate:*) printf "normalized_rms_error=0.5 normalized_rms_error=0.4 signal_to_noise_db=4\n" ;;' \
    '    nan:*) printf "normalized_rms_error=NaN signal_to_noise_db=4\n" ;;' \
    '    infinity:*) printf "normalized_rms_error=0.5 signal_to_noise_db=inf\n" ;;' \
    '    overflow:*) printf "normalized_rms_error=0.5 signal_to_noise_db=1e999\n" ;;' \
    '    error:*) printf "normalized_rms_error=0.8 signal_to_noise_db=4\n" ;;' \
    '    snr:*) printf "normalized_rms_error=0.5 signal_to_noise_db=2\n" ;;' \
    '    *q0.ogg) printf "normalized_rms_error=0.55 signal_to_noise_db=5.1\n" ;;' \
    '    *q5.ogg) printf "normalized_rms_error=0.64 signal_to_noise_db=3.8\n" ;;' \
    '    *q10.ogg) printf "normalized_rms_error=0.66 signal_to_noise_db=3.5\n" ;;' \
    '    *) exit 2 ;;' \
    'esac' \
    >"$probe"
chmod +x "$probe"

run_quality() {
    scripts/test_vorbis_quality.sh \
        "$root/q0.ogg" "$root/q0.f32le" \
        "$root/q5.ogg" "$root/q5.f32le" \
        "$root/q10.ogg" "$root/q10.f32le" \
        "$probe"
}

run_quality >"$root/pass.txt"
grep -q 'Vorbis decoded quality calibration passed' "$root/pass.txt"

expect_failure() {
    mode=$1
    message=$2
    if VORBIS_QUALITY_RUNNER_MODE=$mode run_quality >/dev/null 2>&1; then
        printf '%s\n' "$message" >&2
        exit 1
    fi
}

expect_failure missing 'Vorbis quality runner accepted missing metrics'
expect_failure duplicate 'Vorbis quality runner accepted duplicate metrics'
expect_failure nan 'Vorbis quality runner accepted a NaN metric'
expect_failure infinity 'Vorbis quality runner accepted an infinite metric'
expect_failure overflow 'Vorbis quality runner accepted an overflowing metric'
expect_failure error 'Vorbis quality runner accepted excessive error'
expect_failure snr 'Vorbis quality runner accepted low SNR'

cp "$root/q0.ogg" "$root/q10.ogg"
expect_failure pass 'Vorbis quality runner accepted identical encodings'

printf 'Vorbis quality runner self-test passed\n'
