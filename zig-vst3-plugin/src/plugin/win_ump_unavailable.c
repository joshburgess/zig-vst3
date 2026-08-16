#include "win_ump_shim.h"

#include <string.h>

int32_t zv3_win_ump_available(void)
{
    return 0;
}

int32_t zv3_win_ump_acquire(
    const uint8_t *client_name,
    size_t client_name_length
)
{
    (void)client_name;
    (void)client_name_length;
    return -1;
}

void zv3_win_ump_release(void)
{
}

int32_t zv3_win_ump_refresh_topology(void)
{
    return -1;
}

uint64_t zv3_win_ump_now_nanoseconds(void)
{
    return 0;
}

int32_t zv3_win_ump_device_count(
    uint32_t direction,
    size_t *output
)
{
    (void)direction;
    if (output != NULL) {
        *output = 0;
    }
    return -1;
}

static int32_t unavailable_text(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    (void)direction;
    (void)index;
    (void)output;
    (void)output_capacity;
    if (output_length != NULL) {
        *output_length = 0;
    }
    return -1;
}

int32_t zv3_win_ump_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return unavailable_text(
        direction,
        index,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_win_ump_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return unavailable_text(
        direction,
        index,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_win_ump_start_input(
    const uint8_t *endpoint_id,
    size_t endpoint_id_length,
    void *context,
    zv3_win_ump_receive_fn receive,
    zv3_win_ump_input **output
)
{
    (void)endpoint_id;
    (void)endpoint_id_length;
    (void)context;
    (void)receive;
    if (output != NULL) {
        *output = NULL;
    }
    return -1;
}

void zv3_win_ump_stop_input(
    zv3_win_ump_input *input,
    zv3_win_ump_input_statistics *final_statistics
)
{
    (void)input;
    if (final_statistics != NULL) {
        memset(final_statistics, 0, sizeof(*final_statistics));
    }
}

void zv3_win_ump_get_input_statistics(
    const zv3_win_ump_input *input,
    zv3_win_ump_input_statistics *output
)
{
    (void)input;
    if (output != NULL) {
        memset(output, 0, sizeof(*output));
    }
}

int32_t zv3_win_ump_open_output(
    const uint8_t *endpoint_id,
    size_t endpoint_id_length,
    zv3_win_ump_output **output
)
{
    (void)endpoint_id;
    (void)endpoint_id_length;
    if (output != NULL) {
        *output = NULL;
    }
    return -1;
}

int32_t zv3_win_ump_send(
    zv3_win_ump_output *output,
    uint64_t timestamp_nanoseconds,
    const uint32_t *words,
    size_t word_count
)
{
    (void)output;
    (void)timestamp_nanoseconds;
    (void)words;
    (void)word_count;
    return -1;
}

void zv3_win_ump_get_output_statistics(
    const zv3_win_ump_output *output,
    zv3_win_ump_output_statistics *statistics
)
{
    (void)output;
    if (statistics != NULL) {
        memset(statistics, 0, sizeof(*statistics));
    }
}

void zv3_win_ump_close_output(
    zv3_win_ump_output *output,
    zv3_win_ump_output_statistics *final_statistics
)
{
    (void)output;
    if (final_statistics != NULL) {
        memset(final_statistics, 0, sizeof(*final_statistics));
    }
}
