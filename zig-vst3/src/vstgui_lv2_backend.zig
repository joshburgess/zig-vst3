const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const editor_view = @import("vstgui_editor_view.zig");

pub const ControlKind = editor_view.ControlKind;

pub const Control = struct {
    parameter_id: u32,
    kind: ?ControlKind = null,
    tooltip: ?[:0]const u8 = null,
};

pub const PeakSource = struct {
    port_symbol: [:0]const u8,
    source_id: u32,
    delivery: core.gui.HostPeakDelivery = .dynamic,
};

pub const Description = struct {
    controls: []const Control,
    peak_sources: []const PeakSource = &.{},
    meters: []const editor_view.MeterDescription = &.{},
    initial_size: core.gui.Size = .{
        .width = 400,
        .height = 300,
    },
    resize_policy: core.gui.ResizePolicy = .{
        .resizable = .{
            .minimum = .{ .width = 320, .height = 240 },
            .maximum = .{ .width = 1_920, .height = 1_080 },
        },
    },
};

const NativeEditor = opaque {};

const NativePlatform = enum(c_int) {
    macos,
    windows,
    x11,
    wayland,
};

const ResizeCallbacks = extern struct {
    userdata: ?*anyopaque,
    request_resize: *const fn (
        ?*anyopaque,
        u32,
        u32,
    ) callconv(.c) i32,
};

const MeterCallbacks = extern struct {
    userdata: ?*anyopaque,
    load: *const fn (?*anyopaque, u32) callconv(.c) f64,
};

extern fn zig_vstgui_editor_create(
    [*]const editor_view.ParameterDescription,
    u32,
    editor_view.Callbacks,
) ?*NativeEditor;
extern fn zig_vstgui_editor_create_with_meters(
    [*]const editor_view.ParameterDescription,
    u32,
    editor_view.Callbacks,
    ?[*]const editor_view.MeterDescription,
    u32,
    MeterCallbacks,
) ?*NativeEditor;
extern fn zig_vstgui_editor_open(
    *NativeEditor,
    ?*anyopaque,
    NativePlatform,
) i32;
extern fn zig_vstgui_editor_close(*NativeEditor) void;
extern fn zig_vstgui_editor_native_widget(
    *NativeEditor,
) ?*anyopaque;
extern fn zig_vstgui_editor_idle(*NativeEditor) i32;
extern fn zig_vstgui_editor_destroy(*NativeEditor) void;
extern fn zig_vstgui_editor_resize(
    *NativeEditor,
    u32,
    u32,
) i32;
extern fn zig_vstgui_editor_set_scale(
    *NativeEditor,
    f64,
) i32;
extern fn zig_vstgui_editor_set_parameter(
    *NativeEditor,
    u32,
    f64,
) i32;
extern fn zig_vstgui_editor_set_focus(
    *NativeEditor,
    i32,
) void;
extern fn zig_vstgui_editor_set_resize_callbacks(
    *NativeEditor,
    ResizeCallbacks,
) void;

pub fn verifyAdapterAbi(comptime adapter: type) void {
    editor_view.verifyAdapterAbi(adapter);
    editor_view.verifyStructAbi(
        "LV2 ZigVstguiResizeCallbacks",
        ResizeCallbacks,
        adapter.ZigVstguiResizeCallbacks,
    );
    editor_view.verifyStructAbi(
        "LV2 ZigVstguiMeterCallbacks",
        MeterCallbacks,
        adapter.ZigVstguiMeterCallbacks,
    );
    editor_view.verifyEnumAbi(
        "LV2 ZigVstguiPlatform",
        NativePlatform,
        adapter.ZigVstguiPlatform,
    );
    inline for (.{
        .{ "LV2 zig_vstgui_editor_create", @TypeOf(zig_vstgui_editor_create), @TypeOf(adapter.zig_vstgui_editor_create) },
        .{ "LV2 zig_vstgui_editor_create_with_meters", @TypeOf(zig_vstgui_editor_create_with_meters), @TypeOf(adapter.zig_vstgui_editor_create_with_meters) },
        .{ "LV2 zig_vstgui_editor_open", @TypeOf(zig_vstgui_editor_open), @TypeOf(adapter.zig_vstgui_editor_open) },
        .{ "LV2 zig_vstgui_editor_close", @TypeOf(zig_vstgui_editor_close), @TypeOf(adapter.zig_vstgui_editor_close) },
        .{ "LV2 zig_vstgui_editor_native_widget", @TypeOf(zig_vstgui_editor_native_widget), @TypeOf(adapter.zig_vstgui_editor_native_widget) },
        .{ "LV2 zig_vstgui_editor_idle", @TypeOf(zig_vstgui_editor_idle), @TypeOf(adapter.zig_vstgui_editor_idle) },
        .{ "LV2 zig_vstgui_editor_destroy", @TypeOf(zig_vstgui_editor_destroy), @TypeOf(adapter.zig_vstgui_editor_destroy) },
        .{ "LV2 zig_vstgui_editor_resize", @TypeOf(zig_vstgui_editor_resize), @TypeOf(adapter.zig_vstgui_editor_resize) },
        .{ "LV2 zig_vstgui_editor_set_scale", @TypeOf(zig_vstgui_editor_set_scale), @TypeOf(adapter.zig_vstgui_editor_set_scale) },
        .{ "LV2 zig_vstgui_editor_set_parameter", @TypeOf(zig_vstgui_editor_set_parameter), @TypeOf(adapter.zig_vstgui_editor_set_parameter) },
        .{ "LV2 zig_vstgui_editor_set_focus", @TypeOf(zig_vstgui_editor_set_focus), @TypeOf(adapter.zig_vstgui_editor_set_focus) },
        .{ "LV2 zig_vstgui_editor_set_resize_callbacks", @TypeOf(zig_vstgui_editor_set_resize_callbacks), @TypeOf(adapter.zig_vstgui_editor_set_resize_callbacks) },
    }) |mapping| editor_view.verifyFunctionAbi(
        mapping[0],
        mapping[1],
        mapping[2],
    );
}

