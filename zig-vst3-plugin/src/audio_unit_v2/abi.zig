pub const OSStatus = i32;
pub const OSType = u32;
pub const AudioUnitPropertyID = u32;
pub const AudioUnitScope = u32;
pub const AudioUnitElement = u32;
pub const AudioUnitParameterID = u32;
pub const AudioUnitParameterValue = f32;
pub const AudioUnitParameterUnit = u32;
pub const AudioUnitParameterOptions = u32;
pub const AudioUnitRenderActionFlags = u32;
pub const Boolean = u8;

pub const AudioStreamBasicDescription = extern struct {
    sample_rate: f64,
    format_id: u32,
    format_flags: u32,
    bytes_per_packet: u32,
    frames_per_packet: u32,
    bytes_per_frame: u32,
    channels_per_frame: u32,
    bits_per_channel: u32,
    reserved: u32,
};

pub const SMPTETime = extern struct {
    subframes: i16,
    subframe_divisor: i16,
    counter: u32,
    time_type: u32,
    flags: u32,
    hours: i16,
    minutes: i16,
    seconds: i16,
    frames: i16,
};

pub const AudioTimeStamp = extern struct {
    sample_time: f64,
    host_time: u64,
    rate_scalar: f64,
    word_clock_time: u64,
    smpte_time: SMPTETime,
    flags: u32,
    reserved: u32,
};

pub const timestamp_flag = struct {
    pub const sample_time_valid: u32 = 1 << 0;
    pub const host_time_valid: u32 = 1 << 1;
};

pub const AUChannelInfo = extern struct {
    input_channels: i16,
    output_channels: i16,
};

pub const AudioUnitParameterInfo = extern struct {
    name: [52]u8,
    unit_name: ?*const anyopaque,
    clump_id: u32,
    cf_name_string: ?*const anyopaque,
    unit: AudioUnitParameterUnit,
    min_value: AudioUnitParameterValue,
    max_value: AudioUnitParameterValue,
    default_value: AudioUnitParameterValue,
    flags: AudioUnitParameterOptions,
};

pub const AUParameterEventType = u32;

pub const parameter_event_type = struct {
    pub const immediate: AUParameterEventType = 1;
    pub const ramped: AUParameterEventType = 2;
};

pub const AudioUnitParameterRampEvent = extern struct {
    start_buffer_offset: i32,
    duration_in_frames: u32,
    start_value: AudioUnitParameterValue,
    end_value: AudioUnitParameterValue,
};

pub const AudioUnitParameterImmediateEvent = extern struct {
    buffer_offset: u32,
    value: AudioUnitParameterValue,
};

pub const AudioUnitParameterEvent = extern struct {
    parameter_scope: AudioUnitScope,
    element: AudioUnitElement,
    parameter: AudioUnitParameterID,
    event_type: AUParameterEventType,
    event_values: extern union {
        ramp: AudioUnitParameterRampEvent,
        immediate: AudioUnitParameterImmediateEvent,
    },
};

pub const AudioComponentDescription = extern struct {
    component_type: OSType,
    component_subtype: OSType,
    component_manufacturer: OSType,
    component_flags: u32,
    component_flags_mask: u32,
};

pub const AudioBuffer = extern struct {
    number_channels: u32,
    data_byte_size: u32,
    data: ?*anyopaque,
};

pub const AudioBufferList = extern struct {
    number_buffers: u32,
    buffers: [1]AudioBuffer,
};

pub const AURenderCallback = *const fn (
    reference: ?*anyopaque,
    action_flags: ?*AudioUnitRenderActionFlags,
    timestamp: ?*const AudioTimeStamp,
    bus: u32,
    frame_count: u32,
    data: *AudioBufferList,
) callconv(.c) OSStatus;

pub const AudioUnitPropertyListenerProc = *const fn (
    reference: ?*anyopaque,
    unit: AudioComponentInstance,
    property_id: AudioUnitPropertyID,
    property_scope: AudioUnitScope,
    element: AudioUnitElement,
) callconv(.c) void;

pub const AURenderCallbackStruct = extern struct {
    input: ?AURenderCallback,
    reference: ?*anyopaque,
};

pub const AudioComponentInstance = *opaque {};
pub const AudioComponentMethod = *const anyopaque;

pub const AudioComponentPlugInInterface = extern struct {
    open: *const fn (
        self: *anyopaque,
        instance: AudioComponentInstance,
    ) callconv(.c) OSStatus,
    close: *const fn (self: *anyopaque) callconv(.c) OSStatus,
    lookup: *const fn (
        selector: i16,
    ) callconv(.c) ?AudioComponentMethod,
    reserved: ?*anyopaque,
};

pub const selector = struct {
    pub const initialize: i16 = 0x0001;
    pub const uninitialize: i16 = 0x0002;
    pub const get_property_info: i16 = 0x0003;
    pub const get_property: i16 = 0x0004;
    pub const set_property: i16 = 0x0005;
    pub const get_parameter: i16 = 0x0006;
    pub const set_parameter: i16 = 0x0007;
    pub const reset: i16 = 0x0009;
    pub const add_property_listener: i16 = 0x000a;
    pub const remove_property_listener: i16 = 0x000b;
    pub const render: i16 = 0x000e;
    pub const add_render_notify: i16 = 0x000f;
    pub const remove_render_notify: i16 = 0x0010;
    pub const schedule_parameters: i16 = 0x0011;
    pub const remove_property_listener_with_user_data: i16 = 0x0012;
    pub const complex_render: i16 = 0x0013;
    pub const process: i16 = 0x0014;
    pub const process_multiple: i16 = 0x0015;
};

