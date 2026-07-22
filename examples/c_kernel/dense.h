#ifndef ZIG_VST3_DENSE_H
#define ZIG_VST3_DENSE_H

#if defined(_WIN32)
#define ZIG_VST3_KERNEL_HIDDEN
#else
#define ZIG_VST3_KERNEL_HIDDEN __attribute__((visibility("hidden")))
#endif

ZIG_VST3_KERNEL_HIDDEN void zig_vst3_dense4_portable(
    const float *weights,
    const float *bias,
    const float *input,
    float *output);

ZIG_VST3_KERNEL_HIDDEN void zig_vst3_dense4_neon(
    const float *weights,
    const float *bias,
    const float *input,
    float *output);

ZIG_VST3_KERNEL_HIDDEN void zig_vst3_dense4_avx2(
    const float *weights,
    const float *bias,
    const float *input,
    float *output);

#endif
