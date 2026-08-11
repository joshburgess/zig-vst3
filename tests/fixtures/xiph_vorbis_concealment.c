#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <ogg/ogg.h>
#include <vorbis/vorbisenc.h>

enum {
    XVC_OK = 0,
    XVC_INVALID_ARGUMENT = 1,
    XVC_ALLOCATION_FAILED = 2,
    XVC_ENCOD_FAILED = 3,
    XVC_DECODE_FAILED = 4,
    XVC_CASE_UNAVAILABLE = 5,
    XVC_OUTPUT_TOO_SMALL = 6,
};

enum {
    XVC_PREVIOUS_BLOCK = 1u << 0,
    XVC_FOLLOWING_HEADER = 1u << 1,
    XVC_FOLLOWING_GRANULE = 1u << 2,
    XVC_CHAINED = 1u << 3,
};

typedef struct {
    uint32_t abi_version;
    uint32_t case_index;
    uint32_t channel_count;
    uint32_t sample_rate;
    uint32_t small_block_size;
    uint32_t large_block_size;
    uint32_t logical_stream_count;
    uint32_t loss_logical_stream_index;
    uint32_t loss_after_audio_packets;
    uint32_t missing_block_size;
    uint32_t previous_block_size;
    uint32_t following_block_size;
    uint32_t policy_flags;
    int32_t strict_xiph_status;
    uint32_t reserved;
    uint64_t missing_granule;
    uint64_t following_granule;
    uint64_t terminal_frames;
    uint64_t clean_stream_bytes;
    uint64_t missing_stream_bytes;
    uint64_t corrupt_stream_bytes;
    uint64_t reference_frames;
} xvc_case_info;

typedef struct {
    unsigned char *data;
    long bytes;
    int bos;
    int eos;
    ogg_int64_t granule;
    ogg_int64_t packet_number;
    int large;
    int previous_large;
    int next_large;
} owned_packet;

typedef struct {
    owned_packet *items;
    size_t count;
    size_t capacity;
    int channels;
    long rate;
    int small_block;
    int large_block;
    int serial;
} packet_list;

typedef struct {
    unsigned char *data;
    size_t count;
    size_t capacity;
} byte_buffer;

typedef struct {
    float *data;
    size_t count;
    size_t capacity;
} float_buffer;

static const double xvc_pi = 3.14159265358979323846264338327950288;

static int reserve_bytes(byte_buffer *buffer, size_t extra) {
    size_t needed;
    size_t capacity;
    unsigned char *replacement;
    if (extra > SIZE_MAX - buffer->count) return 0;
    needed = buffer->count + extra;
    if (needed <= buffer->capacity) return 1;
    capacity = buffer->capacity == 0 ? 4096 : buffer->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            capacity = needed;
            break;
        }
        capacity *= 2;
    }
    replacement = (unsigned char *)realloc(buffer->data, capacity);
    if (replacement == NULL) return 0;
    buffer->data = replacement;
    buffer->capacity = capacity;
    return 1;
}

static int append_bytes(byte_buffer *buffer, const void *source, size_t count) {
    if (!reserve_bytes(buffer, count)) return 0;
    memcpy(buffer->data + buffer->count, source, count);
    buffer->count += count;
    return 1;
}

static int reserve_floats(float_buffer *buffer, size_t extra) {
    size_t needed;
    size_t capacity;
    float *replacement;
    if (extra > SIZE_MAX - buffer->count) return 0;
    needed = buffer->count + extra;
    if (needed <= buffer->capacity) return 1;
    capacity = buffer->capacity == 0 ? 16384 : buffer->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            capacity = needed;
            break;
        }
        capacity *= 2;
    }
    if (capacity > SIZE_MAX / sizeof(float)) return 0;
    replacement = (float *)realloc(buffer->data, capacity * sizeof(float));
    if (replacement == NULL) return 0;
    buffer->data = replacement;
    buffer->capacity = capacity;
    return 1;
}

