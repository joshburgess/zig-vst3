#ifndef ZIG_VST3_CORE_AUDIO_SHIM_H
#define ZIG_VST3_CORE_AUDIO_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef int32_t (*zv3_core_audio_process_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels,
    void *const *output_channels
);

typedef int32_t (*zv3_core_audio_capture_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels
);

typedef int32_t (*zv3_core_audio_render_fn)(
    void *context,
    uint32_t frame_count,
    void *const *output_channels
);

typedef struct zv3_core_audio_session zv3_core_audio_session;
typedef struct zv3_core_audio_observer zv3_core_audio_observer;
typedef void (*zv3_core_audio_topology_fn)(void *context);

size_t zv3_core_audio_device_count(void);
int32_t zv3_core_audio_device_at(size_t index, uint32_t *output);
uint32_t zv3_core_audio_default_input_device(void);
uint32_t zv3_core_audio_default_output_device(void);
int32_t zv3_core_audio_device_uid(
    uint32_t device,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_core_audio_device_name(
    uint32_t device,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_core_audio_device_channels(
    uint32_t device,
    uint32_t *input_channels,
    uint32_t *output_channels
);
int32_t zv3_core_audio_device_sample_rate(
    uint32_t device,
    double *output
);
int32_t zv3_core_audio_device_buffer_frames(
    uint32_t device,
    uint32_t *output
);
int32_t zv3_core_audio_observe_topology(
    void *context,
    zv3_core_audio_topology_fn callback,
    zv3_core_audio_observer **output
);
void zv3_core_audio_stop_observing(
    zv3_core_audio_observer *observer
);

int32_t zv3_core_audio_start(
    uint32_t device,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_core_audio_process_fn process,
    zv3_core_audio_session **output
);
int32_t zv3_core_audio_start_split(
    uint32_t input_device,
    uint32_t output_device,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_core_audio_capture_fn capture,
    zv3_core_audio_render_fn render,
    zv3_core_audio_session **output
);
uint64_t zv3_core_audio_device_failures(
    zv3_core_audio_session *session
);
uint64_t zv3_core_audio_input_device_failures(
    zv3_core_audio_session *session
);
uint64_t zv3_core_audio_output_device_failures(
    zv3_core_audio_session *session
);
void zv3_core_audio_stop(zv3_core_audio_session *session);

#if defined(ZIG_VST3_CORE_AUDIO_TESTING)
int32_t zv3_core_audio_test_callback_drain(void);
#endif

#endif
