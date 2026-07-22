#include "dense.h"

#include <arm_neon.h>

void zig_vst3_dense4_neon(
    const float *weights,
    const float *bias,
    const float *input,
    float *output) {
    const float32x4_t values = vld1q_f32(input);
    for (unsigned row = 0; row < 4; ++row) {
        const float32x4_t products = vmulq_f32(vld1q_f32(weights + row * 4), values);
        output[row] = bias[row] + vaddvq_f32(products);
    }
}