const NativeApi = struct {
    const Editor = NativeEditor;

    fn create(
        descriptions: []const editor_view.ParameterDescription,
        callbacks: editor_view.Callbacks,
        meters: []const editor_view.MeterDescription,
        meter_callbacks: MeterCallbacks,
    ) ?*Editor {
        if (meters.len == 0) return zig_vstgui_editor_create(
            descriptions.ptr,
            @intCast(descriptions.len),
            callbacks,
        );
        return zig_vstgui_editor_create_with_meters(
            descriptions.ptr,
            @intCast(descriptions.len),
            callbacks,
            meters.ptr,
            @intCast(meters.len),
            meter_callbacks,
        );
    }

    fn open(
        editor: *Editor,
        parent: *anyopaque,
        platform: core.gui.Platform,
    ) bool {
        return zig_vstgui_editor_open(
            editor,
            parent,
            switch (platform) {
                .macos => .macos,
                .windows => .windows,
                .x11 => .x11,
                .wayland => .wayland,
            },
        ) == 0;
    }

    fn close(editor: *Editor) void {
        zig_vstgui_editor_close(editor);
    }

    fn widget(editor: *Editor) ?*anyopaque {
        return zig_vstgui_editor_native_widget(editor);
    }

    fn idle(editor: *Editor) bool {
        return zig_vstgui_editor_idle(editor) == 0;
    }

    fn destroy(editor: *Editor) void {
        zig_vstgui_editor_destroy(editor);
    }

    fn resize(editor: *Editor, size: core.gui.Size) bool {
        return zig_vstgui_editor_resize(
            editor,
            size.width,
            size.height,
        ) == 0;
    }

    fn scale(editor: *Editor, value: core.gui.Scale) bool {
        if (value.x != value.y) return false;
        return zig_vstgui_editor_set_scale(editor, value.x) == 0;
    }

    fn focus(editor: *Editor, focused: bool) void {
        zig_vstgui_editor_set_focus(editor, @intFromBool(focused));
    }

    fn setParameter(
        editor: *Editor,
        parameter_id: u32,
        normalized: f64,
    ) bool {
        return zig_vstgui_editor_set_parameter(
            editor,
            parameter_id,
            normalized,
        ) == 0;
    }

    fn setResizeCallbacks(
        editor: *Editor,
        callbacks: ResizeCallbacks,
    ) void {
        zig_vstgui_editor_set_resize_callbacks(
            editor,
            callbacks,
        );
    }
};

pub fn Backend(comptime description: Description) type {
    return BackendWithApi(description, NativeApi);
}

