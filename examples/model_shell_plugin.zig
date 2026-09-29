const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const support = @import("model_shell_core.zig");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const Spec = core.plugin.PluginSpec(
    support.RuntimeProcessor,
);
const model_parameter_set = support.parameter_set;

pub const component_cid = vst3.tuid.inlineUid(0xCA8B884C, 0xBE224DA2, 0x9113CA6D, 0x993D0E41);
pub const model_shell_controller_cid = vst3.tuid.inlineUid(0x6EAC0BC1, 0x0B7747EC, 0x9588BFDD, 0x4CE008AD);
const model_resource_target_id = 1;

const Vst3ModelShellProcessor =
    vst3.zig_vst3_plugin_runtime_adapter.Processor(
        support.RuntimeProcessor,
    );

const Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect(
        support.RuntimeProcessor,
        struct {
            pub const component_name = "ModelShellComponent";
            pub const controller_cid = model_shell_controller_cid;
            pub const resource_path_target_id =
                model_resource_target_id;
        },
    );

const Controller =
    vst3.zig_vst3_plugin_effect.HighLevelEditController(
        support.RuntimeProcessor,
        "ModelShellController",
    );

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
    const first_adapter = Effect.processorInstance(first);
    try std.testing.expect(first_adapter.supportsSampleType(f32));
    try std.testing.expect(first_adapter.supportsSampleType(f64));
    try std.testing.expect(Vst3ModelShellProcessor.hasResourcePathReceiver);
    try std.testing.expect(Vst3ModelShellProcessor.hasGuiTelemetryLoad);
    try std.testing.expect(Vst3ModelShellProcessor.hasGuiTelemetryLoadText);
    try std.testing.expectEqual(
        support.RuntimeProcessor.component_state_maximum_encoded_size,
        Vst3ModelShellProcessor.component_state_maximum_encoded_size,
    );
    const first_processor =
        &first_adapter.runtime.instance.plugin;
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
    const second_processor =
        &Effect.processorInstance(second).runtime.instance.plugin;
    second_processor.waitForModel();
    try std.testing.expectEqual(core.resource.RecoveryStatus.ready, second_processor.resourceSnapshot().status);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setComponentState(controller, stream.asStream()));
}

test "model shell controller routes bounded resource recovery commands" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const model = "{\"version\":1,\"gain\":1.25,\"sample_rate\":48000}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "model.json", .data = model });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "moved.json", .data = model });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "invalid.json", .data = "not a model" });
    var model_path: [1024]u8 = undefined;
    const model_length = try temporary.dir.realPathFile(std.testing.io, "model.json", &model_path);
    var moved_path: [1024]u8 = undefined;
    const moved_length = try temporary.dir.realPathFile(std.testing.io, "moved.json", &moved_path);
    var invalid_path: [1024]u8 = undefined;
    const invalid_length = try temporary.dir.realPathFile(std.testing.io, "invalid.json", &invalid_path);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);
    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstmessage.iconnection_point_iid, &component_connection_out));
    const component_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out orelse return error.MissingConnection));
    defer _ = component_connection.vtable.release(component_connection);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller.vtable.queryInterface(controller, &vst.ivstmessage.iconnection_point_iid, &controller_connection_out));
    const controller_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingConnection));
    defer _ = controller_connection.vtable.release(controller_connection);
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));

    const telemetry = Controller.retainGuiTelemetry(controller) orelse return error.MissingTelemetry;
    defer telemetry.release();

    const processor =
        &Effect.processorInstance(component).runtime.instance.plugin;
    try std.testing.expectEqual(types.kResultOk, Controller.importResourcePath(
        controller,
        model_resource_target_id,
        model_path[0..model_length],
    ));
    processor.waitForModel();
    try std.testing.expectEqual(core.resource.RecoveryStatus.ready, processor.resourceSnapshot().status);
    try std.testing.expectEqual(
        @as(f64, @floatFromInt(@intFromEnum(core.resource.RecoveryStatus.ready))),
        telemetry.load(support.resource_status_source_id),
    );
    try std.testing.expectEqual(@as(f64, 1.0), telemetry.load(support.resource_progress_source_id));
    try std.testing.expectEqual(@as(f64, 0.0), telemetry.load(support.resource_can_cancel_source_id));
    try std.testing.expectEqual(@as(f64, 0.0), telemetry.load(support.resource_can_retry_source_id));
    var text: [128]u8 = undefined;
    var text_length = telemetry.loadText(support.resource_status_source_id, &text);
    try std.testing.expectEqualStrings("ready", text[0..text_length]);
    text_length = telemetry.loadText(support.resource_metadata_source_id, &text);
    try std.testing.expectEqualStrings("Linear, 48000 Hz, gain 1.250", text[0..text_length]);
    try std.testing.expectEqual(@as(f64, 0.0), telemetry.load(support.resource_cancellation_pending_source_id));
    var short_text: [6]u8 = undefined;
    const short_length = telemetry.loadText(support.resource_metadata_source_id, &short_text);
    try std.testing.expectEqualStrings("Linear", short_text[0..short_length]);

    try std.testing.expectEqual(types.kResultOk, Controller.relinkResourcePath(
        controller,
        model_resource_target_id,
        moved_path[0..moved_length],
    ));
    processor.waitForModel();
    const relinked = processor.resourceSnapshot();
    try std.testing.expectEqual(core.resource.RecoveryStatus.ready, relinked.status);
    try std.testing.expectEqual(core.resource.RecoveryStatus.moved, relinked.resolution);

    try std.testing.expectEqual(types.kResultOk, Controller.importResourcePath(
        controller,
        model_resource_target_id,
        invalid_path[0..invalid_length],
    ));
    processor.waitForModel();
    try std.testing.expectEqual(core.resource.RecoveryStatus.failed, processor.resourceSnapshot().status);
    text_length = telemetry.loadText(support.resource_status_source_id, &text);
    try std.testing.expectEqualStrings("failed", text[0..text_length]);
    text_length = telemetry.loadText(support.resource_metadata_source_id, &text);
    try std.testing.expectEqualStrings("Linear, 48000 Hz, gain 1.250", text[0..text_length]);
    try std.testing.expectEqual(@as(f64, 1.0), telemetry.load(support.resource_can_retry_source_id));
    try std.testing.expectEqual(types.kResultOk, Controller.retryResourceImport(controller, model_resource_target_id));
    processor.waitForModel();
    try std.testing.expectEqual(core.resource.RecoveryStatus.failed, processor.resourceSnapshot().status);
    try std.testing.expectEqual(types.kResultFalse, Controller.cancelResourceImport(controller, model_resource_target_id));
}
