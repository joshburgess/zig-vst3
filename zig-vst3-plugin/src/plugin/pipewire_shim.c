#include "pipewire_shim.h"

#include <dlfcn.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    ZV3_PW_DIRECTION_INPUT = 0,
    ZV3_PW_DIRECTION_OUTPUT = 1,
    ZV3_PW_ID_ANY = UINT32_MAX,
    ZV3_PW_STREAM_FLAG_AUTOCONNECT = 1u << 0,
    ZV3_PW_STREAM_FLAG_MAP_BUFFERS = 1u << 2,
    ZV3_PW_STREAM_FLAG_RT_PROCESS = 1u << 4,
    ZV3_PW_STREAM_STATE_ERROR = -1,
    ZV3_PW_STREAM_STATE_PAUSED = 2,
    ZV3_PW_STREAM_STATE_STREAMING = 3,
    ZV3_SPA_TYPE_ID = 3,
    ZV3_SPA_TYPE_INT = 4,
    ZV3_SPA_TYPE_OBJECT = 15,
    ZV3_SPA_TYPE_OBJECT_FORMAT = 0x40003,
    ZV3_SPA_PARAM_ENUM_FORMAT = 3,
    ZV3_SPA_FORMAT_MEDIA_TYPE = 1,
    ZV3_SPA_FORMAT_MEDIA_SUBTYPE = 2,
    ZV3_SPA_FORMAT_AUDIO_FORMAT = 0x10001,
    ZV3_SPA_FORMAT_AUDIO_RATE = 0x10003,
    ZV3_SPA_FORMAT_AUDIO_CHANNELS = 0x10004,
    ZV3_SPA_MEDIA_TYPE_AUDIO = 1,
    ZV3_SPA_MEDIA_SUBTYPE_RAW = 1,
    ZV3_SPA_AUDIO_FORMAT_F32P = 0x206,
    ZV3_SPA_AUDIO_FORMAT_F64P = 0x207,
    ZV3_MAXIMUM_CHANNELS = 64,
    ZV3_MAXIMUM_NODES = 256,
    ZV3_MAXIMUM_NODE_TEXT = 512
};

typedef struct zv3_pw_thread_loop zv3_pw_thread_loop;
typedef struct zv3_pw_loop zv3_pw_loop;
typedef struct zv3_pw_stream zv3_pw_stream;
typedef struct zv3_pw_properties zv3_pw_properties;
typedef struct zv3_pw_context zv3_pw_context;
typedef struct zv3_pw_core zv3_pw_core;
typedef struct zv3_pw_registry zv3_pw_registry;
typedef struct zv3_spa_pod zv3_spa_pod;
typedef struct zv3_spa_command zv3_spa_command;
typedef struct zv3_pw_stream_control zv3_pw_stream_control;

typedef struct zv3_spa_list {
    struct zv3_spa_list *next;
    struct zv3_spa_list *prev;
} zv3_spa_list;

typedef struct {
    const void *funcs;
    void *data;
} zv3_spa_callbacks;

typedef struct {
    zv3_spa_list link;
    zv3_spa_callbacks callbacks;
    void (*removed)(void *hook);
    void *private_data;
} zv3_spa_hook;

typedef struct {
    const char *type;
    uint32_t version;
    zv3_spa_callbacks callbacks;
} zv3_spa_interface;

typedef struct {
    const char *key;
    const char *value;
} zv3_spa_dict_item;

typedef struct {
    uint32_t flags;
    uint32_t item_count;
    const zv3_spa_dict_item *items;
} zv3_spa_dict;

typedef struct {
    uint32_t offset;
    uint32_t size;
    int32_t stride;
    int32_t flags;
} zv3_spa_chunk;

typedef struct {
    uint32_t type;
    uint32_t flags;
    int64_t fd;
    uint32_t mapoffset;
    uint32_t maxsize;
    void *data;
    zv3_spa_chunk *chunk;
} zv3_spa_data;

typedef struct {
    uint32_t n_metas;
    uint32_t n_datas;
    void *metas;
    zv3_spa_data *datas;
} zv3_spa_buffer;

typedef struct {
    zv3_spa_buffer *buffer;
    void *user_data;
    uint64_t size;
    uint64_t requested;
    uint64_t time;
} zv3_pw_buffer;

typedef struct {
    uint32_t version;
    void (*destroy)(void *data);
    void (*state_changed)(
        void *data,
        int32_t old_state,
        int32_t state,
        const char *error
    );
    void (*control_info)(
        void *data,
        uint32_t id,
        const zv3_pw_stream_control *control
    );
    void (*io_changed)(
        void *data,
        uint32_t id,
        void *area,
        uint32_t size
    );
    void (*param_changed)(
        void *data,
        uint32_t id,
        const zv3_spa_pod *param
    );
    void (*add_buffer)(void *data, zv3_pw_buffer *buffer);
    void (*remove_buffer)(void *data, zv3_pw_buffer *buffer);
    void (*process)(void *data);
    void (*drained)(void *data);
    void (*command)(void *data, const zv3_spa_command *command);
    void (*trigger_done)(void *data);
} zv3_pw_stream_events;

typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t value;
    uint32_t padding;
} zv3_pod_value;

typedef struct {
    uint32_t key;
    uint32_t flags;
    zv3_pod_value value;
} zv3_pod_property;

typedef struct {
    uint32_t body_size;
    uint32_t pod_type;
    uint32_t object_type;
    uint32_t object_id;
    zv3_pod_property media_type;
    zv3_pod_property media_subtype;
    zv3_pod_property sample_format;
    zv3_pod_property sample_rate;
    zv3_pod_property channel_count;
} zv3_audio_format_pod;

typedef struct {
    uint32_t version;
    int32_t (*add_listener)(
        void *object,
        zv3_spa_hook *listener,
        const void *events,
        void *data
    );
    int32_t (*hello)(void *object, uint32_t version);
    int32_t (*sync)(void *object, uint32_t id, int32_t sequence);
    int32_t (*pong)(void *object, uint32_t id, int32_t sequence);
    int32_t (*error)(
        void *object,
        uint32_t id,
        int32_t sequence,
        int32_t result,
        const char *message
    );
    zv3_pw_registry *(*get_registry)(
        void *object,
        uint32_t version,
        size_t user_data_size
    );
    void *(*create_object)(
        void *object,
        const char *factory_name,
        const char *type,
        uint32_t version,
        const zv3_spa_dict *properties,
        size_t user_data_size
    );
    int32_t (*destroy)(void *object, void *proxy);
} zv3_pw_core_methods;

