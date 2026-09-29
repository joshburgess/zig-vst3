#ifndef INSTALLED_CONSUMER_DENSE_H
#define INSTALLED_CONSUMER_DENSE_H

#if defined(_WIN32)
#define INSTALLED_KERNEL_HIDDEN
#else
#define INSTALLED_KERNEL_HIDDEN __attribute__((visibility("hidden")))
#endif

INSTALLED_KERNEL_HIDDEN float installed_dense_dot4(const float *weights, const float *input);

#endif
