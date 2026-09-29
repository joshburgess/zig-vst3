#include <AudioToolbox/AudioToolbox.h>
#include <stddef.h>
#include <stdio.h>

extern size_t zig_auv2_sizeof_component_description(void);
extern size_t zig_auv2_alignof_component_description(void);
extern size_t zig_auv2_offsetof_component_flags_mask(void);
extern size_t zig_auv2_sizeof_audio_buffer(void);
extern size_t zig_auv2_offsetof_audio_buffer_data(void);
extern size_t zig_auv2_sizeof_audio_buffer_list(void);
extern size_t zig_auv2_offsetof_audio_buffer_list_buffers(void);
extern size_t zig_auv2_sizeof_plugin_interface(void);
extern size_t zig_auv2_offsetof_plugin_interface_lookup(void);
extern size_t zig_auv2_offsetof_plugin_interface_reserved(void);
extern size_t zig_auv2_sizeof_stream_description(void);
extern size_t zig_auv2_alignof_stream_description(void);
extern size_t zig_auv2_offsetof_stream_description_bits(void);
extern size_t zig_auv2_sizeof_channel_info(void);
extern size_t zig_auv2_sizeof_render_callback(void);
extern size_t zig_auv2_offsetof_render_callback_reference(void);
extern size_t zig_auv2_sizeof_audio_timestamp(void);
extern size_t zig_auv2_offsetof_audio_timestamp_flags(void);
extern size_t zig_auv2_sizeof_parameter_info(void);
extern size_t zig_auv2_offsetof_parameter_info_unit_name(void);
extern size_t zig_auv2_offsetof_parameter_info_flags(void);
extern size_t zig_auv2_sizeof_parameter_event(void);
extern size_t zig_auv2_offsetof_parameter_event_values(void);
extern size_t zig_auv2_sizeof_parameter_ramp_event(void);
extern size_t zig_auv2_offsetof_parameter_ramp_duration(void);
extern size_t zig_auv2_offsetof_parameter_ramp_start_value(void);
extern size_t zig_auv2_offsetof_parameter_ramp_end_value(void);
extern unsigned int zig_auv2_parameter_event_ramped(void);
extern short zig_auv2_selector_render(void);
extern short zig_auv2_selector_add_property_listener(void);
extern short zig_auv2_selector_remove_property_listener(void);
extern short zig_auv2_selector_remove_property_listener_with_user_data(void);
extern short zig_auv2_selector_add_render_notify(void);
extern short zig_auv2_selector_remove_render_notify(void);
extern unsigned int zig_auv2_render_action_post_render_error(void);
extern unsigned int zig_auv2_property_maximum_frames(void);
extern unsigned int zig_auv2_property_class_info(void);

#define CHECK_EQUAL(name, actual, expected)                                      \
    do {                                                                         \
        const size_t actual_value = (size_t)(actual);                            \
        const size_t expected_value = (size_t)(expected);                        \
        if (actual_value != expected_value) {                                    \
            fprintf(stderr, "%s: Zig=%zu C=%zu\n", name, actual_value,           \
                    expected_value);                                             \
            return 1;                                                            \
        }                                                                        \
    } while (0)

