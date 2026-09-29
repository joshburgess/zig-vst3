#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-autonomous-runner.XXXXXX")
fixture=$(CDPATH='' cd -- "$fixture" && pwd)

cleanup() {
    rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$fixture/scripts" "$fixture/bin"
cp \
    "$root/scripts/check_zig_cache_budget.sh" \
    "$root/scripts/zig_autonomous.sh" \
    "$fixture/scripts/"
touch "$fixture/build.zig"

cat >"$fixture/bin/zig" <<'SCRIPT'
#!/bin/sh
set -eu
printf 'global=%s\n' "$ZIG_GLOBAL_CACHE_DIR"
printf 'local=%s\n' "$ZIG_LOCAL_CACHE_DIR"
index=0
for argument in "$@"; do
    printf 'argument_%s=%s\n' "$index" "$argument"
    index=$((index + 1))
done
if [ -n "${FAKE_ZIG_CACHE_GROW_KIB:-}" ]; then
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    dd if=/dev/zero \
        of="$ZIG_GLOBAL_CACHE_DIR/postflight-growth" \
        bs=1024 count="$FAKE_ZIG_CACHE_GROW_KIB" \
        >/dev/null 2>&1
fi
exit "${FAKE_ZIG_STATUS:-0}"
SCRIPT
chmod +x "$fixture/bin/zig"

ZIG="$fixture/bin/zig" \
    "$fixture/scripts/zig_autonomous.sh" \
    build test-matrix -Doptimize=ReleaseSafe \
    >"$fixture/success.txt"
grep -q "global=$fixture/.zig-cache-autonomous/global" \
    "$fixture/success.txt"
grep -q "local=$fixture/.zig-cache-autonomous/local" \
    "$fixture/success.txt"
grep -q '^argument_0=build$' "$fixture/success.txt"
grep -q '^argument_1=test-matrix$' "$fixture/success.txt"
grep -q '^argument_2=-Doptimize=ReleaseSafe$' "$fixture/success.txt"

if "$fixture/scripts/zig_autonomous.sh" >/dev/null 2>&1; then
    printf 'autonomous Zig wrapper accepted no arguments\n' >&2
    exit 1
fi

mkdir -p "$fixture/.zig-cache-autonomous"
printf 'oversized fixture\n' >"$fixture/.zig-cache-autonomous/object"
if ZIG_VST3_CACHE_LIMIT_KIB=1 ZIG="$fixture/bin/zig" \
    "$fixture/scripts/zig_autonomous.sh" build \
        >"$fixture/rejected.txt" 2>&1
then
    printf 'autonomous Zig wrapper accepted an oversized cache\n' >&2
    exit 1
fi
grep -q 'cache budget exceeded' "$fixture/rejected.txt"
if grep -q '^global=' "$fixture/rejected.txt"; then
    printf 'autonomous Zig wrapper invoked Zig after budget rejection\n' >&2
    exit 1
fi
rm -rf -- "$fixture/.zig-cache-autonomous"

set +e
ZIG_VST3_CACHE_LIMIT_KIB=1 \
FAKE_ZIG_CACHE_GROW_KIB=2 \
ZIG="$fixture/bin/zig" \
    "$fixture/scripts/zig_autonomous.sh" build \
        >"$fixture/postflight-rejected.txt" 2>&1
postflight_status=$?
set -e
if [ "$postflight_status" -ne 1 ]; then
    printf 'autonomous Zig wrapper did not report postflight growth\n' >&2
    exit 1
fi
grep -q '^global=' "$fixture/postflight-rejected.txt"
grep -q 'cache budget exceeded' "$fixture/postflight-rejected.txt"
rm -rf -- "$fixture/.zig-cache-autonomous"

set +e
FAKE_ZIG_STATUS=37 ZIG="$fixture/bin/zig" \
    "$fixture/scripts/zig_autonomous.sh" build \
        >"$fixture/zig-failed.txt" 2>&1
zig_status=$?
set -e
if [ "$zig_status" -ne 37 ]; then
    printf 'autonomous Zig wrapper changed the compiler failure status\n' >&2
    exit 1
fi
grep -q 'cache budget passed' "$fixture/zig-failed.txt"

set +e
ZIG_VST3_CACHE_LIMIT_KIB=1 \
FAKE_ZIG_CACHE_GROW_KIB=2 \
FAKE_ZIG_STATUS=41 \
ZIG="$fixture/bin/zig" \
    "$fixture/scripts/zig_autonomous.sh" build \
        >"$fixture/zig-and-budget-failed.txt" 2>&1
combined_status=$?
set -e
if [ "$combined_status" -ne 41 ]; then
    printf 'autonomous Zig wrapper replaced a compiler failure with the budget status\n' >&2
    exit 1
fi
grep -q 'cache budget exceeded' "$fixture/zig-and-budget-failed.txt"

printf 'autonomous Zig wrapper runner passed\n'