static int append_interleaved(
    float_buffer *buffer,
    float **channels,
    int channel_count,
    int frames
) {
    size_t values;
    int frame;
    int channel;
    if (frames < 0 || channel_count <= 0) return 0;
    if ((size_t)frames > SIZE_MAX / (size_t)channel_count) return 0;
    values = (size_t)frames * (size_t)channel_count;
    if (!reserve_floats(buffer, values)) return 0;
    for (frame = 0; frame < frames; ++frame) {
        for (channel = 0; channel < channel_count; ++channel) {
            buffer->data[buffer->count++] = channels[channel][frame];
        }
    }
    return 1;
}

static int append_packet(packet_list *list, const ogg_packet *packet) {
    owned_packet *replacement;
    owned_packet *destination;
    size_t capacity;
    if (packet->bytes < 0) return 0;
    if (list->count == list->capacity) {
        capacity = list->capacity == 0 ? 64 : list->capacity * 2;
        if (capacity < list->capacity ||
            capacity > SIZE_MAX / sizeof(owned_packet)) return 0;
        replacement = (owned_packet *)realloc(
            list->items,
            capacity * sizeof(owned_packet)
        );
        if (replacement == NULL) return 0;
        list->items = replacement;
        list->capacity = capacity;
    }
    destination = &list->items[list->count];
    memset(destination, 0, sizeof(*destination));
    if (packet->bytes != 0) {
        destination->data = (unsigned char *)malloc((size_t)packet->bytes);
        if (destination->data == NULL) return 0;
        memcpy(destination->data, packet->packet, (size_t)packet->bytes);
    }
    destination->bytes = packet->bytes;
    destination->bos = packet->b_o_s;
    destination->eos = packet->e_o_s;
    destination->granule = packet->granulepos;
    destination->packet_number = packet->packetno;
    list->count += 1;
    return 1;
}

static void clear_packet_list(packet_list *list) {
    size_t index;
    for (index = 0; index < list->count; ++index) free(list->items[index].data);
    free(list->items);
    memset(list, 0, sizeof(*list));
}

static ogg_packet packet_view(const owned_packet *packet) {
    ogg_packet view;
    memset(&view, 0, sizeof(view));
    view.packet = packet->data;
    view.bytes = packet->bytes;
    view.b_o_s = packet->bos;
    view.e_o_s = packet->eos;
    view.granulepos = packet->granule;
    view.packetno = packet->packet_number;
    return view;
}

static int flush_encoded_packets(
    vorbis_dsp_state *state,
    vorbis_block *block,
    packet_list *packets
) {
    ogg_packet packet;
    while (vorbis_analysis_blockout(state, block) == 1) {
        if (vorbis_analysis(block, NULL) != 0 ||
            vorbis_bitrate_addblock(block) != 0) return 0;
        while (vorbis_bitrate_flushpacket(state, &packet) == 1) {
            if (!append_packet(packets, &packet)) return 0;
        }
    }
    return 1;
}

static float source_sample(int variant, int channel, int frame, int rate) {
    double time = (double)frame / (double)rate;
    double frequency = 190.0 + variant * 31.0 + channel * 137.0;
    double sample = 0.18 * sin(2.0 * xvc_pi * frequency * time);
    int center;
    for (center = 12000 + variant * 700; center < rate * 3; center += 18000) {
        int distance = frame - center;
        if (distance >= 0 && distance < 96) {
            double envelope = 1.0 - (double)distance / 96.0;
            double polarity = channel == 0 ? 1.0 : -0.7;
            sample += polarity * envelope * 0.75 *
                sin(2.0 * xvc_pi * (6500.0 + variant * 211.0) * time);
        }
        if (distance == 0) sample += channel == 0 ? 0.8 : -0.55;
    }
    if (sample > 0.98) sample = 0.98;
    if (sample < -0.98) sample = -0.98;
    return (float)sample;
}

