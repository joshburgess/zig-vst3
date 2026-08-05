const builtin = @import("builtin");
const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const Probe = struct {
    pub const name = "LV2 UI Probe";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const event_output = true;
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = 7,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    pub fn process(
        _: *@This(),
        _: *core.process.ProcessContext(f32),
    ) void {}
};

const CoreAdapter = core.lv2.CoreAdapter(
    Probe,
    "https://zig-vst3.dev/tests/lv2-ui-probe",
    64,
);

const Backend = struct {
    const State = struct {
        context: core.gui.Context,
        size: core.gui.Size = .{ .width = 320, .height = 200 },
        parameter: f64 = 0.5,
        idle_count: usize = 0,
        subscription_status: core.gui.HostSubscriptionStatus = .unsupported,
        atom_status: core.gui.HostSubscriptionStatus = .unsupported,
        peak_count: u32 = 0,
        peak: core.gui.HostPeakMeasurement = .{
            .source_id = 0,
            .period_start = 0,
            .period_size = 1,
            .peak = 0.0,
        },
        atom_count: u32 = 0,
        atom_source_id: u32 = 0,
        atom_body: [32]u8 = @splat(0),
        atom_body_len: usize = 0,
    };

    pub fn create(context: core.gui.Context) core.gui.Error!core.gui.Editor {
        const state = std.heap.page_allocator.create(State) catch
            return error.Rejected;
        state.* = .{ .context = context };
        state.subscription_status = context.subscribeHostPeak(.{
            .port_symbol = "audio_in",
            .source_id = 29,
        }) catch {
            std.heap.page_allocator.destroy(state);
            return error.Rejected;
        };
        state.atom_status = context.registerHostAtomNotification(.{
            .port_symbol = "midi_output",
            .atom_type_uri = "https://zig-vst3.dev/tests/lv2-ui-probe#status",
            .source_id = 37,
        }) catch {
            std.heap.page_allocator.destroy(state);
            return error.Rejected;
        };
        return .{
            .context = context,
            .adapter = .{
                .userdata = state,
                .vtable = &vtable,
            },
            .size = state.size,
            .resize_policy = .{
                .resizable = .{
                    .minimum = .{ .width = 160, .height = 100 },
                    .maximum = .{ .width = 800, .height = 600 },
                },
            },
        };
    }

    pub fn widget(adapter: core.gui.Adapter) ?*anyopaque {
        return adapter.userdata;
    }

    pub fn idle(adapter: core.gui.Adapter) bool {
        from(adapter.userdata).idle_count += 1;
        return true;
    }

    fn from(raw: *anyopaque) *State {
        return @ptrCast(@alignCast(raw));
    }

    fn attach(
        _: *anyopaque,
        _: core.gui.NativeParent,
        _: core.gui.Size,
        _: core.gui.Scale,
    ) core.gui.Error!void {}

    fn detach(_: *anyopaque) void {}

    fn resize(
        raw: *anyopaque,
        size: core.gui.Size,
    ) core.gui.Error!void {
        from(raw).size = size;
    }

    fn scale(
        _: *anyopaque,
        _: core.gui.Scale,
    ) core.gui.Error!void {}

    fn focus(_: *anyopaque, _: bool) void {}

    fn parameterChanged(
        raw: *anyopaque,
        _: u32,
        value: f64,
    ) void {
        from(raw).parameter = value;
    }

    fn hostPeakMeasurement(
        raw: *anyopaque,
        measurement: core.gui.HostPeakMeasurement,
    ) void {
        const state = from(raw);
        state.peak_count +|= 1;
        state.peak = measurement;
    }

    fn hostAtomMessage(
        raw: *anyopaque,
        message: core.gui.HostAtomMessage,
    ) void {
        const state = from(raw);
        if (message.body.len > state.atom_body.len) return;
        state.atom_count +|= 1;
        state.atom_source_id = message.source_id;
        @memset(&state.atom_body, 0);
        @memcpy(state.atom_body[0..message.body.len], message.body);
        state.atom_body_len = message.body.len;
    }

    fn destroy(raw: *anyopaque) void {
        std.heap.page_allocator.destroy(from(raw));
    }

    const vtable = core.gui.Adapter.VTable{
        .attach = attach,
        .detach = detach,
        .resize = resize,
        .scale = scale,
        .focus = focus,
        .parameter_changed = parameterChanged,
        .host_peak_measurement = hostPeakMeasurement,
        .host_atom_message = hostAtomMessage,
        .destroy = destroy,
    };
};

