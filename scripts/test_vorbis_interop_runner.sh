#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-runner.XXXXXX")
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

fixture="$root/input.ogg"
fake_bin="$root/bin"
reference_probe_count="$root/reference-probe-count"
mkdir -p "$fake_bin"
printf 'fixture fixture fixture fixture\n' >"$fixture"

printf '%s\n' \
    '#!/bin/sh' \
    "printf 'vorbis\\n48000\\n'" \
    >"$fake_bin/ffprobe"
printf '%s\n' \
    '#!/bin/sh' \
    "for argument do output=\$argument; done" \
    "printf '\\001\\000\\002\\000' >\"\$output\"" \
    >"$fake_bin/ffmpeg"
chmod +x "$fake_bin/ffprobe" "$fake_bin/ffmpeg"
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
chmod +x "$fake_bin/oggdec"
cat >"$fake_bin/oggenc" <<'EOF'
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
printf '%s\n' '#!/bin/sh' 'printf "Linux\n"' >"$fake_bin/uname"
chmod +x "$fake_bin/oggenc" "$fake_bin/uname"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'test -s "$1"' \
    'if [ "${2-}" = "--write-invalid-audio-packet" ]; then cp "$1" "$3"; exit 0; fi' \
    'if [ "${2-}" = "--recover-invalid-audio-packet" ]; then exit 0; fi' \
    'if [ "${2-}" = "--require-comment" ] && [ "${4-}" = "wrong" ]; then exit 1; fi' \
    'case "$1" in' \
    '    *-corrupt.ogg|*-truncated.ogg|*-geometry-change.ogg|*-invalid-audio-packet.ogg) exit 1 ;;' \
    'esac' \
    >"$fake_bin/decode-probe"
chmod +x "$fake_bin/decode-probe"
cat >"$fake_bin/reference-probe" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$TMPDIR/reference-probe-count" ] ||
    count=$(cat "$TMPDIR/reference-probe-count")
printf '%s\n' $((count + 1)) >"$TMPDIR/reference-probe-count"
EOF
chmod +x "$fake_bin/reference-probe"

PATH="$fake_bin:$PATH" \
    TMPDIR="$root" \
    VORBIS_INTEROP_ONLY_FFMPEG=0 \
    scripts/test_vorbis_interop.sh \
    "$fixture" \
    "$fake_bin/decode-probe" \
    "$fake_bin/reference-probe" \
    >"$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg stereo encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg comment metadata test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg multi-page encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg bounded junk resynchronization probe passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg invalid audio-packet rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg invalid audio-packet concealment passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg chained encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg mono encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg 8 kHz stereo geometry test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg 16 kHz mono geometry test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg chained geometry-change rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg low-quality 512/4096 geometry test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg 5.1 encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project decoder and seek probe passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project comment metadata test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project comment metadata mismatch rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project fixture Xiph decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project chained decoder and seek probe passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project chained Xiph decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project chained checksum corruption rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project checksum corruption rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project truncation rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg chained truncation rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph stereo decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph multi-page decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph chained decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg multi-page decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph mono decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph 8 kHz decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph 16 kHz decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph low-quality decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph 5.1 decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph stereo encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph-encoded FFmpeg decode passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis Xiph-encoded Xiph decoded-PCM reference passed' \
    "$root/ffmpeg.txt"
[ "$(cat "$reference_probe_count")" -eq 12 ] || {
    printf 'Vorbis runner skipped a decoded-PCM reference probe\n' >&2
    exit 1
}

probe_count="$root/probe-count"
expect_probe_failure() {
    failure_call=$1
    failure_message=$2
    rm -f "$probe_count"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/sh' \
        'count_file="${TMPDIR:-/tmp}/probe-count"' \
        'if [ "${2-}" = "--write-invalid-audio-packet" ]; then cp "$1" "$3"; fi' \
        'if [ "${2-}" = "--require-comment" ] && [ "${4-}" = "wrong" ]; then exit 1; fi' \
        'case "$1" in' \
        '    *-invalid-audio-packet.ogg) [ "${2-}" = "--recover-invalid-audio-packet" ] || exit 1 ;;' \
        '    *-corrupt.ogg|*-truncated.ogg|*-geometry-change.ogg) exit 1 ;;' \
        'esac' \
        'count=0' \
        '[ ! -f "$count_file" ] || count=$(cat "$count_file")' \
        'count=$((count + 1))' \
        'printf "%s\n" "$count" >"$count_file"' \
        "[ \"\$count\" -lt \"$failure_call\" ]" \
        >"$fake_bin/decode-probe"
    chmod +x "$fake_bin/decode-probe"
    if PATH="$fake_bin:$PATH" \
        TMPDIR="$root" \
        VORBIS_INTEROP_ONLY_FFMPEG=1 \
        scripts/test_vorbis_interop.sh \
        "$fixture" \
        "$fake_bin/decode-probe" \
        >/dev/null 2>&1; then
        printf '%s\n' "$failure_message" >&2
        exit 1
    fi
}

expect_probe_failure \
    2 \
    'Vorbis runner accepted a project comment metadata failure'
expect_probe_failure \
    3 \
    'Vorbis runner accepted a project chained decode failure'
expect_probe_failure \
    4 \
    'Vorbis runner accepted a stereo decode failure'
expect_probe_failure \
    5 \
    'Vorbis runner accepted a comment metadata failure'
expect_probe_failure \
    6 \
    'Vorbis runner accepted a multi-page stereo decode failure'
expect_probe_failure \
    7 \
    'Vorbis runner accepted a bounded junk recovery failure'
expect_probe_failure \
    8 \
    'Vorbis runner accepted an invalid audio-packet fixture failure'
