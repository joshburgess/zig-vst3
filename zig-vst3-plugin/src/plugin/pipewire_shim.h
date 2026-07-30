#ifndef ZIG_VST3_PIPEWIRE_SHIM_H
#define ZIG_VST3_PIPEWIRE_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef int32_t (*zv3_pipewire_process_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels,
    void *const *output_channels
);

typedef int32_t (*zv3_pipewire_capture_fn)(
    void *context,
    uint32_t frame_count,
    const void *const *input_channels
);

typedef int32_t (*zv3_pipewire_render_fn)(
    void *context,
    uint32_t frame_count,
    void *const *output_channels
);

typedef struct zv3_pipewire_session zv3_pipewire_session;
typedef struct zv3_pipewire_snapshot zv3_pipewire_snapshot;

typedef struct {
    uint64_t processed;
    uint64_t callback_failures;
    uint64_t capture_underflows;
    uint64_t capture_overflows;
    uint64_t recoveries;
    uint64_t device_failures;
} zv3_pipewire_statistics;

int32_t zv3_pipewire_available(void);
int32_t zv3_pipewire_snapshot_create(zv3_pipewire_snapshot **output);
size_t zv3_pipewire_snapshot_count(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction
);
int32_t zv3_pipewire_snapshot_identifier(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_pipewire_snapshot_name(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_pipewire_snapshot_channels(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index,
    uint32_t *output
);
void zv3_pipewire_snapshot_destroy(zv3_pipewire_snapshot *snapshot);
int32_t zv3_pipewire_start(
    const uint8_t *input_target,
    size_t input_target_length,
    const uint8_t *output_target,
    size_t output_target_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_pipewire_process_fn process,
    zv3_pipewire_session **output
);
int32_t zv3_pipewire_start_split(
    const uint8_t *input_target,
    size_t input_target_length,
    const uint8_t *output_target,
    size_t output_target_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_pipewire_capture_fn capture,
    zv3_pipewire_render_fn render,
    zv3_pipewire_session **output
);
void zv3_pipewire_get_statistics(
    const zv3_pipewire_session *session,
    zv3_pipewire_statistics *output
);
void zv3_pipewire_stop(
    zv3_pipewire_session *session,
    zv3_pipewire_statistics *final_statistics
);

#endif
