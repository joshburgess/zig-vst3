#include "dense.h"

void zig_vst3_dense4_portable(
    const float *weights,
    const float *bias,
    const float *input,
    float *output) {
    for (unsigned row = 0; row < 4; ++row) {
        float sum = bias[row];
        for (unsigned column = 0; column < 4; ++column) {
            sum += weights[row * 4 + column] * input[column];
        }
        output[row] = sum;
    }
}
