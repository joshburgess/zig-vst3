const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const support = @import("model_shell_core.zig");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const Spec = core.plugin.PluginSpec(support.ModelShell);
const model_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0xCA8B884C, 0xBE224DA2, 0x9113CA6D, 0x993D0E41);
pub const model_shell_controller_cid = vst3.tuid.inlineUid(0x6EAC0BC1, 0x0B7747EC, 0x9588BFDD, 0x4CE008AD);

const Effect = vst3.zig_vst3_plugin_effect.SimpleEffect(struct {
    pub const component_name = "ModelShellComponent";
    pub const controller_cid = model_shell_controller_cid;
    pub const audio_input_layout = Spec.audio_input_layout;
    pub const audio_output_layout = Spec.audio_output_layout;
    pub const event_input = false;
    pub const Params = Spec.Params;
    pub const parameter_set = &model_parameter_set;
    pub const Processor = support.Processor;
});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ModelShellController";
    pub const Params = Spec.Params;
    pub const parameter_set = &model_parameter_set;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = model_shell_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "model shell component restores a resource without an editor" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "linear.json",
        .data = "{\"version\":1,\"gain\":1.5,\"sample_rate\":48000}",
    });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "linear.json", &path);

    var first_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &first_out));
    const first: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(first_out orelse return error.MissingComponent));
    defer _ = first.vtable.release(first);
    const first_processor = Effect.processorInstance(first);
    try std.testing.expect(first_processor.importModel(path[0..path_length]));
    first_processor.waitForModel();

    const Stream = vst3.vst_stream.FixedBufferStream(2048);
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, first.vtable.getState(first, stream.asStream()));

    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &second_out));
    const second: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(second_out orelse return error.MissingComponent));
    defer _ = second.vtable.release(second);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, second.vtable.setState(second, stream.asStream()));
    const second_processor = Effect.processorInstance(second);
    second_processor.models.preparation.wait();
    try std.testing.expectEqual(core.resource.RecoveryStatus.ready, second_processor.resourceSnapshot().status);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setComponentState(controller, stream.asStream()));
}
