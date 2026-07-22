#include <stddef.h>
#include <stdint.h>

float zig_vst3_bench_recurrent_tail(
    float initial,
    float decay,
    uint32_t steps,
    size_t iterations) {
    float checksum = 0.0f;
    for (size_t iteration = 0; iteration < iterations; ++iteration) {
        float state = initial;
        for (uint32_t step = 0; step < steps; ++step) {
            state *= decay;
        }
        checksum += state;
    }
    return checksum;
}

float zig_vst3_bench_convolution_tail(
    const float *input,
    const float *impulse,
    size_t tap_count,
    size_t iterations) {
    float checksum = 0.0f;
    for (size_t iteration = 0; iteration < iterations; ++iteration) {
        float sample = 0.0f;
        for (size_t tap = 0; tap < tap_count; ++tap) {
            sample += input[tap] * impulse[tap];
        }
        checksum += sample;
    }
    return checksum;
}
