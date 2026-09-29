#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ivorbisfile.h"

enum {
    ZTV_OK = 0,
    ZTV_INVALID_ARGUMENT = 1,
    ZTV_INVALID_OGG = 2,
    ZTV_OPEN_FAILED = 3,
    ZTV_OUTPUT_TOO_SMALL = 4,
    ZTV_DECODE_FAILED = 5,
    ZTV_LENGTH_MISMATCH = 6,
    ZTV_FORMAT_CHANGED = 7,
    ZTV_INJECTED_FAILURE = 8,
};

typedef struct {
    uint32_t abi_version;
    uint32_t channel_count;
    uint32_t sample_rate;
    int32_t open_error;
    int32_t decode_error;
    uint64_t frame_count;
} ztv_info;

typedef struct {
    const unsigned char *data;
    size_t size;
    size_t offset;
} memory_stream;

static uint32_t read_u32le(const unsigned char *bytes) {
    return (uint32_t)bytes[0] |
        ((uint32_t)bytes[1] << 8) |
        ((uint32_t)bytes[2] << 16) |
        ((uint32_t)bytes[3] << 24);
}

static uint32_t ogg_crc(const unsigned char *page, size_t size) {
    uint32_t crc = 0;
    size_t index;
    for (index = 0; index < size; ++index) {
        unsigned char value = (index >= 22 && index < 26) ? 0 : page[index];
        int bit;
        crc ^= (uint32_t)value << 24;
        for (bit = 0; bit < 8; ++bit)
            crc = (crc << 1) ^ ((crc & 0x80000000u) ? 0x04c11db7u : 0);
    }
    return crc;
}

static int validate_single_link(const unsigned char *data, size_t size) {
    size_t offset = 0;
    uint32_t serial = 0;
    uint32_t sequence = 0;
    int page_count = 0;
    int saw_eos = 0;
    while (offset < size) {
        size_t body_size = 0;
        size_t page_size;
        unsigned int segment_count;
        unsigned int segment;
        const unsigned char *page = data + offset;
        if (size - offset < 27 || memcmp(page, "OggS", 4) != 0 || page[4] != 0)
            return 0;
        segment_count = page[26];
        if (size - offset < 27u + segment_count)
            return 0;
        for (segment = 0; segment < segment_count; ++segment)
            body_size += page[27 + segment];
        page_size = 27u + segment_count + body_size;
        if (page_size > size - offset ||
            ogg_crc(page, page_size) != read_u32le(page + 22))
            return 0;
        if (page_count == 0) {
            if ((page[5] & 0x02u) == 0 || read_u32le(page + 18) != 0)
                return 0;
            serial = read_u32le(page + 14);
        } else if ((page[5] & 0x02u) != 0) {
            return 0;
        }
        if (read_u32le(page + 14) != serial || read_u32le(page + 18) != sequence)
            return 0;
        saw_eos = (page[5] & 0x04u) != 0;
        if (saw_eos && offset + page_size != size)
            return 0;
        ++sequence;
        ++page_count;
        offset += page_size;
    }
    return page_count > 0 && saw_eos;
}

static size_t memory_read(void *ptr, size_t size, size_t count, void *source) {
    memory_stream *stream = source;
    size_t available;
    size_t complete;
    if (size == 0 || count == 0)
        return 0;
    available = stream->size - stream->offset;
    complete = available / size;
    if (complete > count)
        complete = count;
    memcpy(ptr, stream->data + stream->offset, complete * size);
    stream->offset += complete * size;
    return complete;
}

static int memory_seek(void *source, ogg_int64_t offset, int whence) {
    memory_stream *stream = source;
    ogg_int64_t base;
    ogg_int64_t position;
    switch (whence) {
        case SEEK_SET: base = 0; break;
        case SEEK_CUR: base = (ogg_int64_t)stream->offset; break;
        case SEEK_END: base = (ogg_int64_t)stream->size; break;
        default: return -1;
    }
    if ((offset > 0 && base > LLONG_MAX - offset) ||
        (offset < 0 && base < LLONG_MIN - offset))
        return -1;
    position = base + offset;
    if (position < 0 || (uint64_t)position > stream->size)
        return -1;
    stream->offset = (size_t)position;
    return 0;
}

static int memory_close(void *source) {
    (void)source;
    return 0;
}

