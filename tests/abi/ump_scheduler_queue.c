#include "ump_scheduler_queue.h"

#include <stdint.h>

static int expect_packet(
    zv3_ump_scheduler_queue *queue,
    uint64_t now,
    uint64_t timestamp,
    size_t word_count,
    uint32_t final_word
)
{
    zv3_ump_scheduled_packet packet;
    if (zv3_ump_scheduler_pop_due(queue, now, &packet) != 1 ||
        packet.timestamp_nanoseconds != timestamp ||
        packet.word_count != word_count ||
        packet.words[word_count - 1] != final_word) {
        return -1;
    }
    return 0;
}

static int randomized_order_test(void)
{
    zv3_ump_scheduler_queue queue = { 0 };
    uint32_t random_state = 0x9e3779b9U;
    uint64_t previous_timestamp = 0;
    size_t previous_submission = 0;
    size_t index;

    for (index = 0; index < ZV3_UMP_SCHEDULER_CAPACITY;
         ++index) {
        uint32_t word;
        uint64_t timestamp;
        random_state = random_state * 1664525U + 1013904223U;
        timestamp = 1U + ((random_state >> 16) & 15U);
        word = 0x20000000U | (uint32_t)index;
        if (zv3_ump_scheduler_insert(
            &queue,
            timestamp,
            &word,
            1
        ) != 0) {
            return -1;
        }
    }

    for (index = 0; index < ZV3_UMP_SCHEDULER_CAPACITY;
         ++index) {
        zv3_ump_scheduled_packet packet;
        size_t submission;
        if (zv3_ump_scheduler_pop_due(
            &queue,
            UINT64_MAX,
            &packet
        ) != 1) {
            return -1;
        }
        submission = packet.words[0] & 0xffU;
        if (packet.timestamp_nanoseconds < previous_timestamp ||
            (index != 0 &&
                packet.timestamp_nanoseconds ==
                    previous_timestamp &&
                submission <= previous_submission)) {
            return -1;
        }
        previous_timestamp = packet.timestamp_nanoseconds;
        previous_submission = submission;
    }
    return queue.count == 0 ? 0 : -1;
}

int main(void)
{
    zv3_ump_scheduler_queue queue = { 0 };
    const uint32_t one_word[] = { 0x20903c64U };
    const uint32_t four_words[] = {
        0x50000000U,
        0x01020304U,
        0x05060708U,
        0x090a0b0cU
    };
    size_t index;

    if (zv3_ump_scheduler_insert(
        &queue,
        300,
        four_words,
        4
    ) != 0 ||
        zv3_ump_scheduler_insert(
            &queue,
            100,
            one_word,
            1
        ) != 0 ||
        zv3_ump_scheduler_insert(
            &queue,
            300,
            one_word,
            1
        ) != 0) {
        return 1;
    }
    if (zv3_ump_scheduler_pop_due(
        &queue,
        99,
        &(zv3_ump_scheduled_packet){ 0 }
    ) != 0 ||
        expect_packet(&queue, 100, 100, 1, one_word[0]) != 0 ||
        expect_packet(&queue, 300, 300, 4, four_words[3]) != 0 ||
        expect_packet(&queue, 300, 300, 1, one_word[0]) != 0) {
        return 2;
    }

    for (index = 0; index < ZV3_UMP_SCHEDULER_CAPACITY;
         ++index) {
        if (zv3_ump_scheduler_insert(
            &queue,
            index + 1,
            one_word,
            1
        ) != 0) {
            return 3;
        }
    }
    if (zv3_ump_scheduler_insert(
        &queue,
        1,
        one_word,
        1
    ) == 0 ||
        zv3_ump_scheduler_clear(&queue) !=
            ZV3_UMP_SCHEDULER_CAPACITY ||
        queue.count != 0 ||
        zv3_ump_scheduler_insert(&queue, 0, one_word, 1) == 0 ||
        zv3_ump_scheduler_insert(&queue, 1, one_word, 0) == 0 ||
        zv3_ump_scheduler_insert(&queue, 1, four_words, 5) == 0 ||
        zv3_ump_scheduler_insert(NULL, 1, one_word, 1) == 0 ||
        zv3_ump_scheduler_insert(&queue, 1, NULL, 1) == 0 ||
        zv3_ump_scheduler_pop_due(
            NULL,
            1,
            &(zv3_ump_scheduled_packet){ 0 }
        ) != 0 ||
        zv3_ump_scheduler_pop_due(&queue, 1, NULL) != 0 ||
        zv3_ump_scheduler_clear(NULL) != 0) {
        return 4;
    }
    if (randomized_order_test() != 0) {
        return 5;
    }
    return 0;
}