int main(void) {
    CHECK_EQUAL("AudioComponentDescription size",
                zig_auv2_sizeof_component_description(),
                sizeof(AudioComponentDescription));
    CHECK_EQUAL("AudioComponentDescription alignment",
                zig_auv2_alignof_component_description(),
                _Alignof(AudioComponentDescription));
    CHECK_EQUAL("AudioComponentDescription flags-mask offset",
                zig_auv2_offsetof_component_flags_mask(),
                offsetof(AudioComponentDescription, componentFlagsMask));
    CHECK_EQUAL("AudioBuffer size", zig_auv2_sizeof_audio_buffer(),
                sizeof(AudioBuffer));
    CHECK_EQUAL("AudioBuffer data offset",
                zig_auv2_offsetof_audio_buffer_data(),
                offsetof(AudioBuffer, mData));
    CHECK_EQUAL("AudioBufferList size", zig_auv2_sizeof_audio_buffer_list(),
                sizeof(AudioBufferList));
    CHECK_EQUAL("AudioBufferList buffers offset",
                zig_auv2_offsetof_audio_buffer_list_buffers(),
                offsetof(AudioBufferList, mBuffers));
    CHECK_EQUAL("AudioComponentPlugInInterface size",
                zig_auv2_sizeof_plugin_interface(),
                sizeof(AudioComponentPlugInInterface));
    CHECK_EQUAL("AudioComponentPlugInInterface lookup offset",
                zig_auv2_offsetof_plugin_interface_lookup(),
                offsetof(AudioComponentPlugInInterface, Lookup));
    CHECK_EQUAL("AudioComponentPlugInInterface reserved offset",
                zig_auv2_offsetof_plugin_interface_reserved(),
                offsetof(AudioComponentPlugInInterface, reserved));
    CHECK_EQUAL("AudioStreamBasicDescription size",
                zig_auv2_sizeof_stream_description(),
                sizeof(AudioStreamBasicDescription));
    CHECK_EQUAL("AudioStreamBasicDescription alignment",
                zig_auv2_alignof_stream_description(),
                _Alignof(AudioStreamBasicDescription));
    CHECK_EQUAL("AudioStreamBasicDescription bits offset",
                zig_auv2_offsetof_stream_description_bits(),
                offsetof(AudioStreamBasicDescription, mBitsPerChannel));
    CHECK_EQUAL("AUChannelInfo size", zig_auv2_sizeof_channel_info(),
                sizeof(AUChannelInfo));
    CHECK_EQUAL("AURenderCallbackStruct size",
                zig_auv2_sizeof_render_callback(),
                sizeof(AURenderCallbackStruct));
    CHECK_EQUAL("AURenderCallbackStruct reference offset",
                zig_auv2_offsetof_render_callback_reference(),
                offsetof(AURenderCallbackStruct, inputProcRefCon));
    CHECK_EQUAL("AudioTimeStamp size", zig_auv2_sizeof_audio_timestamp(),
                sizeof(AudioTimeStamp));
    CHECK_EQUAL("AudioTimeStamp flags offset",
                zig_auv2_offsetof_audio_timestamp_flags(),
                offsetof(AudioTimeStamp, mFlags));
    CHECK_EQUAL("AudioUnitParameterInfo size",
                zig_auv2_sizeof_parameter_info(),
                sizeof(AudioUnitParameterInfo));
    CHECK_EQUAL("AudioUnitParameterInfo unit-name offset",
                zig_auv2_offsetof_parameter_info_unit_name(),
                offsetof(AudioUnitParameterInfo, unitName));
    CHECK_EQUAL("AudioUnitParameterInfo flags offset",
                zig_auv2_offsetof_parameter_info_flags(),
                offsetof(AudioUnitParameterInfo, flags));
    CHECK_EQUAL("AudioUnitParameterEvent size",
                zig_auv2_sizeof_parameter_event(),
                sizeof(AudioUnitParameterEvent));
    CHECK_EQUAL("AudioUnitParameterEvent values offset",
                zig_auv2_offsetof_parameter_event_values(),
                offsetof(AudioUnitParameterEvent, eventValues));
    CHECK_EQUAL("AudioUnitParameterEvent ramp size",
                zig_auv2_sizeof_parameter_ramp_event(),
                sizeof(((AudioUnitParameterEvent *)0)->eventValues.ramp));
    CHECK_EQUAL("AudioUnitParameterEvent ramp duration offset",
                zig_auv2_offsetof_parameter_ramp_duration(),
                offsetof(AudioUnitParameterEvent,
                         eventValues.ramp.durationInFrames) -
                    offsetof(AudioUnitParameterEvent, eventValues));
    CHECK_EQUAL("AudioUnitParameterEvent ramp start value offset",
                zig_auv2_offsetof_parameter_ramp_start_value(),
                offsetof(AudioUnitParameterEvent,
                         eventValues.ramp.startValue) -
                    offsetof(AudioUnitParameterEvent, eventValues));
    CHECK_EQUAL("AudioUnitParameterEvent ramp end value offset",
                zig_auv2_offsetof_parameter_ramp_end_value(),
                offsetof(AudioUnitParameterEvent,
                         eventValues.ramp.endValue) -
                    offsetof(AudioUnitParameterEvent, eventValues));
    CHECK_EQUAL("ramped parameter event",
                zig_auv2_parameter_event_ramped(),
                kParameterEvent_Ramped);
    CHECK_EQUAL("render selector", zig_auv2_selector_render(),
                kAudioUnitRenderSelect);
    CHECK_EQUAL("add-property-listener selector",
                zig_auv2_selector_add_property_listener(),
                kAudioUnitAddPropertyListenerSelect);
    CHECK_EQUAL("remove-property-listener selector",
                zig_auv2_selector_remove_property_listener(),
                kAudioUnitRemovePropertyListenerSelect);
    CHECK_EQUAL("remove-property-listener-with-user-data selector",
                zig_auv2_selector_remove_property_listener_with_user_data(),
                kAudioUnitRemovePropertyListenerWithUserDataSelect);
    CHECK_EQUAL("add-render-notify selector",
                zig_auv2_selector_add_render_notify(),
                kAudioUnitAddRenderNotifySelect);
    CHECK_EQUAL("remove-render-notify selector",
                zig_auv2_selector_remove_render_notify(),
                kAudioUnitRemoveRenderNotifySelect);
    CHECK_EQUAL("post-render-error action flag",
                zig_auv2_render_action_post_render_error(),
                kAudioUnitRenderAction_PostRenderError);
    CHECK_EQUAL("maximum-frames property",
                zig_auv2_property_maximum_frames(),
                kAudioUnitProperty_MaximumFramesPerSlice);
    CHECK_EQUAL("class-info property",
                zig_auv2_property_class_info(),
                kAudioUnitProperty_ClassInfo);
    return 0;
}