pub fn BackendWithApi(
    comptime description: Description,
    comptime Api: type,
) type {
    validateDescription(description);
    const control_count = description.controls.len;
    const peak_source_count = description.peak_sources.len;

    return struct {
        const Self = @This();

        const State = struct {
            context: core.gui.Context,
            editor: ?*Api.Editor = null,
            gesture: ?core.gui.Gesture = null,
            attached: bool = false,
            peaks: [peak_source_count]f64 = @splat(0.0),
            peak_subscriptions: [peak_source_count]bool =
                @splat(false),
        };

        pub fn create(
            context: core.gui.Context,
        ) core.gui.Error!core.gui.Editor {
            const allocator = std.heap.page_allocator;
            const state = allocator.create(State) catch
                return error.Rejected;
            errdefer allocator.destroy(state);

            var titles: [control_count][parameter_title_capacity:0]u8 =
                @splat(@splat(0));
            var units: [control_count][parameter_units_capacity:0]u8 =
                @splat(@splat(0));
            var descriptions: [control_count]editor_view.ParameterDescription =
                undefined;
            for (
                description.controls,
                0..,
            ) |control, index| {
                const metadata =
                    context.metadata(control.parameter_id) orelse
                    return error.InvalidParameter;
                const initial =
                    context.value(control.parameter_id) orelse
                    return error.InvalidParameter;
                if (!std.math.isFinite(initial) or
                    !std.math.isFinite(metadata.default_normalized))
                    return error.Rejected;
                const title = copySentinel(
                    parameter_title_capacity,
                    &titles[index],
                    metadata.name,
                ) orelse return error.Rejected;
                const unit_text = copySentinel(
                    parameter_units_capacity,
                    &units[index],
                    metadata.units,
                ) orelse return error.Rejected;
                descriptions[index] = .{
                    .parameter_id = control.parameter_id,
                    .initial_normalized = std.math.clamp(
                        initial,
                        0.0,
                        1.0,
                    ),
                    .info = .{
                        .title = title,
                        .units = unit_text,
                        .step_count = @max(
                            metadata.step_count,
                            0,
                        ),
                        .default_normalized = std.math.clamp(
                            metadata.default_normalized,
                            0.0,
                            1.0,
                        ),
                        .tooltip = if (control.tooltip) |tooltip|
                            tooltip.ptr
                        else
                            null,
                    },
                    .control_kind = control.kind orelse
                        inferredKind(metadata.kind),
                };
            }

            state.* = .{
                .context = context,
            };
            errdefer unsubscribeHostPeaks(state);
            inline for (description.peak_sources, 0..) |source, index| {
                const subscription = core.gui.HostPeakSubscription{
                    .port_symbol = source.port_symbol,
                    .source_id = source.source_id,
                    .delivery = source.delivery,
                };
                const status = context.subscribeHostPeak(subscription) catch
                    return error.Rejected;
                state.peak_subscriptions[index] = status == .accepted;
            }
            const native_editor = Api.create(
                &descriptions,
                .{
                    .userdata = state,
                    .begin_edit = beginEdit,
                    .perform_edit = performEdit,
                    .end_edit = endEdit,
                    .format_value = formatValue,
                    .parse_value = parseValue,
                    .show_context_menu = showContextMenu,
                },
                description.meters,
                .{
                    .userdata = state,
                    .load = loadPeak,
                },
            ) orelse return error.Rejected;
            state.editor = native_editor;
            Api.setResizeCallbacks(native_editor, .{
                .userdata = state,
                .request_resize = requestResize,
            });
            return .{
                .context = context,
                .adapter = .{
                    .userdata = state,
                    .vtable = &adapter_vtable,
                },
                .size = description.initial_size,
                .resize_policy = description.resize_policy,
            };
        }

        pub fn widget(
            adapter: core.gui.Adapter,
        ) ?*anyopaque {
            const state = from(adapter.userdata);
            if (!state.attached) return null;
            const editor = state.editor orelse return null;
            return Api.widget(editor);
        }

        pub fn idle(adapter: core.gui.Adapter) bool {
            const state = from(adapter.userdata);
            const editor = state.editor orelse return false;
            return state.attached and Api.idle(editor);
        }

        fn from(raw: *anyopaque) *State {
            return @ptrCast(@alignCast(raw));
        }

        fn attach(
            raw: *anyopaque,
            parent: core.gui.NativeParent,
            size: core.gui.Size,
            scale_value: core.gui.Scale,
        ) core.gui.Error!void {
            const state = from(raw);
            if (state.attached) return error.AlreadyAttached;
            const editor = state.editor orelse return error.Rejected;
            const handle = parent.handle orelse return error.Rejected;
            if (!scale_value.valid() or
                scale_value.x != scale_value.y)
                return error.InvalidScale;
            if (!Api.open(editor, handle, parent.platform))
                return error.Rejected;
            errdefer Api.close(editor);
            if (!Api.scale(editor, scale_value) or
                !Api.resize(editor, size) or
                Api.widget(editor) == null)
                return error.Rejected;
            state.attached = true;
        }

        fn detach(raw: *anyopaque) void {
            const state = from(raw);
            if (!state.attached) return;
            const editor = state.editor orelse return;
            Api.close(editor);
            finishGesture(state);
            state.attached = false;
        }

        fn resize(
            raw: *anyopaque,
            size: core.gui.Size,
        ) core.gui.Error!void {
            const state = from(raw);
            if (!state.attached) return error.NotAttached;
            const editor = state.editor orelse return error.Rejected;
            if (!Api.resize(editor, size))
                return error.Rejected;
        }

        fn scale(
            raw: *anyopaque,
            value: core.gui.Scale,
        ) core.gui.Error!void {
            const state = from(raw);
            if (!state.attached) return error.NotAttached;
            if (!value.valid() or value.x != value.y)
                return error.InvalidScale;
            const editor = state.editor orelse return error.Rejected;
            if (!Api.scale(editor, value))
                return error.Rejected;
        }

        fn focus(raw: *anyopaque, focused: bool) void {
            const state = from(raw);
            const editor = state.editor orelse return;
            if (state.attached) Api.focus(editor, focused);
        }

        fn parameterChanged(
            raw: *anyopaque,
            parameter_id: u32,
            normalized: f64,
        ) void {
            const state = from(raw);
            if (!std.math.isFinite(normalized)) return;
            const editor = state.editor orelse return;
            _ = Api.setParameter(
                editor,
                parameter_id,
                std.math.clamp(normalized, 0.0, 1.0),
            );
        }

        fn hostPeakMeasurement(
            raw: *anyopaque,
            measurement: core.gui.HostPeakMeasurement,
        ) void {
            const state = from(raw);
            inline for (description.peak_sources, 0..) |source, index| {
                if (source.source_id == measurement.source_id) {
                    state.peaks[index] = measurement.peak;
                    return;
                }
            }
        }

        fn loadPeak(
            raw: ?*anyopaque,
            source_id: u32,
        ) callconv(.c) f64 {
            const state = from(raw orelse return 0.0);
            inline for (description.peak_sources, 0..) |source, index| {
                if (source.source_id == source_id)
                    return state.peaks[index];
            }
            return 0.0;
        }

        fn destroy(raw: *anyopaque) void {
            const state = from(raw);
            const editor = state.editor;
            if (state.attached) {
                if (editor) |value| Api.close(value);
            }
            finishGesture(state);
            unsubscribeHostPeaks(state);
            if (editor) |value| Api.destroy(value);
            std.heap.page_allocator.destroy(state);
        }

        fn unsubscribeHostPeaks(state: *State) void {
            inline for (description.peak_sources, 0..) |source, index| {
                if (state.peak_subscriptions[index]) {
                    _ = state.context.unsubscribeHostPeak(.{
                        .port_symbol = source.port_symbol,
                        .source_id = source.source_id,
                        .delivery = source.delivery,
                    }) catch {};
                    state.peak_subscriptions[index] = false;
                }
            }
        }

        const adapter_vtable = core.gui.Adapter.VTable{
            .attach = attach,
            .detach = detach,
            .resize = resize,
            .scale = scale,
            .focus = focus,
            .parameter_changed = parameterChanged,
            .host_peak_measurement = hostPeakMeasurement,
            .destroy = destroy,
        };

        fn beginEdit(
            raw: ?*anyopaque,
            parameter_id: u32,
        ) callconv(.c) void {
            const state = from(raw orelse return);
            if (state.gesture != null) return;
            state.gesture =
                state.context.beginGesture(parameter_id) catch null;
        }

        fn performEdit(
            raw: ?*anyopaque,
            parameter_id: u32,
            normalized: f64,
        ) callconv(.c) i32 {
            const state = from(raw orelse return -1);
            const gesture = if (state.gesture) |*value|
                value
            else
                return -1;
            if (gesture.id != parameter_id) return -1;
            gesture.set(normalized) catch return -1;
            return 0;
        }

        fn endEdit(
            raw: ?*anyopaque,
            parameter_id: u32,
        ) callconv(.c) void {
            const state = from(raw orelse return);
            const gesture = if (state.gesture) |*value|
                value
            else
                return;
            if (gesture.id != parameter_id) return;
            gesture.finish();
            state.gesture = null;
        }

        fn finishGesture(state: *State) void {
            if (state.gesture) |*gesture| gesture.finish();
            state.gesture = null;
        }

        fn formatValue(
            raw: ?*anyopaque,
            parameter_id: u32,
            normalized: f64,
            output: [*c]u8,
            capacity: u32,
        ) callconv(.c) i32 {
            const state = from(raw orelse return -1);
            if (capacity == 0) return -1;
            const output_slice = editor_view.cSlice(
                u8,
                output,
                capacity,
            ) orelse return -1;
            const text = state.context.format(
                parameter_id,
                normalized,
                output_slice[0 .. output_slice.len - 1],
            ) catch return -1;
            output_slice[text.len] = 0;
            return std.math.cast(i32, text.len) orelse -1;
        }

        fn parseValue(
            raw: ?*anyopaque,
            parameter_id: u32,
            text: [*c]const u8,
            normalized: [*c]f64,
        ) callconv(.c) i32 {
            const state = from(raw orelse return -1);
            const normalized_output = editor_view.cPointer(
                f64,
                normalized,
            ) orelse return -1;
            const bytes = editor_view.cStringBytes(text) orelse
                return -1;
            normalized_output.* = state.context.parse(
                parameter_id,
                bytes,
            ) catch return -1;
            return 0;
        }

        fn showContextMenu(
            raw: ?*anyopaque,
            parameter_id: u32,
            x: i32,
            y: i32,
        ) callconv(.c) i32 {
            const state = from(raw orelse return -1);
            state.context.openContextMenu(
                parameter_id,
                x,
                y,
            ) catch return -1;
            return 0;
        }

        fn requestResize(
            raw: ?*anyopaque,
            width: u32,
            height: u32,
        ) callconv(.c) i32 {
            const state = from(raw orelse return -1);
            const requested = core.gui.constrained(
                description.resize_policy,
                .{ .width = width, .height = height },
            );
            const accepted =
                state.context.vtable.request_resize(
                    state.context.userdata,
                    requested,
                ) catch return -1;
            const editor = state.editor orelse return -1;
            if (!Api.resize(editor, accepted)) return -1;
            return 0;
        }
    };
}

