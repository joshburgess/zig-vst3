#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-vorbis-runner.XXXXXX")
cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

fixture="$root/input.ogg"
fake_bin="$root/bin"
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
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'test -s "$1"' \
    'case "$1" in' \
    '    *-corrupt.ogg|*-truncated.ogg) exit 1 ;;' \
    'esac' \
    >"$fake_bin/decode-probe"
chmod +x "$fake_bin/decode-probe"

PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_ONLY_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture" "$fake_bin/decode-probe" \
    >"$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg stereo encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg multi-page encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg chained encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg mono encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg 5.1 encoder decode and seek test passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project decoder and seek probe passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project chained decoder and seek probe passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project chained checksum corruption rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project checksum corruption rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis project truncation rejection passed' \
    "$root/ffmpeg.txt"
grep -q 'Vorbis FFmpeg chained truncation rejection passed' \
    "$root/ffmpeg.txt"

probe_count="$root/probe-count"
expect_probe_failure() {
    failure_call=$1
    failure_message=$2
    rm -f "$probe_count"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/sh' \
        'count_file="${TMPDIR:-/tmp}/probe-count"' \
        'case "$1" in' \
        '    *-corrupt.ogg|*-truncated.ogg) exit 1 ;;' \
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
    'Vorbis runner accepted a project chained decode failure'
expect_probe_failure \
    3 \
    'Vorbis runner accepted a stereo decode failure'
expect_probe_failure \
    4 \
    'Vorbis runner accepted a multi-page stereo decode failure'
expect_probe_failure \
    5 \
    'Vorbis runner accepted a chained decode failure'
expect_probe_failure \
    6 \
    'Vorbis runner accepted a mono decode failure'
expect_probe_failure \
    7 \
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