typedef struct {
    uint32_t version;
    int32_t (*add_listener)(
        void *object,
        zv3_spa_hook *listener,
        const void *events,
        void *data
    );
    void *(*bind)(
        void *object,
        uint32_t id,
        const char *type,
        uint32_t version,
        size_t user_data_size
    );
    int32_t (*destroy)(void *object, uint32_t id);
} zv3_pw_registry_methods;

typedef struct {
    uint32_t version;
    void (*info)(void *data, const void *info);
    void (*done)(void *data, uint32_t id, int32_t sequence);
    void (*ping)(void *data, uint32_t id, int32_t sequence);
    void (*error)(
        void *data,
        uint32_t id,
        int32_t sequence,
        int32_t result,
        const char *message
    );
    void (*remove_id)(void *data, uint32_t id);
    void (*bound_id)(void *data, uint32_t id, uint32_t global_id);
    void (*add_mem)(
        void *data,
        uint32_t id,
        uint32_t type,
        int32_t fd,
        uint32_t flags
    );
    void (*remove_mem)(void *data, uint32_t id);
    void (*bound_props)(
        void *data,
        uint32_t id,
        uint32_t global_id,
        const zv3_spa_dict *properties
    );
} zv3_pw_core_events;

typedef struct {
    uint32_t version;
    void (*global)(
        void *data,
        uint32_t id,
        uint32_t permissions,
        const char *type,
        uint32_t version,
        const zv3_spa_dict *properties
    );
    void (*global_remove)(void *data, uint32_t id);
} zv3_pw_registry_events;

typedef struct {
    uint32_t direction;
    uint32_t channels;
    char identifier[ZV3_MAXIMUM_NODE_TEXT];
    char name[ZV3_MAXIMUM_NODE_TEXT];
} zv3_pipewire_snapshot_entry;

struct zv3_pipewire_snapshot {
    size_t count;
    zv3_pipewire_snapshot_entry entries[ZV3_MAXIMUM_NODES];
};

typedef struct {
    void *library;
    void (*init)(int *argc, char ***argv);
    zv3_pw_context *(*context_new)(
        zv3_pw_loop *loop,
        zv3_pw_properties *properties,
        size_t user_data_size
    );
    void (*context_destroy)(zv3_pw_context *context);
    zv3_pw_core *(*context_connect)(
        zv3_pw_context *context,
        zv3_pw_properties *properties,
        size_t user_data_size
    );
    int32_t (*core_disconnect)(zv3_pw_core *core);
    zv3_pw_thread_loop *(*thread_loop_new)(const char *name, const void *props);
    void (*thread_loop_destroy)(zv3_pw_thread_loop *loop);
    zv3_pw_loop *(*thread_loop_get_loop)(zv3_pw_thread_loop *loop);
    int32_t (*thread_loop_start)(zv3_pw_thread_loop *loop);
    void (*thread_loop_stop)(zv3_pw_thread_loop *loop);
    void (*thread_loop_lock)(zv3_pw_thread_loop *loop);
    void (*thread_loop_unlock)(zv3_pw_thread_loop *loop);
    int32_t (*thread_loop_timed_wait)(zv3_pw_thread_loop *loop, int32_t seconds);
    void (*thread_loop_signal)(zv3_pw_thread_loop *loop, bool wait_for_accept);
    zv3_pw_properties *(*properties_new_string)(const char *args);
    void (*properties_free)(zv3_pw_properties *properties);
    int32_t (*properties_set)(
        zv3_pw_properties *properties,
        const char *key,
        const char *value
    );
    zv3_pw_stream *(*stream_new_simple)(
        zv3_pw_loop *loop,
        const char *name,
        zv3_pw_properties *properties,
        const zv3_pw_stream_events *events,
        void *data
    );
    void (*stream_destroy)(zv3_pw_stream *stream);
    int32_t (*stream_connect)(
        zv3_pw_stream *stream,
        int32_t direction,
        uint32_t target_id,
        uint32_t flags,
        const zv3_spa_pod *const *params,
        uint32_t parameter_count
    );
    zv3_pw_buffer *(*stream_dequeue_buffer)(zv3_pw_stream *stream);
    int32_t (*stream_queue_buffer)(
        zv3_pw_stream *stream,
        zv3_pw_buffer *buffer
    );
} zv3_pipewire_api;

typedef struct {
    struct zv3_pipewire_session *session;
    bool capture;
} zv3_stream_context;

struct zv3_pipewire_session {
    zv3_pipewire_api api;
    zv3_pw_thread_loop *loop;
    zv3_pw_stream *capture_stream;
    zv3_pw_stream *playback_stream;
    zv3_stream_context capture_context;
    zv3_stream_context playback_context;
    uint32_t sample_bytes;
    uint32_t maximum_frames;
    uint32_t input_channels;
    uint32_t output_channels;
    void *context;
    zv3_pipewire_process_fn process;
    zv3_pipewire_capture_fn capture;
    zv3_pipewire_render_fn render;
    uint8_t *capture_fifo;
    uint8_t *input_scratch;
    uint64_t fifo_capacity;
    _Atomic uint64_t fifo_read;
    _Atomic uint64_t fifo_write;
    _Atomic uint64_t processed;
    _Atomic uint64_t callback_failures;
    _Atomic uint64_t capture_underflows;
    _Atomic uint64_t capture_overflows;
    _Atomic uint64_t recoveries;
    _Atomic uint64_t device_failures;
    int32_t capture_state;
    int32_t playback_state;
};

static int32_t zv3_load_symbol(
    void *library,
    const char *name,
    void *target,
    size_t target_size
) {
    void *symbol = dlsym(library, name);
    if (symbol == NULL || target_size != sizeof(symbol))
        return -1;
    memcpy(target, &symbol, sizeof(symbol));
    return 0;
}

#define ZV3_LOAD(api, member, name) \
    zv3_load_symbol( \
        (api)->library, \
        (name), \
        &(api)->member, \
        sizeof((api)->member) \
    )