static int classify_packets(packet_list *packets) {
    vorbis_info info;
    vorbis_comment comment;
    vorbis_dsp_state state;
    vorbis_block block;
    int info_ready = 0;
    int comment_ready = 0;
    int state_ready = 0;
    int block_ready = 0;
    size_t index;
    int result = 0;
    vorbis_info_init(&info);
    info_ready = 1;
    vorbis_comment_init(&comment);
    comment_ready = 1;
    if (packets->count < 4) goto cleanup;
    for (index = 0; index < 3; ++index) {
        ogg_packet packet = packet_view(&packets->items[index]);
        if (vorbis_synthesis_headerin(&info, &comment, &packet) != 0) goto cleanup;
    }
    packets->channels = info.channels;
    packets->rate = info.rate;
    packets->small_block = vorbis_info_blocksize(&info, 0);
    packets->large_block = vorbis_info_blocksize(&info, 1);
    if (vorbis_synthesis_init(&state, &info) != 0) goto cleanup;
    state_ready = 1;
    if (vorbis_block_init(&state, &block) != 0) goto cleanup;
    block_ready = 1;
    for (index = 3; index < packets->count; ++index) {
        ogg_packet packet = packet_view(&packets->items[index]);
        if (vorbis_synthesis_trackonly(&block, &packet) != 0) goto cleanup;
        packets->items[index].large = block.W != 0;
        packets->items[index].previous_large = block.lW != 0;
        packets->items[index].next_large = block.nW != 0;
    }
    result = 1;
cleanup:
    if (block_ready) vorbis_block_clear(&block);
    if (state_ready) vorbis_dsp_clear(&state);
    if (comment_ready) vorbis_comment_clear(&comment);
    if (info_ready) vorbis_info_clear(&info);
    return result;
}

static int encode_stream(int channels, int variant, int serial, packet_list *packets) {
    const int rate = 48000;
    const int total_frames = rate * 3;
    vorbis_info info;
    vorbis_comment comment;
    vorbis_dsp_state state;
    vorbis_block block;
    ogg_packet identification;
    ogg_packet comments;
    ogg_packet setup;
    int info_ready = 0;
    int comment_ready = 0;
    int state_ready = 0;
    int block_ready = 0;
    int base;
    int result = 0;
    memset(packets, 0, sizeof(*packets));
    packets->serial = serial;
    vorbis_info_init(&info);
    info_ready = 1;
    if (vorbis_encode_init_vbr(&info, channels, rate, 0.4f) != 0) goto cleanup;
    vorbis_comment_init(&comment);
    comment_ready = 1;
    vorbis_comment_add_tag(&comment, "ENCODER", "xiph-vorbis-concealment-oracle");
    if (vorbis_analysis_init(&state, &info) != 0) goto cleanup;
    state_ready = 1;
    if (vorbis_block_init(&state, &block) != 0) goto cleanup;
    block_ready = 1;
    if (vorbis_analysis_headerout(
            &state,
            &comment,
            &identification,
            &comments,
            &setup
        ) != 0) goto cleanup;
    if (!append_packet(packets, &identification) ||
        !append_packet(packets, &comments) ||
        !append_packet(packets, &setup)) goto cleanup;
    for (base = 0; base < total_frames; base += 512) {
        int count = total_frames - base;
        int frame;
        int channel;
        float **pcm;
        if (count > 512) count = 512;
        pcm = vorbis_analysis_buffer(&state, count);
        if (pcm == NULL) goto cleanup;
        for (frame = 0; frame < count; ++frame) {
            for (channel = 0; channel < channels; ++channel) {
                pcm[channel][frame] = source_sample(
                    variant,
                    channel,
                    base + frame,
                    rate
                );
            }
        }
        if (vorbis_analysis_wrote(&state, count) != 0 ||
            !flush_encoded_packets(&state, &block, packets)) goto cleanup;
    }
    if (vorbis_analysis_wrote(&state, 0) != 0 ||
        !flush_encoded_packets(&state, &block, packets)) goto cleanup;
    if (!classify_packets(packets)) goto cleanup;
    result = 1;
cleanup:
    if (block_ready) vorbis_block_clear(&block);
    if (state_ready) vorbis_dsp_clear(&state);
    if (comment_ready) vorbis_comment_clear(&comment);
    if (info_ready) vorbis_info_clear(&info);
    if (!result) clear_packet_list(packets);
    return result;
}

