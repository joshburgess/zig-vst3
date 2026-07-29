#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-lv2lint-runner.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

bundle="$test_root/probe.lv2"
mkdir -p "$bundle"
for metadata_file in manifest.ttl plugin.ttl presets.ttl; do
    printf 'fixture\n' > "$bundle/$metadata_file"
done

fake_validate="$test_root/fake-lv2-validate"
fake_lint="$test_root/fake-lv2lint"
validate_arguments="$test_root/validate-arguments.txt"
lint_arguments="$test_root/lint-arguments.txt"

{
    printf '#!/usr/bin/env sh\n'
    printf 'printf "%%s\\n" "$@" > "$FAKE_VALIDATE_ARGUMENTS"\n'
    printf 'exit "${FAKE_VALIDATE_STATUS:-0}"\n'
} > "$fake_validate"
{
    printf '#!/usr/bin/env sh\n'
    printf 'printf "%%s\\n" "$@" > "$FAKE_LINT_ARGUMENTS"\n'
    printf 'exit "${FAKE_LINT_STATUS:-0}"\n'
} > "$fake_lint"
chmod +x "$fake_validate" "$fake_lint"

FAKE_VALIDATE_ARGUMENTS="$validate_arguments" \
FAKE_LINT_ARGUMENTS="$lint_arguments" \
LV2_VALIDATE="$fake_validate" \
LV2LINT="$fake_lint" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$bundle" \
    "https://example.test/plugin" \
    >/dev/null

[ "$(sed -n '1p' "$validate_arguments")" = "$bundle/manifest.ttl" ]
[ "$(sed -n '2p' "$validate_arguments")" = "$bundle/plugin.ttl" ]
[ "$(sed -n '3p' "$validate_arguments")" = "$bundle/presets.ttl" ]
[ "$(sed -n '4p' "$validate_arguments")" = "" ]
[ "$(sed -n '1p' "$lint_arguments")" = "-M" ]
[ "$(sed -n '2p' "$lint_arguments")" = "nopack" ]
[ "$(sed -n '3p' "$lint_arguments")" = "-E" ]
[ "$(sed -n '4p' "$lint_arguments")" = "warn" ]
[ "$(sed -n '5p' "$lint_arguments")" = "-I" ]
[ "$(sed -n '6p' "$lint_arguments")" = "$bundle" ]
[ "$(sed -n '7p' "$lint_arguments")" = "https://example.test/plugin" ]
[ "$(sed -n '8p' "$lint_arguments")" = "" ]

set +e
FAKE_VALIDATE_STATUS=7 \
FAKE_VALIDATE_ARGUMENTS="$validate_arguments" \
FAKE_LINT_ARGUMENTS="$lint_arguments" \
LV2_VALIDATE="$fake_validate" \
LV2LINT="$fake_lint" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$bundle" \
    "https://example.test/plugin" \
    >/dev/null 2>&1
validate_status=$?
set -e
[ "$validate_status" -eq 7 ]

set +e
FAKE_LINT_STATUS=9 \
FAKE_VALIDATE_ARGUMENTS="$validate_arguments" \
FAKE_LINT_ARGUMENTS="$lint_arguments" \
LV2_VALIDATE="$fake_validate" \
LV2LINT="$fake_lint" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$bundle" \
    "https://example.test/plugin" \
    >/dev/null 2>&1
lint_status=$?
set -e
[ "$lint_status" -eq 9 ]

if LV2_VALIDATE="$fake_validate" LV2LINT="$fake_lint" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$test_root/missing.lv2" \
    "https://example.test/plugin" \
    >/dev/null 2>&1; then
    printf 'LV2 lint runner accepted a missing bundle\n' >&2
    exit 1
fi

mkdir -p "$test_root/incomplete.lv2"
printf 'fixture\n' > "$test_root/incomplete.lv2/manifest.ttl"
printf 'fixture\n' > "$test_root/incomplete.lv2/plugin.ttl"
if LV2_VALIDATE="$fake_validate" LV2LINT="$fake_lint" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$test_root/incomplete.lv2" \
    "https://example.test/plugin" \
    >/dev/null 2>&1; then
    printf 'LV2 lint runner accepted incomplete metadata\n' >&2
    exit 1
fi

if LV2_VALIDATE="$test_root/missing-validator" LV2LINT="$fake_lint" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$bundle" \
    "https://example.test/plugin" \
    >/dev/null 2>&1; then
    printf 'LV2 lint runner accepted a missing schema validator\n' >&2
    exit 1
fi

if LV2_VALIDATE="$fake_validate" LV2LINT="$test_root/missing-linter" \
    "$script_dir/lint_lv2_bundle.sh" \
    "$bundle" \
    "https://example.test/plugin" \
    >/dev/null 2>&1; then
    printf 'LV2 lint runner accepted a missing linter\n' >&2
    exit 1
fi

printf 'LV2 lint runner tests passed\n'
