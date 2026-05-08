#!/usr/bin/env sh
set -eu

usage() {
  printf 'Usage: %s <host> <host-version> <bundle> <result> [notes]\n' "$0" >&2
  printf 'Example: %s "REAPER" "7.32" "zig_vst3_gain.vst3" "Pass" "Scanned, loaded, automated, saved, reloaded."\n' "$0" >&2
}

if [ "$#" -lt 4 ]; then
  usage
  exit 2
fi

host=$1
host_version=$2
bundle=$3
result=$4
notes=${5:-}

date_value=$(date +%Y-%m-%d)
os_value=$(uname -s)
cpu_value=$(uname -m)
build_hash=$(git rev-parse --short HEAD)

printf '| %s | %s | %s | %s | %s | %s | `%s` | %s | %s |\n' \
  "$date_value" \
  "$host" \
  "$host_version" \
  "$os_value" \
  "$cpu_value" \
  "$build_hash" \
  "$bundle" \
  "$result" \
  "$notes"