static int32_t zv3_load_api(zv3_pipewire_api *api) {
    memset(api, 0, sizeof(*api));
    api->library = dlopen("libpipewire-0.3.so.0", RTLD_NOW | RTLD_LOCAL);
    if (api->library == NULL)
        return -1;
    if (
        ZV3_LOAD(api, init, "pw_init") != 0 ||
        ZV3_LOAD(api, context_new, "pw_context_new") != 0 ||
        ZV3_LOAD(api, context_destroy, "pw_context_destroy") != 0 ||
        ZV3_LOAD(api, context_connect, "pw_context_connect") != 0 ||
        ZV3_LOAD(api, core_disconnect, "pw_core_disconnect") != 0 ||
        ZV3_LOAD(api, thread_loop_new, "pw_thread_loop_new") != 0 ||
        ZV3_LOAD(api, thread_loop_destroy, "pw_thread_loop_destroy") != 0 ||
        ZV3_LOAD(api, thread_loop_get_loop, "pw_thread_loop_get_loop") != 0 ||
        ZV3_LOAD(api, thread_loop_start, "pw_thread_loop_start") != 0 ||
        ZV3_LOAD(api, thread_loop_stop, "pw_thread_loop_stop") != 0 ||
        ZV3_LOAD(api, thread_loop_lock, "pw_thread_loop_lock") != 0 ||
        ZV3_LOAD(api, thread_loop_unlock, "pw_thread_loop_unlock") != 0 ||
        ZV3_LOAD(api, thread_loop_timed_wait, "pw_thread_loop_timed_wait") != 0 ||
        ZV3_LOAD(api, thread_loop_signal, "pw_thread_loop_signal") != 0 ||
        ZV3_LOAD(api, properties_new_string, "pw_properties_new_string") != 0 ||
        ZV3_LOAD(api, properties_free, "pw_properties_free") != 0 ||
        ZV3_LOAD(api, properties_set, "pw_properties_set") != 0 ||
        ZV3_LOAD(api, stream_new_simple, "pw_stream_new_simple") != 0 ||
        ZV3_LOAD(api, stream_destroy, "pw_stream_destroy") != 0 ||
        ZV3_LOAD(api, stream_connect, "pw_stream_connect") != 0 ||
        ZV3_LOAD(api, stream_dequeue_buffer, "pw_stream_dequeue_buffer") != 0 ||
        ZV3_LOAD(api, stream_queue_buffer, "pw_stream_queue_buffer") != 0
    ) {
        dlclose(api->library);
        memset(api, 0, sizeof(*api));
        return -1;
    }
    return 0;
}

static void zv3_unload_api(zv3_pipewire_api *api) {
    if (api->library != NULL)
        dlclose(api->library);
    memset(api, 0, sizeof(*api));
}

typedef struct {
    zv3_pipewire_api *api;
    zv3_pw_thread_loop *loop;
    zv3_pipewire_snapshot *snapshot;
    int32_t sequence;
    bool done;
    bool failed;
} zv3_snapshot_query;

static size_t zv3_bounded_length(const char *value, size_t capacity) {
    size_t length = 0;
    if (value == NULL)
        return 0;
    while (length < capacity && value[length] != '\0')
        ++length;
    return length;
}

static const char *zv3_dict_value(
    const zv3_spa_dict *properties,
    const char *key
) {
    uint32_t index;
    if (properties == NULL || properties->items == NULL)
        return NULL;
    for (index = 0; index < properties->item_count; ++index) {
        const zv3_spa_dict_item *item = &properties->items[index];
        if (
            item->key != NULL &&
            strcmp(item->key, key) == 0
        )
            return item->value;
    }
    return NULL;
}

static uint32_t zv3_parse_channels(const char *value) {
    char *end = NULL;
    unsigned long parsed;
    if (value == NULL || value[0] == '\0')
        return 0;
    parsed = strtoul(value, &end, 10);
    if (
        end == value ||
        *end != '\0' ||
        parsed == 0 ||
        parsed > ZV3_MAXIMUM_CHANNELS
    )
        return 0;
    return (uint32_t)parsed;
}

static bool zv3_snapshot_contains(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    const char *identifier
) {
    size_t index;
    for (index = 0; index < snapshot->count; ++index) {
        const zv3_pipewire_snapshot_entry *entry =
            &snapshot->entries[index];
        if (
            entry->direction == direction &&
            strcmp(entry->identifier, identifier) == 0
        )
            return true;
    }
    return false;
}

static void zv3_registry_global(
    void *data,
    uint32_t id,
    uint32_t permissions,
    const char *type,
    uint32_t version,
    const zv3_spa_dict *properties
) {
    zv3_snapshot_query *query = data;
    const char *media_class;
    const char *identifier;
    const char *name;
    uint32_t direction;
    uint32_t channels;
    size_t identifier_length;
    size_t name_length;
    zv3_pipewire_snapshot_entry *entry;
    (void)id;
    (void)permissions;
    (void)version;
    if (
        type == NULL ||
        strcmp(type, "PipeWire:Interface:Node") != 0
    )
        return;
    media_class = zv3_dict_value(properties, "media.class");
    if (media_class == NULL)
        return;
    if (strcmp(media_class, "Audio/Source") == 0)
        direction = 0;
    else if (strcmp(media_class, "Audio/Sink") == 0)
        direction = 1;
    else
        return;
    identifier = zv3_dict_value(properties, "node.name");
    channels = zv3_parse_channels(
        zv3_dict_value(properties, "audio.channels")
    );
    identifier_length = zv3_bounded_length(
        identifier,
        ZV3_MAXIMUM_NODE_TEXT
    );
    if (
        identifier_length == 0 ||
        identifier_length == ZV3_MAXIMUM_NODE_TEXT ||
        channels == 0 ||
        query->snapshot->count == ZV3_MAXIMUM_NODES ||
        zv3_snapshot_contains(
            query->snapshot,
            direction,
            identifier
        )
    )
        return;
    name = zv3_dict_value(properties, "node.description");
    if (name == NULL || name[0] == '\0')
        name = zv3_dict_value(properties, "node.nick");
    if (name == NULL || name[0] == '\0')
        name = identifier;
    name_length = zv3_bounded_length(name, ZV3_MAXIMUM_NODE_TEXT);
    if (name_length == 0 || name_length == ZV3_MAXIMUM_NODE_TEXT)
        return;
    entry = &query->snapshot->entries[query->snapshot->count];
    memset(entry, 0, sizeof(*entry));
    entry->direction = direction;
    entry->channels = channels;
    memcpy(entry->identifier, identifier, identifier_length);
    memcpy(entry->name, name, name_length);
    query->snapshot->count += 1;
}

