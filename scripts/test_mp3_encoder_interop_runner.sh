#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-mp3-runner.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
fake_bin="$root/bin"
mkdir "$fake_bin"
fixture="$root/fixture.mp3"
printf '\377\373\260\104' >"$fixture"
probe_count="$root/probe-count"
reference_probe_count="$root/reference-probe-count"

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
esac
count=0
[ ! -f "$TMPDIR/probe-count" ] || count=$(cat "$TMPDIR/probe-count")
count=$((count + 1))
printf '%s\n' "$count" >"$TMPDIR/probe-count"
EOF
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
MP3_INTEROP_ONLY_FFMPEG=1 \
scripts/test_mp3_encoder_interop.sh \
    "$fixture" \
    "$fake_bin/decode-probe" \
    "$fake_bin/reference-probe" \
    >"$root/passed.txt"
grep -q 'MP3 FFmpeg interoperability test passed' \
    "$root/passed.txt"
grep -q 'MP3 project decoder probe passed' "$root/passed.txt"
grep -q 'MP3 FFmpeg MPEG-1 stereo decoder probe passed' \
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
grep -q 'MP3 FFmpeg MPEG-2.5 decoded-PCM reference probe passed' \
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
[ "$(cat "$probe_count")" -eq 9 ] || {
    printf 'MP3 runner skipped a decoder probe\n' >&2
    exit 1
}
[ "$(cat "$reference_probe_count")" -eq 6 ] || {
    printf 'MP3 runner skipped the decoded-PCM reference probe\n' >&2
    exit 1
}

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
