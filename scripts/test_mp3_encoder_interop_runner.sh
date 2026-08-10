#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-mp3-runner.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
fake_bin="$root/bin"
mkdir "$fake_bin"
fixture="$root/fixture.mp3"
vbri_fixture="$root/vbri-fixture.mp3"
mpeg2_mono_fixture="$root/project-mpeg2-mono.mp3"
mpeg2_intensity_fixture="$root/project-mpeg2-intensity-joint-stereo.mp3"
mpeg25_intensity_fixture="$root/project-mpeg25-intensity-joint-stereo.mp3"
adaptive_gapless_fixture="$root/project-adaptive-gapless.mp3"
adaptive_gapless_vbr_fixture="$root/project-adaptive-gapless-vbr.mp3"
mpeg2_protected_fixture="$root/project-mpeg2-protected.mp3"
mpeg25_protected_fixture="$root/project-mpeg25-protected.mp3"
androidx_vbri_fixture="$root/androidx-vbri.mp3"
helix_encoder="$fake_bin/hmp3"
printf '\377\373\260\104' >"$fixture"
printf '\377\373\260\104' >"$vbri_fixture"
printf '\377\363\200\300' >"$mpeg2_mono_fixture"
printf '\377\363\200\104' >"$mpeg2_intensity_fixture"
printf '\377\343\200\104' >"$mpeg25_intensity_fixture"
printf '\377\373\260\104' >"$adaptive_gapless_fixture"
printf '\377\373\260\104' >"$adaptive_gapless_vbr_fixture"
printf '\377\362\200\300' >"$mpeg2_protected_fixture"
printf '\377\342\200\104' >"$mpeg25_protected_fixture"
printf '\377\373\260\104' >"$androidx_vbri_fixture"
probe_count="$root/probe-count"
reference_probe_count="$root/reference-probe-count"
external_vbri_fixture="$fake_bin/external-vbri-fixture"

cat >"$fake_bin/ffprobe" <<'EOF'
#!/bin/sh
printf 'sample_rate=44100\nchannels=2\n'
EOF
cat >"$fake_bin/ffmpeg" <<'EOF'
#!/bin/sh
case " $* " in
    *' -encoders '*)
        printf ' A....D libshine             libshine MP3 encoder\n'
        exit 0
        ;;
esac
for output do :; done
printf '\001\002\003\004' >"$output"
EOF
chmod +x "$fake_bin/ffprobe" "$fake_bin/ffmpeg"
cat >"$fake_bin/lame" <<'EOF'
#!/bin/sh
for output do :; done
printf '\001\002\003\004' >"$output"
EOF
chmod +x "$fake_bin/lame"
cat >"$fake_bin/decode-probe" <<'EOF'
#!/bin/sh
case "$1" in
    *-truncated.mp3|*-format-change.mp3) exit 1 ;;
    *-protected.mp3)
        [ "${4-}" = "--require-protected" ] || exit 2
        ;;
    *-joint-stereo.mp3)
        [ "${4-}" = "--require-joint-stereo" ] || exit 2
        ;;
    *androidx-vbri.mp3) [ "${4-}" = "--require-vbri" ] || exit 2 ;;
    *helix-vbr.mp3) [ "${4-}" = "--require-helix" ] || exit 2 ;;
esac
count=0
[ ! -f "$TMPDIR/probe-count" ] || count=$(cat "$TMPDIR/probe-count")
count=$((count + 1))
printf '%s\n' "$count" >"$TMPDIR/probe-count"
EOF
chmod +x "$fake_bin/decode-probe"
cp "$fake_bin/decode-probe" "$root/decode-probe-success"
cat >"$fake_bin/reference-probe" <<'EOF'
#!/bin/sh
case "$1" in
    *adaptive-gapless*|*helix-vbr*)
        [ "$#" -eq 4 ] || exit 2
        [ "$4" = "--accept-full-gapless-reference" ] || exit 2
        ;;
    *) [ "$#" -eq 3 ] || exit 2 ;;
esac
count=0
[ ! -f "$TMPDIR/reference-probe-count" ] ||
    count=$(cat "$TMPDIR/reference-probe-count")
printf '%s\n' $((count + 1)) >"$TMPDIR/reference-probe-count"
EOF
chmod +x "$fake_bin/reference-probe"
cp "$fake_bin/reference-probe" "$root/reference-probe-success"
cat >"$helix_encoder" <<'EOF'
#!/bin/sh
printf '\001\002\003\004' >"$2"
EOF
chmod +x "$helix_encoder"
cat >"$external_vbri_fixture" <<'EOF'
#!/bin/sh
cp "$1" "$2"
EOF
chmod +x "$external_vbri_fixture"