static void zv3_core_done(
    void *data,
    uint32_t id,
    int32_t sequence
) {
    zv3_snapshot_query *query = data;
    (void)id;
    if (sequence != query->sequence)
        return;
    query->done = true;
    query->api->thread_loop_signal(query->loop, false);
}

static void zv3_core_error(
    void *data,
    uint32_t id,
    int32_t sequence,
    int32_t result,
    const char *message
) {
    zv3_snapshot_query *query = data;
    (void)id;
    (void)sequence;
    (void)result;
    (void)message;
    query->failed = true;
    query->api->thread_loop_signal(query->loop, false);
}

static const zv3_pw_core_events zv3_snapshot_core_events = {
    .version = 0,
    .done = zv3_core_done,
    .error = zv3_core_error
};

static const zv3_pw_registry_events zv3_snapshot_registry_events = {
    .version = 0,
    .global = zv3_registry_global
};

static const zv3_pw_core_methods *zv3_core_methods(
    zv3_pw_core *core,
    void **object
) {
    zv3_spa_interface *interface = (zv3_spa_interface *)core;
    if (
        interface == NULL ||
        interface->callbacks.funcs == NULL ||
        interface->callbacks.data == NULL
    )
        return NULL;
    *object = interface->callbacks.data;
    return interface->callbacks.funcs;
}

static const zv3_pw_registry_methods *zv3_registry_methods(
    zv3_pw_registry *registry,
    void **object
) {
    zv3_spa_interface *interface = (zv3_spa_interface *)registry;
    if (
        interface == NULL ||
        interface->callbacks.funcs == NULL ||
        interface->callbacks.data == NULL
    )
        return NULL;
    *object = interface->callbacks.data;
    return interface->callbacks.funcs;
}

static int32_t zv3_query_snapshot(
    zv3_pipewire_api *api,
    zv3_pipewire_snapshot *snapshot
) {
    zv3_pw_thread_loop *loop = NULL;
    zv3_pw_loop *main_loop;
    zv3_pw_context *context = NULL;
    zv3_pw_core *core = NULL;
    zv3_pw_registry *registry = NULL;
    const zv3_pw_core_methods *core_methods;
    const zv3_pw_registry_methods *registry_methods;
    void *core_object = NULL;
    void *registry_object = NULL;
    zv3_spa_hook core_listener;
    zv3_spa_hook registry_listener;
    zv3_snapshot_query query;
    bool started = false;
    bool locked = false;
    int32_t result = -1;
    memset(&core_listener, 0, sizeof(core_listener));
    memset(&registry_listener, 0, sizeof(registry_listener));
    memset(snapshot, 0, sizeof(*snapshot));
    loop = api->thread_loop_new("zig-vst3-pipewire-discovery", NULL);
    if (loop == NULL)
        goto cleanup;
    main_loop = api->thread_loop_get_loop(loop);
    if (main_loop == NULL)
        goto cleanup;
    api->thread_loop_lock(loop);
    locked = true;
    if (api->thread_loop_start(loop) < 0)
        goto cleanup;
    started = true;
    context = api->context_new(main_loop, NULL, 0);
    if (context == NULL)
        goto cleanup;
    core = api->context_connect(context, NULL, 0);
    if (core == NULL)
        goto cleanup;
    query = (zv3_snapshot_query){
        .api = api,
        .loop = loop,
        .snapshot = snapshot
    };
    core_methods = zv3_core_methods(core, &core_object);
    if (
        core_methods == NULL ||
        core_methods->add_listener == NULL ||
        core_methods->sync == NULL ||
        core_methods->get_registry == NULL ||
        core_methods->add_listener(
            core_object,
            &core_listener,
            &zv3_snapshot_core_events,
            &query
        ) < 0
    )
        goto cleanup;
    registry = core_methods->get_registry(core_object, 3, 0);
    registry_methods = zv3_registry_methods(registry, &registry_object);
    if (
        registry_methods == NULL ||
        registry_methods->add_listener == NULL
    )
        goto cleanup;
    if (registry_methods->add_listener(
        registry_object,
        &registry_listener,
        &zv3_snapshot_registry_events,
        &query
    ) < 0)
        goto cleanup;
    query.sequence = core_methods->sync(core_object, 0, 0);
    if (query.sequence < 0)
        goto cleanup;
    while (!query.done && !query.failed) {
        if (api->thread_loop_timed_wait(loop, 2) != 0)
            goto cleanup;
    }
    if (query.failed)
        goto cleanup;
    result = 0;

cleanup:
    if (core != NULL)
        api->core_disconnect(core);
    if (context != NULL)
        api->context_destroy(context);
    if (locked)
        api->thread_loop_unlock(loop);
    if (started)
        api->thread_loop_stop(loop);
    if (loop != NULL)
        api->thread_loop_destroy(loop);
    return result;
}

static zv3_pod_property zv3_id_property(uint32_t key, uint32_t value) {
    zv3_pod_property result = {
        .key = key,
        .flags = 0,
        .value = {
            .size = sizeof(uint32_t),
            .type = ZV3_SPA_TYPE_ID,
            .value = value,
            .padding = 0
        }
    };
    return result;
}

static zv3_pod_property zv3_int_property(uint32_t key, uint32_t value) {
    zv3_pod_property result = {
        .key = key,
        .flags = 0,
        .value = {
            .size = sizeof(uint32_t),
            .type = ZV3_SPA_TYPE_INT,
            .value = value,
            .padding = 0
        }
    };
    return result;
}

