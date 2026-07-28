#include "core_audio_shim.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct zv3_core_audio_session {
    AudioUnit unit;
    AudioUnit input_unit;
    AudioUnit output_unit;
    uint32_t sample_bytes;
    uint32_t maximum_frames;
    uint32_t input_channels;
    uint32_t output_channels;
    void *context;
    zv3_core_audio_process_fn process;
    zv3_core_audio_capture_fn capture;
    zv3_core_audio_render_fn render;
    AudioBufferList *input_list;
    void **input_views;
    void **output_views;
    uint8_t *input_storage;
    _Atomic unsigned long long device_failures;
    _Atomic unsigned long long input_device_failures;
    _Atomic unsigned long long output_device_failures;
};

_Static_assert(
    ATOMIC_LLONG_LOCK_FREE == 2,
    "CoreAudio requires lock-free 64-bit counters"
);
_Static_assert(
    ULLONG_MAX == UINT64_MAX,
    "CoreAudio requires 64-bit unsigned long long"
);

struct zv3_core_audio_observer {
    void *context;
    zv3_core_audio_topology_fn callback;
    uint32_t installed;
};

static AudioObjectPropertyAddress property_address(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope
) {
    AudioObjectPropertyAddress address = {
        selector,
        scope,
        kAudioObjectPropertyElementMain
    };
    return address;
}

static int32_t copy_cf_string(
    CFStringRef value,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    if (value == NULL || output == NULL || output_length == NULL) {
        return -1;
    }
    CFIndex used = 0;
    const CFRange range = CFRangeMake(0, CFStringGetLength(value));
    const CFIndex converted = CFStringGetBytes(
        value,
        range,
        kCFStringEncodingUTF8,
        0,
        false,
        output,
        (CFIndex)output_capacity,
        &used
    );
    if (converted != range.length || used <= 0) {
        return -1;
    }
    *output_length = (size_t)used;
    return 0;
}

static int32_t device_string(
    AudioDeviceID device,
    AudioObjectPropertySelector selector,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    AudioObjectPropertyAddress address = property_address(
        selector,
        kAudioObjectPropertyScopeGlobal
    );
    CFStringRef value = NULL;
    uint32_t size = sizeof(value);
    const OSStatus status = AudioObjectGetPropertyData(
        device,
        &address,
        0,
        NULL,
        &size,
        &value
    );
    if (status != noErr || value == NULL) {
        return status == noErr ? -1 : status;
    }
    const int32_t result = copy_cf_string(
        value,
        output,
        output_capacity,
        output_length
    );
    CFRelease(value);
    return result;
}

static int32_t channel_count(
    AudioDeviceID device,
    AudioObjectPropertyScope scope,
    uint32_t *output
) {
    AudioObjectPropertyAddress address = property_address(
        kAudioDevicePropertyStreamConfiguration,
        scope
    );
    uint32_t size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        device,
        &address,
        0,
        NULL,
        &size
    );
    if (status != noErr) {
        return status;
    }
    AudioBufferList *list = (AudioBufferList *)malloc(size);
    if (list == NULL) {
        return -1;
    }
    status = AudioObjectGetPropertyData(
        device,
        &address,
        0,
        NULL,
        &size,
        list
    );
    if (status != noErr) {
        free(list);
        return status;
    }
    uint64_t count = 0;
    for (uint32_t index = 0; index < list->mNumberBuffers; ++index) {
        count += list->mBuffers[index].mNumberChannels;
    }
    free(list);
    if (count > UINT32_MAX) {
        return -1;
    }
    *output = (uint32_t)count;
    return 0;
}

size_t zv3_core_audio_device_count(void) {
    AudioObjectPropertyAddress address = property_address(
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal
    );
    uint32_t size = 0;
    if (AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &size
    ) != noErr) {
        return 0;
    }
    return size / sizeof(AudioDeviceID);
}