const parameter_title_capacity = 127;
const parameter_units_capacity = 63;

fn copySentinel(
    comptime capacity: usize,
    output: *[capacity:0]u8,
    text: []const u8,
) ?[*:0]const u8 {
    if (text.len > capacity) return null;
    @memset(output, 0);
    @memcpy(output[0..text.len], text);
    return output;
}

fn inferredKind(
    kind: core.gui.ParameterKind,
) ControlKind {
    return switch (kind) {
        .boolean => .toggle,
        .enumeration => .enum_dropdown,
        .float, .integer => .linear_slider,
    };
}

fn validateDescription(comptime description: Description) void {
    if (description.controls.len == 0)
        @compileError("a VSTGUI LV2 backend requires a control");
    if (description.controls.len > editor_view.max_parameters)
        @compileError("a VSTGUI LV2 backend has too many controls");
    for (description.controls, 0..) |control, index| {
        for (description.controls[0..index]) |previous| {
            if (control.parameter_id == previous.parameter_id)
                @compileError(
                    "a VSTGUI LV2 backend has duplicate parameter IDs",
                );
        }
    }
    if (description.peak_sources.len > core.gui.maximum_host_peak_subscriptions)
        @compileError("a VSTGUI LV2 backend has too many peak sources");
    if (description.meters.len > editor_view.max_meters)
        @compileError("a VSTGUI LV2 backend has too many meters");
    for (description.peak_sources, 0..) |source, index| {
        for (description.peak_sources[0..index]) |previous| {
            if (source.source_id == previous.source_id)
                @compileError("a VSTGUI LV2 backend has duplicate peak source IDs");
            if (std.mem.eql(u8, source.port_symbol, previous.port_symbol))
                @compileError("a VSTGUI LV2 backend has duplicate peak port symbols");
        }
    }
    for (description.meters) |meter| {
        var first_found = false;
        var second_found = meter.kind != .stereo;
        for (description.peak_sources) |source| {
            first_found = first_found or source.source_id == meter.first_source_id;
            second_found = second_found or source.source_id == meter.second_source_id;
        }
        if (!first_found or !second_found)
            @compileError("a VSTGUI LV2 meter references an unknown peak source");
    }
    if (description.initial_size.width == 0 or
        description.initial_size.height == 0)
        @compileError(
            "a VSTGUI LV2 backend requires a nonzero initial size",
        );
}

