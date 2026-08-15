#define _POSIX_C_SOURCE 200809L

#include "alsa_ump_shim.h"
#include "ump_scheduler_queue.h"

#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>

typedef struct _snd_ctl snd_ctl_t;
typedef struct _snd_ctl_card_info snd_ctl_card_info_t;
typedef struct _snd_ump snd_ump_t;
typedef struct snd_ump_endpoint_info snd_ump_endpoint_info_t;
typedef struct snd_ump_block_info snd_ump_block_info_t;

enum {
    ZV3_SND_UMP_DIR_INPUT = 0x01,
    ZV3_SND_UMP_DIR_OUTPUT = 0x02,
    ZV3_SND_UMP_DIR_BIDIRECTION = 0x03,
    ZV3_SND_RAWMIDI_NONBLOCK = 0x0002
};

typedef struct {
    void *library;
    int (*card_next)(int *);
    int (*ctl_open)(snd_ctl_t **, const char *, int);
    int (*ctl_close)(snd_ctl_t *);
    int (*ctl_card_info)(snd_ctl_t *, snd_ctl_card_info_t *);
    int (*ctl_card_info_malloc)(snd_ctl_card_info_t **);
    void (*ctl_card_info_free)(snd_ctl_card_info_t *);
    const char *(*ctl_card_info_get_id)(const snd_ctl_card_info_t *);
    const char *(*ctl_card_info_get_name)(const snd_ctl_card_info_t *);
    int (*ctl_ump_next_device)(snd_ctl_t *, int *);
    int (*ctl_ump_endpoint_info)(
        snd_ctl_t *,
        snd_ump_endpoint_info_t *
    );
    int (*ctl_ump_block_info)(snd_ctl_t *, snd_ump_block_info_t *);
    int (*ump_endpoint_info_malloc)(snd_ump_endpoint_info_t **);
    void (*ump_endpoint_info_free)(snd_ump_endpoint_info_t *);
    void (*ump_endpoint_info_clear)(snd_ump_endpoint_info_t *);
    void (*ump_endpoint_info_set_device)(
        snd_ump_endpoint_info_t *,
        unsigned int
    );
    unsigned int (*ump_endpoint_info_get_num_blocks)(
        const snd_ump_endpoint_info_t *
    );
    const char *(*ump_endpoint_info_get_name)(
        const snd_ump_endpoint_info_t *
    );
    const char *(*ump_endpoint_info_get_product_id)(
        const snd_ump_endpoint_info_t *
    );
    int (*ump_block_info_malloc)(snd_ump_block_info_t **);
    void (*ump_block_info_free)(snd_ump_block_info_t *);
    void (*ump_block_info_clear)(snd_ump_block_info_t *);
    void (*ump_block_info_set_device)(
        snd_ump_block_info_t *,
        unsigned int
    );
    void (*ump_block_info_set_block_id)(
        snd_ump_block_info_t *,
        unsigned int
    );
    unsigned int (*ump_block_info_get_active)(
        const snd_ump_block_info_t *
    );
    unsigned int (*ump_block_info_get_direction)(
        const snd_ump_block_info_t *
    );
    int (*ump_open)(snd_ump_t **, snd_ump_t **, const char *, int);
    int (*ump_close)(snd_ump_t *);
    int (*ump_poll_descriptors_count)(snd_ump_t *);
    int (*ump_poll_descriptors)(
        snd_ump_t *,
        struct pollfd *,
        unsigned int
    );
    int (*ump_poll_descriptors_revents)(
        snd_ump_t *,
        struct pollfd *,
        unsigned int,
        unsigned short *
    );
    ssize_t (*ump_read)(snd_ump_t *, void *, size_t);
    ssize_t (*ump_write)(snd_ump_t *, const void *, size_t);
} alsa_ump_api;

