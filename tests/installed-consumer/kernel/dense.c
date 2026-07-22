#include "dense.h"

float installed_dense_dot4(const float *weights, const float *input) {
    float result = 0.0f;
    for (unsigned index = 0; index < 4; ++index) {
        result += weights[index] * input[index];
    }
    return result;
}
