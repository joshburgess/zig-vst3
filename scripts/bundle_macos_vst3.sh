#!/usr/bin/env bash
set -euo pipefail

library="${1:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
bundle_path="${2:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
bundle_id="${3:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
version="${4:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
executable_name="${5:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"

contents_dir="${bundle_path}/Contents"
macos_dir="${contents_dir}/MacOS"

rm -rf "$bundle_path"
mkdir -p "$macos_dir"
cp "$library" "${macos_dir}/${executable_name}"

cat >"${contents_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${executable_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${executable_name}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
</dict>
</plist>
PLIST

printf 'BNDL????' >"${contents_dir}/PkgInfo"
