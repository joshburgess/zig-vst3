#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-abi-cache-routing.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

for script in "$repo_root"/scripts/check_*_abi.sh; do
    if grep -q '^out_dir=' "$script" &&
        ! grep -Eq '^out_dir="\$\{ZIG_LOCAL_CACHE_DIR:-\.zig-cache\}/[^\"]+"$' "$script"
    then
        printf 'ABI script does not route output through ZIG_LOCAL_CACHE_DIR: %s\n' "$script" >&2
        exit 1
    fi
done

fake_bin="$temporary/bin"
local_cache="$temporary/local"
global_cache="$temporary/global"
record="$temporary/zig-environment.txt"
work="$temporary/work"
mkdir -p "$fake_bin" "$work"

cat > "$fake_bin/c++" <<'EOF'
#!/bin/sh
set -eu
output=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = '-o' ]; then
        shift
        output=$1
        break
    fi
    shift
done
[ -n "$output" ]
mkdir -p "$(dirname -- "$output")"
cat > "$output" <<'PROGRAM'
#!/bin/sh
printf 'cache-routing-fixture\n'
PROGRAM
chmod +x "$output"
EOF
chmod +x "$fake_bin/c++"

cat > "$fake_bin/zig" <<'EOF'
#!/bin/sh
set -eu
printf 'local=%s\nglobal=%s\n' \
    "${ZIG_LOCAL_CACHE_DIR:-}" \
    "${ZIG_GLOBAL_CACHE_DIR:-}" > "$ABI_CACHE_TEST_RECORD"
printf 'cache-routing-fixture\n'
EOF
chmod +x "$fake_bin/zig"

(
    cd "$work"
    PATH="$fake_bin:$PATH" \
    ZIG="$fake_bin/zig" \
    VST3_SDK_DIR="$repo_root/.vst3-sdk/vst3sdk" \
    ZIG_LOCAL_CACHE_DIR="$local_cache" \
    ZIG_GLOBAL_CACHE_DIR="$global_cache" \
    ABI_CACHE_TEST_RECORD="$record" \
        sh "$repo_root/scripts/check_tuid_abi.sh"
)

test -f "$local_cache/tuid-abi/cpp.txt"
test -f "$local_cache/tuid-abi/zig.txt"
test ! -e "$work/.zig-cache"
grep -Fx "local=$local_cache" "$record" > /dev/null
grep -Fx "global=$global_cache" "$record" > /dev/null
