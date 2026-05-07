#!/usr/bin/env bash
set -euo pipefail

library="${1:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"
bundle_path="${2:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"
platform_dir="${3:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"
executable_name="${4:?usage: scripts/bundle_linux_vst3.sh library bundle-path platform-dir executable-name}"

target_dir="${bundle_path}/Contents/${platform_dir}"

rm -rf "$bundle_path"
mkdir -p "$target_dir"
cp "$library" "${target_dir}/${executable_name}.so"
