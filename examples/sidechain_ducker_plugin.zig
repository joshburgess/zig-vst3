const plug = @import("zig-vst3-plugin");
const std = @import("std");
const vst3 = @import("zig-vst3");

const core = plug.core;
const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

const Definition =
    @import("sidechain_ducker_core.zig").SidechainDucker;

pub const Spec = core.plugin.PluginSpec(Definition);
const sidechain_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0xF71D6B2A, 0xA25B46A4, 0xBEB35624, 0x942308E1);
pub const sidechain_controller_cid = vst3.tuid.inlineUid(0x658C221F, 0xC49344EC, 0xAD67312C, 0x7FB8AF45);

const Effect = plug.Vst3Effect(Definition, struct {
    pub const component_name = "SidechainDuckerComponent";
    pub const controller_cid = sidechain_controller_cid;
});

const Controller = plug.Vst3Controller(
    Definition,
    "SidechainDuckerController",
);

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = sidechain_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "sidechain ducker exposes main and auxiliary audio input buses" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    const audio = @intFromEnum(vst.ivstcomponent.MediaTypes.kAudio);
    const input = @intFromEnum(vst.ivstcomponent.BusDirections.kInput);
    try std.testing.expectEqual(@as(types.int32, 2), component.vtable.getBusCount(component, audio, input));

    var info: vst.ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(component, audio, input, 1, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);
    try std.testing.expectEqual(@intFromEnum(vst.ivstcomponent.BusTypes.kAux), info.busType);
    try std.testing.expectEqual(@as(types.uint32, 0), info.flags);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *vst.ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var inputs = [_]vst.vsttypes.SpeakerArrangement{
        vst.vstspeaker.SpeakerArr.kStereo,
        vst.vstspeaker.SpeakerArr.kMono,
    };
    var outputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.kStereo};
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setBusArrangements(processor, &inputs, 2, &outputs, 1));
    inputs[1] = vst.vstspeaker.SpeakerArr.kStereo;
    try std.testing.expectEqual(types.kResultFalse, processor.vtable.setBusArrangements(processor, &inputs, 2, &outputs, 1));
}
