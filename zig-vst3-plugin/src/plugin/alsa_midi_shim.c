#define _POSIX_C_SOURCE 200809L

#include "alsa_midi_shim.h"
#include "midi_scheduler_queue.h"

#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>

typedef struct _snd_rawmidi snd_rawmidi_t;

typedef struct {
    void *library;
    int (*device_name_hint)(int, const char *, void ***);
    int (*device_name_free_hint)(void **);
    char *(*device_name_get_hint)(const void *, const char *);
    int (*rawmidi_open)(
        snd_rawmidi_t **,
        snd_rawmidi_t **,
        const char *,
        int
    );
    int (*rawmidi_close)(snd_rawmidi_t *);
    ssize_t (*rawmidi_read)(snd_rawmidi_t *, void *, size_t);
    ssize_t (*rawmidi_write)(snd_rawmidi_t *, const void *, size_t);
    int (*rawmidi_poll_descriptors_count)(snd_rawmidi_t *);
    int (*rawmidi_poll_descriptors)(
        snd_rawmidi_t *,
        struct pollfd *,
        unsigned int
    );
    int (*rawmidi_poll_descriptors_revents)(
        snd_rawmidi_t *,
        struct pollfd *,
        unsigned int,
        unsigned short *
    );
} alsa_midi_api;

#define LOAD_SYMBOL(api, member, name)                                      \
    do {                                                                    \
        *(void **)(&(api)->member) = dlsym((api)->library, (name));          \
        if ((api)->member == NULL) {                                         \
            close_api((api));                                                \
            return -1;                                                       \
        }                                                                   \
    } while (0)

static void close_api(alsa_midi_api *api)
{
    if (api->library != NULL) {
        dlclose(api->library);
    }
    memset(api, 0, sizeof(*api));
}

static int open_api(alsa_midi_api *api)
{
    memset(api, 0, sizeof(*api));
    api->library = dlopen("libasound.so.2", RTLD_NOW | RTLD_LOCAL);
    if (api->library == NULL) {
        return -1;
    }
    LOAD_SYMBOL(api, device_name_hint, "snd_device_name_hint");
    LOAD_SYMBOL(api, device_name_free_hint, "snd_device_name_free_hint");
    LOAD_SYMBOL(api, device_name_get_hint, "snd_device_name_get_hint");
    LOAD_SYMBOL(api, rawmidi_open, "snd_rawmidi_open");
    LOAD_SYMBOL(api, rawmidi_close, "snd_rawmidi_close");
    LOAD_SYMBOL(api, rawmidi_read, "snd_rawmidi_read");
    LOAD_SYMBOL(api, rawmidi_write, "snd_rawmidi_write");
    LOAD_SYMBOL(
        api,
        rawmidi_poll_descriptors_count,
        "snd_rawmidi_poll_descriptors_count"
    );
    LOAD_SYMBOL(
        api,
        rawmidi_poll_descriptors,
        "snd_rawmidi_poll_descriptors"
    );
    LOAD_SYMBOL(
        api,
        rawmidi_poll_descriptors_revents,
        "snd_rawmidi_poll_descriptors_revents"
    );
    return 0;
}

