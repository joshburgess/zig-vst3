#ifndef ZIG_VST3_CORE_MIDI_SHIM_H
#define ZIG_VST3_CORE_MIDI_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef void (*zv3_core_midi_notify_fn)(void *context);
typedef void (*zv3_core_midi_receive_fn)(
    void *context,
    uint64_t timestamp_ticks,
    const uint8_t *bytes,
    size_t length
);

typedef struct {
    void *context;
    zv3_core_midi_notify_fn callback;
} zv3_core_midi_notify_state;

typedef struct {
    void *context;
    zv3_core_midi_receive_fn callback;
} zv3_core_midi_receive_state;

typedef struct {
    uint32_t numerator;
    uint32_t denominator;
} zv3_core_midi_timebase;

int32_t zv3_core_midi_get_timebase(zv3_core_midi_timebase *output);
uint64_t zv3_core_midi_now_ticks(void);

int32_t zv3_core_midi_create_client(
    const uint8_t *name,
    size_t name_length,
    zv3_core_midi_notify_state *notify_state,
    uint32_t *output
);
int32_t zv3_core_midi_create_input_port(
    uint32_t client,
    const uint8_t *name,
    size_t name_length,
    zv3_core_midi_receive_state *receive_state,
    uint32_t *output
);
int32_t zv3_core_midi_create_output_port(
    uint32_t client,
    const uint8_t *name,
    size_t name_length,
    uint32_t *output
);
void zv3_core_midi_dispose_client(uint32_t client);
void zv3_core_midi_dispose_port(uint32_t port);

size_t zv3_core_midi_source_count(void);
size_t zv3_core_midi_destination_count(void);
int32_t zv3_core_midi_source_at(size_t index, uint32_t *output);
int32_t zv3_core_midi_destination_at(
    size_t index,
    uint32_t *output
);
int32_t zv3_core_midi_endpoint_unique_id(
    uint32_t endpoint,
    int32_t *output
);
int32_t zv3_core_midi_endpoint_name(
    uint32_t endpoint,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);

int32_t zv3_core_midi_connect_source(
    uint32_t port,
    uint32_t endpoint
);
int32_t zv3_core_midi_disconnect_source(
    uint32_t port,
    uint32_t endpoint
);
int32_t zv3_core_midi_send(
    uint32_t port,
    uint32_t endpoint,
    uint64_t timestamp_ticks,
    const uint8_t *bytes,
    size_t length
);

#endif
