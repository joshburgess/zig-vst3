const plug = @import("zig-vst3-plugin");
const std = @import("std");
const vst3 = @import("zig-vst3");

const core = plug.core;
const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

const Definition =
    @import("aux_output_splitter_core.zig").AuxiliaryOutputSplitter;

pub const Spec = core.plugin.PluginSpec(Definition);
const splitter_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0xD04A61B7, 0xE63548ED, 0x97C23A18, 0x0DE39942);
pub const splitter_controller_cid = vst3.tuid.inlineUid(0x37EE8519, 0x60624D39, 0xA2B5FC71, 0xF9839B26);

const Effect = plug.Vst3Effect(Definition, struct {
    pub const component_name = "AuxiliaryOutputSplitterComponent";
    pub const controller_cid = splitter_controller_cid;
});

const Controller = plug.Vst3Controller(
    Definition,
    "AuxiliaryOutputSplitterController",
);

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = splitter_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "auxiliary output splitter exposes main and two auxiliary output buses" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    const audio = @intFromEnum(vst.ivstcomponent.MediaTypes.kAudio);
    const output = @intFromEnum(vst.ivstcomponent.BusDirections.kOutput);
    try std.testing.expectEqual(@as(types.int32, 3), component.vtable.getBusCount(component, audio, output));

    var info: vst.ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(component, audio, output, 1, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);
    try std.testing.expectEqual(@intFromEnum(vst.ivstcomponent.BusTypes.kAux), info.busType);
    try std.testing.expectEqual(@as(types.uint32, 0), info.flags);
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(component, audio, output, 2, &info));
    try std.testing.expectEqual(@as(types.int32, 2), info.channelCount);
    try std.testing.expectEqual(@intFromEnum(vst.ivstcomponent.BusTypes.kAux), info.busType);
    try std.testing.expectEqual(@as(types.uint32, 0), info.flags);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *vst.ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var inputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.kStereo};
    var outputs = [_]vst.vsttypes.SpeakerArrangement{
        vst.vstspeaker.SpeakerArr.kStereo,
        vst.vstspeaker.SpeakerArr.kMono,
        vst.vstspeaker.SpeakerArr.kStereo,
    };
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 3));
    outputs[1] = vst.vstspeaker.SpeakerArr.kStereo;
    try std.testing.expectEqual(types.kResultFalse, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 3));
}
