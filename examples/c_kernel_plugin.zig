const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const support = @import("c_kernel_core.zig");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const Spec = core.plugin.PluginSpec(support.CKernelProbe);
const c_kernel_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0x916A3B59, 0x17F54CD8, 0x89E65394, 0xB6C5DBB2);
pub const c_kernel_controller_cid = vst3.tuid.inlineUid(0x9C98BB59, 0x1B3B46EC, 0xBA24D804, 0xB69715D3);

const Effect = vst3.zig_vst3_plugin_effect.SimpleEffect(struct {
    pub const component_name = "CKernelProbeComponent";
    pub const controller_cid = c_kernel_controller_cid;
    pub const audio_input_layout = Spec.audio_input_layout;
    pub const audio_output_layout = Spec.audio_output_layout;
    pub const event_input = false;
    pub const Params = Spec.Params;
    pub const parameter_set = &c_kernel_parameter_set;
    pub const Processor = support.Processor;
});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "CKernelProbeController";
    pub const Params = Spec.Params;
    pub const parameter_set = &c_kernel_parameter_set;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = c_kernel_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "C kernel probe exposes a mono VST3 processor" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);

    var info: vst.ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(
        component,
        @intFromEnum(vst.ivstcomponent.MediaTypes.kAudio),
        @intFromEnum(vst.ivstcomponent.BusDirections.kInput),
        0,
        &info,
    ));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);
}
