#ifndef ZIG_VST3_UMP_SCHEDULER_QUEUE_H
#define ZIG_VST3_UMP_SCHEDULER_QUEUE_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum {
    ZV3_UMP_SCHEDULER_CAPACITY = 256
};

typedef struct {
    uint64_t timestamp_nanoseconds;
    uint32_t words[4];
    size_t word_count;
} zv3_ump_scheduled_packet;

typedef struct {
    size_t count;
    zv3_ump_scheduled_packet
        packets[ZV3_UMP_SCHEDULER_CAPACITY];
} zv3_ump_scheduler_queue;

static int zv3_ump_scheduler_insert(
    zv3_ump_scheduler_queue *queue,
    uint64_t timestamp_nanoseconds,
    const uint32_t *words,
    size_t word_count
)
{
    zv3_ump_scheduled_packet packet;
    size_t index;
    if (queue == NULL || words == NULL ||
        timestamp_nanoseconds == 0 ||
        word_count == 0 || word_count > 4 ||
        queue->count == ZV3_UMP_SCHEDULER_CAPACITY) {
        return -1;
    }
    packet.timestamp_nanoseconds = timestamp_nanoseconds;
    packet.word_count = word_count;
    memcpy(packet.words, words, word_count * sizeof(words[0]));
    index = queue->count;
    while (index != 0 &&
        queue->packets[index - 1].timestamp_nanoseconds >
            timestamp_nanoseconds) {
        queue->packets[index] = queue->packets[index - 1];
        index -= 1;
    }
    queue->packets[index] = packet;
    queue->count += 1;
    return 0;
}

static int zv3_ump_scheduler_pop_due(
    zv3_ump_scheduler_queue *queue,
    uint64_t now_nanoseconds,
    zv3_ump_scheduled_packet *packet
)
{
    if (queue == NULL || packet == NULL || queue->count == 0 ||
        queue->packets[0].timestamp_nanoseconds > now_nanoseconds) {
        return 0;
    }
    *packet = queue->packets[0];
    queue->count -= 1;
    if (queue->count != 0) {
        memmove(
            &queue->packets[0],
            &queue->packets[1],
            queue->count * sizeof(queue->packets[0])
        );
    }
    return 1;
}

static size_t zv3_ump_scheduler_clear(
    zv3_ump_scheduler_queue *queue
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