static int hint_matches_direction(
    alsa_midi_api *api,
    const void *hint,
    uint32_t direction
)
{
    char *io = api->device_name_get_hint(hint, "IOID");
    int matches = io == NULL ||
        (direction == ZV3_ALSA_MIDI_INPUT &&
            strcmp(io, "Input") == 0) ||
        (direction == ZV3_ALSA_MIDI_OUTPUT &&
            strcmp(io, "Output") == 0);
    free(io);
    return matches;
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

static char *duplicate_string(const char *source)
{
    size_t length;
    char *copy;
    if (source == NULL) {
        return NULL;
    }
    length = strlen(source);
    copy = malloc(length + 1);
    if (copy != NULL) {
        memcpy(copy, source, length + 1);
    }
    return copy;
}

static int copy_identifier(
    const uint8_t *identifier,
    size_t identifier_length,
    char **output
)
{
    char *copy;
    if (identifier == NULL || identifier_length == 0 ||
        memchr(identifier, 0, identifier_length) != NULL) {
        return -1;
    }
    copy = malloc(identifier_length + 1);
    if (copy == NULL) {
        return -1;
    }
    memcpy(copy, identifier, identifier_length);
    copy[identifier_length] = '\0';
    *output = copy;
    return 0;
}

static int query_hint(
    alsa_midi_api *api,
    uint32_t direction,
    size_t requested_index,
    const char *property,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    void **hints = NULL;
    size_t matching_index = 0;
    size_t index;
    int result = -1;
    if (api->device_name_hint(
        -1,
        "rawmidi",
        &hints
    ) < 0 || hints == NULL) {
        return -1;
    }
    for (index = 0; hints[index] != NULL; ++index) {
        char *value;
        if (!hint_matches_direction(api, hints[index], direction)) {
            continue;
        }
        if (matching_index++ != requested_index) {
            continue;
        }
        value = api->device_name_get_hint(hints[index], property);
        if (value == NULL && strcmp(property, "DESC") == 0) {
            value = api->device_name_get_hint(hints[index], "NAME");
        }
        result = copy_bytes(
            value,
            output,
            output_capacity,
            output_length
        );
        free(value);
        break;
    }
    api->device_name_free_hint(hints);
    return result;
}

int32_t zv3_alsa_midi_available(void)
{
    alsa_midi_api api;
    if (open_api(&api) != 0) {
        return 0;
    }
    close_api(&api);
    return 1;
}

uint64_t zv3_alsa_midi_now_nanoseconds(void)
{
    struct timespec time;
    if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) {
        return 0;
    }
    return (uint64_t)time.tv_sec * 1000000000u +
        (uint64_t)time.tv_nsec;
}

int32_t zv3_alsa_midi_device_count(
    uint32_t direction,
    size_t *output
)
{
    alsa_midi_api api;
    void **hints = NULL;
    size_t index;
    size_t count = 0;
    if (output == NULL || direction > ZV3_ALSA_MIDI_OUTPUT ||
        open_api(&api) != 0) {
        return -1;
    }
    if (api.device_name_hint(
        -1,
        "rawmidi",
        &hints
    ) < 0 || hints == NULL) {
        close_api(&api);
        return -1;
    }
    for (index = 0; hints[index] != NULL; ++index) {
        if (hint_matches_direction(&api, hints[index], direction)) {
            ++count;
        }
    }
    api.device_name_free_hint(hints);
    close_api(&api);
    *output = count;
    return 0;
}

int32_t zv3_alsa_midi_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_midi_api api;
    int result;
    if (direction > ZV3_ALSA_MIDI_OUTPUT || open_api(&api) != 0) {
        return -1;
    }
    result = query_hint(
        &api,
        direction,
        index,
        "NAME",
        output,
        output_capacity,
        output_length
    );
    close_api(&api);
    return result;
}

int32_t zv3_alsa_midi_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_midi_api api;
    int result;
    if (direction > ZV3_ALSA_MIDI_OUTPUT || open_api(&api) != 0) {
        return -1;
    }
    result = query_hint(
        &api,
        direction,
        index,
        "DESC",
        output,
        output_capacity,
        output_length
    );
    close_api(&api);
    return result;
}

int32_t zv3_alsa_midi_default_device_id(
    uint32_t direction,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_midi_api api;
    void **hints = NULL;
    size_t index;
    char *fallback = NULL;
    int result = -1;
    if (direction > ZV3_ALSA_MIDI_OUTPUT || open_api(&api) != 0) {
        return -1;
    }
    if (api.device_name_hint(
        -1,
        "rawmidi",
        &hints
    ) < 0 || hints == NULL) {
        close_api(&api);
        return -1;
    }
    for (index = 0; hints[index] != NULL; ++index) {
        char *name;
        if (!hint_matches_direction(&api, hints[index], direction)) {
            continue;
        }
        name = api.device_name_get_hint(hints[index], "NAME");
        if (name == NULL) {
            continue;
        }
        if (fallback == NULL) {
            fallback = duplicate_string(name);
        }
        if (strcmp(name, "default") == 0) {
            free(fallback);
            fallback = name;
            break;
        }
        free(name);
    }
    result = copy_bytes(
        fallback,
        output,
        output_capacity,
        output_length
    );
    free(fallback);
    api.device_name_free_hint(hints);
    close_api(&api);
    return result;
}