static int packet_block_size(const packet_list *packets, size_t index) {
    return packets->items[index].large ? packets->large_block : packets->small_block;
}

static int select_loss(const packet_list *packets, uint32_t case_index, size_t *loss) {
    size_t index;
    for (index = 5; index + 2 < packets->count; ++index) {
        int previous = packet_block_size(packets, index - 1);
        int missing = packet_block_size(packets, index);
        int following = packet_block_size(packets, index + 1);
        int match = 0;
        switch (case_index) {
            case 0:
                match = missing == packets->small_block && previous == missing;
                break;
            case 1:
                match = missing == packets->large_block &&
                    previous == missing && following == packets->large_block;
                break;
            case 2:
                match = missing == packets->large_block &&
                    previous == packets->small_block &&
                    following == packets->large_block;
                break;
            case 3:
                match = missing == packets->small_block &&
                    previous == packets->large_block &&
                    following == packets->small_block;
                break;
            case 4:
                match = missing == packets->large_block && previous == missing;
                break;
            default:
                return 0;
        }
        if (match && packets->items[index - 1].granule >= 0 &&
            packets->items[index].granule >= 0 &&
            packets->items[index + 1].granule >= 0 &&
            !packets->items[index].eos) {
            *loss = index;
            return 1;
        }
    }
    return 0;
}

static int append_ogg_page(byte_buffer *output, const ogg_page *page) {
    return page->header_len >= 0 && page->body_len >= 0 &&
        append_bytes(output, page->header, (size_t)page->header_len) &&
        append_bytes(output, page->body, (size_t)page->body_len);
}

static int mux_stream(
    const packet_list *packets,
    size_t loss,
    int variant,
    byte_buffer *output
) {
    ogg_stream_state stream;
    ogg_page page;
    size_t index;
    int stream_ready = 0;
    int result = 0;
    if (ogg_stream_init(&stream, packets->serial) != 0) return 0;
    stream_ready = 1;
    for (index = 0; index < packets->count; ++index) {
        ogg_packet packet;
        unsigned char *corrupt = NULL;
        if (variant == 1 && index == loss) continue;
        packet = packet_view(&packets->items[index]);
        if (variant == 2 && index == loss) {
            if (packet.bytes <= 0) goto cleanup;
            corrupt = (unsigned char *)malloc((size_t)packet.bytes);
            if (corrupt == NULL) goto cleanup;
            memcpy(corrupt, packet.packet, (size_t)packet.bytes);
            corrupt[0] |= 1u;
            packet.packet = corrupt;
        }
        if (ogg_stream_packetin(&stream, &packet) != 0) {
            free(corrupt);
            goto cleanup;
        }
        free(corrupt);
        while (ogg_stream_flush(&stream, &page) == 1) {
            if (!append_ogg_page(output, &page)) goto cleanup;
        }
    }
    result = 1;
cleanup:
    if (stream_ready) ogg_stream_clear(&stream);
    return result;
}

static double window_slope(size_t index, size_t count, int reverse) {
    double position = reverse ? (double)(count - index) : (double)(index + 1);
    double inner = sin(((position - 0.5) / (double)count) * (xvc_pi / 2.0));
    return sin((xvc_pi / 2.0) * inner * inner);
}