#define LOAD_SYMBOL(api, member, name)                                      \
    do {                                                                    \
        *(void **)(&(api)->member) = dlsym((api)->library, (name));          \
        if ((api)->member == NULL) {                                        \
            close_api((api));                                               \
            return -1;                                                      \
        }                                                                   \
    } while (0)

static void close_api(alsa_ump_api *api)
{
    if (api->library != NULL) {
        dlclose(api->library);
    }
    memset(api, 0, sizeof(*api));
}

static int open_api(alsa_ump_api *api)
{
    memset(api, 0, sizeof(*api));
    api->library = dlopen("libasound.so.2", RTLD_NOW | RTLD_LOCAL);
    if (api->library == NULL) {
        return -1;
    }
    LOAD_SYMBOL(api, card_next, "snd_card_next");
    LOAD_SYMBOL(api, ctl_open, "snd_ctl_open");
    LOAD_SYMBOL(api, ctl_close, "snd_ctl_close");
    LOAD_SYMBOL(api, ctl_card_info, "snd_ctl_card_info");
    LOAD_SYMBOL(api, ctl_card_info_malloc, "snd_ctl_card_info_malloc");
    LOAD_SYMBOL(api, ctl_card_info_free, "snd_ctl_card_info_free");
    LOAD_SYMBOL(api, ctl_card_info_get_id, "snd_ctl_card_info_get_id");
    LOAD_SYMBOL(api, ctl_card_info_get_name, "snd_ctl_card_info_get_name");
    LOAD_SYMBOL(api, ctl_ump_next_device, "snd_ctl_ump_next_device");
    LOAD_SYMBOL(api, ctl_ump_endpoint_info, "snd_ctl_ump_endpoint_info");
    LOAD_SYMBOL(api, ctl_ump_block_info, "snd_ctl_ump_block_info");
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_malloc,
        "snd_ump_endpoint_info_malloc"
    );
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_free,
        "snd_ump_endpoint_info_free"
    );
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_clear,
        "snd_ump_endpoint_info_clear"
    );
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_set_device,
        "snd_ump_endpoint_info_set_device"
    );
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_get_num_blocks,
        "snd_ump_endpoint_info_get_num_blocks"
    );
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_get_name,
        "snd_ump_endpoint_info_get_name"
    );
    LOAD_SYMBOL(
        api,
        ump_endpoint_info_get_product_id,
        "snd_ump_endpoint_info_get_product_id"
    );
    LOAD_SYMBOL(
        api,
        ump_block_info_malloc,
        "snd_ump_block_info_malloc"
    );
    LOAD_SYMBOL(api, ump_block_info_free, "snd_ump_block_info_free");
    LOAD_SYMBOL(api, ump_block_info_clear, "snd_ump_block_info_clear");
    LOAD_SYMBOL(
        api,
        ump_block_info_set_device,
        "snd_ump_block_info_set_device"
    );
    LOAD_SYMBOL(
        api,
        ump_block_info_set_block_id,
        "snd_ump_block_info_set_block_id"
    );
    LOAD_SYMBOL(
        api,
        ump_block_info_get_active,
        "snd_ump_block_info_get_active"
    );
    LOAD_SYMBOL(
        api,
        ump_block_info_get_direction,
        "snd_ump_block_info_get_direction"
    );
    LOAD_SYMBOL(api, ump_open, "snd_ump_open");
    LOAD_SYMBOL(api, ump_close, "snd_ump_close");
    LOAD_SYMBOL(
        api,
        ump_poll_descriptors_count,
        "snd_ump_poll_descriptors_count"
    );
    LOAD_SYMBOL(
        api,
        ump_poll_descriptors,
        "snd_ump_poll_descriptors"
    );
    LOAD_SYMBOL(
        api,
        ump_poll_descriptors_revents,
        "snd_ump_poll_descriptors_revents"
    );
    LOAD_SYMBOL(api, ump_read, "snd_ump_read");
    LOAD_SYMBOL(api, ump_write, "snd_ump_write");
    return 0;
}

