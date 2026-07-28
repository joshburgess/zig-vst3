#!/usr/bin/env bash
set -euo pipefail

library="${1:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"
bundle_path="${2:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"
platform_dir="${3:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"
executable_name="${4:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"

if [[ ! -f "$library" ]]; then
    printf 'library is not a file: %s\n' "$library" >&2
    exit 1
fi
if [[ "$bundle_path" != *.vst3 || "$bundle_path" == *.vst3/ ]]; then
    printf 'bundle path must end in .vst3: %s\n' "$bundle_path" >&2
    exit 1
fi
if [[ ! "$platform_dir" =~ ^[A-Za-z0-9._-]+$ ||
    "$platform_dir" == "." || "$platform_dir" == ".." ]]; then
    printf 'platform directory must be a single path component: %s\n' "$platform_dir" >&2
    exit 1
fi
if [[ ! "$executable_name" =~ ^[A-Za-z0-9._-]+$ ||
    "$executable_name" == "." || "$executable_name" == ".." ]]; then
    printf 'executable name must be a single path component: %s\n' "$executable_name" >&2
    exit 1
fi

bundle_parent="$(dirname -- "$bundle_path")"
mkdir -p "$bundle_parent"
staging_path="$(mktemp -d "${bundle_path}.staging.XXXXXX")"
cleanup() {
    if [[ -n "$staging_path" ]]; then
        rm -rf -- "$staging_path"
    fi
}
trap cleanup EXIT
target_dir="${staging_path}/Contents/${platform_dir}"

mkdir -p "$target_dir"
cp "$library" "${target_dir}/${executable_name}.so"
rm -rf -- "$bundle_path"
mv -- "$staging_path" "$bundle_path"
staging_path=""