static zv3_audio_format_pod zv3_audio_format(
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t channel_count
) {
    zv3_audio_format_pod result = {
        .body_size = sizeof(zv3_audio_format_pod) - 2u * sizeof(uint32_t),
        .pod_type = ZV3_SPA_TYPE_OBJECT,
        .object_type = ZV3_SPA_TYPE_OBJECT_FORMAT,
        .object_id = ZV3_SPA_PARAM_ENUM_FORMAT,
        .media_type = zv3_id_property(
            ZV3_SPA_FORMAT_MEDIA_TYPE,
            ZV3_SPA_MEDIA_TYPE_AUDIO
        ),
        .media_subtype = zv3_id_property(
            ZV3_SPA_FORMAT_MEDIA_SUBTYPE,
            ZV3_SPA_MEDIA_SUBTYPE_RAW
        ),
        .sample_format = zv3_id_property(
            ZV3_SPA_FORMAT_AUDIO_FORMAT,
            sample_bytes == sizeof(float)
                ? ZV3_SPA_AUDIO_FORMAT_F32P
                : ZV3_SPA_AUDIO_FORMAT_F64P
        ),
        .sample_rate = zv3_int_property(
            ZV3_SPA_FORMAT_AUDIO_RATE,
            sample_rate
        ),
        .channel_count = zv3_int_property(
            ZV3_SPA_FORMAT_AUDIO_CHANNELS,
            channel_count
        )
    };
    return result;
}

static void zv3_stream_state_changed(
    void *data,
    int32_t old_state,
    int32_t state,
    const char *error
) {
    zv3_stream_context *stream_context = data;
    zv3_pipewire_session *session = stream_context->session;
    int32_t *stored_state = stream_context->capture
        ? &session->capture_state
        : &session->playback_state;
    (void)error;
    *stored_state = state;
    if (state == ZV3_PW_STREAM_STATE_ERROR)
        atomic_fetch_add_explicit(
            &session->device_failures,
            1,
            memory_order_relaxed
        );
    if (
        old_state == ZV3_PW_STREAM_STATE_ERROR &&
        state >= ZV3_PW_STREAM_STATE_PAUSED
    )
        atomic_fetch_add_explicit(
            &session->recoveries,
            1,
            memory_order_relaxed
        );
    session->api.thread_loop_signal(session->loop, false);
}

static int32_t zv3_channel_views(
    zv3_pipewire_session *session,
    zv3_pw_buffer *buffer,
    uint32_t expected_channels,
    const void **views,
    uint32_t *frames
) {
    uint32_t frame_count = UINT32_MAX;
    uint32_t channel;
    if (
        buffer == NULL ||
        buffer->buffer == NULL ||
        buffer->buffer->datas == NULL ||
        buffer->buffer->n_datas != expected_channels
    )
        return -1;
    for (channel = 0; channel < expected_channels; ++channel) {
        zv3_spa_data *data = &buffer->buffer->datas[channel];
        uint32_t offset;
        uint32_t available;
        if (
            data->data == NULL ||
            data->chunk == NULL ||
            data->maxsize == 0
        )
            return -1;
        offset = data->chunk->offset % data->maxsize;
        available = data->chunk->size;
        if (
            available > data->maxsize ||
            offset > data->maxsize - available
        )
            return -1;
        views[channel] = (const uint8_t *)data->data + offset;
        if (available / session->sample_bytes < frame_count)
            frame_count = available / session->sample_bytes;
    }
    if (frame_count > session->maximum_frames)
        return -1;
    *frames = frame_count;
    return 0;
}

static int32_t zv3_output_views(
    zv3_pipewire_session *session,
    zv3_pw_buffer *buffer,
    void **views,
    uint32_t *frames
) {
    uint32_t frame_count = session->maximum_frames;
    uint32_t channel;
    if (
        buffer == NULL ||
        buffer->buffer == NULL ||
        buffer->buffer->datas == NULL ||
        buffer->buffer->n_datas != session->output_channels
    )
        return -1;
    if (buffer->requested != 0 && buffer->requested < frame_count)
        frame_count = (uint32_t)buffer->requested;
    for (channel = 0; channel < session->output_channels; ++channel) {
        zv3_spa_data *data = &buffer->buffer->datas[channel];
        uint32_t capacity;
        if (
            data->data == NULL ||
            data->chunk == NULL
        )
            return -1;
        capacity = data->maxsize / session->sample_bytes;
        if (capacity < frame_count)
            frame_count = capacity;
        views[channel] = data->data;
    }
    if (frame_count == 0)
        return -1;
    for (channel = 0; channel < session->output_channels; ++channel) {
        zv3_spa_data *data = &buffer->buffer->datas[channel];
        data->chunk->offset = 0;
        data->chunk->size = frame_count * session->sample_bytes;
        data->chunk->stride = (int32_t)session->sample_bytes;
        data->chunk->flags = 0;
    }
    buffer->size = frame_count;
    *frames = frame_count;
    return 0;
}

static void zv3_clear_outputs(
    zv3_pipewire_session *session,
    void **views,
    uint32_t frame_count
) {
    uint32_t channel;
    for (channel = 0; channel < session->output_channels; ++channel)
        memset(
            views[channel],
            0,
            (size_t)frame_count * session->sample_bytes
        );
}

static void zv3_fifo_write(
    zv3_pipewire_session *session,
    const void *const *channels,
    uint32_t frame_count
) {
    uint64_t read = atomic_load_explicit(
        &session->fifo_read,
        memory_order_acquire
    );
    uint64_t write = atomic_load_explicit(
        &session->fifo_write,
        memory_order_relaxed
    );
    uint32_t channel;
    uint32_t frame;
    if (frame_count > session->fifo_capacity - (write - read)) {
        atomic_fetch_add_explicit(
            &session->capture_overflows,
            1,
            memory_order_relaxed
        );
        return;
    }
    for (channel = 0; channel < session->input_channels; ++channel) {
        const uint8_t *source = channels[channel];
        uint8_t *destination = session->capture_fifo +
            (uint64_t)channel * session->fifo_capacity * session->sample_bytes;
        for (frame = 0; frame < frame_count; ++frame) {
            uint64_t index = (write + frame) % session->fifo_capacity;
            memcpy(
                destination + index * session->sample_bytes,
                source + (size_t)frame * session->sample_bytes,
                session->sample_bytes
            );
        }
    }
    atomic_store_explicit(
        &session->fifo_write,
        write + frame_count,
        memory_order_release
    );
}

