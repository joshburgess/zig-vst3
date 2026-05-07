const gain_controller = @import("gain_controller.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0xA74E7A0D, 0x6B234163, 0xA0A83EBF, 0xD06F1401);

const GainProcessor = struct {
    pub fn process(_: GainProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(gain_controller.gain());
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

const Effect = zig_plug_effect.SimpleStereoEffect(struct {
    pub const component_name = "GainComponent";
    pub const controller_cid = gain_controller.cid;
    pub const Processor = GainProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        gain_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return gain_controller.readGainState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return gain_controller.writeGainState(state);
    }
});

pub const create = Effect.create;

test "gain component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "gain component exposes process context requirements" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iprocess_context_requirements_iid, &requirements_out),
    );
    try std.testing.expect(requirements_out != null);
    const requirements: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(requirements_out.?));
    defer _ = requirements.vtable.release(requirements);

    try std.testing.expectEqual(@as(types.uint32, 0), requirements.vtable.getProcessContextRequirements(requirements));

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var processor_requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.queryInterface(processor, &ivstaudioprocessor.iprocess_context_requirements_iid, &processor_requirements_out),
    );
    try std.testing.expect(processor_requirements_out != null);
    const processor_requirements: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(processor_requirements_out.?));
    defer _ = processor_requirements.vtable.release(processor_requirements);

    try std.testing.expectEqual(@as(types.uint32, 0), processor_requirements.vtable.getProcessContextRequirements(processor_requirements));
}
