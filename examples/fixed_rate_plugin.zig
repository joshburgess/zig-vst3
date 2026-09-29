const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const support = @import("fixed_rate_core.zig");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const Spec = core.plugin.PluginSpec(support.RuntimeProcessor);
const fixed_rate_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0x89002E15, 0x6D64498B, 0xB10D70C8, 0xAE015B7B);
pub const fixed_rate_controller_cid = vst3.tuid.inlineUid(0xB46987B8, 0xD2214C2E, 0x86AA807E, 0x48C71220);

const Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect(
        support.RuntimeProcessor,
        struct {
            pub const component_name = "FixedRateComponent";
            pub const controller_cid = fixed_rate_controller_cid;
        },
    );

const Controller =
    vst3.zig_vst3_plugin_effect.HighLevelEditController(
        support.RuntimeProcessor,
        "FixedRateController",
    );

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = fixed_rate_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "fixed-rate component reports prepared SRC latency" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);
    const processor = Effect.processorInstance(component);
    try processor.prepareChecked(.{
        .sample_rate = 44_100,
        .max_block_size = 1024,
    });
    try std.testing.expectEqual(@as(u32, 31), processor.latencySamples());
    const telemetry =
        vst3.gui_telemetry_source.query(component) orelse
        return error.MissingTelemetry;
    defer telemetry.release();
    try std.testing.expectEqual(
        @as(f64, 31),
        telemetry.load(
            support.RuntimeProcessor.latency_telemetry_source_id,
        ),
    );
}

test "fixed-rate component coalesces latency and I/O changes into host restarts" {
    const Handler = vst3.vst_component_handler.ComponentHandler(struct {});
    var handler = Handler{};

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
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setComponentHandler(controller, handler.asHandler()));
    defer _ = controller.vtable.setComponentHandler(controller, null);
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller.vtable.queryInterface(controller, &vst.ivstmessage.iconnection_point_iid, &controller_connection_out));
    const controller_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingConnection));
    defer _ = controller_connection.vtable.release(controller_connection);
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));
    defer _ = controller_connection.vtable.disconnect(controller_connection, component_connection);
    try std.testing.expectEqual(types.kResultOk, component_connection.vtable.connect(component_connection, controller_connection));
    defer _ = component_connection.vtable.disconnect(component_connection, controller_connection);

    const processor = Effect.processorInstance(component);
    try processor.prepareChecked(.{
        .sample_rate = 96_000,
        .max_block_size = 64,
    });
    try std.testing.expect(
        processor.runtime.instance.plugin.requestFixedRate(false),
    );
    try std.testing.expectEqual(@as(u32, 1), handler.restart_count);
    try std.testing.expectEqual(vst.ivsteditcontroller.RestartFlags.kLatencyChanged, handler.last_restart_flags);
    try std.testing.expect(
        processor.runtime.instance.plugin.requestFixedRate(false),
    );
    try std.testing.expectEqual(@as(u32, 1), handler.restart_count);

    Effect.markLatencyChanged(component);
    Effect.markLatencyChanged(component);
    const host_requests =
        processor.runtime.instance.plugin.engine.host_requests orelse
        return error.MissingHostRequests;
    host_requests.markIoChanged();
    host_requests.markIoChanged();
    try std.testing.expectEqual(types.kResultOk, Effect.dispatchHostRequests(component));
    try std.testing.expectEqual(@as(u32, 2), handler.restart_count);
    try std.testing.expectEqual(
        vst.ivsteditcontroller.RestartFlags.kLatencyChanged |
            vst.ivsteditcontroller.RestartFlags.kIoChanged,
        handler.last_restart_flags,
    );
}

test "fixed-rate component restores its prepared mode and latency" {
    const Stream = vst3.vst_stream.FixedBufferStream(128);
    var stream = Stream{};

    var source_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &source_out));
    const source: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(source_out orelse return error.MissingComponent));
    defer _ = source.vtable.release(source);
    const source_processor = Effect.processorInstance(source);
    var mode_bytes = [_]u8{ 'F', 'X', 'R', 'T', 1, 0, 0 };
    var mode_reader = std.Io.Reader.fixed(&mode_bytes);
    try source_processor.readComponentState(&mode_reader);
    try std.testing.expectEqual(types.kResultOk, source.vtable.getState(source, stream.asStream()));

    var restored_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &restored_out));
    const restored: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(restored_out orelse return error.MissingComponent));
    defer _ = restored.vtable.release(restored);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, restored.vtable.setState(restored, stream.asStream()));
    const restored_processor = Effect.processorInstance(restored);
    try restored_processor.prepareChecked(.{
        .sample_rate = 96_000,
        .max_block_size = 64,
    });
    try std.testing.expectEqual(@as(u32, 0), restored_processor.latencySamples());

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setComponentState(controller, stream.asStream()));
}
