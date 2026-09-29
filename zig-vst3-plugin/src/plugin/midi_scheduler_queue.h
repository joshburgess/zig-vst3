#ifndef ZIG_VST3_MIDI_SCHEDULER_QUEUE_H
#define ZIG_VST3_MIDI_SCHEDULER_QUEUE_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum {
    ZV3_MIDI_SCHEDULER_CAPACITY = 256
};

typedef struct {
    uint64_t timestamp_nanoseconds;
    uint8_t bytes[3];
    size_t length;
} zv3_midi_scheduled_message;

typedef struct {
    size_t count;
    zv3_midi_scheduled_message
        messages[ZV3_MIDI_SCHEDULER_CAPACITY];
} zv3_midi_scheduler_queue;

static int zv3_midi_scheduler_insert(
    zv3_midi_scheduler_queue *queue,
    uint64_t timestamp_nanoseconds,
    const uint8_t *bytes,
    size_t length
)
{
    zv3_midi_scheduled_message message;
    size_t index;
    if (queue == NULL || bytes == NULL ||
        timestamp_nanoseconds == 0 ||
        length == 0 || length > sizeof(message.bytes) ||
        queue->count == ZV3_MIDI_SCHEDULER_CAPACITY) {
        return -1;
    }
    message.timestamp_nanoseconds = timestamp_nanoseconds;
    message.length = length;
    memcpy(message.bytes, bytes, length);
    index = queue->count;
    while (index != 0) {
        const zv3_midi_scheduled_message *previous =
            &queue->messages[index - 1];
        if (previous->timestamp_nanoseconds <=
            message.timestamp_nanoseconds) {
            break;
        }
        queue->messages[index] = *previous;
        index -= 1;
    }
    queue->messages[index] = message;
    queue->count += 1;
    return 0;
}

static int zv3_midi_scheduler_pop_due(
    zv3_midi_scheduler_queue *queue,
    uint64_t now_nanoseconds,
    zv3_midi_scheduled_message *message
)
{
    if (queue == NULL || message == NULL ||
        queue->count == 0 ||
        queue->messages[0].timestamp_nanoseconds >
            now_nanoseconds) {
        return 0;
    }
    *message = queue->messages[0];
    queue->count -= 1;
    if (queue->count != 0) {
        memmove(
            &queue->messages[0],
            &queue->messages[1],
            queue->count * sizeof(queue->messages[0])
        );
    }
    return 1;
}

static size_t zv3_midi_scheduler_clear(
    zv3_midi_scheduler_queue *queue
)
{
    size_t count;
    if (queue == NULL) {
        return 0;
    }
    count = queue->count;
    queue->count = 0;
    return count;
}

#endif