static void fill_window(
    float *window,
    int block_size,
    int small_block,
    int previous_large,
    int next_large
) {
    size_t left_start;
    size_t left_end;
    size_t right_start;
    size_t right_end;
    size_t index;
    memset(window, 0, (size_t)block_size * sizeof(float));
    left_start = block_size != small_block && !previous_large
        ? (size_t)block_size / 4 - (size_t)small_block / 4
        : 0;
    left_end = block_size != small_block && !previous_large
        ? (size_t)block_size / 4 + (size_t)small_block / 4
        : (size_t)block_size / 2;
    right_start = block_size != small_block && !next_large
        ? (size_t)block_size * 3 / 4 - (size_t)small_block / 4
        : (size_t)block_size / 2;
    right_end = block_size != small_block && !next_large
        ? (size_t)block_size * 3 / 4 + (size_t)small_block / 4
        : (size_t)block_size;
    for (index = left_start; index < left_end; ++index) {
        window[index] = (float)window_slope(index - left_start, left_end - left_start, 0);
    }
    for (index = left_end; index < right_start; ++index) window[index] = 1.0f;
    for (index = right_start; index < right_end; ++index) {
        window[index] = (float)window_slope(index - right_start, right_end - right_start, 1);
    }
}

static int drain_pcm(vorbis_dsp_state *state, int channels, float_buffer *output) {
    float **pcm;
    int frames;
    while ((frames = vorbis_synthesis_pcmout(state, &pcm)) > 0) {
        if (!append_interleaved(output, pcm, channels, frames) ||
            vorbis_synthesis_read(state, frames) != 0) return 0;
    }
    return frames == 0;
}

static int discard_pcm(vorbis_dsp_state *state) {
    int frames;
    while ((frames = vorbis_synthesis_pcmout(state, NULL)) > 0) {
        if (vorbis_synthesis_read(state, frames) != 0) return 0;
    }
    return frames == 0;
}