expect_probe_failure \
    9 \
    'Vorbis runner accepted an invalid audio-packet concealment failure'
expect_probe_failure \
    10 \
    'Vorbis runner accepted a chained decode failure'
expect_probe_failure \
    11 \
    'Vorbis runner accepted a mono decode failure'
expect_probe_failure \
    12 \
    'Vorbis runner accepted an 8 kHz decode failure'
expect_probe_failure \
    13 \
    'Vorbis runner accepted a 16 kHz decode failure'
expect_probe_failure \
    14 \
    'Vorbis runner accepted a low-quality geometry decode failure'
expect_probe_failure \
    15 \
    'Vorbis runner accepted a 5.1 decode failure'
rm -f "$probe_count"

printf '%s\n' \
    '#!/bin/sh' \
    'exit 1' \
    >"$fake_bin/ffmpeg"
chmod +x "$fake_bin/ffmpeg"
if PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_ONLY_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture" \
    >/dev/null 2>&1; then
    printf 'Vorbis runner accepted an FFmpeg decode failure\n' >&2
    exit 1
fi

rm -f "$fake_bin/ffprobe" "$fake_bin/ffmpeg"
printf '%s\n' \
    '#!/bin/sh' \
    "printf 'Darwin\\n'" \
    >"$fake_bin/uname"
printf '%s\n' \
    '#!/bin/sh' \
    'exit 1' \
    >"$fake_bin/afinfo"
printf '%s\n' \
    '#!/bin/sh' \
    'exit 99' \
    >"$fake_bin/afconvert"
chmod +x "$fake_bin/uname" "$fake_bin/afinfo" "$fake_bin/afconvert"
PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_SKIP_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture" \
    >"$root/unavailable.txt"
grep -q 'AudioToolbox decoder unavailable' "$root/unavailable.txt"
grep -q 'decoder interoperability tests skipped' "$root/unavailable.txt"

printf '%s\n' \
    '#!/bin/sh' \
    "printf 'Ogg\\n48000\\n'" \
    >"$fake_bin/afinfo"
printf '%s\n' \
    '#!/bin/sh' \
    'exit 1' \
    >"$fake_bin/afconvert"
chmod +x "$fake_bin/afinfo" "$fake_bin/afconvert"
PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_SKIP_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture" \
    >"$root/conversion-unavailable.txt"
grep -q 'AudioToolbox decoder unavailable' "$root/conversion-unavailable.txt"
grep -q 'decoder interoperability tests skipped' "$root/conversion-unavailable.txt"

printf '%s\n' \
    '#!/bin/sh' \
    "printf 'Ogg\\n48000\\n'" \
    >"$fake_bin/afinfo"
printf '%s\n' \
    '#!/bin/sh' \
    "printf 'RIFF\\050\\000\\000\\000WAVEfmt \\020\\000\\000\\000\\001\\000\\001\\000\\200\\273\\000\\000\\000\\167\\001\\000\\002\\000\\020\\000data\\004\\000\\000\\000\\001\\000\\002\\000' >\"\$2\"" \
    >"$fake_bin/afconvert"
printf '%s\n' \
    '#!/bin/sh' \
    "printf '48000\\n'" \
    >"$fake_bin/ffprobe"
printf '%s\n' \
    '#!/bin/sh' \
    "for argument do output=\$argument; done" \
    "printf '\\001\\000\\002\\000' >\"\$output\"" \
    >"$fake_bin/ffmpeg"
chmod +x "$fake_bin/afinfo" "$fake_bin/afconvert" "$fake_bin/ffprobe" "$fake_bin/ffmpeg"
PATH="$fake_bin:$PATH" \
    scripts/test_vorbis_interop.sh "$fixture" \
    >"$root/audio-toolbox.txt"
grep -q 'Vorbis AudioToolbox interoperability test passed' "$root/audio-toolbox.txt"

printf '%s\n' \
    '#!/bin/sh' \
    "case \"\$1\" in" \
    '    *.wav) printf "WAVE\n48000\naudio data file offset: 4096\naudio bytes: 0\n" ;;' \
    '    *) printf "Ogg\n48000\n" ;;' \
    'esac' \
    >"$fake_bin/afinfo"
printf '%s\n' \
    '#!/bin/sh' \
    "printf 'RIFF\\050\\000\\000\\000WAVEfmt \\020\\000\\000\\000\\001\\000\\001\\000\\200\\273\\000\\000\\000\\167\\001\\000\\002\\000\\020\\000data\\004\\000\\000\\000\\001\\000\\002\\000' >\"\$2\"" \
    >"$fake_bin/afconvert"
chmod +x "$fake_bin/afinfo" "$fake_bin/afconvert"
PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_SKIP_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture" \
    >"$root/audio-toolbox-zero-byte-metadata.txt"
grep -q 'Vorbis AudioToolbox interoperability test passed' \
    "$root/audio-toolbox-zero-byte-metadata.txt"

printf '%s\n' \
    '#!/bin/sh' \
    "printf 'RIFF\\060\\000\\000\\000WAVEfmt \\020\\000\\000\\000\\001\\000\\001\\000\\200\\273\\000\\000\\000\\167\\001\\000\\002\\000\\020\\000JUNK\\004\\000\\000\\000\\000\\000\\000\\000data\\000\\000\\000\\000' >\"\$2\"" \
    >"$fake_bin/afconvert"
chmod +x "$fake_bin/afconvert"
PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_SKIP_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture" \
    >"$root/audio-toolbox-empty-pcm.txt"
grep -q 'AudioToolbox decoder unavailable' \
    "$root/audio-toolbox-empty-pcm.txt"
grep -q 'decoder interoperability tests skipped' \
    "$root/audio-toolbox-empty-pcm.txt"

printf 'Vorbis interoperability runner tests passed\n'
