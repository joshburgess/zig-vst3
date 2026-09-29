#!/usr/bin/env bash
set -euo pipefail

usage="usage: scripts/bundle_macos_auv2.sh library bundle-path bundle-id version executable-name type subtype manufacturer component-name factory-function component-version"
library="${1:?$usage}"
bundle_path="${2:?$usage}"
bundle_id="${3:?$usage}"
version="${4:?$usage}"
executable_name="${5:?$usage}"
component_type="${6:?$usage}"
component_subtype="${7:?$usage}"
component_manufacturer="${8:?$usage}"
component_name="${9:?$usage}"
factory_function="${10:?$usage}"
component_version="${11:?$usage}"

if [[ ! -f "$library" ]]; then
    printf 'library is not a file: %s\n' "$library" >&2
    exit 1
fi
if [[ "$bundle_path" != *.component || "$bundle_path" == *.component/ ]]; then
    printf 'bundle path must end in .component: %s\n' "$bundle_path" >&2
    exit 1
fi
if [[ ! "$executable_name" =~ ^[A-Za-z0-9._-]+$ ||
    "$executable_name" == "." || "$executable_name" == ".." ]]; then
    printf 'executable name must be a single path component: %s\n' "$executable_name" >&2
    exit 1
fi
if [[ ! "$factory_function" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf 'factory function is not a C symbol: %s\n' "$factory_function" >&2
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
for code in "$component_type" "$component_subtype" "$component_manufacturer"; do
    if [[ ! "$code" =~ ^[A-Za-z0-9]{4}$ ]]; then
        printf 'component codes must contain four ASCII letters or digits: %s\n' "$code" >&2
        exit 1
    fi
done
if [[ -z "$component_name" || ! "$component_name" =~ ^[A-Za-z0-9:._\ -]+$ ]]; then
    printf 'component name contains unsupported characters: %s\n' "$component_name" >&2
    exit 1
fi
if [[ ! "$component_version" =~ ^[0-9]+$ ]]; then
    printf 'component version must be an unsigned integer: %s\n' "$component_version" >&2
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
    <string>${component_name}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>AudioComponents</key>
    <array>
        <dict>
            <key>type</key>
            <string>${component_type}</string>
            <key>subtype</key>
            <string>${component_subtype}</string>
            <key>manufacturer</key>
            <string>${component_manufacturer}</string>
            <key>name</key>
            <string>${component_name}</string>
            <key>version</key>
            <integer>${component_version}</integer>
            <key>factoryFunction</key>
            <string>${factory_function}</string>
            <key>sandboxSafe</key>
            <true/>
        </dict>
    </array>
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
