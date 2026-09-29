#include "alsa_shim.h"

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct snd_pcm_t snd_pcm_t;
typedef struct snd_pcm_hw_params_t snd_pcm_hw_params_t;
typedef long snd_pcm_sframes_t;
typedef unsigned long snd_pcm_uframes_t;

typedef struct {
    void *library;
    int (*device_name_hint)(int, const char *, void ***);
    int (*device_name_free_hint)(void **);
    char *(*device_name_get_hint)(const void *, const char *);
    int (*pcm_open)(snd_pcm_t **, const char *, int, int);
    int (*pcm_close)(snd_pcm_t *);
    int (*pcm_format_value)(const char *);
    int (*pcm_set_params)(
        snd_pcm_t *,
        int,
        int,
        unsigned int,
        unsigned int,
        int,
        unsigned int
    );
    int (*pcm_get_params)(
        snd_pcm_t *,
        snd_pcm_uframes_t *,
        snd_pcm_uframes_t *
    );
    int (*pcm_wait)(snd_pcm_t *, int);
    snd_pcm_sframes_t (*pcm_readi)(
        snd_pcm_t *,
        void *,
        snd_pcm_uframes_t
    );
    snd_pcm_sframes_t (*pcm_writei)(
        snd_pcm_t *,
        const void *,
        snd_pcm_uframes_t
    );
    int (*pcm_recover)(snd_pcm_t *, int, int);
    int (*pcm_drop)(snd_pcm_t *);
    int (*hw_params_malloc)(snd_pcm_hw_params_t **);
    void (*hw_params_free)(snd_pcm_hw_params_t *);
    int (*hw_params_any)(snd_pcm_t *, snd_pcm_hw_params_t *);
    int (*hw_params_get_channels_max)(
        const snd_pcm_hw_params_t *,
        unsigned int *
    );
} alsa_api;

#define LOAD_SYMBOL(api, member, name)                                      \
    do {                                                                    \
        *(void **)(&(api)->member) = dlsym((api)->library, (name));          \
        if ((api)->member == NULL) {                                         \
            close_api((api));                                                \
            return -1;                                                       \
        }                                                                   \
    } while (0)

static void close_api(alsa_api *api)
{
    if (api->library != NULL) {
        dlclose(api->library);
    }
    memset(api, 0, sizeof(*api));
}

static int open_api(alsa_api *api)
{
    memset(api, 0, sizeof(*api));
    api->library = dlopen("libasound.so.2", RTLD_NOW | RTLD_LOCAL);
    if (api->library == NULL) {
        return -1;
    }
    LOAD_SYMBOL(api, device_name_hint, "snd_device_name_hint");
    LOAD_SYMBOL(api, device_name_free_hint, "snd_device_name_free_hint");
    LOAD_SYMBOL(api, device_name_get_hint, "snd_device_name_get_hint");
    LOAD_SYMBOL(api, pcm_open, "snd_pcm_open");
    LOAD_SYMBOL(api, pcm_close, "snd_pcm_close");
    LOAD_SYMBOL(api, pcm_format_value, "snd_pcm_format_value");
    LOAD_SYMBOL(api, pcm_set_params, "snd_pcm_set_params");
    LOAD_SYMBOL(api, pcm_get_params, "snd_pcm_get_params");
    LOAD_SYMBOL(api, pcm_wait, "snd_pcm_wait");
    LOAD_SYMBOL(api, pcm_readi, "snd_pcm_readi");
    LOAD_SYMBOL(api, pcm_writei, "snd_pcm_writei");
    LOAD_SYMBOL(api, pcm_recover, "snd_pcm_recover");
    LOAD_SYMBOL(api, pcm_drop, "snd_pcm_drop");
    LOAD_SYMBOL(api, hw_params_malloc, "snd_pcm_hw_params_malloc");
    LOAD_SYMBOL(api, hw_params_free, "snd_pcm_hw_params_free");
    LOAD_SYMBOL(api, hw_params_any, "snd_pcm_hw_params_any");
    LOAD_SYMBOL(
        api,
        hw_params_get_channels_max,
        "snd_pcm_hw_params_get_channels_max"
    );
    return 0;
}

