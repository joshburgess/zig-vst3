#include "../zig-vst3-plugin/src/plugin/pipewire_shim.c"

static int32_t test_format_descriptor(void) {
    zv3_audio_format_pod format = zv3_audio_format(sizeof(float), 48000, 2);
    if (sizeof(format) != 136 || format.body_size != 128)
        return 1;
    if (
        format.pod_type != ZV3_SPA_TYPE_OBJECT ||
        format.object_type != ZV3_SPA_TYPE_OBJECT_FORMAT ||
        format.object_id != ZV3_SPA_PARAM_ENUM_FORMAT
    )
        return 2;
    if (
        format.sample_format.value.value != ZV3_SPA_AUDIO_FORMAT_F32P ||
        format.sample_rate.value.value != 48000 ||
        format.channel_count.value.value != 2
    )
        return 3;
    format = zv3_audio_format(sizeof(double), 96000, 8);
    if (format.sample_format.value.value != ZV3_SPA_AUDIO_FORMAT_F64P)
        return 4;
    return 0;
}

static int32_t test_capture_fifo(void) {
    zv3_pipewire_session session;
    float fifo[2][8] = {{0}};
    float scratch[2][4] = {{0}};
    float first[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    float second[4] = {5.0f, 6.0f, 7.0f, 8.0f};
    const void *source[2] = {first, second};
    const void *views[2] = {NULL, NULL};
    memset(&session, 0, sizeof(session));
    session.sample_bytes = sizeof(float);
    session.maximum_frames = 4;
    session.input_channels = 2;
    session.capture_fifo = (uint8_t *)fifo;
    session.input_scratch = (uint8_t *)scratch;
    session.fifo_capacity = 8;
    zv3_fifo_write(&session, source, 4);
    zv3_fifo_read(&session, views, 4);
    if (views[0] == NULL || views[1] == NULL)
        return 9;
    if (
        memcmp(views[0], first, sizeof(first)) != 0 ||
        memcmp(views[1], second, sizeof(second)) != 0
    )
        return 10;
    zv3_fifo_read(&session, views, 2);
    if (
        atomic_load_explicit(
            &session.capture_underflows,
            memory_order_relaxed
        ) != 1
    )
        return 11;
    if (
        ((const float *)views[0])[0] != 0.0f ||
        ((const float *)views[1])[1] != 0.0f
    )
        return 12;
    zv3_fifo_write(&session, source, 4);
    zv3_fifo_write(&session, source, 4);
    zv3_fifo_write(&session, source, 1);
    if (
        atomic_load_explicit(
            &session.capture_overflows,
            memory_order_relaxed
        ) != 1
    )
        return 13;
    return 0;
}

static int32_t test_planar_views(void) {
    zv3_pipewire_session session;
    float left[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    float right[4] = {5.0f, 6.0f, 7.0f, 8.0f};
    zv3_spa_chunk chunks[2] = {
        {.size = sizeof(left), .stride = sizeof(float)},
        {.size = sizeof(right), .stride = sizeof(float)}
    };
    zv3_spa_data data[2] = {
        {
            .maxsize = sizeof(left),
            .data = left,
            .chunk = &chunks[0]
        },
        {
            .maxsize = sizeof(right),
            .data = right,
            .chunk = &chunks[1]
        }
    };
    zv3_spa_buffer spa_buffer = {
        .n_datas = 2,
        .datas = data
    };
    zv3_pw_buffer buffer = {
        .buffer = &spa_buffer
    };
    const void *inputs[2] = {NULL, NULL};
    void *outputs[2] = {NULL, NULL};
    uint32_t frames = 0;
    memset(&session, 0, sizeof(session));
    session.sample_bytes = sizeof(float);
    session.maximum_frames = 4;
    session.input_channels = 2;
    session.output_channels = 2;
    if (
        zv3_channel_views(&session, &buffer, 2, inputs, &frames) != 0 ||
        frames != 4 ||
        inputs[0] != left ||
        inputs[1] != right
    )
        return 20;
    chunks[0].size = 0;
    chunks[1].size = 0;
    buffer.requested = 3;
    if (
        zv3_output_views(&session, &buffer, outputs, &frames) != 0 ||
        frames != 3 ||
        chunks[0].size != 3 * sizeof(float) ||
        chunks[1].stride != sizeof(float)
    )
        return 21;
    zv3_clear_outputs(&session, outputs, frames);
    if (left[0] != 0.0f || right[2] != 0.0f)
        return 22;
    spa_buffer.n_datas = 1;
    if (zv3_output_views(&session, &buffer, outputs, &frames) == 0)
        return 23;
    return 0;
}

int32_t zv3_pipewire_shim_self_test(void) {
    int32_t result = test_format_descriptor();
    if (result != 0)
        return result;
    result = test_capture_fifo();
    if (result != 0)
        return result;
    return test_planar_views();
}
