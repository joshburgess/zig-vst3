#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_INTEGER_CONVERSION
#define STB_VORBIS_MAX_CHANNELS 8
#include "stb_vorbis.c"

enum {
    ZSV_OK = 0,
    ZSV_INVALID_ARGUMENT = 1,
    ZSV_INVALID_OGG = 2,
    ZSV_OPEN_FAILED = 3,
    ZSV_OUTPUT_TOO_SMALL = 4,
    ZSV_DECODE_FAILED = 5,
    ZSV_LENGTH_MISMATCH = 6,
};

typedef struct {
    uint32_t abi_version;
    uint32_t channel_count;
    uint32_t sample_rate;
    uint32_t open_error;
    uint32_t decode_error;
    uint64_t frame_count;
} zsv_info;

static uint32_t read_u32le(const unsigned char *bytes) {
    return (uint32_t)bytes[0] |
        ((uint32_t)bytes[1] << 8) |
        ((uint32_t)bytes[2] << 16) |
        ((uint32_t)bytes[3] << 24);
}

static uint32_t ogg_crc(const unsigned char *page, size_t size) {
    uint32_t crc = 0;
    size_t i;
    for (i = 0; i < size; ++i) {
        unsigned char value = (i >= 22 && i < 26) ? 0 : page[i];
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
        if (size - offset < 27 || memcmp(page, "OggS", 4) != 0 ||
            page[4] != 0)
            return 0;
        segment_count = page[26];
        if (size - offset < 27u + segment_count)
            return 0;
        for (segment = 0; segment < segment_count; ++segment)
            body_size += page[27 + segment];
        page_size = 27u + segment_count + body_size;
        if (page_size > size - offset || ogg_crc(page, page_size) != read_u32le(page + 22))
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

int zsv_probe(const unsigned char *data, size_t size, zsv_info *info) {
    stb_vorbis *decoder;
    stb_vorbis_info decoder_info;
    int open_error = VORBIS__no_error;
    if (data == NULL || info == NULL || size == 0 || size > INT_MAX)
        return ZSV_INVALID_ARGUMENT;
    memset(info, 0, sizeof(*info));
    info->abi_version = 1;
    if (!validate_single_link(data, size))
        return ZSV_INVALID_OGG;
    decoder = stb_vorbis_open_memory(data, (int)size, &open_error, NULL);
    info->open_error = (uint32_t)open_error;
    if (decoder == NULL)
        return ZSV_OPEN_FAILED;
    decoder_info = stb_vorbis_get_info(decoder);
    info->channel_count = decoder_info.channels;
    info->sample_rate = decoder_info.sample_rate;
    info->frame_count = stb_vorbis_stream_length_in_samples(decoder);
    stb_vorbis_close(decoder);
    if (info->channel_count == 0 || info->channel_count > STB_VORBIS_MAX_CHANNELS ||
        info->sample_rate == 0 || info->frame_count == 0)
        return ZSV_OPEN_FAILED;
    return ZSV_OK;
}

int zsv_decode(
    const unsigned char *data,
    size_t size,
    float *output,
    size_t output_values,
    zsv_info *info
) {
    stb_vorbis *decoder;
    size_t frames = 0;
    size_t required_values;
    int open_error = VORBIS__no_error;
    int status = zsv_probe(data, size, info);
    if (status != ZSV_OK)
        return status;
    if (info->frame_count > SIZE_MAX / info->channel_count)
        return ZSV_INVALID_ARGUMENT;
    required_values = (size_t)info->frame_count * info->channel_count;
    if (output == NULL || output_values < required_values)
        return ZSV_OUTPUT_TOO_SMALL;
    decoder = stb_vorbis_open_memory(data, (int)size, &open_error, NULL);
    if (decoder == NULL) {
        info->open_error = (uint32_t)open_error;
        return ZSV_OPEN_FAILED;
    }
    while (frames < info->frame_count) {
        size_t remaining_values =
            (size_t)(info->frame_count - frames) * info->channel_count;
        int requested_values = remaining_values > INT_MAX
            ? INT_MAX - (INT_MAX % (int)info->channel_count)
            : (int)remaining_values;
        int decoded = stb_vorbis_get_samples_float_interleaved(
            decoder,
            (int)info->channel_count,
            output + frames * info->channel_count,
            requested_values
        );
        if (decoded == 0)
            break;
        if ((uint64_t)decoded > info->frame_count - frames) {
            stb_vorbis_close(decoder);
            return ZSV_LENGTH_MISMATCH;
        }
        frames += (size_t)decoded;
    }
    info->decode_error = (uint32_t)stb_vorbis_get_error(decoder);
    stb_vorbis_close(decoder);
    if (info->decode_error != VORBIS__no_error)
        return ZSV_DECODE_FAILED;
    if (frames != info->frame_count)
        return ZSV_LENGTH_MISMATCH;
    return ZSV_OK;
}
