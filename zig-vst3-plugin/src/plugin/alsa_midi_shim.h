#ifndef ZIG_VST3_ALSA_MIDI_SHIM_H
#define ZIG_VST3_ALSA_MIDI_SHIM_H

#include <stddef.h>
#include <stdint.h>

enum {
    ZV3_ALSA_MIDI_INPUT = 0,
    ZV3_ALSA_MIDI_OUTPUT = 1
};

typedef void (*zv3_alsa_midi_receive_fn)(
    void *context,
    uint64_t timestamp_nanoseconds,
    const uint8_t *bytes,
    size_t length
);

typedef struct zv3_alsa_midi_input zv3_alsa_midi_input;
typedef struct zv3_alsa_midi_output zv3_alsa_midi_output;

typedef struct {
    uint64_t read_failures;
} zv3_alsa_midi_input_statistics;

typedef struct {
    uint64_t queued;
    uint64_t delivered;
    uint64_t late;
    uint64_t rejected;
    uint64_t canceled;
    uint64_t write_failures;
} zv3_alsa_midi_output_statistics;

int32_t zv3_alsa_midi_available(void);
uint64_t zv3_alsa_midi_now_nanoseconds(void);
int32_t zv3_alsa_midi_device_count(
    uint32_t direction,
    size_t *output
);
int32_t zv3_alsa_midi_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_midi_default_device_id(
    uint32_t direction,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_midi_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
);
int32_t zv3_alsa_midi_start_input(
    const uint8_t *identifier,
    size_t identifier_length,
    void *context,
    zv3_alsa_midi_receive_fn receive,
    zv3_alsa_midi_input **output
);
void zv3_alsa_midi_stop_input(
    zv3_alsa_midi_input *input,
    zv3_alsa_midi_input_statistics *final_statistics
);
void zv3_alsa_midi_get_input_statistics(
    const zv3_alsa_midi_input *input,
    zv3_alsa_midi_input_statistics *output
);
int32_t zv3_alsa_midi_open_output(
    const uint8_t *identifier,
    size_t identifier_length,
    zv3_alsa_midi_output **output
);
int32_t zv3_alsa_midi_send(
    zv3_alsa_midi_output *output,
    uint64_t timestamp_nanoseconds,
    const uint8_t *bytes,
    size_t length
);
void zv3_alsa_midi_get_output_statistics(
    const zv3_alsa_midi_output *output,
    zv3_alsa_midi_output_statistics *statistics
);
void zv3_alsa_midi_close_output(
    zv3_alsa_midi_output *output,
    zv3_alsa_midi_output_statistics *final_statistics
);

#endif