static void zv3_fifo_read(
    zv3_pipewire_session *session,
    const void **views,
    uint32_t frame_count
) {
    uint64_t read = atomic_load_explicit(
        &session->fifo_read,
        memory_order_relaxed
    );
    uint64_t write = atomic_load_explicit(
        &session->fifo_write,
        memory_order_acquire
    );
    uint64_t available = write - read;
    uint32_t copied = available < frame_count
        ? (uint32_t)available
        : frame_count;
    uint32_t channel;
    uint32_t frame;
    if (copied < frame_count)
        atomic_fetch_add_explicit(
            &session->capture_underflows,
            1,
            memory_order_relaxed
        );
    for (channel = 0; channel < session->input_channels; ++channel) {
        const uint8_t *source = session->capture_fifo +
            (uint64_t)channel * session->fifo_capacity * session->sample_bytes;
        uint8_t *destination = session->input_scratch +
            (size_t)channel * session->maximum_frames * session->sample_bytes;
        for (frame = 0; frame < copied; ++frame) {
            uint64_t index = (read + frame) % session->fifo_capacity;
            memcpy(
                destination + (size_t)frame * session->sample_bytes,
                source + index * session->sample_bytes,
                session->sample_bytes
            );
        }
        memset(
            destination + (size_t)copied * session->sample_bytes,
            0,
            (size_t)(frame_count - copied) * session->sample_bytes
        );
        views[channel] = destination;
    }
    atomic_store_explicit(
        &session->fifo_read,
        read + copied,
        memory_order_release
    );
}

static void zv3_capture_process(void *data) {
    zv3_stream_context *stream_context = data;
    zv3_pipewire_session *session = stream_context->session;
    zv3_pw_buffer *buffer = session->api.stream_dequeue_buffer(
        session->capture_stream
    );
    const void *views[ZV3_MAXIMUM_CHANNELS];
    uint32_t frame_count = 0;
    int32_t result = -1;
    if (
        zv3_channel_views(
            session,
            buffer,
            session->input_channels,
            views,
            &frame_count
        ) == 0
    ) {
        if (session->capture != NULL)
            result = session->capture(
                session->context,
                frame_count,
                views
            );
        else if (session->output_channels == 0)
            result = session->process(
                session->context,
                frame_count,
                views,
                NULL
            );
        else {
            zv3_fifo_write(session, views, frame_count);
            result = 0;
        }
    }
    if (result != 0)
        atomic_fetch_add_explicit(
            &session->callback_failures,
            1,
            memory_order_relaxed
        );
    if (buffer != NULL)
        session->api.stream_queue_buffer(session->capture_stream, buffer);
}

static void zv3_playback_process(void *data) {
    zv3_stream_context *stream_context = data;
    zv3_pipewire_session *session = stream_context->session;
    zv3_pw_buffer *buffer = session->api.stream_dequeue_buffer(
        session->playback_stream
    );
    void *outputs[ZV3_MAXIMUM_CHANNELS];
    const void *inputs[ZV3_MAXIMUM_CHANNELS];
    uint32_t frame_count = 0;
    int32_t result = -1;
    if (zv3_output_views(session, buffer, outputs, &frame_count) == 0) {
        if (session->render != NULL)
            result = session->render(
                session->context,
                frame_count,
                outputs
            );
        else {
            if (session->input_channels != 0)
                zv3_fifo_read(session, inputs, frame_count);
            result = session->process(
                session->context,
                frame_count,
                session->input_channels == 0 ? NULL : inputs,
                outputs
            );
        }
        if (result != 0)
            zv3_clear_outputs(session, outputs, frame_count);
    }
    if (result != 0)
        atomic_fetch_add_explicit(
            &session->callback_failures,
            1,
            memory_order_relaxed
        );
    else
        atomic_fetch_add_explicit(
            &session->processed,
            1,
            memory_order_relaxed
        );
    if (buffer != NULL)
        session->api.stream_queue_buffer(session->playback_stream, buffer);
}

static const zv3_pw_stream_events zv3_capture_events = {
    .version = 0,
    .state_changed = zv3_stream_state_changed,
    .process = zv3_capture_process
};

static const zv3_pw_stream_events zv3_playback_events = {
    .version = 0,
    .state_changed = zv3_stream_state_changed,
    .process = zv3_playback_process
};

static int32_t zv3_set_stream_properties(
    zv3_pipewire_api *api,
    zv3_pw_properties *properties,
    bool capture
) {
    if (
        properties == NULL ||
        api->properties_set(properties, "media.type", "Audio") < 0 ||
        api->properties_set(
            properties,
            "media.category",
            capture ? "Capture" : "Playback"
        ) < 0 ||
        api->properties_set(
            properties,
            "media.role",
            "Production"
        ) < 0 ||
        api->properties_set(
            properties,
            "node.dont-reconnect",
            "false"
        ) < 0
    )
        return -1;
    return 0;
}

static bool zv3_stream_ready(int32_t state) {
    return
        state == ZV3_PW_STREAM_STATE_PAUSED ||
        state == ZV3_PW_STREAM_STATE_STREAMING;
}

static bool zv3_session_ready(const zv3_pipewire_session *session) {
    return
        (
            session->capture_stream == NULL ||
            zv3_stream_ready(session->capture_state)
        ) &&
        (
            session->playback_stream == NULL ||
            zv3_stream_ready(session->playback_state)
        );
}

static bool zv3_session_failed(const zv3_pipewire_session *session) {
    return
        session->capture_state == ZV3_PW_STREAM_STATE_ERROR ||
        session->playback_state == ZV3_PW_STREAM_STATE_ERROR;
}

static void zv3_destroy_streams(zv3_pipewire_session *session) {
    if (session->playback_stream != NULL) {
        session->api.stream_destroy(session->playback_stream);
        session->playback_stream = NULL;
    }
    if (session->capture_stream != NULL) {
        session->api.stream_destroy(session->capture_stream);
        session->capture_stream = NULL;
    }
}

static void zv3_free_session(zv3_pipewire_session *session) {
    free(session->capture_fifo);
    free(session->input_scratch);
    zv3_unload_api(&session->api);
    free(session);
}

