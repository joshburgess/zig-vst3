#!/usr/bin/env bash
set -euo pipefail

library="${1:?usage: scripts/bundle_windows_vst3.sh library bundle-path platform-dir executable-name}"
bundle_path="${2:?usage: scripts/bundle_windows_vst3.sh library bundle-path platform-dir executable-name}"
platform_dir="${3:?usage: scripts/bundle_windows_vst3.sh library bundle-path platform-dir executable-name}"
executable_name="${4:?usage: scripts/bundle_windows_vst3.sh library bundle-path platform-dir executable-name}"

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
backup_path=""
cleanup() {
    if [[ -n "$staging_path" ]]; then
        rm -rf -- "$staging_path"
    fi
    if [[ -n "$backup_path" ]]; then
        if [[ -e "$bundle_path" || -L "$bundle_path" ]]; then
            rm -rf -- "$backup_path"
        elif ! mv -- "$backup_path" "$bundle_path"; then
            printf 'failed to restore prior bundle: %s\n' "$bundle_path" >&2
        fi
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
target_dir="${staging_path}/Contents/${platform_dir}"

mkdir -p "$target_dir"
cp "$library" "${target_dir}/${executable_name}.vst3"
if [[ -e "$bundle_path" || -L "$bundle_path" ]]; then
    backup_path="$(mktemp -d "${bundle_path}.backup.XXXXXX")"
    rmdir -- "$backup_path"
    mv -- "$bundle_path" "$backup_path"
fi
mv -- "$staging_path" "$bundle_path"
staging_path=""
if [[ -n "$backup_path" ]]; then
    rm -rf -- "$backup_path"
    backup_path=""
fi