pub const scope = struct {
    pub const global: AudioUnitScope = 0;
    pub const input: AudioUnitScope = 1;
    pub const output: AudioUnitScope = 2;
    pub const group: AudioUnitScope = 3;
    pub const part: AudioUnitScope = 4;
    pub const note: AudioUnitScope = 5;
    pub const layer: AudioUnitScope = 6;
    pub const layer_item: AudioUnitScope = 7;
};

pub const property = struct {
    pub const class_info: AudioUnitPropertyID = 0;
    pub const make_connection: AudioUnitPropertyID = 1;
    pub const sample_rate: AudioUnitPropertyID = 2;
    pub const parameter_list: AudioUnitPropertyID = 3;
    pub const parameter_info: AudioUnitPropertyID = 4;
    pub const stream_format: AudioUnitPropertyID = 8;
    pub const element_count: AudioUnitPropertyID = 11;
    pub const latency: AudioUnitPropertyID = 12;
    pub const supported_channel_counts: AudioUnitPropertyID = 13;
    pub const maximum_frames_per_slice: AudioUnitPropertyID = 14;
    pub const tail_time: AudioUnitPropertyID = 20;
    pub const set_render_callback: AudioUnitPropertyID = 23;
    pub const host_callbacks: AudioUnitPropertyID = 27;
    pub const in_place_processing: AudioUnitPropertyID = 29;
};

pub const parameter_unit = struct {
    pub const generic: AudioUnitParameterUnit = 0;
    pub const indexed: AudioUnitParameterUnit = 1;
    pub const boolean: AudioUnitParameterUnit = 2;
    pub const percent: AudioUnitParameterUnit = 3;
    pub const seconds: AudioUnitParameterUnit = 4;
    pub const sample_frames: AudioUnitParameterUnit = 5;
    pub const phase: AudioUnitParameterUnit = 6;
    pub const rate: AudioUnitParameterUnit = 7;
    pub const hertz: AudioUnitParameterUnit = 8;
    pub const cents: AudioUnitParameterUnit = 9;
    pub const relative_semitones: AudioUnitParameterUnit = 10;
    pub const midi_note_number: AudioUnitParameterUnit = 11;
    pub const midi_controller: AudioUnitParameterUnit = 12;
    pub const decibels: AudioUnitParameterUnit = 13;
    pub const linear_gain: AudioUnitParameterUnit = 14;
    pub const degrees: AudioUnitParameterUnit = 15;
    pub const pan: AudioUnitParameterUnit = 18;
    pub const bpm: AudioUnitParameterUnit = 22;
    pub const beats: AudioUnitParameterUnit = 23;
    pub const milliseconds: AudioUnitParameterUnit = 24;
    pub const ratio: AudioUnitParameterUnit = 25;
};

pub const parameter_flag = struct {
    pub const values_have_strings: AudioUnitParameterOptions = 1 << 21;
    pub const display_logarithmic: AudioUnitParameterOptions = 1 << 22;
    pub const is_high_resolution: AudioUnitParameterOptions = 1 << 23;
    pub const can_ramp: AudioUnitParameterOptions = 1 << 25;
    pub const is_readable: AudioUnitParameterOptions = 1 << 30;
    pub const is_writable: AudioUnitParameterOptions = 1 << 31;
};

pub const render_action = struct {
    pub const pre_render: AudioUnitRenderActionFlags = 1 << 2;
    pub const post_render: AudioUnitRenderActionFlags = 1 << 3;
    pub const output_is_silence: AudioUnitRenderActionFlags = 1 << 4;
    pub const offline_preflight: AudioUnitRenderActionFlags = 1 << 5;
    pub const offline_render: AudioUnitRenderActionFlags = 1 << 6;
    pub const offline_complete: AudioUnitRenderActionFlags = 1 << 7;
    pub const post_render_error: AudioUnitRenderActionFlags = 1 << 8;
    pub const do_not_check_render_args: AudioUnitRenderActionFlags = 1 << 9;
};

pub const audio_format = struct {
    pub const linear_pcm: u32 = 0x6c70636d;
    pub const is_float: u32 = 1 << 0;
    pub const is_packed: u32 = 1 << 3;
    pub const is_non_interleaved: u32 = 1 << 5;
    pub const native_float_non_interleaved =
        is_float | is_packed | is_non_interleaved;
};

pub const status = struct {
    pub const success: OSStatus = 0;
    pub const invalid_property: OSStatus = -10879;
    pub const invalid_parameter: OSStatus = -10878;
    pub const invalid_element: OSStatus = -10877;
    pub const no_connection: OSStatus = -10876;
    pub const failed_initialization: OSStatus = -10875;
    pub const too_many_frames: OSStatus = -10874;
    pub const format_not_supported: OSStatus = -10868;
    pub const uninitialized: OSStatus = -10867;
    pub const invalid_scope: OSStatus = -10866;
    pub const property_not_writable: OSStatus = -10865;
    pub const cannot_do_in_current_context: OSStatus = -10863;
    pub const invalid_property_value: OSStatus = -10851;
    pub const property_not_in_use: OSStatus = -10850;
    pub const initialized: OSStatus = -10849;
};
