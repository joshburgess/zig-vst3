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
    const features = [_:null]?*const ui.Feature{
        &parent_feature,
        &touch_feature,
        &resize_feature,
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

    const plain: f32 = 0.25;
    descriptor.port_event(handle, 2, @sizeOf(f32), 0, &plain);
    descriptor.port_event(handle, 2, 1, 0, &plain);
    descriptor.port_event(handle, 2, @sizeOf(f32), 1, &plain);

    const idle_ptr = descriptor.extension_data(
        ui.idle_interface_uri,
    ) orelse return error.MissingIdleInterface;
    const idle: *const ui.IdleInterface =
        @ptrCast(@alignCast(idle_ptr));
    if (idle.idle(handle) != 0) return error.IdleFailed;

    const resize_ptr = descriptor.extension_data(
        ui.resize_uri,
    ) orelse return error.MissingResizeInterface;
    const resize_interface: *const ui.ResizeInterface =
        @ptrCast(@alignCast(resize_ptr));
    if (resize_interface.ui_resize(handle, 640, 480) != 0)
        return error.ResizeFailed;
    if (resize_interface.ui_resize(handle, 0, 480) == 0)
        return error.InvalidResizeAccepted;

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
