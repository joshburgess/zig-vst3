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
printf 'fixture\n' >"$fixture"

printf '%s\n' \
    '#!/bin/sh' \
    "printf 'vorbis\\n48000\\n'" \
    >"$fake_bin/ffprobe"
printf '%s\n' \
    '#!/bin/sh' \
    'for argument do output=$argument; done' \
    "printf '\\001\\000\\002\\000' >\"\$output\"" \
    >"$fake_bin/ffmpeg"
chmod +x "$fake_bin/ffprobe" "$fake_bin/ffmpeg"

PATH="$fake_bin:$PATH" \
    VORBIS_INTEROP_ONLY_FFMPEG=1 \
    scripts/test_vorbis_interop.sh "$fixture"

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

printf 'Vorbis interoperability runner tests passed\n'