const TestApi = struct {
    const Editor = opaque {};

    var callbacks: editor_view.Callbacks = .{
        .userdata = null,
    };
    var resize_callbacks: ResizeCallbacks = undefined;
    var create_count: usize = 0;
    var open_count: usize = 0;
    var close_count: usize = 0;
    var idle_count: usize = 0;
    var destroy_count: usize = 0;
    var resize_count: usize = 0;
    var scale_count: usize = 0;
    var focus_count: usize = 0;
    var parameter_count: usize = 0;
    var meter_count: usize = 0;
    var meter_callbacks: MeterCallbacks = undefined;
    var description_valid = false;
    var fail_create = false;
    var fail_open = false;
    var widget_available = true;
    var last_resize: core.gui.Size = .{
        .width = 0,
        .height = 0,
    };
    var last_parameter_id: u32 = 0;
    var last_parameter_value: f64 = 0.0;

    fn reset() void {
        callbacks = .{ .userdata = null };
        resize_callbacks = undefined;
        create_count = 0;
        open_count = 0;
        close_count = 0;
        idle_count = 0;
        destroy_count = 0;
        resize_count = 0;
        scale_count = 0;
        focus_count = 0;
        parameter_count = 0;
        meter_count = 0;
        meter_callbacks = undefined;
        description_valid = false;
        fail_create = false;
        fail_open = false;
        widget_available = true;
        last_resize = .{ .width = 0, .height = 0 };
        last_parameter_id = 0;
        last_parameter_value = 0.0;
    }

    fn create(
        descriptions: []const editor_view.ParameterDescription,
        received_callbacks: editor_view.Callbacks,
        meters: []const editor_view.MeterDescription,
        received_meter_callbacks: MeterCallbacks,
    ) ?*Editor {
        create_count += 1;
        callbacks = received_callbacks;
        meter_count = meters.len;
        meter_callbacks = received_meter_callbacks;
        description_valid =
            descriptions.len == 2 and
            descriptions[0].parameter_id == 7 and
            descriptions[0].control_kind == .rotary_knob and
            std.mem.eql(
                u8,
                std.mem.span(descriptions[0].info.title),
                "Gain",
            ) and
            descriptions[1].parameter_id == 9 and
            descriptions[1].control_kind == .toggle and
            std.mem.eql(
                u8,
                std.mem.span(descriptions[1].info.title),
                "Bypass",
            );
        return if (fail_create) null else @ptrFromInt(0x1000);
    }

    fn open(
        _: *Editor,
        _: *anyopaque,
        _: core.gui.Platform,
    ) bool {
        open_count += 1;
        return !fail_open;
    }

    fn close(_: *Editor) void {
        close_count += 1;
    }

    fn widget(_: *Editor) ?*anyopaque {
        return if (widget_available)
            @ptrFromInt(0x2000)
        else
            null;
    }

    fn idle(_: *Editor) bool {
        idle_count += 1;
        return true;
    }

    fn destroy(_: *Editor) void {
        destroy_count += 1;
    }

    fn resize(_: *Editor, size: core.gui.Size) bool {
        resize_count += 1;
        last_resize = size;
        return true;
    }

    fn scale(_: *Editor, _: core.gui.Scale) bool {
        scale_count += 1;
        return true;
    }

    fn focus(_: *Editor, _: bool) void {
        focus_count += 1;
    }

    fn setParameter(
        _: *Editor,
        parameter_id: u32,
        normalized: f64,
    ) bool {
        parameter_count += 1;
        last_parameter_id = parameter_id;
        last_parameter_value = normalized;
        return true;
    }

    fn setResizeCallbacks(
        _: *Editor,
        value: ResizeCallbacks,
    ) void {
        resize_callbacks = value;
    }
};

