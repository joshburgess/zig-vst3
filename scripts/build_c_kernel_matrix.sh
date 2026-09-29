#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
    printf 'C kernel universal build requires macOS\n' >&2
    exit 1
fi

root=zig-out/c-kernel-matrix
arm=$root/aarch64-macos
x86=$root/x86_64-macos
linux_arm=$root/aarch64-linux
linux_x86=$root/x86_64-linux
windows=$root/x86_64-windows
universal=$root/universal/zig_vst3_c_kernel.vst3
linux_arm_binary=$linux_arm/bundle/zig_vst3_c_kernel_linux.vst3/Contents/aarch64-linux/zig_vst3_c_kernel_linux.so
linux_x86_binary=$linux_x86/bundle/zig_vst3_c_kernel_linux.vst3/Contents/x86_64-linux/zig_vst3_c_kernel_linux.so
windows_binary=$windows/bundle/zig_vst3_c_kernel_windows.vst3/Contents/x86_64-win/zig_vst3_c_kernel_windows.vst3

rm -rf "$root"

build_target() {
    target=$1
    prefix=$2
    step=$3
    ZIG_GLOBAL_CACHE_DIR=${ZIG_GLOBAL_CACHE_DIR:-.zig-global-cache} zig build \
        -Dtarget="$target" -Doptimize=ReleaseSafe \
        --cache-dir "$prefix/cache" --prefix "$prefix" "$step"
}

build_target aarch64-macos "$arm" bundle-c-kernel
build_target x86_64-macos "$x86" bundle-c-kernel
build_target aarch64-linux-gnu "$linux_arm" bundle-c-kernel-linux
build_target x86_64-linux-gnu "$linux_x86" bundle-c-kernel-linux
build_target x86_64-windows-gnu "$windows" bundle-c-kernel-windows

mkdir -p "$root/universal"
cp -R "$arm/bundle/zig_vst3_c_kernel.vst3" "$universal"
lipo -create \
    "$arm/bundle/zig_vst3_c_kernel.vst3/Contents/MacOS/zig_vst3_c_kernel" \
    "$x86/bundle/zig_vst3_c_kernel.vst3/Contents/MacOS/zig_vst3_c_kernel" \
    -output "$universal/Contents/MacOS/zig_vst3_c_kernel"
lipo "$universal/Contents/MacOS/zig_vst3_c_kernel" -verify_arch arm64 x86_64

if xcrun dyld_info -exports "$universal/Contents/MacOS/zig_vst3_c_kernel" | grep -Eq 'zig_vst3_dense4_(portable|neon|avx2)'; then
    printf 'C kernel symbols escaped the universal plugin bundle\n' >&2
    exit 1
fi

for binary in "$linux_arm_binary" "$linux_x86_binary"; do
    exports=$(objdump -T "$binary")
    if ! printf '%s\n' "$exports" | grep -Eq '[[:space:]]GetPluginFactory$'; then
        printf 'Linux C kernel bundle is missing GetPluginFactory: %s\n' "$binary" >&2
        exit 1
    fi
    if printf '%s\n' "$exports" | grep -Eq 'zig_vst3_dense4_(portable|neon|avx2)$'; then
        printf 'C kernel symbols escaped a Linux plugin bundle: %s\n' "$binary" >&2
        exit 1
    fi
done

windows_exports=$(objdump -p "$windows_binary")
for symbol in GetPluginFactory InitDll ExitDll; do
    if ! printf '%s\n' "$windows_exports" | grep -Eq "[[:space:]]${symbol}$"; then
        printf 'Windows C kernel bundle is missing %s\n' "$symbol" >&2
        exit 1
    fi
done
if printf '%s\n' "$windows_exports" | grep -Eq 'zig_vst3_dense4_(portable|neon|avx2)$'; then
    printf 'C kernel symbols escaped the Windows plugin bundle\n' >&2
    exit 1
fi

printf 'C kernel bundles passed: macOS universal, Linux aarch64/x86_64, Windows x86_64\n'