struct zv3_alsa_midi_input {
    alsa_midi_api api;
    snd_rawmidi_t *handle;
    pthread_t thread;
    atomic_int stop_requested;
    atomic_uint_fast64_t read_failures;
    void *context;
    zv3_alsa_midi_receive_fn receive;
};

static void *input_thread(void *context)
{
    zv3_alsa_midi_input *input = context;
    int descriptor_count =
        input->api.rawmidi_poll_descriptors_count(input->handle);
    struct pollfd *descriptors;
    uint8_t bytes[256];
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
        input->api.rawmidi_poll_descriptors(
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
        if (input->api.rawmidi_poll_descriptors_revents(
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
        while (1) {
            ssize_t count = input->api.rawmidi_read(
                input->handle,
                bytes,
                sizeof(bytes)
            );
            if (count > 0) {
                input->receive(
                    input->context,
                    zv3_alsa_midi_now_nanoseconds(),
                    bytes,
                    (size_t)count
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

int32_t zv3_alsa_midi_start_input(
    const uint8_t *identifier,
    size_t identifier_length,
    void *context,
    zv3_alsa_midi_receive_fn receive,
    zv3_alsa_midi_input **output
)
{
    zv3_alsa_midi_input *input;
    char *name = NULL;
    if (output == NULL || receive == NULL ||
        copy_identifier(identifier, identifier_length, &name) != 0) {
        free(name);
        return -1;
    }
    *output = NULL;
    input = calloc(1, sizeof(*input));
    if (input == NULL || open_api(&input->api) != 0 ||
        input->api.rawmidi_open(
            &input->handle,
            NULL,
            name,
            0x0002
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
    if (pthread_create(
        &input->thread,
        NULL,
        input_thread,
        input
    ) != 0) {
        input->api.rawmidi_close(input->handle);
        close_api(&input->api);
        free(input);
        return -1;
    }
    *output = input;
    return 0;
}

void zv3_alsa_midi_get_input_statistics(
    const zv3_alsa_midi_input *input,
    zv3_alsa_midi_input_statistics *output
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

void zv3_alsa_midi_stop_input(
    zv3_alsa_midi_input *input,
    zv3_alsa_midi_input_statistics *final_statistics
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
    zv3_alsa_midi_get_input_statistics(input, final_statistics);
    input->api.rawmidi_close(input->handle);
    close_api(&input->api);
    free(input);
}

struct zv3_alsa_midi_output {
    alsa_midi_api api;
    snd_rawmidi_t *handle;
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    atomic_int stop_requested;
    zv3_midi_scheduler_queue queue;
    atomic_uint_fast64_t queued;
    atomic_uint_fast64_t delivered;
    atomic_uint_fast64_t late;
    atomic_uint_fast64_t rejected;
    atomic_uint_fast64_t canceled;
    atomic_uint_fast64_t write_failures;
};

static int write_scheduled_message(
    zv3_alsa_midi_output *output,
    const zv3_midi_scheduled_message *message
)
{
    size_t written = 0;
    while (written < message->length) {
        ssize_t count = output->api.rawmidi_write(
            output->handle,
            message->bytes + written,
            message->length - written
        );
        if (count > 0) {
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
    zv3_alsa_midi_output *output = context;
    pthread_mutex_lock(&output->mutex);
    while (!atomic_load_explicit(
        &output->stop_requested,
        memory_order_acquire
    )) {
        zv3_midi_scheduled_message message;
        uint64_t now;
        if (output->queue.count == 0) {
            pthread_cond_wait(&output->condition, &output->mutex);
            continue;
        }
        now = zv3_alsa_midi_now_nanoseconds();
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
        if (output->queue.messages[0].timestamp_nanoseconds > now) {
            struct timespec deadline;
            deadline.tv_sec = (time_t)(
                output->queue.messages[0].timestamp_nanoseconds /
                    1000000000u
            );
            deadline.tv_nsec = (long)(
                output->queue.messages[0].timestamp_nanoseconds %
                    1000000000u
            );
            pthread_cond_timedwait(
                &output->condition,
                &output->mutex,
                &deadline
            );
            continue;
        }
        if (!zv3_midi_scheduler_pop_due(
            &output->queue,
            now,
            &message
        ))
            continue;
        pthread_mutex_unlock(&output->mutex);
        if (message.timestamp_nanoseconds < now) {
            atomic_fetch_add_explicit(
                &output->late,
                1,
                memory_order_relaxed
            );
        }
        if (write_scheduled_message(output, &message) == 0) {
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
        zv3_midi_scheduler_clear(&output->queue),
        memory_order_relaxed
    );
    pthread_mutex_unlock(&output->mutex);
    return NULL;
}

int32_t zv3_alsa_midi_open_output(
    const uint8_t *identifier,
    size_t identifier_length,
    zv3_alsa_midi_output **output
)
{
    zv3_alsa_midi_output *midi_output;
    char *name = NULL;
    pthread_condattr_t condition_attributes;
    int mutex_ready = 0;
    int condition_attributes_ready = 0;
    int condition_ready = 0;
    if (output == NULL ||
        copy_identifier(identifier, identifier_length, &name) != 0) {
        free(name);
        return -1;
    }
    *output = NULL;
    midi_output = calloc(1, sizeof(*midi_output));
    if (midi_output == NULL) {
        goto fail;
    }
    if (open_api(&midi_output->api) != 0)
        goto fail;
    if (midi_output->api.rawmidi_open(
        NULL,
        &midi_output->handle,
        name,
        0x0002
    ) < 0)
        goto fail;
    if (pthread_mutex_init(&midi_output->mutex, NULL) != 0)
        goto fail;
    mutex_ready = 1;
    if (pthread_condattr_init(&condition_attributes) != 0)
        goto fail;
    condition_attributes_ready = 1;
    if (pthread_condattr_setclock(
        &condition_attributes,
        CLOCK_MONOTONIC
    ) != 0)
        goto fail;
    if (pthread_cond_init(
        &midi_output->condition,
        &condition_attributes
    ) != 0)
        goto fail;
    condition_ready = 1;
    pthread_condattr_destroy(&condition_attributes);
    condition_attributes_ready = 0;
    if (pthread_create(
        &midi_output->thread,
        NULL,
        output_thread,
        midi_output
    ) != 0)
        goto fail;
    free(name);
    *output = midi_output;
    return 0;
fail:
    if (condition_ready)
        pthread_cond_destroy(&midi_output->condition);
    if (condition_attributes_ready)
        pthread_condattr_destroy(&condition_attributes);
    if (mutex_ready)
        pthread_mutex_destroy(&midi_output->mutex);
    if (midi_output != NULL) {
        if (midi_output->handle != NULL)
            midi_output->api.rawmidi_close(midi_output->handle);
        close_api(&midi_output->api);
    }
    free(midi_output);
    free(name);
    return -1;
}

int32_t zv3_alsa_midi_send(
    zv3_alsa_midi_output *output,
    uint64_t timestamp_nanoseconds,
    const uint8_t *bytes,
    size_t length
)
{
    if (output == NULL || bytes == NULL ||
        timestamp_nanoseconds == 0 ||
        length == 0 || length > 3) {
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
        output->queue.count == ZV3_MIDI_SCHEDULER_CAPACITY) {
        atomic_fetch_add_explicit(
            &output->rejected,
            1,
            memory_order_relaxed
        );
        pthread_mutex_unlock(&output->mutex);
        return -2;
    }
    if (zv3_midi_scheduler_insert(
        &output->queue,
        timestamp_nanoseconds,
        bytes,
        length
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

void zv3_alsa_midi_get_output_statistics(
    const zv3_alsa_midi_output *output,
    zv3_alsa_midi_output_statistics *statistics
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

void zv3_alsa_midi_close_output(
    zv3_alsa_midi_output *output,
    zv3_alsa_midi_output_statistics *final_statistics
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
    pthread_cond_destroy(&output->condition);
    pthread_mutex_destroy(&output->mutex);
    if (output->api.rawmidi_close(output->handle) < 0) {
        atomic_fetch_add_explicit(
            &output->write_failures,
            1,
            memory_order_relaxed
        );
    }
    zv3_alsa_midi_get_output_statistics(output, final_statistics);
    close_api(&output->api);
    free(output);
}
