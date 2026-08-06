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
fake_bin="$root/bin"
external_probe_count="$root/external-probe-count"
mkdir -p "$fake_bin"
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

cat >"$fake_bin/ffmpeg" <<'EOF'
#!/bin/sh
for argument do output=$argument; done
printf '\001\000\002\000' >"$output"
EOF
cat >"$fake_bin/oggdec" <<'EOF'
#!/bin/sh
output=
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        shift
        output=$1
    fi
    shift
done
[ -n "$output" ]
printf '\001\000\002\000' >"$output"
EOF
chmod +x "$fake_bin/ffmpeg" "$fake_bin/oggdec"

external_probe="$root/external-probe"
cat >"$external_probe" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$TMPDIR/external-probe-count" ] ||
    count=$(cat "$TMPDIR/external-probe-count")
printf '%s\n' $((count + 1)) >"$TMPDIR/external-probe-count"
case "${VORBIS_QUALITY_EXTERNAL_RUNNER_MODE:-pass}" in
    missing) printf 'normalized_rms_error=0.5\n' ;;
    error) printf 'normalized_rms_error=0.8 signal_to_noise_db=4\n' ;;
    snr) printf 'normalized_rms_error=0.5 signal_to_noise_db=2\n' ;;
    pass) printf 'normalized_rms_error=0.5 signal_to_noise_db=4\n' ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$external_probe"

run_quality() {
    PATH="$fake_bin:$PATH" \
    TMPDIR="$root" \
        scripts/test_vorbis_quality.sh \
        "$root/q0.ogg" "$root/q0.f32le" \
        "$root/q5.ogg" "$root/q5.f32le" \
        "$root/q10.ogg" "$root/q10.f32le" \
        "$probe" "$external_probe"
}

run_quality >"$root/pass.txt"
grep -q 'Vorbis decoded quality calibration passed' "$root/pass.txt"
for decoder in FFmpeg Xiph; do
    for quality in 0 5 10; do
        grep -q "Vorbis $decoder q$quality objective quality passed" \
            "$root/pass.txt"
    done
done
[ "$(cat "$external_probe_count")" -eq 6 ] || {
    printf 'Vorbis quality runner skipped an external decoder probe\n' >&2
    exit 1
}

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

expect_external_failure() {
    mode=$1
    message=$2
    if VORBIS_QUALITY_EXTERNAL_RUNNER_MODE=$mode \
        run_quality >/dev/null 2>&1; then
        printf '%s\n' "$message" >&2
        exit 1
    fi
}

expect_external_failure \
    missing \
    'Vorbis quality runner accepted missing external metrics'
expect_external_failure \
    error \
    'Vorbis quality runner accepted excessive external error'
expect_external_failure \
    snr \
    'Vorbis quality runner accepted low external SNR'

cp "$root/q0.ogg" "$root/q10.ogg"
expect_failure pass 'Vorbis quality runner accepted identical encodings'

printf 'Vorbis quality runner self-test passed\n'