const TestContext = struct {
    gain: f64 = 0.5,
    bypass: f64 = 0.0,
    begin_count: usize = 0,
    perform_count: usize = 0,
    end_count: usize = 0,
    menu_count: usize = 0,
    resize_count: usize = 0,
    peak_subscription_count: usize = 0,
    peak_unsubscription_count: usize = 0,
    peak_subscription_source: u32 = 0,
    peak_subscription_delivery: core.gui.HostPeakDelivery = .dynamic,
    last_resize: core.gui.Size = .{
        .width = 0,
        .height = 0,
    },

    fn context(self: *@This()) core.gui.Context {
        return .{
            .userdata = self,
            .vtable = &vtable,
        };
    }

    fn from(raw: *anyopaque) *@This() {
        return @ptrCast(@alignCast(raw));
    }

    fn begin(raw: *anyopaque, id: u32) core.gui.Error!void {
        if (id != 7 and id != 9)
            return error.InvalidParameter;
        from(raw).begin_count += 1;
    }

    fn perform(
        raw: *anyopaque,
        id: u32,
        normalized: f64,
    ) core.gui.Error!void {
        const self = from(raw);
        switch (id) {
            7 => self.gain = normalized,
            9 => self.bypass = normalized,
            else => return error.InvalidParameter,
        }
        self.perform_count += 1;
    }

    fn end(raw: *anyopaque, _: u32) void {
        from(raw).end_count += 1;
    }

    fn value(raw: *anyopaque, id: u32) ?f64 {
        const self = from(raw);
        return switch (id) {
            7 => self.gain,
            9 => self.bypass,
            else => null,
        };
    }

    fn metadata(
        _: *anyopaque,
        id: u32,
    ) ?core.gui.ParameterMetadata {
        return switch (id) {
            7 => .{
                .id = 7,
                .name = "Gain",
                .short_name = "Gain",
                .units = "dB",
                .default_normalized = 0.5,
                .step_count = 0,
            },
            9 => .{
                .id = 9,
                .name = "Bypass",
                .short_name = "Byp",
                .units = "",
                .default_normalized = 0.0,
                .step_count = 1,
                .kind = .boolean,
            },
            else => null,
        };
    }

    fn format(
        _: *anyopaque,
        id: u32,
        _: f64,
        output: []u8,
    ) core.gui.Error!usize {
        if (id != 7 or output.len < 4)
            return error.Rejected;
        @memcpy(output[0..4], "gain");
        return 4;
    }

    fn parse(
        _: *anyopaque,
        id: u32,
        text: []const u8,
    ) core.gui.Error!f64 {
        if (id != 7 or !std.mem.eql(u8, text, "half"))
            return error.Rejected;
        return 0.5;
    }

    fn requestResize(
        raw: *anyopaque,
        requested: core.gui.Size,
    ) core.gui.Error!core.gui.Size {
        const self = from(raw);
        self.resize_count += 1;
        self.last_resize = requested;
        return requested;
    }

    fn repaint(_: *anyopaque) void {}

    fn menu(
        raw: *anyopaque,
        id: u32,
        _: i32,
        _: i32,
    ) core.gui.Error!void {
        if (id != 7) return error.InvalidParameter;
        from(raw).menu_count += 1;
    }

    fn subscribeHostPeak(
        raw: *anyopaque,
        subscription: core.gui.HostPeakSubscription,
    ) core.gui.HostSubscriptionStatus {
        const self = from(raw);
        if (!std.mem.eql(u8, subscription.port_symbol, "output"))
            return .rejected;
        self.peak_subscription_count += 1;
        self.peak_subscription_source = subscription.source_id;
        self.peak_subscription_delivery = subscription.delivery;
        return .accepted;
    }

    fn unsubscribeHostPeak(
        raw: *anyopaque,
        subscription: core.gui.HostPeakSubscription,
    ) core.gui.HostSubscriptionStatus {
        const self = from(raw);
        if (!std.mem.eql(u8, subscription.port_symbol, "output"))
            return .rejected;
        self.peak_unsubscription_count += 1;
        self.peak_subscription_source = subscription.source_id;
        self.peak_subscription_delivery = subscription.delivery;
        return .accepted;
    }

    const vtable = core.gui.Context.VTable{
        .begin_edit = begin,
        .perform_edit = perform,
        .end_edit = end,
        .value = value,
        .metadata = metadata,
        .format = format,
        .parse = parse,
        .request_resize = requestResize,
        .request_repaint = repaint,
        .open_context_menu = menu,
        .subscribe_host_peak = subscribeHostPeak,
        .unsubscribe_host_peak = unsubscribeHostPeak,
    };
};

