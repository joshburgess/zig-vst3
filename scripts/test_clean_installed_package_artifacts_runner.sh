#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-installed-cleaner.XXXXXX")
cleanup() {
    rm -rf -- "$root"
}
trap cleanup EXIT HUP INT TERM

completed=$root/zig-vst3-installed-consumer.completed
active=$root/zig-vst3-installed-consumer.active
active_namespace=$root/zig-vst3-installed-consumer-active.running
mkdir -p "$completed" "$active" "$active_namespace"
touch \
    "$completed/payload" \
    "$active/payload" \
    "$active/.active" \
    "$active_namespace/payload"

TMPDIR=$root scripts/clean_installed_package_artifacts.sh inspect \
    >"$root/inspect.txt"
test -f "$completed/payload"
test -f "$active/payload"
test -f "$active_namespace/payload"
grep -q 'active staging tree retained' "$root/inspect.txt"
grep -q 'run .* --apply' "$root/inspect.txt"

TMPDIR=$root scripts/clean_installed_package_artifacts.sh --apply \
    >"$root/apply.txt"
test ! -e "$completed"
test -f "$active/payload"
test -f "$active_namespace/payload"
grep -q 'completed staging trees removed; active trees remain' \
    "$root/apply.txt"

rm "$active/.active"
TMPDIR=$root scripts/clean_installed_package_artifacts.sh --apply \
    >"$root/second-apply.txt"
test ! -e "$active"
test -f "$active_namespace/payload"
grep -q 'completed installed-package staging trees removed' \
    "$root/second-apply.txt"

TMPDIR=$root scripts/clean_installed_package_artifacts.sh inspect \
    >"$root/empty.txt"
grep -q 'no installed-package staging trees found' "$root/empty.txt"

if TMPDIR=$root scripts/clean_installed_package_artifacts.sh invalid \
    >/dev/null 2>&1
then
    printf 'installed-package artifact cleaner accepted an invalid mode\n' >&2
    exit 1
fi

mkdir "$root/target"
ln -s "$root/target" "$root/zig-vst3-installed-consumer.link"
if TMPDIR=$root scripts/clean_installed_package_artifacts.sh --apply \
    >/dev/null 2>&1
then
    printf 'installed-package artifact cleaner followed a symbolic link\n' >&2
    exit 1
fi
test -d "$root/target"

printf 'installed-package artifact cleaner runner passed\n'
