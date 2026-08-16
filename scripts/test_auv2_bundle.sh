#!/bin/sh
set -eu

if [ "$#" -ne 7 ]; then
    printf 'usage: %s <component-bundle> <executable> <type> <subtype> <manufacturer> <factory> <version>\n' "$0" >&2
    exit 2
fi

bundle=$1
executable=$2
component_type=$3
component_subtype=$4
component_manufacturer=$5
factory=$6
version=$7
plist="$bundle/Contents/Info.plist"
binary="$bundle/Contents/MacOS/$executable"

test -d "$bundle"
test -f "$plist"
test -f "$binary"
test -f "$bundle/Contents/PkgInfo"
plutil -lint "$plist" >/dev/null

plist_buddy=/usr/libexec/PlistBuddy
test "$("$plist_buddy" -c 'Print :AudioComponents:0:type' "$plist")" = "$component_type"
test "$("$plist_buddy" -c 'Print :AudioComponents:0:subtype' "$plist")" = "$component_subtype"
test "$("$plist_buddy" -c 'Print :AudioComponents:0:manufacturer' "$plist")" = "$component_manufacturer"
test "$("$plist_buddy" -c 'Print :AudioComponents:0:factoryFunction' "$plist")" = "$factory"
test "$("$plist_buddy" -c 'Print :AudioComponents:0:version' "$plist")" = "$version"
test "$("$plist_buddy" -c 'Print :AudioComponents:0:sandboxSafe' "$plist")" = "true"

nm -gU "$binary" | grep -q "_${factory}$"

printf 'AUv2 bundle metadata and factory symbol checks passed\n'
