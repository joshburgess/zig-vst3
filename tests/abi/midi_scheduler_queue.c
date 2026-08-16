#include "midi_scheduler_queue.h"

#include <stdint.h>
#include <string.h>

static int expect_message(
    zv3_midi_scheduler_queue *queue,
    uint64_t now,
    uint64_t timestamp,
    uint8_t note
)
{
    zv3_midi_scheduled_message message;
    if (zv3_midi_scheduler_pop_due(queue, now, &message) != 1 ||
        message.timestamp_nanoseconds != timestamp ||
        message.length != 3 ||
        message.bytes[1] != note) {
        return -1;
    }
    return 0;
}

static int randomized_order_test(void)
{
    zv3_midi_scheduler_queue queue = { 0 };
    uint32_t random_state = 0x9e3779b9U;
    uint64_t previous_timestamp = 0;
    size_t previous_submission = 0;
    size_t index;

    for (index = 0; index < ZV3_MIDI_SCHEDULER_CAPACITY;
         ++index) {
        uint8_t message[3];
        uint64_t timestamp;
        random_state = random_state * 1664525U + 1013904223U;
        timestamp = 1U + ((random_state >> 16) & 15U);
        message[0] = 0x90;
        message[1] = (uint8_t)(index & 0x7fU);
        message[2] = (uint8_t)(index >> 7);
        if (zv3_midi_scheduler_insert(
            &queue,
            timestamp,
            message,
            sizeof(message)
        ) != 0) {
            return -1;
        }
    }

    for (index = 0; index < ZV3_MIDI_SCHEDULER_CAPACITY;
         ++index) {
        zv3_midi_scheduled_message message;
        size_t submission;
        if (zv3_midi_scheduler_pop_due(
            &queue,
            UINT64_MAX,
            &message
        ) != 1) {
            return -1;
        }
        submission =
            (size_t)message.bytes[1] |
            ((size_t)message.bytes[2] << 7);
        if (message.timestamp_nanoseconds < previous_timestamp ||
            (index != 0 &&
                message.timestamp_nanoseconds ==
                    previous_timestamp &&
                submission <= previous_submission)) {
            return -1;
        }
        previous_timestamp = message.timestamp_nanoseconds;
        previous_submission = submission;
    }
    return queue.count == 0 ? 0 : -1;
}

int main(void)
{
    zv3_midi_scheduler_queue queue = { 0 };
    const uint8_t late[3] = { 0x90, 60, 100 };
    const uint8_t equal_a[3] = { 0x90, 61, 100 };
    const uint8_t equal_b[3] = { 0x90, 62, 100 };
    const uint8_t future[3] = { 0x80, 60, 0 };
    size_t index;

    if (zv3_midi_scheduler_insert(&queue, 300, future, 3) != 0 ||
        zv3_midi_scheduler_insert(&queue, 100, late, 3) != 0 ||
        zv3_midi_scheduler_insert(&queue, 200, equal_a, 3) != 0 ||
        zv3_midi_scheduler_insert(&queue, 200, equal_b, 3) != 0) {
        return 1;
    }
    if (zv3_midi_scheduler_pop_due(&queue, 99, &(zv3_midi_scheduled_message){ 0 }) != 0 ||
        expect_message(&queue, 100, 100, 60) != 0 ||
        expect_message(&queue, 200, 200, 61) != 0 ||
        expect_message(&queue, 200, 200, 62) != 0 ||
        expect_message(&queue, 300, 300, 60) != 0) {
        return 2;
    }
    for (index = 0; index < ZV3_MIDI_SCHEDULER_CAPACITY; ++index) {
        uint8_t message[3] = { 0x90, (uint8_t)(index & 0x7f), 1 };
        if (zv3_midi_scheduler_insert(
            &queue,
            1000 + index,
            message,
            sizeof(message)
        ) != 0) {
            return 3;
        }
    }
    if (zv3_midi_scheduler_insert(&queue, 999, late, 3) == 0 ||
        zv3_midi_scheduler_clear(&queue) !=
            ZV3_MIDI_SCHEDULER_CAPACITY ||
        queue.count != 0 ||
        zv3_midi_scheduler_insert(&queue, 0, late, 3) == 0 ||
        zv3_midi_scheduler_insert(&queue, 1, late, 0) == 0 ||
        zv3_midi_scheduler_insert(&queue, 1, late, 4) == 0 ||
        zv3_midi_scheduler_insert(NULL, 1, late, 3) == 0 ||
        zv3_midi_scheduler_insert(&queue, 1, NULL, 3) == 0 ||
        zv3_midi_scheduler_pop_due(NULL, 1, &(zv3_midi_scheduled_message){ 0 }) != 0 ||
        zv3_midi_scheduler_pop_due(&queue, 1, NULL) != 0 ||
        zv3_midi_scheduler_clear(NULL) != 0) {
        return 4;
    }
    if (randomized_order_test() != 0) {
        return 5;
    }
    return 0;
}
