#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-installed-runner.XXXXXX")
cleanup() {
    rm -rf -- "$root"
}
trap cleanup EXIT HUP INT TERM

fake_bin=$root/bin
staging=$root/staging
mkdir -p "$fake_bin" "$staging"

write_zig() {
    status=$1
    printf '%s\n' \
        '#!/bin/sh' \
        "exit $status" \
        >"$fake_bin/zig"
    chmod +x "$fake_bin/zig"
}

run_installed() {
    TMPDIR=$staging PATH="$fake_bin:$PATH" \
        scripts/test_installed_package.sh "$@"
}

assert_empty_staging() {
    if find "$staging" -mindepth 1 -maxdepth 1 | grep -q .; then
        printf 'installed-package runner left an unexpected staging tree\n' >&2
        exit 1
    fi
}

write_zig 0
run_installed >"$root/success.txt"
grep -q 'installed-package effect, instrument, core, DSP fixture, and C kernel consumers passed' "$root/success.txt"
assert_empty_staging

write_zig 1
if run_installed >"$root/failure.txt" 2>&1; then
    printf 'installed-package runner accepted a failed build\n' >&2
    exit 1
fi
grep -q 'set ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE=1' "$root/failure.txt"
assert_empty_staging

if (
    ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE=invalid
    export ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE
    run_installed
) >"$root/invalid.txt" 2>&1; then
    printf 'installed-package runner accepted an invalid preservation setting\n' >&2
    exit 1
fi
grep -q 'must be 0 or 1' "$root/invalid.txt"
assert_empty_staging

if run_installed --optimize=invalid >"$root/invalid-argument.txt" 2>&1; then
    printf 'installed-package runner accepted an invalid argument\n' >&2
    exit 1
fi
grep -q '^usage:' "$root/invalid-argument.txt"
assert_empty_staging

if ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE=1 \
    run_installed >"$root/preserved.txt" 2>&1
then
    printf 'installed-package runner accepted a preserved failed build\n' >&2
    exit 1
fi
grep -q 'preserved staged package at' "$root/preserved.txt"
preserved_count=$(find "$staging" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$preserved_count" -ne 1 ]; then
    printf 'installed-package runner did not preserve exactly one requested tree\n' >&2
    exit 1
fi
if find "$staging" -mindepth 1 -maxdepth 1 \
    -type d -name 'zig-vst3-installed-consumer-active.*' | grep -q .
then
    printf 'installed-package runner preserved a live staging namespace\n' >&2
    exit 1
fi
if find "$staging" -mindepth 2 -maxdepth 2 -name .active | grep -q .; then
    printf 'installed-package runner preserved an active marker\n' >&2
    exit 1
fi
TMPDIR=$staging scripts/clean_installed_package_artifacts.sh --apply >/dev/null
assert_empty_staging

cat >"$fake_bin/zig" <<'SCRIPT'
#!/bin/sh
set -eu
touch "$INTERRUPT_READY"
while [ ! -f "$INTERRUPT_RELEASE" ]; do
    sleep 0.01
done
SCRIPT
chmod +x "$fake_bin/zig"
INTERRUPT_READY="$root/interrupt-ready" \
INTERRUPT_RELEASE="$root/interrupt-release" \
ZIG_VST3_KEEP_FAILED_INSTALL_PACKAGE=1 \
TMPDIR=$staging \
PATH="$fake_bin:$PATH" \
    scripts/test_installed_package.sh >"$root/interrupted.txt" 2>&1 &
interrupted_pid=$!
attempt=0
while [ ! -f "$root/interrupt-ready" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -gt 500 ]; then
        printf 'installed-package interrupt fixture did not start\n' >&2
        exit 1
    fi
    sleep 0.01
done
kill -TERM "$interrupted_pid"
touch "$root/interrupt-release"
set +e
wait "$interrupted_pid"
interrupted_status=$?
set -e
if [ "$interrupted_status" -ne 143 ]; then
    printf 'installed-package runner returned %s after TERM instead of 143\n' \
        "$interrupted_status" >&2
    exit 1
fi
assert_empty_staging

printf 'installed-package runner passed\n'
