#!/usr/bin/env bash
set -euo pipefail

library="${1:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
bundle_path="${2:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
bundle_id="${3:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
version="${4:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"
executable_name="${5:?usage: scripts/bundle_macos_vst3.sh library bundle-path bundle-id version executable-name}"

if [[ ! -f "$library" ]]; then
    printf 'library is not a file: %s\n' "$library" >&2
    exit 1
fi
if [[ "$bundle_path" != *.vst3 || "$bundle_path" == *.vst3/ ]]; then
    printf 'bundle path must end in .vst3: %s\n' "$bundle_path" >&2
    exit 1
fi
if [[ ! "$executable_name" =~ ^[A-Za-z0-9._-]+$ ||
    "$executable_name" == "." || "$executable_name" == ".." ]]; then
    printf 'executable name must be a single path component: %s\n' "$executable_name" >&2
    exit 1
fi
if [[ ! "$bundle_id" =~ ^[A-Za-z0-9.-]+$ ]]; then
    printf 'bundle identifier contains unsupported characters: %s\n' "$bundle_id" >&2
    exit 1
fi
if [[ ! "$version" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'bundle version contains unsupported characters: %s\n' "$version" >&2
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
contents_dir="${staging_path}/Contents"
macos_dir="${contents_dir}/MacOS"

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