int32_t zv3_core_audio_device_at(size_t index, uint32_t *output) {
    if (output == NULL) {
        return -1;
    }
    AudioObjectPropertyAddress address = property_address(
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal
    );
    uint32_t size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &size
    );
    if (status != noErr || index >= size / sizeof(AudioDeviceID)) {
        return status == noErr ? -1 : status;
    }
    AudioDeviceID *devices = (AudioDeviceID *)malloc(size);
    if (devices == NULL) {
        return -1;
    }
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &size,
        devices
    );
    if (status == noErr) {
        *output = devices[index];
    }
    free(devices);
    return status;
}

static uint32_t default_device(AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = property_address(
        selector,
        kAudioObjectPropertyScopeGlobal
    );
    AudioDeviceID device = kAudioObjectUnknown;
    uint32_t size = sizeof(device);
    if (AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &size,
        &device
    ) != noErr) {
        return kAudioObjectUnknown;
    }
    return device;
}

uint32_t zv3_core_audio_default_input_device(void) {
    return default_device(kAudioHardwarePropertyDefaultInputDevice);
}

uint32_t zv3_core_audio_default_output_device(void) {
    return default_device(kAudioHardwarePropertyDefaultOutputDevice);
}

int32_t zv3_core_audio_device_uid(
    uint32_t device,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    return device_string(
        device,
        kAudioDevicePropertyDeviceUID,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_core_audio_device_name(
    uint32_t device,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    return device_string(
        device,
        kAudioObjectPropertyName,
        output,
        output_capacity,
        output_length
    );
}

int32_t zv3_core_audio_device_channels(
    uint32_t device,
    uint32_t *input_channels,
    uint32_t *output_channels
) {
    if (input_channels == NULL || output_channels == NULL) {
        return -1;
    }
    int32_t status = channel_count(
        device,
        kAudioDevicePropertyScopeInput,
        input_channels
    );
    if (status != 0) {
        return status;
    }
    return channel_count(
        device,
        kAudioDevicePropertyScopeOutput,
        output_channels
    );
}

int32_t zv3_core_audio_device_sample_rate(
    uint32_t device,
    double *output
) {
    if (output == NULL) {
        return -1;
    }
    AudioObjectPropertyAddress address = property_address(
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal
    );
    uint32_t size = sizeof(*output);
    return AudioObjectGetPropertyData(
        device,
        &address,
        0,
        NULL,
        &size,
        output
    );
}

int32_t zv3_core_audio_device_buffer_frames(
    uint32_t device,
    uint32_t *output
) {
    if (output == NULL) {
        return -1;
    }
    AudioObjectPropertyAddress address = property_address(
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal
    );
    uint32_t size = sizeof(*output);
    return AudioObjectGetPropertyData(
        device,
        &address,
        0,
        NULL,
        &size,
        output
    );
}

static OSStatus topology_changed(
    AudioObjectID object,
    uint32_t address_count,
    const AudioObjectPropertyAddress addresses[],
    void *context
) {
    (void)object;
    (void)address_count;
    (void)addresses;
    zv3_core_audio_observer *observer =
        (zv3_core_audio_observer *)context;
    if (observer != NULL && observer->callback != NULL) {
        observer->callback(observer->context);
    }
    return noErr;
}

static const AudioObjectPropertySelector topology_selectors[] = {
    kAudioHardwarePropertyDevices,
    kAudioHardwarePropertyDefaultInputDevice,
    kAudioHardwarePropertyDefaultOutputDevice
};

static void remove_topology_listeners(
    zv3_core_audio_observer *observer
) {
    if (observer == NULL) {
        return;
    }
    for (uint32_t index = 0;
         index < observer->installed;
         ++index) {
        AudioObjectPropertyAddress address = property_address(
            topology_selectors[index],
            kAudioObjectPropertyScopeGlobal
        );
        (void)AudioObjectRemovePropertyListener(
            kAudioObjectSystemObject,
            &address,
            topology_changed,
            observer
        );
    }
    observer->installed = 0;
}

int32_t zv3_core_audio_observe_topology(
    void *context,
    zv3_core_audio_topology_fn callback,
    zv3_core_audio_observer **output
) {
    if (context == NULL || callback == NULL || output == NULL) {
        return -1;
    }
    zv3_core_audio_observer *observer =
        (zv3_core_audio_observer *)calloc(1, sizeof(*observer));
    if (observer == NULL) {
        return -1;
    }
    observer->context = context;
    observer->callback = callback;
    const uint32_t count = (uint32_t)(
        sizeof(topology_selectors) / sizeof(topology_selectors[0])
    );
    for (uint32_t index = 0; index < count; ++index) {
        AudioObjectPropertyAddress address = property_address(
            topology_selectors[index],
            kAudioObjectPropertyScopeGlobal
        );
        const OSStatus status = AudioObjectAddPropertyListener(
            kAudioObjectSystemObject,
            &address,
            topology_changed,
            observer
        );
        if (status != noErr) {
            remove_topology_listeners(observer);
            free(observer);
            return status;
        }
        observer->installed += 1;
    }
    *output = observer;
    return 0;
}

void zv3_core_audio_stop_observing(
    zv3_core_audio_observer *observer
) {
    remove_topology_listeners(observer);
    free(observer);
}

static void clear_outputs(
    AudioBufferList *output
) {
    if (output == NULL) {
        return;
    }
    for (uint32_t index = 0; index < output->mNumberBuffers; ++index) {
        AudioBuffer *buffer = &output->mBuffers[index];
        if (buffer->mData != NULL) {
            memset(buffer->mData, 0, buffer->mDataByteSize);
        }
    }
}

static void increment_counter(
    _Atomic unsigned long long *counter
) {
    unsigned long long current = atomic_load_explicit(
        counter,
        memory_order_relaxed
    );
    while (current != ULLONG_MAX &&
           !atomic_compare_exchange_weak_explicit(
               counter,
               &current,
               current + 1,
               memory_order_relaxed,
               memory_order_relaxed
           )) {
    }
}

static void record_device_failure(
    zv3_core_audio_session *session
) {
    increment_counter(&session->device_failures);
}

static void record_input_device_failure(
    zv3_core_audio_session *session
) {
    increment_counter(&session->device_failures);
    increment_counter(&session->input_device_failures);
}

static void record_output_device_failure(
    zv3_core_audio_session *session
) {
    increment_counter(&session->device_failures);
    increment_counter(&session->output_device_failures);
}

static OSStatus render_input(
    zv3_core_audio_session *session,
    AudioUnit unit,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp,
    uint32_t frame_count
) {
    if (session->input_channels == 0) {
        return noErr;
    }
    for (uint32_t index = 0;
         index < session->input_channels;
         ++index) {
        AudioBuffer *buffer = &session->input_list->mBuffers[index];
        buffer->mNumberChannels = 1;
        buffer->mDataByteSize = frame_count * session->sample_bytes;
        buffer->mData = session->input_storage +
            (size_t)index * session->maximum_frames *
                session->sample_bytes;
        session->input_views[index] = buffer->mData;
    }
    session->input_list->mNumberBuffers = session->input_channels;
    return AudioUnitRender(
        unit,
        flags,
        timestamp,
        1,
        frame_count,
        session->input_list
    );
}

static OSStatus process_callback(
    zv3_core_audio_session *session,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp,
    uint32_t frame_count,
    AudioBufferList *output
) {
    if (frame_count > session->maximum_frames ||
        (session->output_channels != 0 &&
         (output == NULL ||
          output->mNumberBuffers < session->output_channels))) {
        record_device_failure(session);
        clear_outputs(output);
        return kAudio_ParamError;
    }
    OSStatus status = render_input(
        session,
        session->unit,
        flags,
        timestamp,
        frame_count
    );
    if (status != noErr) {
        record_device_failure(session);
        clear_outputs(output);
        return status;
    }
    for (uint32_t index = 0;
         index < session->output_channels;
         ++index) {
        AudioBuffer *buffer = &output->mBuffers[index];
        if (buffer->mNumberChannels != 1 ||
            buffer->mData == NULL ||
            buffer->mDataByteSize <
                frame_count * session->sample_bytes) {
            record_device_failure(session);
            clear_outputs(output);
            return kAudio_ParamError;
        }
        session->output_views[index] = buffer->mData;
    }
    if (session->process(
        session->context,
        frame_count,
        (const void *const *)session->input_views,
        session->output_views
    ) != 0) {
        clear_outputs(output);
        return kAudio_ParamError;
    }
    return noErr;
}

static OSStatus output_callback(
    void *context,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp,
    uint32_t bus,
    uint32_t frame_count,
    AudioBufferList *output
) {
    (void)bus;
    return process_callback(
        (zv3_core_audio_session *)context,
        flags,
        timestamp,
        frame_count,
        output
    );
}

static OSStatus input_callback(
    void *context,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp,
    uint32_t bus,
    uint32_t frame_count,
    AudioBufferList *output
) {
    (void)bus;
    (void)output;
    return process_callback(
        (zv3_core_audio_session *)context,
        flags,
        timestamp,
        frame_count,
        NULL
    );
}

static OSStatus split_input_callback(
    void *context,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp,
    uint32_t bus,
    uint32_t frame_count,
    AudioBufferList *output
) {
    (void)bus;
    (void)output;
    zv3_core_audio_session *session =
        (zv3_core_audio_session *)context;
    if (frame_count > session->maximum_frames) {
        record_input_device_failure(session);
        return kAudio_ParamError;
    }
    OSStatus status = render_input(
        session,
        session->input_unit,
        flags,
        timestamp,
        frame_count
    );
    if (status != noErr) {
        record_input_device_failure(session);
        return status;
    }
    if (session->capture(
        session->context,
        frame_count,
        (const void *const *)session->input_views
    ) != 0) {
        return kAudio_ParamError;
    }
    return noErr;
}

static OSStatus split_output_callback(
    void *context,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp,
    uint32_t bus,
    uint32_t frame_count,
    AudioBufferList *output
) {
    (void)flags;
    (void)timestamp;
    (void)bus;
    zv3_core_audio_session *session =
        (zv3_core_audio_session *)context;
    if (frame_count > session->maximum_frames ||
        output == NULL ||
        output->mNumberBuffers < session->output_channels) {
        record_output_device_failure(session);
        clear_outputs(output);
        return kAudio_ParamError;
    }
    for (uint32_t index = 0;
         index < session->output_channels;
         ++index) {
        AudioBuffer *buffer = &output->mBuffers[index];
        if (buffer->mNumberChannels != 1 ||
            buffer->mData == NULL ||
            buffer->mDataByteSize <
                frame_count * session->sample_bytes) {
            record_output_device_failure(session);
            clear_outputs(output);
            return kAudio_ParamError;
        }
        session->output_views[index] = buffer->mData;
    }
    if (session->render(
        session->context,
        frame_count,
        session->output_views
    ) != 0) {
        clear_outputs(output);
        return kAudio_ParamError;
    }
    return noErr;
}

static AudioStreamBasicDescription stream_format(
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t channel_count
) {
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = sample_rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags =
        kAudioFormatFlagIsFloat |
        kAudioFormatFlagsNativeEndian |
        kAudioFormatFlagIsPacked |
        kAudioFormatFlagIsNonInterleaved;
    format.mBytesPerPacket = sample_bytes;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sample_bytes;
    format.mChannelsPerFrame = channel_count;
    format.mBitsPerChannel = sample_bytes * 8;
    return format;
}

static void dispose_unit(AudioUnit *unit) {
    if (unit == NULL || *unit == NULL) {
        return;
    }
    (void)AudioOutputUnitStop(*unit);
    (void)AudioUnitUninitialize(*unit);
    (void)AudioComponentInstanceDispose(*unit);
    *unit = NULL;
}

static void dispose_session(zv3_core_audio_session *session) {
    if (session == NULL) {
        return;
    }
    dispose_unit(&session->output_unit);
    dispose_unit(&session->input_unit);
    dispose_unit(&session->unit);
    free(session->input_list);
    free(session->input_views);
    free(session->output_views);
    free(session->input_storage);
    free(session);
}

static int allocate_session_buffers(
    zv3_core_audio_session *session
) {
    if (session->input_channels != 0) {
        const size_t list_size =
            offsetof(AudioBufferList, mBuffers) +
            sizeof(AudioBuffer) * session->input_channels;
        session->input_list =
            (AudioBufferList *)calloc(1, list_size);
        session->input_views = (void **)calloc(
            session->input_channels,
            sizeof(void *)
        );
        session->input_storage = (uint8_t *)calloc(
            (size_t)session->input_channels *
                session->maximum_frames,
            session->sample_bytes
        );
        if (session->input_list == NULL ||
            session->input_views == NULL ||
            session->input_storage == NULL) {
            return -1;
        }
    }
    if (session->output_channels != 0) {
        session->output_views = (void **)calloc(
            session->output_channels,
            sizeof(void *)
        );
        if (session->output_views == NULL) {
            return -1;
        }
    }
    return 0;
}

static OSStatus create_hal_unit(AudioUnit *output) {
    AudioComponentDescription description = {
        kAudioUnitType_Output,
        kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple,
        0,
        0
    };
    AudioComponent component = AudioComponentFindNext(
        NULL,
        &description
    );
    if (component == NULL) {
        return kAudio_ParamError;
    }
    return AudioComponentInstanceNew(component, output);
}

int32_t zv3_core_audio_start(
    uint32_t device,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_core_audio_process_fn process,
    zv3_core_audio_session **output
) {
    if (device == kAudioObjectUnknown ||
        (sample_bytes != 4 && sample_bytes != 8) ||
        !isfinite(sample_rate) ||
        sample_rate <= 0.0 ||
        maximum_frames == 0 ||
        maximum_frames > UINT32_MAX / sample_bytes ||
        (input_channels == 0 && output_channels == 0) ||
        context == NULL ||
        process == NULL ||
        output == NULL) {
        return -1;
    }

    uint32_t device_input_channels = 0;
    uint32_t device_output_channels = 0;
    int32_t status = zv3_core_audio_device_channels(
        device,
        &device_input_channels,
        &device_output_channels
    );
    if (status != 0 ||
        input_channels > device_input_channels ||
        output_channels > device_output_channels) {
        return status == 0 ? -1 : status;
    }
    uint32_t buffer_frames = 0;
    status = zv3_core_audio_device_buffer_frames(
        device,
        &buffer_frames
    );
    if (status != 0 || buffer_frames > maximum_frames) {
        return status == 0 ? -1 : status;
    }

    zv3_core_audio_session *session =
        (zv3_core_audio_session *)calloc(1, sizeof(*session));
    if (session == NULL) {
        return -1;
    }
    atomic_init(&session->device_failures, 0);
    atomic_init(&session->input_device_failures, 0);
    atomic_init(&session->output_device_failures, 0);
    session->sample_bytes = sample_bytes;
    session->maximum_frames = maximum_frames;
    session->input_channels = input_channels;
    session->output_channels = output_channels;
    session->context = context;
    session->process = process;

    if (allocate_session_buffers(session) != 0) {
        dispose_session(session);
        return -1;
    }

    OSStatus os_status = create_hal_unit(&session->unit);
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }

    uint32_t enabled = input_channels != 0;
    os_status = AudioUnitSetProperty(
        session->unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input,
        1,
        &enabled,
        sizeof(enabled)
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    enabled = output_channels != 0;
    os_status = AudioUnitSetProperty(
        session->unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output,
        0,
        &enabled,
        sizeof(enabled)
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    os_status = AudioUnitSetProperty(
        session->unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &device,
        sizeof(device)
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }

    if (input_channels != 0) {
        const AudioStreamBasicDescription format = stream_format(
            sample_bytes,
            sample_rate,
            input_channels
        );
        os_status = AudioUnitSetProperty(
            session->unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &format,
            sizeof(format)
        );
        if (os_status != noErr) {
            dispose_session(session);
            return os_status;
        }
    }
    if (output_channels != 0) {
        const AudioStreamBasicDescription format = stream_format(
            sample_bytes,
            sample_rate,
            output_channels
        );
        os_status = AudioUnitSetProperty(
            session->unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &format,
            sizeof(format)
        );
        if (os_status != noErr) {
            dispose_session(session);
            return os_status;
        }
    }
    os_status = AudioUnitSetProperty(
        session->unit,
        kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global,
        0,
        &maximum_frames,
        sizeof(maximum_frames)
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }

    AURenderCallbackStruct callback = {
        output_channels != 0 ? output_callback : input_callback,
        session
    };
    os_status = AudioUnitSetProperty(
        session->unit,
        output_channels != 0
            ? kAudioUnitProperty_SetRenderCallback
            : kAudioOutputUnitProperty_SetInputCallback,
        output_channels != 0
            ? kAudioUnitScope_Input
            : kAudioUnitScope_Global,
        0,
        &callback,
        sizeof(callback)
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    os_status = AudioUnitInitialize(session->unit);
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    os_status = AudioOutputUnitStart(session->unit);
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    *output = session;
    return 0;
}

static OSStatus configure_split_input(
    zv3_core_audio_session *session,
    AudioDeviceID device,
    double sample_rate
) {
    OSStatus status = create_hal_unit(&session->input_unit);
    if (status != noErr) {
        return status;
    }
    uint32_t enabled = 1;
    status = AudioUnitSetProperty(
        session->input_unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input,
        1,
        &enabled,
        sizeof(enabled)
    );
    if (status != noErr) {
        return status;
    }
    enabled = 0;
    status = AudioUnitSetProperty(
        session->input_unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output,
        0,
        &enabled,
        sizeof(enabled)
    );
    if (status != noErr) {
        return status;
    }
    status = AudioUnitSetProperty(
        session->input_unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &device,
        sizeof(device)
    );
    if (status != noErr) {
        return status;
    }
    const AudioStreamBasicDescription format = stream_format(
        session->sample_bytes,
        sample_rate,
        session->input_channels
    );
    status = AudioUnitSetProperty(
        session->input_unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output,
        1,
        &format,
        sizeof(format)
    );
    if (status != noErr) {
        return status;
    }
    status = AudioUnitSetProperty(
        session->input_unit,
        kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global,
        0,
        &session->maximum_frames,
        sizeof(session->maximum_frames)
    );
    if (status != noErr) {
        return status;
    }
    const AURenderCallbackStruct callback = {
        split_input_callback,
        session
    };
    status = AudioUnitSetProperty(
        session->input_unit,
        kAudioOutputUnitProperty_SetInputCallback,
        kAudioUnitScope_Global,
        0,
        &callback,
        sizeof(callback)
    );
    if (status != noErr) {
        return status;
    }
    return AudioUnitInitialize(session->input_unit);
}

static OSStatus configure_split_output(
    zv3_core_audio_session *session,
    AudioDeviceID device,
    double sample_rate
) {
    OSStatus status = create_hal_unit(&session->output_unit);
    if (status != noErr) {
        return status;
    }
    uint32_t enabled = 0;
    status = AudioUnitSetProperty(
        session->output_unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input,
        1,
        &enabled,
        sizeof(enabled)
    );
    if (status != noErr) {
        return status;
    }
    enabled = 1;
    status = AudioUnitSetProperty(
        session->output_unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output,
        0,
        &enabled,
        sizeof(enabled)
    );
    if (status != noErr) {
        return status;
    }
    status = AudioUnitSetProperty(
        session->output_unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &device,
        sizeof(device)
    );
    if (status != noErr) {
        return status;
    }
    const AudioStreamBasicDescription format = stream_format(
        session->sample_bytes,
        sample_rate,
        session->output_channels
    );
    status = AudioUnitSetProperty(
        session->output_unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        0,
        &format,
        sizeof(format)
    );
    if (status != noErr) {
        return status;
    }
    status = AudioUnitSetProperty(
        session->output_unit,
        kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global,
        0,
        &session->maximum_frames,
        sizeof(session->maximum_frames)
    );
    if (status != noErr) {
        return status;
    }
    const AURenderCallbackStruct callback = {
        split_output_callback,
        session
    };
    status = AudioUnitSetProperty(
        session->output_unit,
        kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input,
        0,
        &callback,
        sizeof(callback)
    );
    if (status != noErr) {
        return status;
    }
    return AudioUnitInitialize(session->output_unit);
}

int32_t zv3_core_audio_start_split(
    uint32_t input_device,
    uint32_t output_device,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_core_audio_capture_fn capture,
    zv3_core_audio_render_fn render,
    zv3_core_audio_session **output
) {
    if (input_device == kAudioObjectUnknown ||
        output_device == kAudioObjectUnknown ||
        (sample_bytes != 4 && sample_bytes != 8) ||
        !isfinite(sample_rate) ||
        sample_rate <= 0.0 ||
        maximum_frames == 0 ||
        maximum_frames > UINT32_MAX / sample_bytes ||
        input_channels == 0 ||
        output_channels == 0 ||
        context == NULL ||
        capture == NULL ||
        render == NULL ||
        output == NULL) {
        return -1;
    }
    *output = NULL;

    uint32_t available_input_channels = 0;
    uint32_t ignored_output_channels = 0;
    int32_t status = zv3_core_audio_device_channels(
        input_device,
        &available_input_channels,
        &ignored_output_channels
    );
    if (status != 0 || input_channels > available_input_channels) {
        return status == 0 ? -1 : status;
    }
    uint32_t ignored_input_channels = 0;
    uint32_t available_output_channels = 0;
    status = zv3_core_audio_device_channels(
        output_device,
        &ignored_input_channels,
        &available_output_channels
    );
    if (status != 0 || output_channels > available_output_channels) {
        return status == 0 ? -1 : status;
    }
    uint32_t input_buffer_frames = 0;
    uint32_t output_buffer_frames = 0;
    status = zv3_core_audio_device_buffer_frames(
        input_device,
        &input_buffer_frames
    );
    if (status != 0 || input_buffer_frames > maximum_frames) {
        return status == 0 ? -1 : status;
    }
    status = zv3_core_audio_device_buffer_frames(
        output_device,
        &output_buffer_frames
    );
    if (status != 0 || output_buffer_frames > maximum_frames) {
        return status == 0 ? -1 : status;
    }

    zv3_core_audio_session *session =
        (zv3_core_audio_session *)calloc(1, sizeof(*session));
    if (session == NULL) {
        return -1;
    }
    atomic_init(&session->device_failures, 0);
    atomic_init(&session->input_device_failures, 0);
    atomic_init(&session->output_device_failures, 0);
    session->sample_bytes = sample_bytes;
    session->maximum_frames = maximum_frames;
    session->input_channels = input_channels;
    session->output_channels = output_channels;
    session->context = context;
    session->capture = capture;
    session->render = render;
    if (allocate_session_buffers(session) != 0) {
        dispose_session(session);
        return -1;
    }

    OSStatus os_status = configure_split_input(
        session,
        input_device,
        sample_rate
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    os_status = configure_split_output(
        session,
        output_device,
        sample_rate
    );
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    os_status = AudioOutputUnitStart(session->input_unit);
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    os_status = AudioOutputUnitStart(session->output_unit);
    if (os_status != noErr) {
        dispose_session(session);
        return os_status;
    }
    *output = session;
    return 0;
}

uint64_t zv3_core_audio_device_failures(
    zv3_core_audio_session *session
) {
    if (session == NULL) {
        return 0;
    }
    return atomic_load_explicit(
        &session->device_failures,
        memory_order_acquire
    );
}

uint64_t zv3_core_audio_input_device_failures(
    zv3_core_audio_session *session
) {
    if (session == NULL) {
        return 0;
    }
    return atomic_load_explicit(
        &session->input_device_failures,
        memory_order_acquire
    );
}

uint64_t zv3_core_audio_output_device_failures(
    zv3_core_audio_session *session
) {
    if (session == NULL) {
        return 0;
    }
    return atomic_load_explicit(
        &session->output_device_failures,
        memory_order_acquire
    );
}

void zv3_core_audio_stop(zv3_core_audio_session *session) {
    dispose_session(session);
}
