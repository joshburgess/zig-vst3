#include "dense.h"

#include <immintrin.h>

#if defined(__clang__) || defined(__GNUC__)
#define ZIG_VST3_AVX2_TARGET __attribute__((target("avx2,sse3")))
#else
#define ZIG_VST3_AVX2_TARGET
#endif

ZIG_VST3_AVX2_TARGET void zig_vst3_dense4_avx2(
    const float *weights,
    const float *bias,
    const float *input,
    float *output) {
    const __m256i indices = _mm256_setr_epi32(0, 1, 2, 3, 0, 1, 2, 3);
    const __m256 values = _mm256_i32gather_ps(input, indices, 4);
    for (unsigned row = 0; row < 4; row += 2) {
        const __m256 products = _mm256_mul_ps(_mm256_loadu_ps(weights + row * 4), values);
        const __m256 pairs = _mm256_hadd_ps(products, products);
        const __m256 sums = _mm256_hadd_ps(pairs, pairs);
        float lanes[8];
        _mm256_storeu_ps(lanes, sums);
        output[row] = bias[row] + lanes[0];
        output[row + 1] = bias[row + 1] + lanes[4];
    }
}
