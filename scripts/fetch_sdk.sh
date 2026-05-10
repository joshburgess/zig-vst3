#!/usr/bin/env sh
set -eu

SDK_REPO="${VST3_SDK_REPO:-https://github.com/steinbergmedia/vst3sdk.git}"
SDK_TAG="${VST3_SDK_TAG:-v3.8.0_build_66}"
SDK_COMMIT="${VST3_SDK_COMMIT:-9fad9770f2ae8542ab1a548a68c1ad1ac690abe0}"
SDK_DIR="${VST3_SDK_DIR:-.vst3-sdk/vst3sdk}"

retry() {
    attempts=3
    delay=5
    attempt=1

    while [ "$attempt" -le "$attempts" ]; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -eq "$attempts" ]; then
            return 1
        fi
        printf 'command failed, retrying in %ss: %s\n' "$delay" "$*" >&2
        sleep "$delay"
        attempt=$((attempt + 1))
    done
}

if [ -d "$SDK_DIR/.git" ]; then
    retry git -C "$SDK_DIR" fetch --tags "$SDK_REPO" "$SDK_TAG"
    git -C "$SDK_DIR" checkout --force "$SDK_COMMIT"
else
    mkdir -p "$(dirname "$SDK_DIR")"
    retry git clone --branch "$SDK_TAG" --depth 1 "$SDK_REPO" "$SDK_DIR"
fi

actual_commit="$(git -C "$SDK_DIR" rev-parse HEAD)"
if [ "$actual_commit" != "$SDK_COMMIT" ]; then
    printf 'VST3 SDK commit mismatch\nexpected: %s\nactual:   %s\n' "$SDK_COMMIT" "$actual_commit" >&2
    exit 1
fi

git -C "$SDK_DIR" submodule sync --recursive
retry git -C "$SDK_DIR" submodule update --init --depth 1

printf 'VST3 SDK ready at %s (%s)\n' "$SDK_DIR" "$actual_commit"