static int render_list(
    const packet_list *packets,
    size_t loss,
    int signal_policy,
    float_buffer *output
) {
    vorbis_info info;
    vorbis_comment comment;
    vorbis_dsp_state state;
    vorbis_block block;
    int info_ready = 0;
    int comment_ready = 0;
    int state_ready = 0;
    int block_ready = 0;
    float **previous_windowed = NULL;
    float *previous_storage = NULL;
    int previous_size = 0;
    size_t index;
    int result = 0;
    vorbis_info_init(&info);
    info_ready = 1;
    vorbis_comment_init(&comment);
    comment_ready = 1;
    for (index = 0; index < 3; ++index) {
        ogg_packet packet = packet_view(&packets->items[index]);
        if (vorbis_synthesis_headerin(&info, &comment, &packet) != 0) goto cleanup;
    }
    if (vorbis_synthesis_init(&state, &info) != 0) goto cleanup;
    state_ready = 1;
    if (vorbis_block_init(&state, &block) != 0) goto cleanup;
    block_ready = 1;
    previous_windowed = (float **)calloc((size_t)info.channels, sizeof(float *));
    if (previous_windowed == NULL) goto cleanup;
    if ((size_t)info.channels > SIZE_MAX /
        ((size_t)packets->large_block * sizeof(float))) goto cleanup;
    previous_storage = (float *)calloc(
        (size_t)info.channels * (size_t)packets->large_block,
        sizeof(float)
    );
    if (previous_storage == NULL) goto cleanup;
    for (index = 0; index < (size_t)info.channels; ++index) {
        previous_windowed[index] = previous_storage + index * (size_t)packets->large_block;
    }
    for (index = 3; index < packets->count; ++index) {
        const owned_packet *owned = &packets->items[index];
        if (index == loss) {
            vorbis_block synthetic;
            float **pcm = NULL;
            float *storage = NULL;
            float *window = NULL;
            float *retained = NULL;
            int block_size = packet_block_size(packets, index);
            int channel;
            int sample;
            memset(&synthetic, 0, sizeof(synthetic));
            if (previous_size == 0) goto cleanup;
            pcm = (float **)calloc((size_t)info.channels, sizeof(float *));
            storage = (float *)calloc(
                (size_t)info.channels * (size_t)block_size,
                sizeof(float)
            );
            window = (float *)malloc((size_t)block_size * sizeof(float));
            retained = (float *)malloc(
                (size_t)info.channels * (size_t)previous_size * sizeof(float)
            );
            if (pcm == NULL || storage == NULL || window == NULL || retained == NULL) {
                free(pcm);
                free(storage);
                free(window);
                free(retained);
                goto cleanup;
            }
            for (channel = 0; channel < info.channels; ++channel) {
                memcpy(
                    retained + (size_t)channel * (size_t)previous_size,
                    previous_windowed[channel],
                    (size_t)previous_size * sizeof(float)
                );
            }
            fill_window(
                window,
                block_size,
                packets->small_block,
                owned->previous_large,
                owned->next_large
            );
            for (channel = 0; channel < info.channels; ++channel) {
                pcm[channel] = storage + (size_t)channel * (size_t)block_size;
                if (signal_policy) {
                    int source_offset = previous_size / 2 - block_size / 2;
                    for (sample = 0; sample < block_size; ++sample) {
                        int source = source_offset + sample;
                        double progress = (double)sample / (double)(block_size - 1);
                        double gain = 1.0 - 0.5 * progress;
                        float target = source >= 0 && source < previous_size
                            ? retained[(size_t)channel * (size_t)previous_size +
                                (size_t)source] * (float)gain
                            : 0.0f;
                        previous_windowed[channel][sample] = target;
                        pcm[channel][sample] = window[sample] == 0.0f
                            ? 0.0f
                            : target / window[sample];
                    }
                } else {
                    memset(previous_windowed[channel], 0, (size_t)block_size * sizeof(float));
                }
            }
            synthetic.vd = &state;
            synthetic.pcm = pcm;
            synthetic.W = owned->large;
            synthetic.lW = owned->previous_large;
            synthetic.nW = owned->next_large;
            synthetic.pcmend = block_size;
            synthetic.granulepos = owned->granule;
            synthetic.sequence = owned->packet_number;
            synthetic.eofflag = owned->eos;
            if (vorbis_synthesis_blockin(&state, &synthetic) != 0 ||
                !drain_pcm(&state, info.channels, output)) {
                free(pcm);
                free(storage);
                free(window);
                free(retained);
                goto cleanup;
            }
            free(pcm);
            free(storage);
            free(window);
            free(retained);
            previous_size = block_size;
        } else {
            ogg_packet packet = packet_view(owned);
            float *window;
            int channel;
            int sample;
            if (vorbis_synthesis(&block, &packet) != 0) goto cleanup;
            window = (float *)malloc((size_t)block.pcmend * sizeof(float));
            if (window == NULL) goto cleanup;
            fill_window(
                window,
                block.pcmend,
                packets->small_block,
                block.lW,
                block.nW
            );
            for (channel = 0; channel < info.channels; ++channel) {
                for (sample = 0; sample < block.pcmend; ++sample) {
                    previous_windowed[channel][sample] =
                        block.pcm[channel][sample] * window[sample];
                }
            }
            previous_size = block.pcmend;
            free(window);
            if (vorbis_synthesis_blockin(&state, &block) != 0 ||
                !drain_pcm(&state, info.channels, output)) goto cleanup;
        }
    }
    result = 1;
cleanup:
    free(previous_storage);
    free(previous_windowed);
    if (block_ready) vorbis_block_clear(&block);
    if (state_ready) vorbis_dsp_clear(&state);
    if (comment_ready) vorbis_comment_clear(&comment);
    if (info_ready) vorbis_info_clear(&info);
    return result;
}