const PeakProbe = extern struct {
    subscription_status: c_int,
    peak_count: u32,
    source_id: u32,
    period_start: u32,
    period_size: u32,
    peak: f32,
};

const AtomProbe = extern struct {
    registration_status: c_int,
    message_count: u32,
    source_id: u32,
    body_size: u32,
    body: [32]u8,
};

const platform: core.gui.Platform = switch (builtin.os.tag) {
    .macos => .macos,
    .windows => .windows,
    else => .x11,
};

const UiAdapter = core.lv2.ui.Adapter(
    Probe,
    CoreAdapter,
    "https://zig-vst3.dev/tests/lv2-ui-probe",
    "https://zig-vst3.dev/tests/lv2-ui-probe#ui",
    .{},
    platform,
    Backend,
);

pub export fn lv2ui_descriptor(
    index: u32,
) callconv(.c) ?*const core.lv2.ui.Descriptor {
    return UiAdapter.descriptorAt(index);
}

pub export fn lv2_ui_probe_request_value(
    widget: core.lv2.ui.Widget,
    include_type: bool,
) callconv(.c) c_int {
    const raw = widget orelse return -1;
    const state: *Backend.State = @ptrCast(@alignCast(raw));
    const status = state.context.requestHostValue(.{
        .key_uri = "https://zig-vst3.dev/tests/lv2-ui-probe#samplePath",
        .value_type_uri = if (include_type)
            "http://lv2plug.in/ns/ext/atom#Path"
        else
            null,
    }) catch return -1;
    return @intFromEnum(status);
}

pub export fn lv2_ui_probe_peak(
    widget: core.lv2.ui.Widget,
    result: ?*PeakProbe,
) callconv(.c) bool {
    const raw = widget orelse return false;
    const output = result orelse return false;
    const state: *Backend.State = @ptrCast(@alignCast(raw));
    output.* = .{
        .subscription_status = @intFromEnum(state.subscription_status),
        .peak_count = state.peak_count,
        .source_id = state.peak.source_id,
        .period_start = state.peak.period_start,
        .period_size = state.peak.period_size,
        .peak = state.peak.peak,
    };
    return true;
}

pub export fn lv2_ui_probe_register_static_peak(
    widget: core.lv2.ui.Widget,
) callconv(.c) c_int {
    const raw = widget orelse return -1;
    const state: *Backend.State = @ptrCast(@alignCast(raw));
    state.subscription_status = state.context.subscribeHostPeak(.{
        .port_symbol = "audio_in",
        .source_id = 31,
        .delivery = .static,
    }) catch return -1;
    return @intFromEnum(state.subscription_status);
}

pub export fn lv2_ui_probe_atom(
    widget: core.lv2.ui.Widget,
    result: ?*AtomProbe,
) callconv(.c) bool {
    const raw = widget orelse return false;
    const output = result orelse return false;
    const state: *Backend.State = @ptrCast(@alignCast(raw));
    output.* = .{
        .registration_status = @intFromEnum(state.atom_status),
        .message_count = state.atom_count,
        .source_id = state.atom_source_id,
        .body_size = @intCast(state.atom_body_len),
        .body = state.atom_body,
    };
    return true;
}

pub export fn lv2_ui_probe_send_atom(
    widget: core.lv2.ui.Widget,
) callconv(.c) c_int {
    const raw = widget orelse return -1;
    const state: *Backend.State = @ptrCast(@alignCast(raw));
    const body = [_]u8{ 8, 6, 4, 2 };
    const status = state.context.sendPluginAtomMessage(.{
        .port_symbol = "midi_input",
        .atom_type_uri = "https://zig-vst3.dev/tests/lv2-ui-probe#command",
        .body = &body,
    }) catch return -1;
    return @intFromEnum(status);
}
