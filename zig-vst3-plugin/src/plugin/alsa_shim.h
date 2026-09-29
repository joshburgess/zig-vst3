#ifndef ZIG_VST3_ALSA_SHIM_H
#define ZIG_VST3_ALSA_SHIM_H

#include <stddef.h>
#include <stdint.h>

enum {
    ZV3_ALSA_CAPTURE = 0,
    ZV3_ALSA_PLAYBACK = 1
};

typedef int32_t (*zv3_alsa_process_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels,
    void *const *output_channels
);

typedef int32_t (*zv3_alsa_capture_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels
);

typedef int32_t (*zv3_alsa_render_fn)(
    void *context,
    uint32_t frame_count,
    void *const *output_channels
);

typedef struct zv3_alsa_session zv3_alsa_session;

typedef struct {
    uint64_t processed;
    uint64_t callback_failures;
    uint64_t capture_underflows;
    uint64_t capture_overflows;
    uint64_t recoveries;
    uint64_t device_failures;
    uint32_t realtime_priority_acquired;
} zv3_alsa_statistics;

int32_t zv3_alsa_available(void);
int32_t zv3_alsa_device_count(uint32_t direction, size_t *output);
int32_t zv3_alsa_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_default_device_id(
    uint32_t direction,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_device_channels(
    uint32_t direction,
    const uint8_t *identifier,
    size_t identifier_length,
    uint32_t *output
);
int32_t zv3_alsa_start(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_alsa_process_fn process,
    zv3_alsa_session **output
);
int32_t zv3_alsa_start_split(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_alsa_capture_fn capture,
    zv3_alsa_render_fn render,
    zv3_alsa_session **output
);
void zv3_alsa_get_statistics(
    const zv3_alsa_session *session,
    zv3_alsa_statistics *output
);
void zv3_alsa_stop(
    zv3_alsa_session *session,
    zv3_alsa_statistics *final_statistics
);

#endif