PATH="$fake_bin:$PATH" \
TMPDIR="$root" \
MP3_INTEROP_ONLY_FFMPEG=1 \
MP3_INTEROP_REQUIRE_EXTENDED=1 \
ZIG_VST3_EXTERNAL_VBRI_TEST_FILE="$androidx_vbri_fixture" \
ZIG_VST3_HELIX_MP3_ENCODER="$helix_encoder" \
scripts/test_mp3_encoder_interop.sh \
    "$fixture" \
    "$fake_bin/decode-probe" \
    "$fake_bin/reference-probe" \
    "$vbri_fixture" \
    "$external_vbri_fixture" \
    "$mpeg2_mono_fixture" \
    "$mpeg2_intensity_fixture" \
    "$mpeg25_intensity_fixture" \
    "$adaptive_gapless_fixture" \
    "$adaptive_gapless_vbr_fixture" \
    "$mpeg2_protected_fixture" \
    "$mpeg25_protected_fixture" \
    >"$root/passed.txt"
grep -q 'MP3 FFmpeg interoperability test passed' \
    "$root/passed.txt"
grep -q 'MP3 project decoder probe passed' "$root/passed.txt"
grep -q 'MP3 project VBRI decoder probe passed' "$root/passed.txt"
grep -q 'MP3 project MPEG-2 mono decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 project MPEG-2 intensity-stereo decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 project MPEG-2.5 intensity-stereo decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 project adaptive gapless CBR decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 project adaptive gapless VBR decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 project protected MPEG-2 decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 project protected MPEG-2.5 decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 AndroidX VBRI decoder and seek probe passed' \
    "$root/passed.txt"
grep -q 'MP3 AndroidX VBRI FFmpeg decoded-PCM reference passed' \
    "$root/passed.txt"
grep -q 'MP3 Helix VBR decoder and metadata probe passed' \
    "$root/passed.txt"
grep -q 'MP3 Helix VBR FFmpeg decoded-PCM reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project MPEG-2 mono FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project MPEG-2 intensity FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project MPEG-2.5 intensity FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project adaptive gapless CBR FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project adaptive gapless VBR FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project protected MPEG-2 FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 project protected MPEG-2.5 FFmpeg reference passed' \
    "$root/passed.txt"
grep -q 'MP3 VBRI FFmpeg interoperability test passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-1 stereo decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 external-audio VBRI decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 external-audio VBRI FFmpeg decode passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg bounded junk resynchronization probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg trailing-junk rejection probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-1 decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 Shine MPEG-1 stereo decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 Shine MPEG-1 decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME protected-frame decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME protected decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME free-format decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME free-format decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-2 decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME MPEG-2 joint-stereo decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME MPEG-2 joint-stereo decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-2.5 decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME MPEG-2.5 joint-stereo decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 LAME MPEG-2.5 joint-stereo decoded-PCM reference probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg tagged multi-point seek probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg ID3v2.4 decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-2 mono decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-2.5 mono decoder probe passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg truncation rejection passed' \
    "$root/passed.txt"
grep -q 'MP3 FFmpeg format-change rejection passed' \
    "$root/passed.txt"
[ "$(cat "$probe_count")" -eq 24 ] || {
    printf 'MP3 runner skipped a decoder probe\n' >&2
    exit 1
}
[ "$(cat "$reference_probe_count")" -eq 17 ] || {
    printf 'MP3 runner skipped the decoded-PCM reference probe\n' >&2
    exit 1
}

expect_decode_probe_failure() {
    failure_call=$1
    rm -f "$probe_count" "$reference_probe_count"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '    *-truncated.mp3|*-format-change.mp3) exit 1 ;;' \
        '    *-protected.mp3) [ "${4-}" = "--require-protected" ] || exit 2 ;;' \
        '    *-joint-stereo.mp3) [ "${4-}" = "--require-joint-stereo" ] || exit 2 ;;' \
        '    *androidx-vbri.mp3) [ "${4-}" = "--require-vbri" ] || exit 2 ;;' \
        '    *helix-vbr.mp3) [ "${4-}" = "--require-helix" ] || exit 2 ;;' \
        'esac' \
        'count_file="${TMPDIR:-/tmp}/probe-count"' \
        'count=0' \
        '[ ! -f "$count_file" ] || count=$(cat "$count_file")' \
        'count=$((count + 1))' \
        'printf "%s\n" "$count" >"$count_file"' \
        "[ \"\$count\" -lt \"$failure_call\" ]" \
        >"$fake_bin/decode-probe"
    chmod +x "$fake_bin/decode-probe"
    if PATH="$fake_bin:$PATH" \
        TMPDIR="$root" \
        MP3_INTEROP_ONLY_FFMPEG=1 \
        MP3_INTEROP_REQUIRE_EXTENDED=1 \
        ZIG_VST3_EXTERNAL_VBRI_TEST_FILE="$androidx_vbri_fixture" \
        ZIG_VST3_HELIX_MP3_ENCODER="$helix_encoder" \
        scripts/test_mp3_encoder_interop.sh \
        "$fixture" \
        "$fake_bin/decode-probe" \
        "$root/reference-probe-success" \
        "$vbri_fixture" \
        "$external_vbri_fixture" \
        "$mpeg2_mono_fixture" \
        "$mpeg2_intensity_fixture" \
        "$mpeg25_intensity_fixture" \
        "$adaptive_gapless_fixture" \
        "$adaptive_gapless_vbr_fixture" \
        "$mpeg2_protected_fixture" \
        "$mpeg25_protected_fixture" \
        >/dev/null 2>&1; then
        printf 'MP3 runner accepted decoder probe failure %s\n' \
            "$failure_call" >&2
        exit 1
    fi
}