static int32_t zv3_start_internal(
    const uint8_t *input_target,
    size_t input_target_length,
    const uint8_t *output_target,
    size_t output_target_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_pipewire_process_fn process,
    zv3_pipewire_capture_fn capture,
    zv3_pipewire_render_fn render,
    zv3_pipewire_session **output
) {
    zv3_pipewire_session *session;
    zv3_pw_loop *loop;
    uint64_t fifo_capacity;
    size_t fifo_bytes = 0;
    size_t scratch_bytes = 0;
    char input_target_text[ZV3_MAXIMUM_NODE_TEXT];
    char output_target_text[ZV3_MAXIMUM_NODE_TEXT];
    bool started = false;
    bool locked = false;
    if (
        output == NULL ||
        context == NULL ||
        sample_rate == 0 ||
        maximum_frames == 0 ||
        (sample_bytes != sizeof(float) && sample_bytes != sizeof(double)) ||
        (input_channels == 0 && output_channels == 0) ||
        input_channels > ZV3_MAXIMUM_CHANNELS ||
        output_channels > ZV3_MAXIMUM_CHANNELS ||
        ((process == NULL) == (capture == NULL || render == NULL)) ||
        ((capture != NULL || render != NULL) &&
            (input_channels == 0 || output_channels == 0)) ||
        input_target_length >= ZV3_MAXIMUM_NODE_TEXT ||
        output_target_length >= ZV3_MAXIMUM_NODE_TEXT ||
        (input_target_length != 0 && input_target == NULL) ||
        (output_target_length != 0 && output_target == NULL)
    )
        return -1;
    if (input_target_length != 0)
        memcpy(input_target_text, input_target, input_target_length);
    input_target_text[input_target_length] = '\0';
    if (output_target_length != 0)
        memcpy(output_target_text, output_target, output_target_length);
    output_target_text[output_target_length] = '\0';
    fifo_capacity = (uint64_t)maximum_frames * 4u;
    if (process != NULL && input_channels != 0 && output_channels != 0) {
        if (
            fifo_capacity > SIZE_MAX / sample_bytes ||
            fifo_capacity * sample_bytes > SIZE_MAX / input_channels ||
            (size_t)maximum_frames > SIZE_MAX / sample_bytes ||
            (size_t)maximum_frames * sample_bytes > SIZE_MAX / input_channels
        )
            return -1;
        fifo_bytes = (size_t)(
            fifo_capacity * sample_bytes * input_channels
        );
        scratch_bytes = (size_t)(
            maximum_frames * sample_bytes * input_channels
        );
    }
    session = calloc(1, sizeof(*session));
    if (session == NULL)
        return -1;
    session->sample_bytes = sample_bytes;
    session->maximum_frames = maximum_frames;
    session->input_channels = input_channels;
    session->output_channels = output_channels;
    session->context = context;
    session->process = process;
    session->capture = capture;
    session->render = render;
    session->fifo_capacity = fifo_capacity;
    session->capture_context = (zv3_stream_context){
        .session = session,
        .capture = true
    };
    session->playback_context = (zv3_stream_context){
        .session = session,
        .capture = false
    };
    if (fifo_bytes != 0) {
        session->capture_fifo = calloc(1, fifo_bytes);
        session->input_scratch = calloc(1, scratch_bytes);
        if (
            session->capture_fifo == NULL ||
            session->input_scratch == NULL
        )
            goto error;
    }
    if (zv3_load_api(&session->api) != 0)
        goto error;
    session->api.init(NULL, NULL);
    session->loop = session->api.thread_loop_new("zig-vst3-pipewire", NULL);
    if (session->loop == NULL)
        goto error;
    loop = session->api.thread_loop_get_loop(session->loop);
    if (loop == NULL)
        goto error;
    session->api.thread_loop_lock(session->loop);
    locked = true;
    if (session->api.thread_loop_start(session->loop) < 0)
        goto error;
    started = true;
    if (input_channels != 0) {
        zv3_pw_properties *properties =
            session->api.properties_new_string("");
        zv3_audio_format_pod format = zv3_audio_format(
            sample_bytes,
            sample_rate,
            input_channels
        );
        const zv3_spa_pod *params[] = {
            (const zv3_spa_pod *)&format
        };
        if (zv3_set_stream_properties(&session->api, properties, true) != 0) {
            if (properties != NULL)
                session->api.properties_free(properties);
            goto error;
        }
        if (
            input_target_length != 0 &&
            session->api.properties_set(
                properties,
                "target.object",
                input_target_text
            ) < 0
        ) {
            session->api.properties_free(properties);
            goto error;
        }
        session->capture_stream = session->api.stream_new_simple(
            loop,
            "zig-vst3 capture",
            properties,
            &zv3_capture_events,
            &session->capture_context
        );
        if (
            session->capture_stream == NULL ||
            session->api.stream_connect(
                session->capture_stream,
                ZV3_PW_DIRECTION_INPUT,
                ZV3_PW_ID_ANY,
                ZV3_PW_STREAM_FLAG_AUTOCONNECT |
                    ZV3_PW_STREAM_FLAG_MAP_BUFFERS |
                    ZV3_PW_STREAM_FLAG_RT_PROCESS,
                params,
                1
            ) < 0
        )
            goto error;
    }
    if (output_channels != 0) {
        zv3_pw_properties *properties =
            session->api.properties_new_string("");
        zv3_audio_format_pod format = zv3_audio_format(
            sample_bytes,
            sample_rate,
            output_channels
        );
        const zv3_spa_pod *params[] = {
            (const zv3_spa_pod *)&format
        };
        if (zv3_set_stream_properties(&session->api, properties, false) != 0) {
            if (properties != NULL)
                session->api.properties_free(properties);
            goto error;
        }
        if (
            output_target_length != 0 &&
            session->api.properties_set(
                properties,
                "target.object",
                output_target_text
            ) < 0
        ) {
            session->api.properties_free(properties);
            goto error;
        }
        session->playback_stream = session->api.stream_new_simple(
            loop,
            "zig-vst3 playback",
            properties,
            &zv3_playback_events,
            &session->playback_context
        );
        if (
            session->playback_stream == NULL ||
            session->api.stream_connect(
                session->playback_stream,
                ZV3_PW_DIRECTION_OUTPUT,
                ZV3_PW_ID_ANY,
                ZV3_PW_STREAM_FLAG_AUTOCONNECT |
                    ZV3_PW_STREAM_FLAG_MAP_BUFFERS |
                    ZV3_PW_STREAM_FLAG_RT_PROCESS,
                params,
                1
            ) < 0
        )
            goto error;
    }
    while (!zv3_session_ready(session) && !zv3_session_failed(session)) {
        if (session->api.thread_loop_timed_wait(session->loop, 2) != 0)
            goto error;
    }
    if (zv3_session_failed(session))
        goto error;
    session->api.thread_loop_unlock(session->loop);
    *output = session;
    return 0;

error:
    if (locked)
        zv3_destroy_streams(session);
    if (locked)
        session->api.thread_loop_unlock(session->loop);
    if (started)
        session->api.thread_loop_stop(session->loop);
    if (session->loop != NULL)
        session->api.thread_loop_destroy(session->loop);
    zv3_free_session(session);
    return -1;
}