static int hint_matches_direction(
    alsa_api *api,
    const void *hint,
    uint32_t direction
)
{
    char *io = api->device_name_get_hint(hint, "IOID");
    int matches = io == NULL ||
        (direction == ZV3_ALSA_CAPTURE && strcmp(io, "Input") == 0) ||
        (direction == ZV3_ALSA_PLAYBACK && strcmp(io, "Output") == 0);
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

static int query_hint(
    alsa_api *api,
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
    if (api->device_name_hint(-1, "pcm", &hints) < 0 || hints == NULL) {
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

int32_t zv3_alsa_available(void)
{
    alsa_api api;
    if (open_api(&api) != 0) {
        return 0;
    }
    close_api(&api);
    return 1;
}

int32_t zv3_alsa_device_count(uint32_t direction, size_t *output)
{
    alsa_api api;
    void **hints = NULL;
    size_t index;
    size_t count = 0;
    if (output == NULL || direction > ZV3_ALSA_PLAYBACK ||
        open_api(&api) != 0) {
        return -1;
    }
    if (api.device_name_hint(-1, "pcm", &hints) < 0 || hints == NULL) {
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

int32_t zv3_alsa_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_api api;
    int result;
    if (direction > ZV3_ALSA_PLAYBACK || open_api(&api) != 0) {
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

int32_t zv3_alsa_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_api api;
    int result;
    if (direction > ZV3_ALSA_PLAYBACK || open_api(&api) != 0) {
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

int32_t zv3_alsa_default_device_id(
    uint32_t direction,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    alsa_api api;
    void **hints = NULL;
    size_t index;
    char *fallback = NULL;
    int result = -1;
    if (direction > ZV3_ALSA_PLAYBACK || open_api(&api) != 0) {
        return -1;
    }
    if (api.device_name_hint(-1, "pcm", &hints) < 0 || hints == NULL) {
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

int32_t zv3_alsa_device_channels(
    uint32_t direction,
    const uint8_t *identifier,
    size_t identifier_length,
    uint32_t *output
)
{
    alsa_api api;
    snd_pcm_t *pcm = NULL;
    snd_pcm_hw_params_t *params = NULL;
    char *name = NULL;
    unsigned int channels = 0;
    int stream = direction == ZV3_ALSA_CAPTURE ? 1 : 0;
    int result = -1;
    if (output == NULL || direction > ZV3_ALSA_PLAYBACK ||
        copy_identifier(identifier, identifier_length, &name) != 0 ||
        open_api(&api) != 0) {
        free(name);
        return -1;
    }
    if (api.pcm_open(&pcm, name, stream, 1) < 0 ||
        api.hw_params_malloc(&params) < 0 ||
        api.hw_params_any(pcm, params) < 0 ||
        api.hw_params_get_channels_max(params, &channels) < 0 ||
        channels == 0) {
        goto done;
    }
    *output = channels;
    result = 0;
done:
    if (params != NULL) {
        api.hw_params_free(params);
    }
    if (pcm != NULL) {
        api.pcm_close(pcm);
    }
    close_api(&api);
    free(name);
    return result;
}

struct zv3_alsa_session {
    alsa_api api;
    snd_pcm_t *capture;
    snd_pcm_t *playback;
    pthread_t thread;
    pthread_t capture_thread;
    pthread_t playback_thread;
    int thread_started;
    int capture_thread_started;
    int playback_thread_started;
    atomic_int stop_requested;
    atomic_uint_fast64_t processed;
    atomic_uint_fast64_t callback_failures;
    atomic_uint_fast64_t capture_underflows;
    atomic_uint_fast64_t capture_overflows;
    atomic_uint_fast64_t recoveries;
    atomic_uint_fast64_t device_failures;
    atomic_uint realtime_priority_acquired;
    uint32_t sample_bytes;
    uint32_t maximum_frames;
    uint32_t capture_period_frames;
    uint32_t playback_period_frames;
    uint32_t input_channels;
    uint32_t output_channels;
    void *input_interleaved;
    void *output_interleaved;
    void *input_planar;
    void *output_planar;
    const void **input_views;
    void **output_views;
    void *context;
    zv3_alsa_process_fn process;
    zv3_alsa_capture_fn capture_callback;
    zv3_alsa_render_fn render_callback;
};

static void clear_output(zv3_alsa_session *session, uint32_t frames)
{
    if (frames == 0 || session->output_channels == 0) {
        return;
    }
    memset(
        session->output_planar,
        0,
        (size_t)frames * session->output_channels * session->sample_bytes
    );
}

static void deinterleave_input(zv3_alsa_session *session, uint32_t frames)
{
    size_t channel;
    size_t frame;
    if (session->sample_bytes == 4) {
        const float *source = session->input_interleaved;
        float *target = session->input_planar;
        for (channel = 0; channel < session->input_channels; ++channel) {
            for (frame = 0; frame < frames; ++frame) {
                target[channel * frames + frame] =
                    source[frame * session->input_channels + channel];
            }
        }
    } else {
        const double *source = session->input_interleaved;
        double *target = session->input_planar;
        for (channel = 0; channel < session->input_channels; ++channel) {
            for (frame = 0; frame < frames; ++frame) {
                target[channel * frames + frame] =
                    source[frame * session->input_channels + channel];
            }
        }
    }
}

static void interleave_output(zv3_alsa_session *session, uint32_t frames)
{
    size_t channel;
    size_t frame;
    if (session->sample_bytes == 4) {
        const float *source = session->output_planar;
        float *target = session->output_interleaved;
        for (frame = 0; frame < frames; ++frame) {
            for (channel = 0; channel < session->output_channels; ++channel) {
                target[frame * session->output_channels + channel] =
                    source[channel * frames + frame];
            }
        }
    } else {
        const double *source = session->output_planar;
        double *target = session->output_interleaved;
        for (frame = 0; frame < frames; ++frame) {
            for (channel = 0; channel < session->output_channels; ++channel) {
                target[frame * session->output_channels + channel] =
                    source[channel * frames + frame];
            }
        }
    }
}

static int recover_stream(
    zv3_alsa_session *session,
    snd_pcm_t *pcm,
    int error
)
{
    int result = session->api.pcm_recover(pcm, error, 1);
    if (result >= 0) {
        atomic_fetch_add_explicit(
            &session->recoveries,
            1,
            memory_order_relaxed
        );
    }
    return result;
}

static int read_capture(zv3_alsa_session *session, uint32_t frames)
{
    snd_pcm_sframes_t read_count = session->api.pcm_readi(
        session->capture,
        session->input_interleaved,
        frames
    );
    if (read_count == (snd_pcm_sframes_t)frames) {
        deinterleave_input(session, frames);
        return 0;
    }
    if (atomic_load_explicit(
        &session->stop_requested,
        memory_order_acquire
    )) {
        return -1;
    }
    if (read_count < 0 && read_count != -EAGAIN) {
        if (recover_stream(session, session->capture, (int)read_count) < 0) {
            atomic_fetch_add_explicit(
                &session->device_failures,
                1,
                memory_order_relaxed
            );
            return -1;
        }
        atomic_fetch_add_explicit(
            &session->capture_overflows,
            1,
            memory_order_relaxed
        );
    } else {
        atomic_fetch_add_explicit(
            &session->capture_underflows,
            1,
            memory_order_relaxed
        );
    }
    memset(
        session->input_planar,
        0,
        (size_t)frames * session->input_channels * session->sample_bytes
    );
    return 0;
}

static int write_playback(zv3_alsa_session *session, uint32_t frames)
{
    uint32_t written = 0;
    while (written < frames &&
        !atomic_load_explicit(&session->stop_requested, memory_order_acquire)) {
        const uint8_t *source = session->output_interleaved;
        snd_pcm_sframes_t result = session->api.pcm_writei(
            session->playback,
            source + (size_t)written * session->output_channels *
                session->sample_bytes,
            frames - written
        );
        if (result > 0) {
            written += (uint32_t)result;
            continue;
        }
        if (result == -EAGAIN || result == 0) {
            session->api.pcm_wait(session->playback, 20);
            continue;
        }
        if (atomic_load_explicit(
            &session->stop_requested,
            memory_order_acquire
        )) {
            return -1;
        }
        if (recover_stream(session, session->playback, (int)result) < 0) {
            atomic_fetch_add_explicit(
                &session->device_failures,
                1,
                memory_order_relaxed
            );
            return -1;
        }
    }
    return 0;
}

static void set_realtime_priority(zv3_alsa_session *session)
{
    struct sched_param parameter;
    int priority = sched_get_priority_min(SCHED_FIFO);
    if (priority < 0) {
        return;
    }
    memset(&parameter, 0, sizeof(parameter));
    parameter.sched_priority = priority;
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &parameter) == 0) {
        atomic_store_explicit(
            &session->realtime_priority_acquired,
            1,
            memory_order_release
        );
    }
}

static int wait_for_stream(
    zv3_alsa_session *session,
    snd_pcm_t *stream
)
{
    while (!atomic_load_explicit(
        &session->stop_requested,
        memory_order_acquire
    )) {
        int wait_result = session->api.pcm_wait(stream, 20);
        if (wait_result < 0) {
            if (recover_stream(session, stream, wait_result) < 0) {
                atomic_fetch_add_explicit(
                    &session->device_failures,
                    1,
                    memory_order_relaxed
                );
                return -1;
            }
            continue;
        }
        if (wait_result > 0) {
            return 1;
        }
    }
    return 0;
}

static void prepare_input_views(
    zv3_alsa_session *session,
    uint32_t frames
)
{
    size_t channel;
    for (channel = 0; channel < session->input_channels; ++channel) {
        session->input_views[channel] =
            (const uint8_t *)session->input_planar +
            channel * frames * session->sample_bytes;
    }
}

static void prepare_output_views(
    zv3_alsa_session *session,
    uint32_t frames
)
{
    size_t channel;
    for (channel = 0; channel < session->output_channels; ++channel) {
        session->output_views[channel] =
            (uint8_t *)session->output_planar +
            channel * frames * session->sample_bytes;
    }
}

static void *combined_audio_thread(void *context)
{
    zv3_alsa_session *session = context;
    uint32_t frames = session->playback != NULL
        ? session->playback_period_frames
        : session->capture_period_frames;
    set_realtime_priority(session);
    while (!atomic_load_explicit(
        &session->stop_requested,
        memory_order_acquire
    )) {
        snd_pcm_t *driver = session->playback != NULL
            ? session->playback
            : session->capture;
        if (wait_for_stream(session, driver) <= 0) {
            break;
        }
        if (session->capture != NULL &&
            read_capture(session, frames) != 0) {
            break;
        }
        clear_output(session, frames);
        prepare_input_views(session, frames);
        prepare_output_views(session, frames);
        if (session->process(
            session->context,
            frames,
            session->input_views,
            session->output_views
        ) != 0) {
            atomic_fetch_add_explicit(
                &session->callback_failures,
                1,
                memory_order_relaxed
            );
            clear_output(session, frames);
        }
        atomic_fetch_add_explicit(
            &session->processed,
            frames,
            memory_order_relaxed
        );
        if (session->playback != NULL) {
            interleave_output(session, frames);
            if (write_playback(session, frames) != 0) {
                break;
            }
        }
    }
    return NULL;
}

static void *capture_audio_thread(void *context)
{
    zv3_alsa_session *session = context;
    uint32_t frames = session->capture_period_frames;
    set_realtime_priority(session);
    while (!atomic_load_explicit(
        &session->stop_requested,
        memory_order_acquire
    )) {
        if (wait_for_stream(session, session->capture) <= 0) {
            break;
        }
        if (read_capture(session, frames) != 0) {
            break;
        }
        prepare_input_views(session, frames);
        if (session->capture_callback(
            session->context,
            frames,
            session->input_views
        ) != 0) {
            atomic_fetch_add_explicit(
                &session->callback_failures,
                1,
                memory_order_relaxed
            );
        }
    }
    return NULL;
}

static void *playback_audio_thread(void *context)
{
    zv3_alsa_session *session = context;
    uint32_t frames = session->playback_period_frames;
    set_realtime_priority(session);
    while (!atomic_load_explicit(
        &session->stop_requested,
        memory_order_acquire
    )) {
        if (wait_for_stream(session, session->playback) <= 0) {
            break;
        }
        clear_output(session, frames);
        prepare_output_views(session, frames);
        if (session->render_callback(
            session->context,
            frames,
            session->output_views
        ) != 0) {
            atomic_fetch_add_explicit(
                &session->callback_failures,
                1,
                memory_order_relaxed
            );
            clear_output(session, frames);
        }
        atomic_fetch_add_explicit(
            &session->processed,
            frames,
            memory_order_relaxed
        );
        interleave_output(session, frames);
        if (write_playback(session, frames) != 0) {
            break;
        }
    }
    return NULL;
}

static void stop_threads(zv3_alsa_session *session)
{
    atomic_store_explicit(
        &session->stop_requested,
        1,
        memory_order_release
    );
    if (session->capture != NULL) {
        session->api.pcm_drop(session->capture);
    }
    if (session->playback != NULL) {
        session->api.pcm_drop(session->playback);
    }
    if (session->thread_started) {
        pthread_join(session->thread, NULL);
        session->thread_started = 0;
    }
    if (session->capture_thread_started) {
        pthread_join(session->capture_thread, NULL);
        session->capture_thread_started = 0;
    }
    if (session->playback_thread_started) {
        pthread_join(session->playback_thread, NULL);
        session->playback_thread_started = 0;
    }
}

static void release_session(zv3_alsa_session *session)
{
    if (session == NULL) {
        return;
    }
    if (session->capture != NULL) {
        session->api.pcm_close(session->capture);
    }
    if (session->playback != NULL) {
        session->api.pcm_close(session->playback);
    }
    close_api(&session->api);
    free(session->input_interleaved);
    free(session->output_interleaved);
    free(session->input_planar);
    free(session->output_planar);
    free(session->input_views);
    free(session->output_views);
    free(session);
}

static int open_pcm(
    zv3_alsa_session *session,
    const uint8_t *identifier,
    size_t identifier_length,
    int stream,
    uint32_t channels,
    uint32_t sample_rate,
    snd_pcm_t **output,
    uint32_t *period_frames
)
{
    char *name = NULL;
    snd_pcm_uframes_t buffer_size = 0;
    snd_pcm_uframes_t period_size = 0;
    int format;
    unsigned int latency;
    int result = -1;
    if (copy_identifier(identifier, identifier_length, &name) != 0) {
        return -1;
    }
    format = session->api.pcm_format_value(
        session->sample_bytes == 4 ? "FLOAT_LE" : "FLOAT64_LE"
    );
    latency = (unsigned int)(
        ((uint64_t)session->maximum_frames * 4u * 1000000u) / sample_rate
    );
    if (latency < 5000u) {
        latency = 5000u;
    }
    if (format < 0 ||
        session->api.pcm_open(output, name, stream, 1) < 0 ||
        session->api.pcm_set_params(
            *output,
            format,
            3,
            channels,
            sample_rate,
            0,
            latency
        ) < 0 ||
        session->api.pcm_get_params(
            *output,
            &buffer_size,
            &period_size
        ) < 0 ||
        period_size == 0 ||
        period_size > session->maximum_frames) {
        goto done;
    }
    *period_frames = (uint32_t)period_size;
    result = 0;
done:
    free(name);
    return result;
}

static int32_t start_session(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_alsa_process_fn process,
    zv3_alsa_capture_fn capture_callback,
    zv3_alsa_render_fn render_callback,
    zv3_alsa_session **output
)
{
    zv3_alsa_session *session;
    uint32_t input_period = 0;
    uint32_t output_period = 0;
    size_t input_samples;
    size_t output_samples;
    int combined_mode = process != NULL &&
        capture_callback == NULL &&
        render_callback == NULL;
    int split_mode = process == NULL &&
        capture_callback != NULL &&
        render_callback != NULL;
    if (output == NULL || (!combined_mode && !split_mode) ||
        (sample_bytes != 4 && sample_bytes != 8) ||
        sample_rate == 0 || maximum_frames == 0 ||
        (input_channels == 0 && output_channels == 0) ||
        (split_mode && (input_channels == 0 || output_channels == 0))) {
        return -1;
    }
    *output = NULL;
    session = calloc(1, sizeof(*session));
    if (session == NULL || open_api(&session->api) != 0) {
        release_session(session);
        return -1;
    }
    session->sample_bytes = sample_bytes;
    session->maximum_frames = maximum_frames;
    session->input_channels = input_channels;
    session->output_channels = output_channels;
    session->context = context;
    session->process = process;
    session->capture_callback = capture_callback;
    session->render_callback = render_callback;
    if (input_channels != 0 &&
        open_pcm(
            session,
            input_identifier,
            input_identifier_length,
            1,
            input_channels,
            sample_rate,
            &session->capture,
            &input_period
        ) != 0) {
        release_session(session);
        return -1;
    }
    if (output_channels != 0 &&
        open_pcm(
            session,
            output_identifier,
            output_identifier_length,
            0,
            output_channels,
            sample_rate,
            &session->playback,
            &output_period
        ) != 0) {
        release_session(session);
        return -1;
    }
    session->capture_period_frames = input_period;
    session->playback_period_frames = output_period;
    input_samples = (size_t)maximum_frames * input_channels;
    output_samples = (size_t)maximum_frames * output_channels;
    if (input_samples != 0) {
        session->input_interleaved = calloc(input_samples, sample_bytes);
        session->input_planar = calloc(input_samples, sample_bytes);
        session->input_views = calloc(input_channels, sizeof(void *));
    }
    if (output_samples != 0) {
        session->output_interleaved = calloc(output_samples, sample_bytes);
        session->output_planar = calloc(output_samples, sample_bytes);
        session->output_views = calloc(output_channels, sizeof(void *));
    }
    if ((input_samples != 0 &&
        (session->input_interleaved == NULL ||
         session->input_planar == NULL ||
         session->input_views == NULL)) ||
        (output_samples != 0 &&
        (session->output_interleaved == NULL ||
         session->output_planar == NULL ||
         session->output_views == NULL))) {
        release_session(session);
        return -1;
    }
    if (combined_mode) {
        if (pthread_create(
            &session->thread,
            NULL,
            combined_audio_thread,
            session
        ) != 0) {
            release_session(session);
            return -1;
        }
        session->thread_started = 1;
    } else {
        if (pthread_create(
            &session->capture_thread,
            NULL,
            capture_audio_thread,
            session
        ) != 0) {
            release_session(session);
            return -1;
        }
        session->capture_thread_started = 1;
        if (pthread_create(
            &session->playback_thread,
            NULL,
            playback_audio_thread,
            session
        ) != 0) {
            stop_threads(session);
            release_session(session);
            return -1;
        }
        session->playback_thread_started = 1;
    }
    *output = session;
    return 0;
}

int32_t zv3_alsa_start(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_alsa_process_fn process,
    zv3_alsa_session **output
)
{
    return start_session(
        input_identifier,
        input_identifier_length,
        output_identifier,
        output_identifier_length,
        sample_bytes,
        sample_rate,
        maximum_frames,
        input_channels,
        output_channels,
        context,
        process,
        NULL,
        NULL,
        output
    );
}

int32_t zv3_alsa_start_split(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_alsa_capture_fn capture_callback,
    zv3_alsa_render_fn render_callback,
    zv3_alsa_session **output
)
{
    return start_session(
        input_identifier,
        input_identifier_length,
        output_identifier,
        output_identifier_length,
        sample_bytes,
        sample_rate,
        maximum_frames,
        input_channels,
        output_channels,
        context,
        NULL,
        capture_callback,
        render_callback,
        output
    );
}

void zv3_alsa_get_statistics(
    const zv3_alsa_session *session,
    zv3_alsa_statistics *output
)
{
    if (session == NULL || output == NULL) {
        return;
    }
    output->processed = atomic_load_explicit(
        &session->processed,
        memory_order_relaxed
    );
    output->callback_failures = atomic_load_explicit(
        &session->callback_failures,
        memory_order_relaxed
    );
    output->capture_underflows = atomic_load_explicit(
        &session->capture_underflows,
        memory_order_relaxed
    );
    output->capture_overflows = atomic_load_explicit(
        &session->capture_overflows,
        memory_order_relaxed
    );
    output->recoveries = atomic_load_explicit(
        &session->recoveries,
        memory_order_relaxed
    );
    output->device_failures = atomic_load_explicit(
        &session->device_failures,
        memory_order_relaxed
    );
    output->realtime_priority_acquired = atomic_load_explicit(
        &session->realtime_priority_acquired,
        memory_order_relaxed
    );
}

void zv3_alsa_stop(
    zv3_alsa_session *session,
    zv3_alsa_statistics *final_statistics
)
{
    if (session == NULL) {
        return;
    }
    stop_threads(session);
    zv3_alsa_get_statistics(session, final_statistics);
    release_session(session);
}
