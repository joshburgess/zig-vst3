#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-tremor-interop.XXXXXX")
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
fake_bin=$root/bin
mkdir "$fake_bin"

cat >"$fake_bin/ffmpeg" <<'SCRIPT'
#!/bin/sh
set -eu
for argument do output=$argument; done
count=0
[ ! -f "$FAKE_STATE/ffmpeg-count" ] || count=$(cat "$FAKE_STATE/ffmpeg-count")
count=$((count + 1))
printf '%s\n' "$count" >"$FAKE_STATE/ffmpeg-count"
if [ "${FAKE_MISSING_CASE-0}" = "$count" ]; then exit 0; fi
dd if=/dev/zero of="$output" bs=1 count=128 2>/dev/null
printf 'OggS' | dd of="$output" conv=notrunc 2>/dev/null
SCRIPT
cat >"$fake_bin/oggenc" <<'SCRIPT'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then shift; output=$1; fi
    shift
done
dd if=/dev/zero of="$output" bs=1 count=128 2>/dev/null
printf 'OggS' | dd of="$output" conv=notrunc 2>/dev/null
SCRIPT
cat >"$fake_bin/oggdec" <<'SCRIPT'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then shift; output=$1; fi
    shift
done
printf '\001\000\002\000' >"$output"
SCRIPT
chmod +x "$fake_bin"/*

cat >"$root/stb-probe" <<'SCRIPT'
#!/bin/sh
set -eu
output=$1
channels=$3
case "$output" in
    *.rejected.f32le) exit 1 ;;
esac
dd if=/dev/zero of="$output" bs=1 count=$((channels * 8)) 2>/dev/null
printf '\000\000\000\077' | dd of="$output" conv=notrunc 2>/dev/null
peak=0.5
case "$output" in *fixed-clipping*) peak=1.25 ;; esac
printf 'stb_vorbis decoded links=1 frames=2 values=2 peak=%s\n' "$peak" >&2
SCRIPT
cat >"$root/project-probe" <<'SCRIPT'
#!/bin/sh
set -eu
if [ "${2-}" = --write-invalid-audio-packet ]; then
    cp "$1" "$3"
fi
SCRIPT
cat >"$root/tremor-probe" <<'SCRIPT'
#!/bin/sh
set -eu
output=$1
channels=$3
case "$output" in
    *.tremor-rejected.s16le) exit 1 ;;
esac
if [ "${ZIG_VST3_TREMOR_FAIL_LINK-}" = 1 ]; then exit 1; fi
if [ "${FAKE_EMPTY_TREMOR-0}" = 1 ]; then
    : >"$output"
elif [ "${FAKE_TREMOR_SHAPE-0}" = 1 ]; then
    printf '\001\000' >"$output"
else
    dd if=/dev/zero of="$output" bs=1 count=$((channels * 4)) 2>/dev/null
    printf '\001\000' | dd of="$output" conv=notrunc 2>/dev/null
fi
printf 'Tremor decoded links=1 frames=2 values=2 peak=2\n' >&2
SCRIPT
cat >"$root/quality-probe" <<'SCRIPT'
#!/bin/sh
set -eu
case "${FAKE_METRIC_MODE-pass}" in
    pass) printf 'peak_error=0.00001 normalized_rms_error=0.0001\n' >&2 ;;
    missing) printf 'peak_error=0.00001\n' >&2 ;;
    excessive) printf 'peak_error=0.5 normalized_rms_error=0.5\n' >&2 ;;
    *) exit 2 ;;
esac
SCRIPT
chmod +x "$root"/*-probe

fixture=$root/project.ogg
dd if=/dev/zero of="$fixture" bs=1 count=128 2>/dev/null
printf 'OggS' | dd of="$fixture" conv=notrunc 2>/dev/null
script=$repo/scripts/test_stb_vorbis_interop.sh

run_gate() {
    rm -f "$root/ffmpeg-count"
    PATH="$fake_bin:$PATH" FAKE_STATE="$root" "$@" "$script" \
        "$fixture" "$root/stb-probe" "$root/project-probe" \
        "$root/quality-probe" "$root/tremor-probe"
}

run_gate >/dev/null

expect_failure() {
    message=$1
    shift
    if run_gate "$@" >/dev/null 2>&1; then
        printf 'Tremor interoperability runner accepted %s\n' "$message" >&2
        exit 1
    fi
}

expect_failure 'an omitted generated case' env FAKE_MISSING_CASE=1
expect_failure 'an empty Tremor result' env FAKE_EMPTY_TREMOR=1
expect_failure 'a Tremor shape mismatch' env FAKE_TREMOR_SHAPE=1
expect_failure 'a missing metric' env FAKE_METRIC_MODE=missing
expect_failure 'an excessive metric' env FAKE_METRIC_MODE=excessive

if PATH="$fake_bin:$PATH" FAKE_STATE="$root" "$script" \
    "$fixture" "$root/missing-stb-probe" "$root/project-probe" \
    "$root/quality-probe" "$root/tremor-probe" >/dev/null 2>&1; then
    printf 'Tremor interoperability runner accepted a missing artifact\n' >&2
    exit 1
fi

printf 'Tremor interoperability failure runner passed\n'
