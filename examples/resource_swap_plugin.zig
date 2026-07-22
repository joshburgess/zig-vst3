const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const support = @import("resource_swap_core.zig");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const Spec = core.plugin.PluginSpec(support.ResourceSwap);
const resource_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0xC53F6721, 0x4B3A4CB2, 0xB7715B8D, 0x631128D4);
pub const resource_controller_cid = vst3.tuid.inlineUid(0xA8F14DB5, 0xE0614ED5, 0x9CF50412, 0x98D7AB62);

const Effect = vst3.zig_vst3_plugin_effect.SimpleEffect(struct {
    pub const component_name = "ResourceSwapComponent";
    pub const controller_cid = resource_controller_cid;
    pub const audio_input_layout = Spec.audio_input_layout;
    pub const audio_output_layout = Spec.audio_output_layout;
    pub const event_input = false;
    pub const Params = Spec.Params;
    pub const parameter_set = &resource_parameter_set;
    pub const Processor = support.Processor;
});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ResourceSwapController";
    pub const Params = Spec.Params;
    pub const parameter_set = &resource_parameter_set;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = resource_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "resource swap component prepares before processing without an editor" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);
    const processor = Effect.processorInstance(component);
    try std.testing.expect(processor.waitForPreparation());
}