static int copy_bytes(
    const char *source,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    size_t length;
    if (source == NULL || output == NULL || output_length == NULL) {
        return -1;
    }
    length = strlen(source);
    if (length == 0 || length > output_capacity) {
        return -1;
    }
    memcpy(output, source, length);
    *output_length = length;
    return 0;
}

static int format_identity(
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length,
    const char *card_id,
    int device,
    const char *product_id
)
{
    int length;
    if (output == NULL || output_length == NULL ||
        card_id == NULL || card_id[0] == '\0') {
        return -1;
    }
    length = snprintf(
        (char *)output,
        output_capacity,
        "%s:%d:%s",
        card_id,
        device,
        product_id != NULL ? product_id : ""
    );
    if (length <= 0 || (size_t)length >= output_capacity) {
        return -1;
    }
    *output_length = (size_t)length;
    return 0;
}

static int format_open_name(
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length,
    const char *card_id,
    int device
)
{
    int length;
    if (output == NULL || output_length == NULL ||
        card_id == NULL || card_id[0] == '\0') {
        return -1;
    }
    length = snprintf(
        (char *)output,
        output_capacity,
        "hw:%s,%d",
        card_id,
        device
    );
    if (length <= 0 || (size_t)length >= output_capacity) {
        return -1;
    }
    *output_length = (size_t)length;
    return 0;
}

static char *duplicate_name(
    const uint8_t *source,
    size_t source_length
)
{
    char *copy;
    if (source == NULL || source_length == 0 ||
        source_length == SIZE_MAX ||
        memchr(source, 0, source_length) != NULL) {
        return NULL;
    }
    copy = malloc(source_length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, source, source_length);
    copy[source_length] = '\0';
    return copy;
}

static int block_matches_direction(
    unsigned int block_direction,
    uint32_t requested_direction
)
{
    unsigned int native_direction = requested_direction ==
        ZV3_ALSA_UMP_INPUT
        ? ZV3_SND_UMP_DIR_INPUT
        : ZV3_SND_UMP_DIR_OUTPUT;
    return block_direction == native_direction ||
        block_direction == ZV3_SND_UMP_DIR_BIDIRECTION;
}

static int endpoint_matches_direction(
    alsa_ump_api *api,
    snd_ctl_t *control,
    int device,
    const snd_ump_endpoint_info_t *endpoint,
    uint32_t direction
)
{
    snd_ump_block_info_t *block = NULL;
    unsigned int block_count;
    unsigned int block_index;
    int matches = 0;
    if (api->ump_block_info_malloc(&block) < 0 || block == NULL) {
        return -1;
    }
    block_count = api->ump_endpoint_info_get_num_blocks(endpoint);
    for (block_index = 0; block_index < block_count; ++block_index) {
        api->ump_block_info_clear(block);
        api->ump_block_info_set_device(block, (unsigned int)device);
        api->ump_block_info_set_block_id(block, block_index);
        if (api->ctl_ump_block_info(control, block) < 0) {
            matches = -1;
            break;
        }
        if (api->ump_block_info_get_active(block) == 0) {
            continue;
        }
        if (block_matches_direction(
            api->ump_block_info_get_direction(block),
            direction
        )) {
            matches = 1;
            break;
        }
    }
    api->ump_block_info_free(block);
    return matches;
}

typedef enum {
    ENDPOINT_COUNT,
    ENDPOINT_IDENTITY,
    ENDPOINT_OPEN_NAME,
    ENDPOINT_DISPLAY_NAME
} endpoint_query;

