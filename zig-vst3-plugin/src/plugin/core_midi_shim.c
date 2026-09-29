#include "core_midi_shim.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMIDI/MIDIServices.h>
#include <mach/mach_time.h>

static CFStringRef make_string(
    const uint8_t *bytes,
    size_t length
) {
    return CFStringCreateWithBytes(
        kCFAllocatorDefault,
        bytes,
        (CFIndex)length,
        kCFStringEncodingUTF8,
        false
    );
}

static void notify_bridge(
    const MIDINotification *message,
    void *context
) {
    (void)message;
    zv3_core_midi_notify_state *state =
        (zv3_core_midi_notify_state *)context;
    if (state != NULL && state->callback != NULL) {
        state->callback(state->context);
    }
}

static void receive_bridge(
    const MIDIPacketList *packet_list,
    void *context,
    void *source_context
) {
    (void)source_context;
    zv3_core_midi_receive_state *state =
        (zv3_core_midi_receive_state *)context;
    if (state == NULL || state->callback == NULL) {
        return;
    }

    const MIDIPacket *packet = &packet_list->packet[0];
    for (UInt32 index = 0;
         index < packet_list->numPackets;
         ++index) {
        state->callback(
            state->context,
            packet->timeStamp,
            packet->data,
            packet->length
        );
        packet = MIDIPacketNext(packet);
    }
}

int32_t zv3_core_midi_get_timebase(
    zv3_core_midi_timebase *output
) {
    if (output == NULL) {
        return -1;
    }
    mach_timebase_info_data_t info;
    const kern_return_t status = mach_timebase_info(&info);
    if (status != KERN_SUCCESS) {
        return status;
    }
    output->numerator = info.numer;
    output->denominator = info.denom;
    return 0;
}

uint64_t zv3_core_midi_now_ticks(void) {
    return mach_absolute_time();
}

int32_t zv3_core_midi_create_client(
    const uint8_t *name,
    size_t name_length,
    zv3_core_midi_notify_state *notify_state,
    uint32_t *output
) {
    if (name == NULL || notify_state == NULL || output == NULL) {
        return -1;
    }
    CFStringRef string = make_string(name, name_length);
    if (string == NULL) {
        return -1;
    }
    MIDIClientRef client = 0;
    const OSStatus status = MIDIClientCreate(
        string,
        notify_bridge,
        notify_state,
        &client
    );
    CFRelease(string);
    if (status == noErr) {
        *output = client;
    }
    return status;
}

int32_t zv3_core_midi_create_input_port(
    uint32_t client,
    const uint8_t *name,
    size_t name_length,
    zv3_core_midi_receive_state *receive_state,
    uint32_t *output
) {
    if (name == NULL || receive_state == NULL || output == NULL) {
        return -1;
    }
    CFStringRef string = make_string(name, name_length);
    if (string == NULL) {
        return -1;
    }
    MIDIPortRef port = 0;
    const OSStatus status = MIDIInputPortCreate(
        client,
        string,
        receive_bridge,
        receive_state,
        &port
    );
    CFRelease(string);
    if (status == noErr) {
        *output = port;
    }
    return status;
}

int32_t zv3_core_midi_create_output_port(
    uint32_t client,
    const uint8_t *name,
    size_t name_length,
    uint32_t *output
) {
    if (name == NULL || output == NULL) {
        return -1;
    }
    CFStringRef string = make_string(name, name_length);
    if (string == NULL) {
        return -1;
    }
    MIDIPortRef port = 0;
    const OSStatus status = MIDIOutputPortCreate(
        client,
        string,
        &port
    );
    CFRelease(string);
    if (status == noErr) {
        *output = port;
    }
    return status;
}

void zv3_core_midi_dispose_client(uint32_t client) {
    (void)MIDIClientDispose(client);
}

void zv3_core_midi_dispose_port(uint32_t port) {
    (void)MIDIPortDispose(port);
}

size_t zv3_core_midi_source_count(void) {
    return MIDIGetNumberOfSources();
}

size_t zv3_core_midi_destination_count(void) {
    return MIDIGetNumberOfDestinations();
}

int32_t zv3_core_midi_source_at(
    size_t index,
    uint32_t *output
) {
    if (output == NULL) {
        return -1;
    }
    const MIDIEndpointRef endpoint = MIDIGetSource(index);
    if (endpoint == 0) {
        return -1;
    }
    *output = endpoint;
    return 0;
}

int32_t zv3_core_midi_destination_at(
    size_t index,
    uint32_t *output
) {
    if (output == NULL) {
        return -1;
    }
    const MIDIEndpointRef endpoint = MIDIGetDestination(index);
    if (endpoint == 0) {
        return -1;
    }
    *output = endpoint;
    return 0;
}

int32_t zv3_core_midi_endpoint_unique_id(
    uint32_t endpoint,
    int32_t *output
) {
    if (output == NULL) {
        return -1;
    }
    SInt32 unique_id = 0;
    const OSStatus status = MIDIObjectGetIntegerProperty(
        endpoint,
        kMIDIPropertyUniqueID,
        &unique_id
    );
    if (status == noErr && unique_id != 0) {
        *output = unique_id;
        return 0;
    }
    return status == noErr ? -1 : status;
}

int32_t zv3_core_midi_endpoint_name(
    uint32_t endpoint,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    if (output == NULL || output_length == NULL) {
        return -1;
    }
    CFStringRef name = NULL;
    const OSStatus status = MIDIObjectGetStringProperty(
        endpoint,
        kMIDIPropertyDisplayName,
        &name
    );
    if (status != noErr || name == NULL) {
        return status == noErr ? -1 : status;
    }
    CFIndex used = 0;
    const CFRange range = CFRangeMake(
        0,
        CFStringGetLength(name)
    );
    const CFIndex converted = CFStringGetBytes(
        name,
        range,
        kCFStringEncodingUTF8,
        0,
        false,
        output,
        (CFIndex)output_capacity,
        &used
    );
    CFRelease(name);
    if (converted != range.length || used <= 0) {
        return -1;
    }
    *output_length = (size_t)used;
    return 0;
}

int32_t zv3_core_midi_connect_source(
    uint32_t port,
    uint32_t endpoint
) {
    return MIDIPortConnectSource(port, endpoint, NULL);
}

int32_t zv3_core_midi_disconnect_source(
    uint32_t port,
    uint32_t endpoint
) {
    return MIDIPortDisconnectSource(port, endpoint);
}

int32_t zv3_core_midi_send(
    uint32_t port,
    uint32_t endpoint,
    uint64_t timestamp_ticks,
    const uint8_t *bytes,
    size_t length
) {
    if (bytes == NULL || length == 0 || length > 3) {
        return -1;
    }
    MIDIPacketList packet_list;
    MIDIPacket *packet = MIDIPacketListInit(&packet_list);
    packet = MIDIPacketListAdd(
        &packet_list,
        sizeof(packet_list),
        packet,
        timestamp_ticks,
        length,
        bytes
    );
    if (packet == NULL) {
        return -1;
    }
    return MIDISend(port, endpoint, &packet_list);
}
