#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-validator-runner-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM
mkdir -p "$tmp_root/fake.vst3" "$tmp_root/success" "$tmp_root/failure"
printf 'fixture\n' > "$tmp_root/fake.vst3/module.bin"
fake_validator="$tmp_root/fake-validator"
{
    printf '#!/bin/sh\n'
    printf 'printf "fake validator stdout\\n"\n'
    printf 'printf "fake validator stderr\\n" >&2\n'
    # shellcheck disable=SC2016
    printf 'exit "${FAKE_VALIDATOR_STATUS:-0}"\n'
} > "$fake_validator"
chmod +x "$fake_validator"

VST3_VALIDATOR="$fake_validator" VALIDATOR_OUTPUT_DIR="$tmp_root/success" \
    "$script_dir/validate.sh" "$tmp_root/fake.vst3" >/dev/null 2>/dev/null
success_dir="$(find "$tmp_root/success" -mindepth 1 -maxdepth 1 -type d | head -1)"
grep -q '^classification=succeeded$' "$success_dir/runner-status.txt"
grep -q '^phase=steinberg-validator$' "$success_dir/runner-status.txt"
grep -q '^bundle_hash=' "$success_dir/runner-status.txt"
grep -q 'fake validator stdout' "$success_dir/validator.stdout"
grep -q 'fake validator stderr' "$success_dir/validator.stderr"

set +e
FAKE_VALIDATOR_STATUS=139 VST3_VALIDATOR="$fake_validator" VALIDATOR_OUTPUT_DIR="$tmp_root/failure" \
    "$script_dir/validate.sh" "$tmp_root/fake.vst3" >/dev/null 2>/dev/null
failure_status=$?
set -e
[ "$failure_status" -eq 139 ]
failure_dir="$(find "$tmp_root/failure" -mindepth 1 -maxdepth 1 -type d | head -1)"
grep -q '^classification=signaled$' "$failure_dir/runner-status.txt"
grep -q '^signal=11$' "$failure_dir/runner-status.txt"

printf 'validator runner artifact tests passed\n'