failure_call=1
while [ "$failure_call" -le 24 ]; do
    expect_decode_probe_failure "$failure_call"
    failure_call=$((failure_call + 1))
done
cp "$root/decode-probe-success" "$fake_bin/decode-probe"

expect_reference_probe_failure() {
    failure_call=$1
    rm -f "$probe_count" "$reference_probe_count"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '    *adaptive-gapless*|*helix-vbr*)' \
        '        [ "$#" -eq 4 ] || exit 2' \
        '        [ "$4" = "--accept-full-gapless-reference" ] || exit 2' \
        '        ;;' \
        '    *) [ "$#" -eq 3 ] || exit 2 ;;' \
        'esac' \
        'count_file="${TMPDIR:-/tmp}/reference-probe-count"' \
        'count=0' \
        '[ ! -f "$count_file" ] || count=$(cat "$count_file")' \
        'count=$((count + 1))' \
        'printf "%s\n" "$count" >"$count_file"' \
        "[ \"\$count\" -lt \"$failure_call\" ]" \
        >"$fake_bin/reference-probe"
    chmod +x "$fake_bin/reference-probe"
    if PATH="$fake_bin:$PATH" \
        TMPDIR="$root" \
        MP3_INTEROP_ONLY_FFMPEG=1 \
        MP3_INTEROP_REQUIRE_EXTENDED=1 \
        ZIG_VST3_EXTERNAL_VBRI_TEST_FILE="$androidx_vbri_fixture" \
        ZIG_VST3_HELIX_MP3_ENCODER="$helix_encoder" \
        scripts/test_mp3_encoder_interop.sh \
        "$fixture" \
        "$fake_bin/decode-probe" \
        "$fake_bin/reference-probe" \
        "$vbri_fixture" \
        "$external_vbri_fixture" \
        "$mpeg2_mono_fixture" \
        "$mpeg2_intensity_fixture" \
        "$mpeg25_intensity_fixture" \
        "$adaptive_gapless_fixture" \
        "$adaptive_gapless_vbr_fixture" \
        "$mpeg2_protected_fixture" \
        "$mpeg25_protected_fixture" \
        >/dev/null 2>&1; then
        printf 'MP3 runner accepted PCM reference failure %s\n' \
            "$failure_call" >&2
        exit 1
    fi
}

failure_call=1
while [ "$failure_call" -le 17 ]; do
    expect_reference_probe_failure "$failure_call"
    failure_call=$((failure_call + 1))
done
cp "$root/reference-probe-success" "$fake_bin/reference-probe"

if PATH="$fake_bin:$PATH" TMPDIR="$root" \
    MP3_INTEROP_SKIP_FFMPEG=1 \
    MP3_INTEROP_REQUIRE_EXTENDED=1 \
    scripts/test_mp3_encoder_interop.sh \
        "$fixture" "$fake_bin/decode-probe" \
        >"$root/missing-vbri.txt" 2>&1; then
    printf 'MP3 runner accepted a missing required VBRI fixture\n' >&2
    exit 1
fi
grep -q 'required AndroidX VBRI fixture is unavailable' \
    "$root/missing-vbri.txt"

if PATH="$fake_bin:$PATH" TMPDIR="$root" \
    MP3_INTEROP_ONLY_FFMPEG=1 \
    MP3_INTEROP_REQUIRE_EXTENDED=1 \
    ZIG_VST3_EXTERNAL_VBRI_TEST_FILE="$androidx_vbri_fixture" \
    scripts/test_mp3_encoder_interop.sh \
        "$fixture" "$fake_bin/decode-probe" \
        "$fake_bin/reference-probe" \
        >"$root/missing-helix.txt" 2>&1; then
    printf 'MP3 runner accepted a missing required Helix encoder\n' >&2
    exit 1
fi
grep -q 'required Helix MP3 encoder is unavailable' \
    "$root/missing-helix.txt"

cat >"$fake_bin/ffmpeg" <<'EOF'
#!/bin/sh
for output do :; done
: >"$output"
EOF
chmod +x "$fake_bin/ffmpeg"
if PATH="$fake_bin:$PATH" \
    MP3_INTEROP_ONLY_FFMPEG=1 \
    scripts/test_mp3_encoder_interop.sh "$fixture" \
        >"$root/empty.txt" 2>&1; then
    printf 'empty fake MP3 decode unexpectedly passed\n' >&2
    exit 1
fi
grep -q 'independent decoder produced empty MP3 PCM' \
    "$root/empty.txt"

MP3_INTEROP_SKIP_FFMPEG=1 \
MP3_INTEROP_ONLY_FFMPEG=1 \
scripts/test_mp3_encoder_interop.sh "$fixture" \
    >"$root/skipped.txt"
grep -q 'MP3 decoder interoperability tests skipped' \
    "$root/skipped.txt"

printf 'MP3 interoperability runner tests passed\n'
