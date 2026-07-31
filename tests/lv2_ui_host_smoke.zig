const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const ui = core.lv2.ui;
const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const ui.Descriptor;

const Host = struct {
    writes: usize = 0,
    touches: usize = 0,
    releases: usize = 0,
    resize_requests: usize = 0,
    last_value: f32 = 0.0,

    fn map(
        _: ?*anyopaque,
        uri: [*:0]const u8,
    ) callconv(.c) ui.Urid {
        const value = std.mem.span(uri);
        if (std.mem.eql(u8, value, ui.scale_factor_uri)) return 139;
        if (std.mem.eql(u8, value, ui.atom_float_uri)) return 47;
        return 0;
    }

    fn write(
        controller: ui.Controller,
        port: u32,
        size: u32,
        format: u32,
        buffer: ?*const anyopaque,
    ) callconv(.c) void {
        const raw_host = controller orelse return;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (port != 2 or size != @sizeOf(f32) or format != 0) return;
        const raw_value = buffer orelse return;
        self.last_value =
            @as(*align(1) const f32, @ptrCast(raw_value)).*;
        self.writes += 1;
    }

    fn touch(
        handle: ui.Handle,
        port: u32,
        grabbed: bool,
    ) callconv(.c) c_int {
        const raw_host = handle orelse return 1;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (port != 2) return 1;
        if (grabbed)
            self.touches += 1
        else
            self.releases += 1;
        return 0;
    }

    fn resize(
        handle: ui.Handle,
        width: c_int,
        height: c_int,
    ) callconv(.c) c_int {
        const raw_host = handle orelse return 1;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (width <= 0 or height <= 0) return 1;
        self.resize_requests += 1;
        return 0;
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.InvalidArguments;

    var library = try std.DynLib.open(args[1]);
    defer library.close();
    const descriptor_at = library.lookup(
        DescriptorFunction,
        "lv2ui_descriptor",
    ) orelse return error.MissingLv2UiDescriptor;
    const descriptor = descriptor_at(0) orelse
        return error.MissingLv2UiDescriptor;
    if (descriptor_at(1) != null)
        return error.UnexpectedLv2UiDescriptor;
    if (!std.mem.eql(
        u8,
        std.mem.span(descriptor.URI),
        "https://zig-vst3.dev/tests/lv2-ui-probe#ui",
    )) return error.InvalidLv2UiUri;

    var host = Host{};
    var parent_feature = ui.Feature{
        .URI = ui.parent_uri,
        .data = &host,
    };
    var touch = ui.Touch{
        .handle = &host,
        .touch = Host.touch,
    };
    var touch_feature = ui.Feature{
        .URI = ui.touch_uri,
        .data = &touch,
    };
    var resize = ui.Resize{
        .handle = &host,
        .ui_resize = Host.resize,
    };
    var resize_feature = ui.Feature{
        .URI = ui.resize_uri,
        .data = &resize,
    };
    var urid_map = ui.UridMap{
        .handle = null,
        .map = Host.map,
    };
    var map_feature = ui.Feature{
        .URI = ui.urid_map_uri,
        .data = &urid_map,
    };
    const initial_scale: f32 = 1.25;
    const initial_options = [_]ui.OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &initial_scale,
        },
        .{},
    };
    var options_feature = ui.Feature{
        .URI = ui.options_options_uri,
        .data = @constCast(&initial_options),
    };
    const features = [_:null]?*const ui.Feature{
        &parent_feature,
        &touch_feature,
        &resize_feature,
        &map_feature,
        &options_feature,
    };
    var widget: ui.Widget = null;
    const handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &features,
    ) orelse return error.Lv2UiInstantiationFailed;
    defer descriptor.cleanup(handle);
    if (widget == null) return error.MissingLv2Widget;

    const options_ptr = descriptor.extension_data(
        ui.options_interface_uri,
    ) orelse return error.MissingOptionsInterface;
    const runtime_options: *const ui.OptionsInterface =
        @ptrCast(@alignCast(options_ptr));
    var scale_query = [_]ui.OptionsOption{
        .{ .key = 139 },
        .{},
    };
    if (runtime_options.get(handle, &scale_query) !=
        ui.options_status_success)
        return error.ScaleQueryFailed;
    const queried_scale = scale_query[0].value orelse
        return error.MissingScaleValue;
    if (@as(*align(1) const f32, @ptrCast(queried_scale)).* != 1.25)
        return error.InvalidInitialScale;
    const next_scale: f32 = 2.0;
    const scale_update = [_]ui.OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &next_scale,
        },
        .{},
    };
    if (runtime_options.set(handle, &scale_update) !=
        ui.options_status_success)
        return error.ScaleUpdateFailed;
    scale_query[0] = .{ .key = 139 };
    if (runtime_options.get(handle, &scale_query) !=
        ui.options_status_success)
        return error.UpdatedScaleQueryFailed;
    const updated_scale = scale_query[0].value orelse
        return error.MissingUpdatedScaleValue;
    if (@as(*align(1) const f32, @ptrCast(updated_scale)).* != 2.0)
        return error.InvalidUpdatedScale;

    var second_host = Host{};
    var second_widget: ui.Widget = null;
    const second_handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &second_host,
        &second_widget,
        &features,
    ) orelse return error.SecondLv2UiInstantiationFailed;
    var second_active = true;
    defer if (second_active) descriptor.cleanup(second_handle);
    if (second_widget == null or second_widget == widget)
        return error.InvalidSecondLv2Widget;

    const plain: f32 = 0.25;
    descriptor.port_event(handle, 2, @sizeOf(f32), 0, &plain);
    descriptor.port_event(handle, 2, 1, 0, &plain);
    descriptor.port_event(handle, 2, @sizeOf(f32), 1, &plain);
    const second_plain: f32 = 0.75;
    descriptor.port_event(
        second_handle,
        2,
        @sizeOf(f32),
        0,
        &second_plain,
    );

    const idle_ptr = descriptor.extension_data(
        ui.idle_interface_uri,
    ) orelse return error.MissingIdleInterface;
    const idle: *const ui.IdleInterface =
        @ptrCast(@alignCast(idle_ptr));
    if (idle.idle(handle) != 0) return error.IdleFailed;
    if (idle.idle(second_handle) != 0)
        return error.SecondIdleFailed;

    const resize_ptr = descriptor.extension_data(
        ui.resize_uri,
    ) orelse return error.MissingResizeInterface;
    const resize_interface: *const ui.ResizeInterface =
        @ptrCast(@alignCast(resize_ptr));
    if (resize_interface.ui_resize(handle, 640, 480) != 0)
        return error.ResizeFailed;
    if (resize_interface.ui_resize(handle, 0, 480) == 0)
        return error.InvalidResizeAccepted;
    if (resize_interface.ui_resize(second_handle, 480, 320) != 0)
        return error.SecondResizeFailed;

    const show_ptr = descriptor.extension_data(
        ui.show_interface_uri,
    ) orelse return error.MissingShowInterface;
    const show: *const ui.ShowInterface =
        @ptrCast(@alignCast(show_ptr));
    if (show.show(handle) != 0 or show.hide(handle) != 0)
        return error.ShowHideFailed;
    if (show.show(second_handle) != 0 or
        show.hide(second_handle) != 0)
        return error.SecondShowHideFailed;

    descriptor.cleanup(second_handle);
    second_active = false;
    var reopened_widget: ui.Widget = null;
    const reopened_handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &second_host,
        &reopened_widget,
        &features,
    ) orelse return error.ReopenedLv2UiInstantiationFailed;
    defer descriptor.cleanup(reopened_handle);
    if (reopened_widget == null)
        return error.MissingReopenedLv2Widget;
    if (idle.idle(reopened_handle) != 0)
        return error.ReopenedIdleFailed;
    if (show.show(reopened_handle) != 0 or
        show.hide(reopened_handle) != 0)
        return error.ReopenedShowHideFailed;

    for (0..64) |index| {
        var cycle_widget: ui.Widget = null;
        const cycle_handle = descriptor.instantiate(
            descriptor,
            "https://zig-vst3.dev/tests/lv2-ui-probe",
            "/tmp/lv2-ui-probe.lv2",
            Host.write,
            &second_host,
            &cycle_widget,
            &features,
        ) orelse return error.LifecycleStressInstantiationFailed;
        const cycle_value: f32 =
            @floatFromInt(index % 5);
        descriptor.port_event(
            cycle_handle,
            2,
            @sizeOf(f32),
            0,
            &cycle_value,
        );
        const idle_status = idle.idle(cycle_handle);
        const resize_status = resize_interface.ui_resize(
            cycle_handle,
            @intCast(320 + index % 4),
            @intCast(200 + index % 3),
        );
        const show_status = show.show(cycle_handle);
        const hide_status = show.hide(cycle_handle);
        descriptor.cleanup(cycle_handle);
        if (cycle_widget == null or idle_status != 0 or
            resize_status != 0 or show_status != 0 or
            hide_status != 0)
            return error.LifecycleStressFailed;
    }

    const misaligned: ui.Handle =
        @ptrFromInt(@intFromPtr(handle) + 1);
    descriptor.port_event(
        misaligned,
        2,
        @sizeOf(f32),
        0,
        &plain,
    );
    if (idle.idle(null) == 0 or idle.idle(misaligned) == 0)
        return error.InvalidIdleHandleAccepted;
    if (resize_interface.ui_resize(null, 640, 480) == 0 or
        resize_interface.ui_resize(misaligned, 640, 480) == 0)
        return error.InvalidResizeHandleAccepted;
    if (show.show(null) == 0 or show.hide(misaligned) == 0)
        return error.InvalidShowHideHandleAccepted;
    descriptor.cleanup(null);
    descriptor.cleanup(misaligned);

    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/wrong-plugin",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &features,
    ) != null) return error.WrongPluginAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        null,
        &host,
        &widget,
        &features,
    ) != null) return error.MissingWriteFunctionAccepted;
    const no_features = [_:null]?*const ui.Feature{};
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &no_features,
    ) != null) return error.MissingParentAccepted;
}