static int strict_status(const packet_list *packets, size_t loss, int *status) {
    vorbis_info info;
    vorbis_comment comment;
    vorbis_dsp_state state;
    vorbis_block block;
    int info_ready = 0;
    int comment_ready = 0;
    int state_ready = 0;
    int block_ready = 0;
    size_t index;
    int result = 0;
    vorbis_info_init(&info);
    info_ready = 1;
    vorbis_comment_init(&comment);
    comment_ready = 1;
    for (index = 0; index < 3; ++index) {
        ogg_packet packet = packet_view(&packets->items[index]);
        if (vorbis_synthesis_headerin(&info, &comment, &packet) != 0) goto cleanup;
    }
    if (vorbis_synthesis_init(&state, &info) != 0) goto cleanup;
    state_ready = 1;
    if (vorbis_block_init(&state, &block) != 0) goto cleanup;
    block_ready = 1;
    for (index = 3; index <= loss; ++index) {
        ogg_packet packet = packet_view(&packets->items[index]);
        unsigned char *corrupt = NULL;
        if (index == loss) {
            if (packet.bytes <= 0) goto cleanup;
            corrupt = (unsigned char *)malloc((size_t)packet.bytes);
            if (corrupt == NULL) goto cleanup;
            memcpy(corrupt, packet.packet, (size_t)packet.bytes);
            corrupt[0] |= 1u;
            packet.packet = corrupt;
        }
        *status = vorbis_synthesis(&block, &packet);
        free(corrupt);
        if (index == loss) {
            result = 1;
            goto cleanup;
        }
        if (*status != 0 || vorbis_synthesis_blockin(&state, &block) != 0 ||
            !discard_pcm(&state)) goto cleanup;
    }
cleanup:
    if (block_ready) vorbis_block_clear(&block);
    if (state_ready) vorbis_dsp_clear(&state);
    if (comment_ready) vorbis_comment_clear(&comment);
    if (info_ready) vorbis_info_clear(&info);
    return result;
}

static uint32_t policy_flags(uint32_t case_index) {
    switch (case_index) {
        case 0: return XVC_PREVIOUS_BLOCK;
        case 1: return XVC_PREVIOUS_BLOCK | XVC_FOLLOWING_HEADER;
        case 2: return XVC_FOLLOWING_HEADER;
        case 3: return XVC_FOLLOWING_GRANULE;
        case 4: return XVC_PREVIOUS_BLOCK | XVC_CHAINED;
        default: return 0;
    }
}

