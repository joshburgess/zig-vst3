#ifndef ZIG_VST3_ALSA_UMP_SHIM_H
#define ZIG_VST3_ALSA_UMP_SHIM_H

#include <stddef.h>
#include <stdint.h>

enum {
    ZV3_ALSA_UMP_INPUT = 0,
    ZV3_ALSA_UMP_OUTPUT = 1
};

typedef void (*zv3_alsa_ump_receive_fn)(
    void *context,
    uint64_t timestamp_nanoseconds,
    const uint32_t *words,
    size_t word_count
);

typedef struct zv3_alsa_ump_input zv3_alsa_ump_input;
typedef struct zv3_alsa_ump_output zv3_alsa_ump_output;

typedef struct {
    uint64_t read_failures;
} zv3_alsa_ump_input_statistics;

typedef struct {
    uint64_t queued;
    uint64_t delivered;
    uint64_t late;
    uint64_t rejected;
    uint64_t canceled;
    uint64_t write_failures;
} zv3_alsa_ump_output_statistics;

int32_t zv3_alsa_ump_available(void);
uint64_t zv3_alsa_ump_now_nanoseconds(void);
int32_t zv3_alsa_ump_device_count(
    uint32_t direction,
    size_t *output
);
int32_t zv3_alsa_ump_device_identity(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_ump_device_open_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_ump_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_ump_start_input(
    const uint8_t *open_name,
    size_t open_name_length,
    void *context,
    zv3_alsa_ump_receive_fn receive,
    zv3_alsa_ump_input **output
);
void zv3_alsa_ump_stop_input(
    zv3_alsa_ump_input *input,
    zv3_alsa_ump_input_statistics *final_statistics
);
void zv3_alsa_ump_get_input_statistics(
    const zv3_alsa_ump_input *input,
    zv3_alsa_ump_input_statistics *output
);
int32_t zv3_alsa_ump_open_output(
    const uint8_t *open_name,
    size_t open_name_length,
    zv3_alsa_ump_output **output
);
int32_t zv3_alsa_ump_send(
    zv3_alsa_ump_output *output,
    uint64_t timestamp_nanoseconds,
    const uint32_t *words,
    size_t word_count
);
void zv3_alsa_ump_get_output_statistics(
    const zv3_alsa_ump_output *output,
    zv3_alsa_ump_output_statistics *statistics
);
void zv3_alsa_ump_close_output(
    zv3_alsa_ump_output *output,
    zv3_alsa_ump_output_statistics *final_statistics
);

#endif