static long memory_tell(void *source) {
    memory_stream *stream = source;
    if (stream->offset > LONG_MAX)
        return -1;
    return (long)stream->offset;
}

static int open_decoder(
    const unsigned char *data,
    size_t size,
    memory_stream *stream,
    OggVorbis_File *decoder,
    ztv_info *info
) {
    ov_callbacks callbacks = {
        memory_read,
        memory_seek,
        memory_close,
        memory_tell,
    };
    int status;
    vorbis_info *format;
    ogg_int64_t frames;
    stream->data = data;
    stream->size = size;
    stream->offset = 0;
    memset(decoder, 0, sizeof(*decoder));
    status = ov_open_callbacks(stream, decoder, NULL, 0, callbacks);
    info->open_error = status;
    if (status != 0)
        return ZTV_OPEN_FAILED;
    if (ov_seekable(decoder) != 1 || ov_streams(decoder) != 1) {
        ov_clear(decoder);
        return ZTV_OPEN_FAILED;
    }
    format = ov_info(decoder, 0);
    frames = ov_pcm_total(decoder, 0);
    if (format == NULL || format->channels <= 0 || format->rate <= 0 || frames <= 0) {
        ov_clear(decoder);
        return ZTV_OPEN_FAILED;
    }
    info->channel_count = (uint32_t)format->channels;
    info->sample_rate = (uint32_t)format->rate;
    info->frame_count = (uint64_t)frames;
    return ZTV_OK;
}

int ztv_probe(const unsigned char *data, size_t size, ztv_info *info) {
    memory_stream stream;
    OggVorbis_File decoder;
    int status;
    if (data == NULL || info == NULL || size == 0 || size > LONG_MAX)
        return ZTV_INVALID_ARGUMENT;
    memset(info, 0, sizeof(*info));
    info->abi_version = 1;
    if (!validate_single_link(data, size))
        return ZTV_INVALID_OGG;
    status = open_decoder(data, size, &stream, &decoder, info);
    if (status != ZTV_OK)
        return status;
    ov_clear(&decoder);
    return ZTV_OK;
}

int ztv_decode(
    const unsigned char *data,
    size_t size,
    int16_t *output,
    size_t output_values,
    uint64_t fail_after_frames,
    ztv_info *info
) {
    memory_stream stream;
    OggVorbis_File decoder;
    size_t frames = 0;
    size_t required_values;
    int status = ztv_probe(data, size, info);
    if (status != ZTV_OK)
        return status;
    if (info->frame_count > SIZE_MAX / info->channel_count)
        return ZTV_INVALID_ARGUMENT;
    required_values = (size_t)info->frame_count * info->channel_count;
    if (output == NULL || output_values < required_values)
        return ZTV_OUTPUT_TOO_SMALL;
    status = open_decoder(data, size, &stream, &decoder, info);
    if (status != ZTV_OK)
        return status;
    while (frames < info->frame_count) {
        size_t remaining_frames = (size_t)info->frame_count - frames;
        size_t requested_frames = remaining_frames;
        size_t maximum_frames = INT_MAX / (2u * info->channel_count);
        int section = -1;
        long decoded;
        if (fail_after_frames != UINT64_MAX) {
            if (frames >= fail_after_frames) {
                info->decode_error = ZTV_INJECTED_FAILURE;
                ov_clear(&decoder);
                return ZTV_INJECTED_FAILURE;
            }
            if (requested_frames > fail_after_frames - frames)
                requested_frames = (size_t)(fail_after_frames - frames);
        }
        if (requested_frames > maximum_frames)
            requested_frames = maximum_frames;
        decoded = ov_read(
            &decoder,
            (char *)(output + frames * info->channel_count),
            (int)(requested_frames * info->channel_count * 2u),
            &section
        );
        if (decoded < 0) {
            info->decode_error = (int32_t)decoded;
            ov_clear(&decoder);
            return ZTV_DECODE_FAILED;
        }
        if (decoded == 0)
            break;
        if (section != 0 || decoded % (long)(2u * info->channel_count) != 0) {
            ov_clear(&decoder);
            return ZTV_FORMAT_CHANGED;
        }
        frames += (size_t)decoded / (2u * info->channel_count);
    }
    ov_clear(&decoder);
    if (frames != info->frame_count)
        return ZTV_LENGTH_MISMATCH;
    return ZTV_OK;
}