int32_t zv3_pipewire_available(void) {
    zv3_pipewire_api api;
    if (zv3_load_api(&api) != 0)
        return 0;
    zv3_unload_api(&api);
    return 1;
}

int32_t zv3_pipewire_snapshot_create(zv3_pipewire_snapshot **output) {
    zv3_pipewire_snapshot *snapshot;
    zv3_pipewire_api api;
    int32_t result;
    if (output == NULL)
        return -1;
    snapshot = calloc(1, sizeof(*snapshot));
    if (snapshot == NULL)
        return -1;
    if (zv3_load_api(&api) != 0) {
        free(snapshot);
        return -1;
    }
    api.init(NULL, NULL);
    result = zv3_query_snapshot(&api, snapshot);
    zv3_unload_api(&api);
    if (result != 0) {
        free(snapshot);
        return -1;
    }
    *output = snapshot;
    return 0;
}

static const zv3_pipewire_snapshot_entry *zv3_snapshot_entry(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index
) {
    size_t current;
    size_t matched = 0;
    if (snapshot == NULL || direction > 1)
        return NULL;
    for (current = 0; current < snapshot->count; ++current) {
        const zv3_pipewire_snapshot_entry *entry =
            &snapshot->entries[current];
        if (entry->direction != direction)
            continue;
        if (matched == index)
            return entry;
        matched += 1;
    }
    return NULL;
}

size_t zv3_pipewire_snapshot_count(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction
) {
    size_t current;
    size_t count = 0;
    if (snapshot == NULL || direction > 1)
        return 0;
    for (current = 0; current < snapshot->count; ++current) {
        if (snapshot->entries[current].direction == direction)
            count += 1;
    }
    return count;
}

static int32_t zv3_copy_snapshot_text(
    const char *value,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    size_t length = zv3_bounded_length(value, ZV3_MAXIMUM_NODE_TEXT);
    if (
        length == 0 ||
        length == ZV3_MAXIMUM_NODE_TEXT ||
        output == NULL ||
        output_length == NULL ||
        output_capacity < length
    )
        return -1;
    memcpy(output, value, length);
    *output_length = length;
    return 0;
}

int32_t zv3_pipewire_snapshot_identifier(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    const zv3_pipewire_snapshot_entry *entry =
        zv3_snapshot_entry(snapshot, direction, index);
    if (entry == NULL)
        return -1;
    return zv3_copy_snapshot_text(
        entry->identifier,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_pipewire_snapshot_name(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    const zv3_pipewire_snapshot_entry *entry =
        zv3_snapshot_entry(snapshot, direction, index);
    if (entry == NULL)
        return -1;
    return zv3_copy_snapshot_text(
        entry->name,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_pipewire_snapshot_channels(
    const zv3_pipewire_snapshot *snapshot,
    uint32_t direction,
    size_t index,
    uint32_t *output
) {
    const zv3_pipewire_snapshot_entry *entry =
        zv3_snapshot_entry(snapshot, direction, index);
    if (entry == NULL || output == NULL)
        return -1;
    *output = entry->channels;
    return 0;
}

void zv3_pipewire_snapshot_destroy(zv3_pipewire_snapshot *snapshot) {
    free(snapshot);
}

int32_t zv3_pipewire_start(
    const uint8_t *input_target,
    size_t input_target_length,
    const uint8_t *output_target,
    size_t output_target_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_pipewire_process_fn process,
    zv3_pipewire_session **output
) {
    return zv3_start_internal(
        input_target,
        input_target_length,
        output_target,
        output_target_length,
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

int32_t zv3_pipewire_start_split(
    const uint8_t *input_target,
    size_t input_target_length,
    const uint8_t *output_target,
    size_t output_target_length,
    uint32_t sample_bytes,
    uint32_t sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_pipewire_capture_fn capture,
    zv3_pipewire_render_fn render,
    zv3_pipewire_session **output
) {
    return zv3_start_internal(
        input_target,
        input_target_length,
        output_target,
        output_target_length,
        sample_bytes,
        sample_rate,
        maximum_frames,
        input_channels,
        output_channels,
        context,
        NULL,
        capture,
        render,
        output
    );
}

void zv3_pipewire_get_statistics(
    const zv3_pipewire_session *session,
    zv3_pipewire_statistics *output
) {
    if (session == NULL || output == NULL)
        return;
    *output = (zv3_pipewire_statistics){
        .processed = atomic_load_explicit(
            &session->processed,
            memory_order_relaxed
        ),
        .callback_failures = atomic_load_explicit(
            &session->callback_failures,
            memory_order_relaxed
        ),
        .capture_underflows = atomic_load_explicit(
            &session->capture_underflows,
            memory_order_relaxed
        ),
        .capture_overflows = atomic_load_explicit(
            &session->capture_overflows,
            memory_order_relaxed
        ),
        .recoveries = atomic_load_explicit(
            &session->recoveries,
            memory_order_relaxed
        ),
        .device_failures = atomic_load_explicit(
            &session->device_failures,
            memory_order_relaxed
        )
    };
}

void zv3_pipewire_stop(
    zv3_pipewire_session *session,
    zv3_pipewire_statistics *final_statistics
) {
    if (session == NULL)
        return;
    session->api.thread_loop_lock(session->loop);
    zv3_destroy_streams(session);
    session->api.thread_loop_unlock(session->loop);
    session->api.thread_loop_stop(session->loop);
    session->api.thread_loop_destroy(session->loop);
    session->loop = NULL;
    zv3_pipewire_get_statistics(session, final_statistics);
    zv3_free_session(session);
}
