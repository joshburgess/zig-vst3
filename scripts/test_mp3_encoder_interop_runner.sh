#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-mp3-runner.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
fake_bin="$root/bin"
mkdir "$fake_bin"
fixture="$root/fixture.mp3"
printf '\377\373\260\104' >"$fixture"

cat >"$fake_bin/ffprobe" <<'EOF'
#!/bin/sh
printf 'sample_rate=44100\nchannels=2\n'
EOF
cat >"$fake_bin/ffmpeg" <<'EOF'
#!/bin/sh
for output do :; done
printf '\001\002\003\004' >"$output"
EOF
chmod +x "$fake_bin/ffprobe" "$fake_bin/ffmpeg"

PATH="$fake_bin:$PATH" \
MP3_INTEROP_ONLY_FFMPEG=1 \
scripts/test_mp3_encoder_interop.sh "$fixture" \
    >"$root/passed.txt"
grep -q 'MP3 FFmpeg interoperability test passed' \
    "$root/passed.txt"

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