test "VSTGUI LV2 backend owns native lifecycle and host callbacks" {
    const TestBackend = BackendWithApi(.{
        .controls = &.{
            .{
                .parameter_id = 7,
                .kind = .rotary_knob,
                .tooltip = "Gain control",
            },
            .{ .parameter_id = 9 },
        },
        .peak_sources = &.{.{
            .port_symbol = "output",
            .source_id = 42,
            .delivery = .static,
        }},
        .meters = &.{.{
            .title = "Output",
            .kind = .peak,
            .first_source_id = 42,
            .second_source_id = 0,
        }},
        .initial_size = .{ .width = 400, .height = 300 },
        .resize_policy = .{
            .resizable = .{
                .minimum = .{ .width = 200, .height = 100 },
                .maximum = .{ .width = 800, .height = 600 },
            },
        },
    }, TestApi);
    TestApi.reset();
    var context_state = TestContext{};
    var editor = try TestBackend.create(context_state.context());

    try std.testing.expectEqual(@as(usize, 1), TestApi.create_count);
    try std.testing.expect(TestApi.description_valid);
    try std.testing.expectEqual(
        @as(usize, 1),
        context_state.peak_subscription_count,
    );
    try std.testing.expectEqual(
        @as(u32, 42),
        context_state.peak_subscription_source,
    );
    try std.testing.expectEqual(
        core.gui.HostPeakDelivery.static,
        context_state.peak_subscription_delivery,
    );
    try std.testing.expectEqual(@as(usize, 1), TestApi.meter_count);
    try std.testing.expectEqual(
        @as(f64, 0.0),
        TestApi.meter_callbacks.load(
            TestApi.meter_callbacks.userdata,
            42,
        ),
    );
    editor.hostPeakMeasurement(.{
        .source_id = 42,
        .period_start = 0,
        .period_size = 64,
        .peak = 0.875,
    });
    try std.testing.expectEqual(
        @as(f64, 0.875),
        TestApi.meter_callbacks.load(
            TestApi.meter_callbacks.userdata,
            42,
        ),
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        TestApi.meter_callbacks.load(
            TestApi.meter_callbacks.userdata,
            99,
        ),
    );
    try std.testing.expect(
        TestBackend.widget(editor.adapter) == null,
    );
    try std.testing.expectError(
        error.Rejected,
        editor.attach(.{ .platform = .x11, .handle = null }),
    );

    const parent: *anyopaque = @ptrFromInt(0x3000);
    TestApi.fail_open = true;
    try std.testing.expectError(
        error.Rejected,
        editor.attach(.{ .platform = .x11, .handle = parent }),
    );
    try std.testing.expectEqual(@as(usize, 1), TestApi.open_count);
    try std.testing.expectEqual(@as(usize, 0), TestApi.close_count);

    TestApi.fail_open = false;
    TestApi.widget_available = false;
    try std.testing.expectError(
        error.Rejected,
        editor.attach(.{ .platform = .x11, .handle = parent }),
    );
    try std.testing.expectEqual(@as(usize, 1), TestApi.close_count);

    TestApi.widget_available = true;
    try editor.attach(.{ .platform = .x11, .handle = parent });
    try std.testing.expect(
        TestBackend.widget(editor.adapter) ==
            @as(*anyopaque, @ptrFromInt(0x2000)),
    );
    try std.testing.expect(TestBackend.idle(editor.adapter));
    try std.testing.expectEqual(@as(usize, 1), TestApi.idle_count);

    const callbacks = TestApi.callbacks;
    callbacks.begin_edit.?(callbacks.userdata, 7);
    try std.testing.expectEqual(
        @as(i32, 0),
        callbacks.perform_edit.?(
            callbacks.userdata,
            7,
            0.75,
        ),
    );
    callbacks.end_edit.?(callbacks.userdata, 7);
    try std.testing.expectEqual(@as(f64, 0.75), context_state.gain);
    try std.testing.expectEqual(@as(usize, 1), context_state.begin_count);
    try std.testing.expectEqual(@as(usize, 1), context_state.perform_count);
    try std.testing.expectEqual(@as(usize, 1), context_state.end_count);

    var formatted: [8]u8 = undefined;
    try std.testing.expectEqual(
        @as(i32, 4),
        callbacks.format_value.?(
            callbacks.userdata,
            7,
            0.75,
            &formatted,
            formatted.len,
        ),
    );
    try std.testing.expectEqualStrings(
        "gain",
        std.mem.sliceTo(&formatted, 0),
    );
    var parsed: f64 = 0.0;
    try std.testing.expectEqual(
        @as(i32, 0),
        callbacks.parse_value.?(
            callbacks.userdata,
            7,
            "half",
            &parsed,
        ),
    );
    try std.testing.expectEqual(@as(f64, 0.5), parsed);
    try std.testing.expectEqual(
        @as(i32, 0),
        callbacks.show_context_menu.?(
            callbacks.userdata,
            7,
            10,
            20,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), context_state.menu_count);

    editor.hostParameterChanged(7, 0.25);
    try std.testing.expectEqual(@as(u32, 7), TestApi.last_parameter_id);
    try std.testing.expectEqual(
        @as(f64, 0.25),
        TestApi.last_parameter_value,
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        TestApi.resize_callbacks.request_resize(
            TestApi.resize_callbacks.userdata,
            50,
            900,
        ),
    );
    try std.testing.expectEqual(
        core.gui.Size{ .width = 200, .height = 600 },
        context_state.last_resize,
    );
    try std.testing.expectEqual(
        context_state.last_resize,
        TestApi.last_resize,
    );

    try editor.hostResize(.{ .width = 640, .height = 480 });
    try editor.setScale(.{ .x = 2.0, .y = 2.0 });
    try std.testing.expectError(
        error.InvalidScale,
        editor.setScale(.{ .x = 1.0, .y = 2.0 }),
    );
    editor.setFocus(true);
    try std.testing.expectEqual(@as(usize, 1), TestApi.focus_count);
    editor.detach();
    try std.testing.expectEqual(@as(usize, 2), TestApi.close_count);
    try std.testing.expect(
        TestBackend.widget(editor.adapter) == null,
    );
    editor.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        context_state.peak_unsubscription_count,
    );
    try std.testing.expectEqual(@as(usize, 1), TestApi.destroy_count);
}

test "VSTGUI LV2 backend rolls back host peak subscriptions" {
    const TestBackend = BackendWithApi(.{
        .controls = &.{.{ .parameter_id = 7 }},
        .peak_sources = &.{.{
            .port_symbol = "output",
            .source_id = 42,
            .delivery = .static,
        }},
        .meters = &.{},
        .initial_size = .{ .width = 400, .height = 300 },
        .resize_policy = .{ .fixed = .{ .width = 400, .height = 300 } },
    }, TestApi);
    TestApi.reset();
    TestApi.fail_create = true;
    var context_state = TestContext{};

    try std.testing.expectError(
        error.Rejected,
        TestBackend.create(context_state.context()),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        context_state.peak_subscription_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        context_state.peak_unsubscription_count,
    );
}
