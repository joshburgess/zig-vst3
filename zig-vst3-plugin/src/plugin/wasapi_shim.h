#ifndef ZIG_VST3_WASAPI_SHIM_H
#define ZIG_VST3_WASAPI_SHIM_H

#include <stddef.h>
#include <stdint.h>

enum {
    ZV3_WASAPI_CAPTURE = 0,
    ZV3_WASAPI_RENDER = 1
};

typedef int32_t (*zv3_wasapi_process_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels,
    void *const *output_channels
);
typedef int32_t (*zv3_wasapi_capture_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels
);
typedef int32_t (*zv3_wasapi_render_fn)(
    void *context,
    uint32_t frame_count,
    void *const *output_channels
);

typedef struct zv3_wasapi_session zv3_wasapi_session;
typedef struct zv3_wasapi_observer zv3_wasapi_observer;
typedef void (*zv3_wasapi_topology_fn)(void *context);

typedef struct {
    uint64_t processed;
    uint64_t callback_failures;
    uint64_t capture_underflows;
    uint64_t capture_overflows;
    uint64_t device_failures;
} zv3_wasapi_statistics;

int32_t zv3_wasapi_device_count(
    uint32_t direction,
    size_t *output
);
int32_t zv3_wasapi_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_wasapi_default_device_id(
    uint32_t direction,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_wasapi_status_is_not_found(int32_t status);
int32_t zv3_wasapi_device_name(
    const uint8_t *identifier,
    size_t identifier_length,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_wasapi_device_channels(
    const uint8_t *identifier,
    size_t identifier_length,
    uint32_t *output
);
int32_t zv3_wasapi_observe_topology(
    void *context,
    zv3_wasapi_topology_fn callback,
    zv3_wasapi_observer **output
);
void zv3_wasapi_stop_observing(
    zv3_wasapi_observer *observer
);
int32_t zv3_wasapi_start(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_wasapi_process_fn process,
    zv3_wasapi_session **output
);
int32_t zv3_wasapi_start_split(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_wasapi_capture_fn capture,
    zv3_wasapi_render_fn render,
    zv3_wasapi_session **output
);
void zv3_wasapi_get_statistics(
    const zv3_wasapi_session *session,
    zv3_wasapi_statistics *output
);
void zv3_wasapi_stop(
    zv3_wasapi_session *session,
    zv3_wasapi_statistics *final_statistics
);

#endif