static int query_endpoint(
    alsa_ump_api *api,
    uint32_t direction,
    size_t requested_index,
    endpoint_query query,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length,
    size_t *matched_count
)
{
    int card = -1;
    int card_result;
    size_t index = 0;
    int result = -1;
    if (direction > ZV3_ALSA_UMP_OUTPUT) {
        return -1;
    }
    while (1) {
        char control_name[32];
        snd_ctl_t *control = NULL;
        snd_ctl_card_info_t *card_info = NULL;
        snd_ump_endpoint_info_t *endpoint = NULL;
        int device = -1;
        int device_result;
        int failed = 0;
        const char *card_id;
        const char *card_name;
        card_result = api->card_next(&card);
        if (card_result < 0) {
            return -1;
        }
        if (card < 0) {
            break;
        }
        if (snprintf(
            control_name,
            sizeof(control_name),
            "hw:%d",
            card
        ) <= 0 || api->ctl_open(&control, control_name, 0) < 0) {
            continue;
        }
        if (api->ctl_card_info_malloc(&card_info) < 0 ||
            card_info == NULL ||
            api->ctl_card_info(control, card_info) < 0 ||
            api->ump_endpoint_info_malloc(&endpoint) < 0 ||
            endpoint == NULL) {
            if (endpoint != NULL) {
                api->ump_endpoint_info_free(endpoint);
            }
            if (card_info != NULL) {
                api->ctl_card_info_free(card_info);
            }
            api->ctl_close(control);
            return -1;
        }
        card_id = api->ctl_card_info_get_id(card_info);
        card_name = api->ctl_card_info_get_name(card_info);
        if (card_id == NULL || card_id[0] == '\0') {
            api->ump_endpoint_info_free(endpoint);
            api->ctl_card_info_free(card_info);
            api->ctl_close(control);
            return -1;
        }
        while (1) {
            const char *endpoint_name;
            const char *product_id;
            int direction_match;
            device_result =
                api->ctl_ump_next_device(control, &device);
            if (device_result < 0) {
                failed = 1;
                break;
            }
            if (device < 0) {
                break;
            }
            api->ump_endpoint_info_clear(endpoint);
            api->ump_endpoint_info_set_device(
                endpoint,
                (unsigned int)device
            );
            if (api->ctl_ump_endpoint_info(control, endpoint) < 0) {
                failed = 1;
                break;
            }
            direction_match = endpoint_matches_direction(
                api,
                control,
                device,
                endpoint,
                direction
            );
            if (direction_match < 0) {
                failed = 1;
                break;
            }
            if (!direction_match) {
                continue;
            }
            if (query == ENDPOINT_COUNT) {
                index += 1;
                continue;
            }
            if (index++ != requested_index) {
                continue;
            }
            endpoint_name =
                api->ump_endpoint_info_get_name(endpoint);
            product_id =
                api->ump_endpoint_info_get_product_id(endpoint);
            if (query == ENDPOINT_IDENTITY) {
                result = format_identity(
                    output,
                    output_capacity,
                    output_length,
                    card_id,
                    device,
                    product_id
                );
            } else if (query == ENDPOINT_OPEN_NAME) {
                result = format_open_name(
                    output,
                    output_capacity,
                    output_length,
                    card_id,
                    device
                );
            } else {
                const char *name =
                    endpoint_name != NULL && endpoint_name[0] != '\0'
                    ? endpoint_name
                    : card_name;
                result = copy_bytes(
                    name,
                    output,
                    output_capacity,
                    output_length
                );
            }
            break;
        }
        api->ump_endpoint_info_free(endpoint);
        api->ctl_card_info_free(card_info);
        api->ctl_close(control);
        if (failed) {
            return -1;
        }
        if (result == 0) {
            break;
        }
    }
    if (query == ENDPOINT_COUNT && matched_count != NULL) {
        *matched_count = index;
        return 0;
    }
    return result;
}

int32_t zv3_alsa_ump_available(void)
{
    alsa_ump_api api;
    if (open_api(&api) != 0) {
        return 0;
    }
    close_api(&api);
    return 1;
}

uint64_t zv3_alsa_ump_now_nanoseconds(void)
{
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return 0;
    }
    return (uint64_t)value.tv_sec * 1000000000u +
        (uint64_t)value.tv_nsec;
}

