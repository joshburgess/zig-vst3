const base_types = @import("../base/types.zig");
const events = @import("ivstevents.zig");
const parameter_changes = @import("ivstparameterchanges.zig");
const process_context = @import("ivstprocesscontext.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iaudio_processor_iid = tuid.inlineUid(0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D);
pub const iaudio_presentation_latency_iid = tuid.inlineUid(0x309ECE78, 0xEB7D4FAE, 0x8B2225D9, 0x09FD08B6);
pub const iprocess_context_requirements_iid = tuid.inlineUid(0x2A654303, 0xEF764E3D, 0x95B5FE83, 0x730EF6D0);

pub const kVstAudioEffectClass: base_types.FIDString = "Audio Module Class";

pub const ComponentFlags = packed struct(base_types.uint32) {
    distributable: bool = false,
    simple_mode_supported: bool = false,
    _: u30 = 0,

    pub const kDistributable: base_types.uint32 = 1 << 0;
    pub const kSimpleModeSupported: base_types.uint32 = 1 << 1;
};

pub const SymbolicSampleSizes = enum(base_types.int32) {
    kSample32 = 0,
    kSample64 = 1,
};

pub const ProcessModes = enum(base_types.int32) {
    kRealtime = 0,
    kPrefetch = 1,
    kOffline = 2,
};

pub const kNoTail: base_types.uint32 = 0;
pub const kInfiniteTail: base_types.uint32 = base_types.kMaxInt32u;

pub const ProcessSetup = extern struct {
    processMode: base_types.int32 = 0,
    symbolicSampleSize: base_types.int32 = 0,
    maxSamplesPerBlock: base_types.int32 = 0,
    sampleRate: vsttypes.SampleRate = 0,
};

pub const AudioBusBuffers = extern struct {
    numChannels: base_types.int32 = 0,
    silenceFlags: base_types.uint64 = 0,
    channelBuffers: extern union {
        channelBuffers32: ?[*][*]vsttypes.Sample32,
        channelBuffers64: ?[*][*]vsttypes.Sample64,
    } = .{ .channelBuffers64 = null },
};

pub const ProcessData = extern struct {
    processMode: base_types.int32 = 0,
    symbolicSampleSize: base_types.int32 = 0,
    numSamples: base_types.int32 = 0,
    numInputs: base_types.int32 = 0,
    numOutputs: base_types.int32 = 0,
    inputs: ?[*]AudioBusBuffers = null,
    outputs: ?[*]AudioBusBuffers = null,
    inputParameterChanges: ?*parameter_changes.IParameterChanges = null,
    outputParameterChanges: ?*parameter_changes.IParameterChanges = null,
    inputEvents: ?*events.IEventList = null,
    outputEvents: ?*events.IEventList = null,
    processContext: ?*process_context.ProcessContext = null,
};

pub const IAudioProcessorVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setBusArrangements: *const fn (*anyopaque, ?[*]vsttypes.SpeakerArrangement, base_types.int32, ?[*]vsttypes.SpeakerArrangement, base_types.int32) callconv(.C) base_types.tresult,
    getBusArrangement: *const fn (*anyopaque, vsttypes.BusDirection, base_types.int32, *vsttypes.SpeakerArrangement) callconv(.C) base_types.tresult,
    canProcessSampleSize: *const fn (*anyopaque, base_types.int32) callconv(.C) base_types.tresult,
    getLatencySamples: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setupProcessing: *const fn (*anyopaque, *ProcessSetup) callconv(.C) base_types.tresult,
    setProcessing: *const fn (*anyopaque, base_types.TBool) callconv(.C) base_types.tresult,
    process: *const fn (*anyopaque, *ProcessData) callconv(.C) base_types.tresult,
    getTailSamples: *const fn (*anyopaque) callconv(.C) base_types.uint32,
};

pub const IAudioProcessor = extern struct {
    vtable: *const IAudioProcessorVTable,
};

pub const IAudioPresentationLatencyVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setAudioPresentationLatencySamples: *const fn (*anyopaque, vsttypes.BusDirection, base_types.int32, base_types.uint32) callconv(.C) base_types.tresult,
};

pub const ProcessContextRequirementFlags = packed struct(base_types.uint32) {
    need_system_time: bool = false,
    need_continous_time_samples: bool = false,
    need_project_time_music: bool = false,
    need_bar_position_music: bool = false,
    need_cycle_music: bool = false,
    need_samples_to_next_clock: bool = false,
    need_tempo: bool = false,
    need_time_signature: bool = false,
    need_chord: bool = false,
    need_frame_rate: bool = false,
    need_transport_state: bool = false,
    _: u21 = 0,

    pub const kNeedSystemTime: base_types.uint32 = 1 << 0;
    pub const kNeedContinousTimeSamples: base_types.uint32 = 1 << 1;
    pub const kNeedProjectTimeMusic: base_types.uint32 = 1 << 2;
    pub const kNeedBarPositionMusic: base_types.uint32 = 1 << 3;
    pub const kNeedCycleMusic: base_types.uint32 = 1 << 4;
    pub const kNeedSamplesToNextClock: base_types.uint32 = 1 << 5;
    pub const kNeedTempo: base_types.uint32 = 1 << 6;
    pub const kNeedTimeSignature: base_types.uint32 = 1 << 7;
    pub const kNeedChord: base_types.uint32 = 1 << 8;
    pub const kNeedFrameRate: base_types.uint32 = 1 << 9;
    pub const kNeedTransportState: base_types.uint32 = 1 << 10;
};

pub const IProcessContextRequirementsVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getProcessContextRequirements: *const fn (*anyopaque) callconv(.C) base_types.uint32,
};

test "audio processor struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 24), @sizeOf(ProcessSetup));
    try @import("std").testing.expectEqual(@as(usize, 24), @sizeOf(AudioBusBuffers));
    try @import("std").testing.expectEqual(@as(usize, 80), @sizeOf(ProcessData));
    try @import("std").testing.expectEqual(@as(usize, 11), @typeInfo(IAudioProcessorVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IAudioPresentationLatencyVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IProcessContextRequirementsVTable).@"struct".fields.len);
}