int xvc_generate_case(
    uint32_t case_index,
    unsigned char *clean_stream,
    size_t clean_capacity,
    unsigned char *missing_stream,
    size_t missing_capacity,
    unsigned char *corrupt_stream,
    size_t corrupt_capacity,
    float *silence_reference,
    size_t silence_capacity,
    float *signal_reference,
    size_t signal_capacity,
    xvc_case_info *info
) {
    packet_list first;
    packet_list second;
    packet_list *target;
    byte_buffer clean = {0};
    byte_buffer missing = {0};
    byte_buffer corrupt = {0};
    float_buffer silence = {0};
    float_buffer signal = {0};
    size_t loss = 0;
    int strict = 0;
    int channels;
    int chained;
    int result = XVC_ENCOD_FAILED;
    uint64_t first_frames = 0;
    uint64_t second_frames = 0;
    memset(&first, 0, sizeof(first));
    memset(&second, 0, sizeof(second));
    if (info == NULL || case_index >= 5) return XVC_INVALID_ARGUMENT;
    channels = case_index == 0 || case_index == 2 ? 1 : 2;
    chained = case_index == 4;
    if (!encode_stream(channels, (int)case_index, 0x51f100 + (int)case_index, &first))
        goto cleanup;
    target = &first;
    if (chained) {
        if (!encode_stream(channels, 7, 0x61f100 + (int)case_index, &second))
            goto cleanup;
        target = &second;
    }
    if (!select_loss(target, case_index, &loss)) {
        result = XVC_CASE_UNAVAILABLE;
        goto cleanup;
    }
    if (!mux_stream(&first, chained ? SIZE_MAX : loss, 0, &clean) ||
        !mux_stream(&first, chained ? SIZE_MAX : loss, chained ? 0 : 1, &missing) ||
        !mux_stream(&first, chained ? SIZE_MAX : loss, chained ? 0 : 2, &corrupt))
        goto cleanup;
    if (chained) {
        if (!mux_stream(&second, loss, 0, &clean) ||
            !mux_stream(&second, loss, 1, &missing) ||
            !mux_stream(&second, loss, 2, &corrupt)) goto cleanup;
        if (!render_list(&first, SIZE_MAX, 0, &silence) ||
            !render_list(&first, SIZE_MAX, 0, &signal)) {
            result = XVC_DECODE_FAILED;
            goto cleanup;
        }
    }
    if (!render_list(target, loss, 0, &silence) ||
        !render_list(target, loss, 1, &signal) ||
        !strict_status(target, loss, &strict)) {
        result = XVC_DECODE_FAILED;
        goto cleanup;
    }
    if (first.items[first.count - 1].granule < 0 ||
        (chained && second.items[second.count - 1].granule < 0)) {
        result = XVC_DECODE_FAILED;
        goto cleanup;
    }
    first_frames = (uint64_t)first.items[first.count - 1].granule;
    second_frames = chained
        ? (uint64_t)second.items[second.count - 1].granule
        : 0;
    if (silence.count != signal.count ||
        silence.count % (size_t)channels != 0 ||
        silence.count / (size_t)channels != first_frames + second_frames) {
        result = XVC_DECODE_FAILED;
        goto cleanup;
    }
    if (clean.count > clean_capacity || missing.count > missing_capacity ||
        corrupt.count > corrupt_capacity || silence.count > silence_capacity ||
        signal.count > signal_capacity) {
        result = XVC_OUTPUT_TOO_SMALL;
        goto cleanup;
    }
    if ((clean.count != 0 && clean_stream == NULL) ||
        (missing.count != 0 && missing_stream == NULL) ||
        (corrupt.count != 0 && corrupt_stream == NULL) ||
        (silence.count != 0 && silence_reference == NULL) ||
        (signal.count != 0 && signal_reference == NULL)) {
        result = XVC_INVALID_ARGUMENT;
        goto cleanup;
    }
    memcpy(clean_stream, clean.data, clean.count);
    memcpy(missing_stream, missing.data, missing.count);
    memcpy(corrupt_stream, corrupt.data, corrupt.count);
    memcpy(silence_reference, silence.data, silence.count * sizeof(float));
    memcpy(signal_reference, signal.data, signal.count * sizeof(float));
    memset(info, 0, sizeof(*info));
    info->abi_version = 1;
    info->case_index = case_index;
    info->channel_count = (uint32_t)channels;
    info->sample_rate = (uint32_t)target->rate;
    info->small_block_size = (uint32_t)target->small_block;
    info->large_block_size = (uint32_t)target->large_block;
    info->logical_stream_count = chained ? 2u : 1u;
    info->loss_logical_stream_index = chained ? 1u : 0u;
    info->loss_after_audio_packets = (uint32_t)(loss - 3);
    info->missing_block_size = (uint32_t)packet_block_size(target, loss);
    info->previous_block_size = (uint32_t)packet_block_size(target, loss - 1);
    info->following_block_size = (uint32_t)packet_block_size(target, loss + 1);
    info->policy_flags = policy_flags(case_index);
    info->strict_xiph_status = strict;
    info->missing_granule = (uint64_t)target->items[loss].granule;
    info->following_granule = (uint64_t)target->items[loss + 1].granule;
    info->terminal_frames = first_frames + second_frames;
    info->clean_stream_bytes = clean.count;
    info->missing_stream_bytes = missing.count;
    info->corrupt_stream_bytes = corrupt.count;
    info->reference_frames = silence.count / (size_t)channels;
    result = XVC_OK;
cleanup:
    clear_packet_list(&first);
    clear_packet_list(&second);
    free(clean.data);
    free(missing.data);
    free(corrupt.data);
    free(silence.data);
    free(signal.data);
    return result;
}

uint32_t xvc_case_count(void) {
    return 5;
}