int32_t zv3_alsa_ump_device_count(
    uint32_t direction,
    size_t *output
)
{
    alsa_ump_api api;
    int result;
    if (output == NULL || open_api(&api) != 0) {
        return -1;
    }
    result = query_endpoint(
        &api,
        direction,
        0,
        ENDPOINT_COUNT,
        NULL,
        0,
        NULL,
        output
    );
    close_api(&api);
    return result;
}

static int32_t device_text(
    uint32_t direction,
    size_t index,
    endpoint_query query,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_ump_api api;
    int result;
    if (open_api(&api) != 0) {
        return -1;
    }
    result = query_endpoint(
        &api,
        direction,
        index,
        query,
        output,
        output_capacity,
        output_length,
        NULL
    );
    close_api(&api);
    return result;
}

int32_t zv3_alsa_ump_device_identity(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return device_text(
        direction,
        index,
        ENDPOINT_IDENTITY,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_alsa_ump_device_open_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return device_text(
        direction,
        index,
        ENDPOINT_OPEN_NAME,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_alsa_ump_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return device_text(
        direction,
        index,
        ENDPOINT_DISPLAY_NAME,
        output,
        output_capacity,
        output_length
    );
}

struct zv3_alsa_ump_input {
    alsa_ump_api api;
    snd_ump_t *handle;
    pthread_t thread;
    atomic_int stop_requested;
    atomic_uint_fast64_t read_failures;
    void *context;
    zv3_alsa_ump_receive_fn receive;
};

static void *input_thread(void *context)
{
    zv3_alsa_ump_input *input = context;
    int descriptor_count =
        input->api.ump_poll_descriptors_count(input->handle);
    struct pollfd *descriptors;
    uint32_t words[64];
    if (descriptor_count <= 0) {
        atomic_fetch_add_explicit(
            &input->read_failures,
            1,
            memory_order_relaxed
        );
        return NULL;
    }
    descriptors = calloc(
        (size_t)descriptor_count,
        sizeof(*descriptors)
    );
    if (descriptors == NULL ||
        input->api.ump_poll_descriptors(
            input->handle,
            descriptors,
            (unsigned int)descriptor_count
        ) < 0) {
        free(descriptors);
        atomic_fetch_add_explicit(
            &input->read_failures,
            1,
            memory_order_relaxed
        );
        return NULL;
    }
    while (!atomic_load_explicit(
        &input->stop_requested,
        memory_order_acquire
    )) {
        unsigned short revents = 0;
        int poll_result = poll(descriptors, (nfds_t)descriptor_count, 20);
        if (poll_result < 0) {
            if (errno == EINTR) {
                continue;
            }
            atomic_fetch_add_explicit(
                &input->read_failures,
                1,
                memory_order_relaxed
            );
            break;
        }
        if (poll_result == 0) {
            continue;
        }
        if (input->api.ump_poll_descriptors_revents(
            input->handle,
            descriptors,
            (unsigned int)descriptor_count,
            &revents
        ) < 0 || (revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
            atomic_fetch_add_explicit(
                &input->read_failures,
                1,
                memory_order_relaxed
            );
            break;
        }
        if ((revents & POLLIN) == 0) {
            continue;
        }
        while (!atomic_load_explicit(
            &input->stop_requested,
            memory_order_acquire
        )) {
            ssize_t count = input->api.ump_read(
                input->handle,
                words,
                sizeof(words)
            );
            if (count > 0 && (size_t)count % sizeof(words[0]) == 0) {
                uint64_t timestamp = zv3_alsa_ump_now_nanoseconds();
                if (timestamp == 0) {
                    atomic_fetch_add_explicit(
                        &input->read_failures,
                        1,
                        memory_order_relaxed
                    );
                    free(descriptors);
                    return NULL;
                }
                input->receive(
                    input->context,
                    timestamp,
                    words,
                    (size_t)count / sizeof(words[0])
                );
                continue;
            }
            if (count == -EAGAIN || count == 0) {
                break;
            }
            if (!atomic_load_explicit(
                &input->stop_requested,
                memory_order_acquire
            )) {
                atomic_fetch_add_explicit(
                    &input->read_failures,
                    1,
                    memory_order_relaxed
                );
            }
            free(descriptors);
            return NULL;
        }
    }
    free(descriptors);
    return NULL;
}

int32_t zv3_alsa_ump_start_input(
    const uint8_t *open_name,
    size_t open_name_length,
    void *context,
    zv3_alsa_ump_receive_fn receive,
    zv3_alsa_ump_input **output
)
{
    zv3_alsa_ump_input *input;
    char *name = duplicate_name(open_name, open_name_length);
    if (output == NULL || receive == NULL || name == NULL) {
        free(name);
        return -1;
    }
    *output = NULL;
    input = calloc(1, sizeof(*input));
    if (input == NULL || open_api(&input->api) != 0 ||
        input->api.ump_open(
            &input->handle,
            NULL,
            name,
            ZV3_SND_RAWMIDI_NONBLOCK
        ) < 0) {
        if (input != NULL) {
            close_api(&input->api);
        }
        free(input);
        free(name);
        return -1;
    }
    free(name);
    input->context = context;
    input->receive = receive;
    atomic_init(&input->stop_requested, 0);
    atomic_init(&input->read_failures, 0);
    if (pthread_create(
        &input->thread,
        NULL,
        input_thread,
        input
    ) != 0) {
        input->api.ump_close(input->handle);
        close_api(&input->api);
        free(input);
        return -1;
    }
    *output = input;
    return 0;
}

void zv3_alsa_ump_get_input_statistics(
    const zv3_alsa_ump_input *input,
    zv3_alsa_ump_input_statistics *output
)
{
    if (input == NULL || output == NULL) {
        return;
    }
    output->read_failures = atomic_load_explicit(
        &input->read_failures,
        memory_order_relaxed
    );
}

void zv3_alsa_ump_stop_input(
    zv3_alsa_ump_input *input,
    zv3_alsa_ump_input_statistics *final_statistics
)
{
    if (input == NULL) {
        return;
    }
    atomic_store_explicit(
        &input->stop_requested,
        1,
        memory_order_release
    );
    pthread_join(input->thread, NULL);
    zv3_alsa_ump_get_input_statistics(input, final_statistics);
    input->api.ump_close(input->handle);
    close_api(&input->api);
    free(input);
}

struct zv3_alsa_ump_output {
    alsa_ump_api api;
    snd_ump_t *handle;
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    atomic_int stop_requested;
    zv3_ump_scheduler_queue queue;
    atomic_uint_fast64_t queued;
    atomic_uint_fast64_t delivered;
    atomic_uint_fast64_t late;
    atomic_uint_fast64_t rejected;
    atomic_uint_fast64_t canceled;
    atomic_uint_fast64_t write_failures;
};

static int write_packet(
    zv3_alsa_ump_output *output,
    const zv3_ump_scheduled_packet *packet
)
{
    size_t written = 0;
    size_t length = packet->word_count * sizeof(packet->words[0]);
    const uint8_t *bytes = (const uint8_t *)packet->words;
    while (written < length) {
        ssize_t count = output->api.ump_write(
            output->handle,
            bytes + written,
            length - written
        );
        if (count > 0 && (size_t)count % sizeof(uint32_t) == 0) {
            written += (size_t)count;
            continue;
        }
        if (count == -EAGAIN) {
            struct timespec pause = { 0, 1000000 };
            nanosleep(&pause, NULL);
            if (atomic_load_explicit(
                &output->stop_requested,
                memory_order_acquire
            )) {
                return -1;
            }
            continue;
        }
        return -1;
    }
    return 0;
}

static void *output_thread(void *context)
{
    zv3_alsa_ump_output *output = context;
    pthread_mutex_lock(&output->mutex);
    while (!atomic_load_explicit(
        &output->stop_requested,
        memory_order_acquire
    )) {
        zv3_ump_scheduled_packet packet;
        uint64_t now;
        if (output->queue.count == 0) {
            pthread_cond_wait(&output->condition, &output->mutex);
            continue;
        }
        now = zv3_alsa_ump_now_nanoseconds();
        if (now == 0) {
            atomic_fetch_add_explicit(
                &output->write_failures,
                1,
                memory_order_relaxed
            );
            atomic_store_explicit(
                &output->stop_requested,
                1,
                memory_order_release
            );
            break;
        }
        if (output->queue.packets[0].timestamp_nanoseconds > now) {
            struct timespec deadline;
            deadline.tv_sec = (time_t)(
                output->queue.packets[0].timestamp_nanoseconds /
                    1000000000u
            );
            deadline.tv_nsec = (long)(
                output->queue.packets[0].timestamp_nanoseconds %
                    1000000000u
            );
            pthread_cond_timedwait(
                &output->condition,
                &output->mutex,
                &deadline
            );
            continue;
        }
        if (!zv3_ump_scheduler_pop_due(
            &output->queue,
            now,
            &packet
        )) {
            continue;
        }
        pthread_mutex_unlock(&output->mutex);
        if (packet.timestamp_nanoseconds < now) {
            atomic_fetch_add_explicit(
                &output->late,
                1,
                memory_order_relaxed
            );
        }
        if (write_packet(output, &packet) == 0) {
            atomic_fetch_add_explicit(
                &output->delivered,
                1,
                memory_order_relaxed
            );
        } else if (!atomic_load_explicit(
            &output->stop_requested,
            memory_order_acquire
        )) {
            atomic_fetch_add_explicit(
                &output->write_failures,
                1,
                memory_order_relaxed
            );
        }
        pthread_mutex_lock(&output->mutex);
    }
    atomic_fetch_add_explicit(
        &output->canceled,
        zv3_ump_scheduler_clear(&output->queue),
        memory_order_relaxed
    );
    pthread_mutex_unlock(&output->mutex);
    return NULL;
}

int32_t zv3_alsa_ump_open_output(
    const uint8_t *open_name,
    size_t open_name_length,
    zv3_alsa_ump_output **output
)
{
    zv3_alsa_ump_output *ump_output;
    char *name = duplicate_name(open_name, open_name_length);
    pthread_condattr_t condition_attributes;
    int mutex_ready = 0;
    int condition_attributes_ready = 0;
    int condition_ready = 0;
    if (output == NULL || name == NULL) {
        free(name);
        return -1;
    }
    *output = NULL;
    ump_output = calloc(1, sizeof(*ump_output));
    if (ump_output == NULL) {
        goto fail;
    }
    atomic_init(&ump_output->stop_requested, 0);
    atomic_init(&ump_output->queued, 0);
    atomic_init(&ump_output->delivered, 0);
    atomic_init(&ump_output->late, 0);
    atomic_init(&ump_output->rejected, 0);
    atomic_init(&ump_output->canceled, 0);
    atomic_init(&ump_output->write_failures, 0);
    if (open_api(&ump_output->api) != 0) {
        goto fail;
    }
    if (ump_output->api.ump_open(
        NULL,
        &ump_output->handle,
        name,
        ZV3_SND_RAWMIDI_NONBLOCK
    ) < 0) {
        goto fail;
    }
    if (pthread_mutex_init(&ump_output->mutex, NULL) != 0) {
        goto fail;
    }
    mutex_ready = 1;
    if (pthread_condattr_init(&condition_attributes) != 0) {
        goto fail;
    }
    condition_attributes_ready = 1;
    if (pthread_condattr_setclock(
        &condition_attributes,
        CLOCK_MONOTONIC
    ) != 0) {
        goto fail;
    }
    if (pthread_cond_init(
        &ump_output->condition,
        &condition_attributes
    ) != 0) {
        goto fail;
    }
    condition_ready = 1;
    pthread_condattr_destroy(&condition_attributes);
    condition_attributes_ready = 0;
    if (pthread_create(
        &ump_output->thread,
        NULL,
        output_thread,
        ump_output
    ) != 0) {
        goto fail;
    }
    free(name);
    *output = ump_output;
    return 0;

fail:
    if (condition_attributes_ready) {
        pthread_condattr_destroy(&condition_attributes);
    }
    if (condition_ready) {
        pthread_cond_destroy(&ump_output->condition);
    }
    if (mutex_ready) {
        pthread_mutex_destroy(&ump_output->mutex);
    }
    if (ump_output != NULL && ump_output->handle != NULL) {
        ump_output->api.ump_close(ump_output->handle);
    }
    if (ump_output != NULL) {
        close_api(&ump_output->api);
    }
    free(ump_output);
    free(name);
    return -1;
}

int32_t zv3_alsa_ump_send(
    zv3_alsa_ump_output *output,
    uint64_t timestamp_nanoseconds,
    const uint32_t *words,
    size_t word_count
)
{
    if (output == NULL || words == NULL || timestamp_nanoseconds == 0 ||
        word_count == 0 || word_count > 4) {
        return -1;
    }
    if (pthread_mutex_trylock(&output->mutex) != 0) {
        atomic_fetch_add_explicit(
            &output->rejected,
            1,
            memory_order_relaxed
        );
        return -2;
    }
    if (atomic_load_explicit(
        &output->stop_requested,
        memory_order_acquire
    ) ||
        output->queue.count == ZV3_UMP_SCHEDULER_CAPACITY ||
        zv3_ump_scheduler_insert(
            &output->queue,
            timestamp_nanoseconds,
            words,
            word_count
        ) != 0) {
        atomic_fetch_add_explicit(
            &output->rejected,
            1,
            memory_order_relaxed
        );
        pthread_mutex_unlock(&output->mutex);
        return -2;
    }
    atomic_fetch_add_explicit(
        &output->queued,
        1,
        memory_order_relaxed
    );
    pthread_cond_signal(&output->condition);
    pthread_mutex_unlock(&output->mutex);
    return 0;
}

void zv3_alsa_ump_get_output_statistics(
    const zv3_alsa_ump_output *output,
    zv3_alsa_ump_output_statistics *statistics
)
{
    if (output == NULL || statistics == NULL) {
        return;
    }
    statistics->queued = atomic_load_explicit(
        &output->queued,
        memory_order_relaxed
    );
    statistics->delivered = atomic_load_explicit(
        &output->delivered,
        memory_order_relaxed
    );
    statistics->late = atomic_load_explicit(
        &output->late,
        memory_order_relaxed
    );
    statistics->rejected = atomic_load_explicit(
        &output->rejected,
        memory_order_relaxed
    );
    statistics->canceled = atomic_load_explicit(
        &output->canceled,
        memory_order_relaxed
    );
    statistics->write_failures = atomic_load_explicit(
        &output->write_failures,
        memory_order_relaxed
    );
}

void zv3_alsa_ump_close_output(
    zv3_alsa_ump_output *output,
    zv3_alsa_ump_output_statistics *final_statistics
)
{
    if (output == NULL) {
        return;
    }
    pthread_mutex_lock(&output->mutex);
    atomic_store_explicit(
        &output->stop_requested,
        1,
        memory_order_release
    );
    pthread_cond_signal(&output->condition);
    pthread_mutex_unlock(&output->mutex);
    pthread_join(output->thread, NULL);
    zv3_alsa_ump_get_output_statistics(output, final_statistics);
    output->api.ump_close(output->handle);
    pthread_cond_destroy(&output->condition);
    pthread_mutex_destroy(&output->mutex);
    close_api(&output->api);
    free(output);
}
