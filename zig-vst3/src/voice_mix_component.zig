const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const plug_state = @import("zig-vst3-plugin-core").state;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const voice_mix_controller = @import("voice_mix_controller.zig");
const voice_mix_spec = @import("voice_mix_spec.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x1B74B03C, 0xFA7B4B7D, 0x8B8429F7, 0xA1A1418F);

const VoiceMixProcessor = struct {
    pub fn process(_: VoiceMixProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(voice_mix_controller.voiceGain());
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "VoiceMixComponent";
    pub const controller_cid = voice_mix_controller.cid;
    pub const Processor = VoiceMixProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        voice_mix_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return voice_mix_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return voice_mix_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "voice mix component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "voice mix component applies host parameter changes through processor shell" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    defer voice_mix_controller.applyParameterChanges(.{ .items = &.{.{
        .id = voice_mix_controller.voices_param_id,
        .sample_offset = 0,
        .normalized = 0.0,
    }} });

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const voices_queue = changes.addQueue(voice_mix_controller.voices_param_id).?;
    try std.testing.expectEqual(types.kResultOk, voices_queue.appendPoint(0, 1.0));

    var input_samples = [_]f32{ 0.5, -0.25, 0.125 };
    var output_samples = [_]f32{ 0.0, 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = &output_channel_ptrs },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 2.0, -1.0, 0.5 }, &output_samples);
    try std.testing.expectEqual(@as(f64, 4.0), voice_mix_controller.voiceGain());
}

test "voice mix component applies host parameter changes through double precision processor shell" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    defer voice_mix_controller.applyParameterChanges(.{ .items = &.{.{
        .id = voice_mix_controller.voices_param_id,
        .sample_offset = 0,
        .normalized = 0.0,
    }} });

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const voices_queue = changes.addQueue(voice_mix_controller.voices_param_id).?;
    try std.testing.expectEqual(types.kResultOk, voices_queue.appendPoint(0, 1.0));

    var input_samples = [_]f64{ 0.5, -0.25, 0.125 };
    var output_samples = [_]f64{ 0.0, 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f64{&input_samples};
    var output_channel_ptrs = [_][*]f64{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = &output_channel_ptrs },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f64, &.{ 2.0, -1.0, 0.5 }, &output_samples);
    try std.testing.expectEqual(@as(f64, 4.0), voice_mix_controller.voiceGain());
}

test "voice mix component round-trips voice state through host callbacks" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    voice_mix_controller.applyParameterChanges(.{ .items = &.{.{
        .id = voice_mix_controller.voices_param_id,
        .sample_offset = 0,
        .normalized = 1.0,
    }} });
    defer voice_mix_controller.applyParameterChanges(.{ .items = &.{.{
        .id = voice_mix_controller.voices_param_id,
        .sample_offset = 0,
        .normalized = 0.0,
    }} });

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    const Stream = vst_stream.FixedBufferStream(plug_state.encodedSize(voice_mix_spec.Spec.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_state.encodedSize(voice_mix_spec.Spec.Params)), stream.data().len);

    voice_mix_controller.applyParameterChanges(.{ .items = &.{.{
        .id = voice_mix_controller.voices_param_id,
        .sample_offset = 0,
        .normalized = 0.0,
    }} });
    try std.testing.expectEqual(@as(f64, 1.0), voice_mix_controller.voiceGain());
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(f64, 4.0), voice_mix_controller.voiceGain());
}
