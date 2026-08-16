const plug = @import("zig-vst3-plugin");
const std = @import("std");
const vst3 = @import("zig-vst3");

const core = plug.core;
const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

const Definition =
    @import("surround_gain_core.zig").SurroundGain;

pub const Spec = core.plugin.PluginSpec(Definition);
const surround_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0x4697E2CA, 0x6C404099, 0xB070052C, 0x54C431EE);
pub const surround_controller_cid = vst3.tuid.inlineUid(0x1725A278, 0xA57044B5, 0xB236C65F, 0xD09E8E68);

const Effect = plug.Vst3Effect(Definition, struct {
    pub const component_name = "SurroundGainComponent";
    pub const controller_cid = surround_controller_cid;
});

const Controller = plug.Vst3Controller(
    Definition,
    "SurroundGainController",
);

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = surround_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "surround gain exposes exact 5.1 buses and arrangements" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    var info: vst.ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(component, @intFromEnum(vst.ivstcomponent.MediaTypes.kAudio), @intFromEnum(vst.ivstcomponent.BusDirections.kInput), 0, &info));
    try std.testing.expectEqual(@as(types.int32, 6), info.channelCount);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *vst.ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var inputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.k51};
    var outputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.k51};
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 1));
    inputs[0] = vst.vstspeaker.SpeakerArr.kStereo;
    try std.testing.expectEqual(types.kResultFalse, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 1));
}
