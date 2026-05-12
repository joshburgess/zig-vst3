const bypass_controller = @import("bypass_controller.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x69B21F85, 0x804045F7, 0x9F452845, 0xC7B18EE0);

const BypassProcessor = struct {
    pub fn process(_: BypassProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const bypassed = bypass_controller.bypassed();
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = if (bypassed) input[sample] else 0;
            }
        }
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "BypassComponent";
    pub const controller_cid = bypass_controller.cid;
    pub const Processor = BypassProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        bypass_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return bypass_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return bypass_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "bypass component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "bypass component applies host parameter changes through processor shell" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    defer bypass_controller.applyParameterChanges(.{ .items = &.{.{
        .id = bypass_controller.bypass_param_id,
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
    const bypass_queue = changes.addQueue(bypass_controller.bypass_param_id).?;
    try std.testing.expectEqual(types.kResultOk, bypass_queue.appendPoint(0, 1.0));

    var input_samples = [_]f32{ 0.75, -0.25, 0.125 };
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
    try std.testing.expectEqualSlices(f32, &input_samples, &output_samples);
    try std.testing.expect(bypass_controller.bypassed());
}
