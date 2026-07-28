//! Toolkit-neutral renderer and host-lifecycle contracts.
//!
//! This module is for adapter implementations and custom renderers. Plugin UI
//! composition should normally use `@import("zig-vst3").vstgui`.

const std = @import("std");

pub const ParameterId = u32;
pub const NormalizedValue = f64;

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const Scale = struct {
    x: f64 = 1.0,
    y: f64 = 1.0,

    pub fn valid(self: Scale) bool {
        return std.math.isFinite(self.x) and std.math.isFinite(self.y) and self.x > 0 and self.y > 0;
    }
};

pub const ResizePolicy = union(enum) {
    fixed: Size,
    resizable: struct {
        minimum: Size,
        maximum: Size,
    },
};

pub const Platform = enum {
    macos,
    windows,
    x11,
    wayland,
};

pub const NativeParent = struct {
    platform: Platform,
    handle: ?*anyopaque,
};

pub const ParameterMetadata = struct {
    id: ParameterId,
    name: []const u8,
    short_name: []const u8,
    units: []const u8,
    minimum_plain: f64 = 0.0,
    maximum_plain: f64 = 1.0,
    default_normalized: NormalizedValue,
    step_count: i32,
    kind: ParameterKind = .float,
};

pub const ParameterKind = enum {
    float,
    integer,
    boolean,
    enumeration,
};

pub const Error = error{
    InvalidParameter,
    Rejected,
    NotAttached,
    AlreadyAttached,
    InvalidScale,
};

/// Calls supplied by the plugin controller. All calls run on the host GUI thread.
pub const Context = struct {
    userdata: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        begin_edit: *const fn (*anyopaque, ParameterId) Error!void,
        perform_edit: *const fn (*anyopaque, ParameterId, NormalizedValue) Error!void,
        end_edit: *const fn (*anyopaque, ParameterId) void,
        value: *const fn (*anyopaque, ParameterId) ?NormalizedValue,
        metadata: *const fn (*anyopaque, ParameterId) ?ParameterMetadata,
        format: *const fn (*anyopaque, ParameterId, NormalizedValue, []u8) Error!usize,
        parse: *const fn (*anyopaque, ParameterId, []const u8) Error!NormalizedValue,
        request_resize: *const fn (*anyopaque, Size) Error!Size,
        request_repaint: *const fn (*anyopaque) void,
        open_context_menu: *const fn (*anyopaque, ParameterId, i32, i32) Error!void,
    };

    pub fn value(self: Context, id: ParameterId) ?NormalizedValue {
        return self.vtable.value(self.userdata, id);
    }

    pub fn metadata(self: Context, id: ParameterId) ?ParameterMetadata {
        return self.vtable.metadata(self.userdata, id);
    }

    pub fn beginGesture(self: Context, id: ParameterId) Error!Gesture {
        const initial = clampNormalized(self.value(id) orelse return error.InvalidParameter);
        try self.vtable.begin_edit(self.userdata, id);
        return .{
            .context = self,
            .id = id,
            .initial = initial,
            .accepted = initial,
        };
    }

    pub fn format(self: Context, id: ParameterId, value_to_format: NormalizedValue, buffer: []u8) Error![]const u8 {
        const length = try self.vtable.format(self.userdata, id, value_to_format, buffer);
        if (length > buffer.len) return error.Rejected;
        return buffer[0..length];
    }

    pub fn parse(self: Context, id: ParameterId, text: []const u8) Error!NormalizedValue {
        return self.vtable.parse(self.userdata, id, text);
    }

    pub fn requestRepaint(self: Context) void {
        self.vtable.request_repaint(self.userdata);
    }

    pub fn openContextMenu(self: Context, id: ParameterId, x: i32, y: i32) Error!void {
        try self.vtable.open_context_menu(self.userdata, id, x, y);
    }
};

pub const Gesture = struct {
    context: Context,
    id: ParameterId,
    initial: NormalizedValue,
    accepted: NormalizedValue,
    active: bool = true,

    pub fn set(self: *Gesture, value: NormalizedValue) Error!void {
        if (!self.active) return error.Rejected;
        const normalized = clampNormalized(value);
        try self.context.vtable.perform_edit(self.context.userdata, self.id, normalized);
        self.accepted = normalized;
    }

    pub fn finish(self: *Gesture) void {
        if (!self.active) return;
        self.context.vtable.end_edit(self.context.userdata, self.id);
        self.active = false;
    }

    pub fn cancel(self: *Gesture) void {
        if (!self.active) return;
        self.context.vtable.perform_edit(self.context.userdata, self.id, self.initial) catch {};
        self.context.vtable.end_edit(self.context.userdata, self.id);
        self.accepted = self.initial;
        self.active = false;
    }
};

pub const ParameterAttachment = struct {
    context: Context,
    metadata: ParameterMetadata,
    value: NormalizedValue,
    gesture: ?Gesture = null,

    pub fn init(context: Context, id: ParameterId) Error!ParameterAttachment {
        const metadata = context.metadata(id) orelse return error.InvalidParameter;
        const value = context.value(id) orelse return error.InvalidParameter;
        return .{
            .context = context,
            .metadata = metadata,
            .value = quantized(metadata, value),
        };
    }

    pub fn begin(self: *ParameterAttachment) Error!void {
        if (self.gesture != null) return error.Rejected;
        self.gesture = try self.context.beginGesture(self.metadata.id);
    }

    pub fn set(self: *ParameterAttachment, value: NormalizedValue) Error!void {
        if (self.gesture) |*gesture| {
            const normalized = quantized(self.metadata, value);
            try gesture.set(normalized);
            self.value = normalized;
            return;
        }
        return error.Rejected;
    }

    pub fn finish(self: *ParameterAttachment) void {
        if (self.gesture) |*gesture| gesture.finish();
        self.gesture = null;
    }

    pub fn cancel(self: *ParameterAttachment) void {
        if (self.gesture) |*gesture| {
            gesture.cancel();
            self.value = gesture.accepted;
        }
        self.gesture = null;
    }

    pub fn resetToDefault(self: *ParameterAttachment) Error!void {
        try self.begin();
        errdefer self.cancel();
        try self.set(self.metadata.default_normalized);
        self.finish();
    }

    pub fn hostChanged(self: *ParameterAttachment, value: NormalizedValue) void {
        self.value = quantized(self.metadata, value);
    }

    pub fn adjust(self: *ParameterAttachment, delta: f64, fine: bool) Error!void {
        const multiplier: f64 = if (fine) 0.1 else 1.0;
        try self.set(self.value + delta * multiplier);
    }

    pub fn format(self: *const ParameterAttachment, buffer: []u8) Error![]const u8 {
        return self.context.format(self.metadata.id, self.value, buffer);
    }

    pub fn parseAndSet(self: *ParameterAttachment, text: []const u8) Error!void {
        const parsed = try self.context.parse(self.metadata.id, text);
        if (self.gesture == null) try self.begin();
        errdefer self.cancel();
        try self.set(parsed);
        self.finish();
    }
};

pub fn MultiParameterAttachment(comptime parameter_count: usize) type {
    if (parameter_count == 0) @compileError("a multi-parameter attachment requires at least one parameter");
    return struct {
        attachments: [parameter_count]ParameterAttachment,
        active: bool = false,

        pub fn init(context: Context, ids: [parameter_count]ParameterId) Error!@This() {
            for (ids, 0..) |id, index| {
                for (ids[0..index]) |previous| {
                    if (id == previous) return error.InvalidParameter;
                }
            }
            var result: @This() = undefined;
            result.active = false;
            for (ids, 0..) |id, index| {
                result.attachments[index] = try ParameterAttachment.init(context, id);
            }
            return result;
        }

        pub fn begin(self: *@This()) Error!void {
            if (self.active) return error.Rejected;
            var begun: usize = 0;
            errdefer {
                for (self.attachments[0..begun]) |*attachment| attachment.finish();
            }
            for (&self.attachments) |*attachment| {
                try attachment.begin();
                begun += 1;
            }
            self.active = true;
        }

        pub fn set(self: *@This(), requested: [parameter_count]NormalizedValue) Error!void {
            if (!self.active) return error.Rejected;
            for (&self.attachments, requested) |*attachment, value| {
                attachment.set(value) catch |err| {
                    self.cancel();
                    return err;
                };
            }
        }

        pub fn finish(self: *@This()) void {
            if (!self.active) return;
            for (&self.attachments) |*attachment| attachment.finish();
            self.active = false;
        }

        pub fn cancel(self: *@This()) void {
            if (!self.active) return;
            for (&self.attachments) |*attachment| attachment.cancel();
            self.active = false;
        }

        pub fn hostChanged(self: *@This(), id: ParameterId, value: NormalizedValue) void {
            for (&self.attachments) |*attachment| {
                if (attachment.metadata.id == id) attachment.hostChanged(value);
            }
        }

        pub fn values(self: *const @This()) [parameter_count]NormalizedValue {
            var result: [parameter_count]NormalizedValue = undefined;
            for (self.attachments, 0..) |attachment, index| result[index] = attachment.value;
            return result;
        }
    };
}

pub fn ParameterEnvelopeAttachment(comptime point_count: usize) type {
    if (point_count == 0) @compileError("a parameter envelope attachment requires at least one point");
    return struct {
        pub const Binding = struct {
            point_id: u32,
            x_parameter_id: ParameterId,
            y_parameter_id: ParameterId,
        };

        bindings: [point_count]Binding,
        points: [point_count]MultiParameterAttachment(2),
        active_index: ?usize = null,

        pub fn init(context: Context, bindings: [point_count]Binding) Error!@This() {
            var result: @This() = undefined;
            result.bindings = bindings;
            result.active_index = null;
            for (bindings, 0..) |binding, index| {
                if (binding.point_id == 0) return error.InvalidParameter;
                for (bindings[0..index]) |previous| {
                    if (previous.point_id == binding.point_id) return error.InvalidParameter;
                }
                result.points[index] = try MultiParameterAttachment(2).init(
                    context,
                    .{ binding.x_parameter_id, binding.y_parameter_id },
                );
            }
            return result;
        }

        pub fn begin(self: *@This(), point_id: u32) Error!void {
            if (self.active_index != null) return error.Rejected;
            const index = self.indexOf(point_id) orelse return error.InvalidParameter;
            try self.points[index].begin();
            self.active_index = index;
        }

        pub fn set(self: *@This(), values_to_set: [2]NormalizedValue) Error!void {
            const index = self.active_index orelse return error.Rejected;
            self.points[index].set(values_to_set) catch |err| {
                self.active_index = null;
                return err;
            };
        }

        pub fn finish(self: *@This()) void {
            const index = self.active_index orelse return;
            self.points[index].finish();
            self.active_index = null;
        }

        pub fn cancel(self: *@This()) void {
            const index = self.active_index orelse return;
            self.points[index].cancel();
            self.active_index = null;
        }

        pub fn hostChanged(self: *@This(), parameter_id: ParameterId, value: NormalizedValue) void {
            for (&self.points) |*point| point.hostChanged(parameter_id, value);
        }

        pub fn pointValues(self: *const @This(), point_id: u32) ?[2]NormalizedValue {
            const index = self.indexOf(point_id) orelse return null;
            return self.points[index].values();
        }

        fn indexOf(self: *const @This(), point_id: u32) ?usize {
            for (self.bindings, 0..) |binding, index| {
                if (binding.point_id == point_id) return index;
            }
            return null;
        }
    };
}

/// A fixed-size development panel built entirely from reflected parameter IDs.
pub fn ParameterPanel(comptime parameter_count: usize) type {
    return struct {
        attachments: [parameter_count]ParameterAttachment,

        pub fn init(context: Context, ids: [parameter_count]ParameterId) Error!@This() {
            var panel: @This() = undefined;
            var initialized: usize = 0;
            errdefer for (panel.attachments[0..initialized]) |*attachment| attachment.cancel();
            for (ids, 0..) |id, index| {
                panel.attachments[index] = try ParameterAttachment.init(context, id);
                initialized += 1;
            }
            return panel;
        }

        pub fn hostChanged(self: *@This(), id: ParameterId, value: NormalizedValue) void {
            for (&self.attachments) |*attachment| {
                if (attachment.metadata.id == id) attachment.hostChanged(value);
            }
        }

        pub fn cancelGestures(self: *@This()) void {
            for (&self.attachments) |*attachment| attachment.cancel();
        }
    };
}

pub fn quantized(metadata: ParameterMetadata, value: NormalizedValue) NormalizedValue {
    const clamped = clampNormalized(value);
    if (metadata.step_count <= 0) return clamped;
    const steps: f64 = @floatFromInt(metadata.step_count);
    return @round(clamped * steps) / steps;
}

/// Toolkit adapters receive lifecycle calls on the host GUI thread.
pub const Adapter = struct {
    userdata: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        attach: *const fn (*anyopaque, NativeParent, Size, Scale) Error!void,
        detach: *const fn (*anyopaque) void,
        resize: *const fn (*anyopaque, Size) Error!void,
        scale: *const fn (*anyopaque, Scale) Error!void,
        focus: *const fn (*anyopaque, bool) void,
        parameter_changed: *const fn (*anyopaque, ParameterId, NormalizedValue) void,
        destroy: *const fn (*anyopaque) void,
    };
};

pub const Editor = struct {
    context: Context,
    adapter: Adapter,
    size: Size,
    scale: Scale = .{},
    resize_policy: ResizePolicy,
    attached: bool = false,
    active_gesture: ?Gesture = null,

    pub fn attach(self: *Editor, parent: NativeParent) Error!void {
        if (self.attached) return error.AlreadyAttached;
        try self.adapter.vtable.attach(self.adapter.userdata, parent, self.size, self.scale);
        self.attached = true;
    }

    pub fn detach(self: *Editor) void {
        if (self.active_gesture) |*gesture| gesture.cancel();
        self.active_gesture = null;
        if (!self.attached) return;
        self.adapter.vtable.detach(self.adapter.userdata);
        self.attached = false;
    }

    pub fn deinit(self: *Editor) void {
        self.detach();
        self.adapter.vtable.destroy(self.adapter.userdata);
    }

    pub fn beginGesture(self: *Editor, id: ParameterId) Error!void {
        if (!self.attached) return error.NotAttached;
        if (self.active_gesture != null) return error.Rejected;
        self.active_gesture = try self.context.beginGesture(id);
    }

    pub fn setGestureValue(self: *Editor, value: NormalizedValue) Error!void {
        if (self.active_gesture) |*gesture| {
            try gesture.set(value);
            return;
        }
        return error.Rejected;
    }

    pub fn endGesture(self: *Editor) void {
        if (self.active_gesture) |*gesture| gesture.finish();
        self.active_gesture = null;
    }

    pub fn requestResize(self: *Editor, requested: Size) Error!void {
        const accepted = try self.context.vtable.request_resize(self.context.userdata, constrained(self.resize_policy, requested));
        try self.acceptSize(accepted);
    }

    pub fn hostResize(self: *Editor, accepted: Size) Error!void {
        try self.acceptSize(accepted);
    }

    pub fn setScale(self: *Editor, scale: Scale) Error!void {
        if (!scale.valid()) return error.InvalidScale;
        try self.adapter.vtable.scale(self.adapter.userdata, scale);
        self.scale = scale;
    }

    pub fn setFocus(self: *Editor, focused: bool) void {
        self.adapter.vtable.focus(self.adapter.userdata, focused);
    }

    pub fn hostParameterChanged(self: *Editor, id: ParameterId, value: NormalizedValue) void {
        self.adapter.vtable.parameter_changed(self.adapter.userdata, id, value);
    }

    fn acceptSize(self: *Editor, accepted: Size) Error!void {
        try self.adapter.vtable.resize(self.adapter.userdata, accepted);
        self.size = accepted;
    }
};

pub fn constrained(policy: ResizePolicy, requested: Size) Size {
    return switch (policy) {
        .fixed => |size| size,
        .resizable => |bounds| blk: {
            const minimum_width = @min(bounds.minimum.width, bounds.maximum.width);
            const maximum_width = @max(bounds.minimum.width, bounds.maximum.width);
            const minimum_height = @min(bounds.minimum.height, bounds.maximum.height);
            const maximum_height = @max(bounds.minimum.height, bounds.maximum.height);
            break :blk .{
                .width = std.math.clamp(requested.width, minimum_width, maximum_width),
                .height = std.math.clamp(requested.height, minimum_height, maximum_height),
            };
        },
    };
}

fn clampNormalized(value: NormalizedValue) NormalizedValue {
    return if (std.math.isNan(value)) 0.0 else std.math.clamp(value, 0.0, 1.0);
}

const Fake = struct {
    value: NormalizedValue = 0.5,
    reject_edit: bool = false,
    reject_resize: bool = false,
    reject_scale: bool = false,
    calls: [16]u8 = undefined,
    call_count: usize = 0,
    attach_count: usize = 0,
    detach_count: usize = 0,
    destroy_count: usize = 0,
    repaint_count: usize = 0,
    parameter_change_count: usize = 0,
    last_size: Size = .{ .width = 400, .height = 300 },
    last_scale: Scale = .{},

    fn record(self: *Fake, call: u8) void {
        self.calls[self.call_count] = call;
        self.call_count += 1;
    }

    fn context(self: *Fake) Context {
        return .{ .userdata = self, .vtable = &context_vtable };
    }

    fn adapter(self: *Fake) Adapter {
        return .{ .userdata = self, .vtable = &adapter_vtable };
    }

    fn from(ptr: *anyopaque) *Fake {
        return @ptrCast(@alignCast(ptr));
    }

    fn begin(ptr: *anyopaque, _: ParameterId) Error!void {
        from(ptr).record('b');
    }

    fn perform(ptr: *anyopaque, _: ParameterId, value: NormalizedValue) Error!void {
        const self = from(ptr);
        self.record('p');
        if (self.reject_edit) return error.Rejected;
        self.value = value;
    }

    fn end(ptr: *anyopaque, _: ParameterId) void {
        from(ptr).record('e');
    }

    fn getValue(ptr: *anyopaque, id: ParameterId) ?NormalizedValue {
        return if (id == 7) from(ptr).value else null;
    }

    fn getMetadata(_: *anyopaque, id: ParameterId) ?ParameterMetadata {
        if (id != 7) return null;
        return .{ .id = id, .name = "Gain", .short_name = "Gain", .units = "dB", .default_normalized = 0.5, .step_count = 0 };
    }

    fn formatValue(_: *anyopaque, id: ParameterId, value: NormalizedValue, buffer: []u8) Error!usize {
        if (id != 7) return error.InvalidParameter;
        const text = std.fmt.bufPrint(buffer, "{d:.3} dB", .{value}) catch return error.Rejected;
        return text.len;
    }

    fn parseValue(_: *anyopaque, id: ParameterId, text: []const u8) Error!NormalizedValue {
        if (id != 7) return error.InvalidParameter;
        const value_end = std.mem.indexOfScalar(u8, text, ' ') orelse text.len;
        return std.fmt.parseFloat(f64, text[0..value_end]) catch return error.Rejected;
    }

    fn requestResize(ptr: *anyopaque, size: Size) Error!Size {
        const self = from(ptr);
        if (self.reject_resize) return error.Rejected;
        return size;
    }

    fn repaint(ptr: *anyopaque) void {
        from(ptr).repaint_count += 1;
    }

    fn contextMenu(_: *anyopaque, id: ParameterId, _: i32, _: i32) Error!void {
        if (id != 7) return error.InvalidParameter;
    }

    fn attach(ptr: *anyopaque, _: NativeParent, _: Size, _: Scale) Error!void {
        from(ptr).attach_count += 1;
    }

    fn detach(ptr: *anyopaque) void {
        from(ptr).detach_count += 1;
    }

    fn resize(ptr: *anyopaque, size: Size) Error!void {
        const self = from(ptr);
        self.last_size = size;
    }

    fn setScale(ptr: *anyopaque, scale: Scale) Error!void {
        const self = from(ptr);
        if (self.reject_scale) return error.Rejected;
        self.last_scale = scale;
    }

    fn focus(_: *anyopaque, _: bool) void {}

    fn parameterChanged(ptr: *anyopaque, _: ParameterId, _: NormalizedValue) void {
        from(ptr).parameter_change_count += 1;
    }

    fn destroy(ptr: *anyopaque) void {
        from(ptr).destroy_count += 1;
    }

    const context_vtable = Context.VTable{
        .begin_edit = begin,
        .perform_edit = perform,
        .end_edit = end,
        .value = getValue,
        .metadata = getMetadata,
        .format = formatValue,
        .parse = parseValue,
        .request_resize = requestResize,
        .request_repaint = repaint,
        .open_context_menu = contextMenu,
    };

    const adapter_vtable = Adapter.VTable{
        .attach = attach,
        .detach = detach,
        .resize = resize,
        .scale = setScale,
        .focus = focus,
        .parameter_changed = parameterChanged,
        .destroy = destroy,
    };
};

fn fakeEditor(fake: *Fake) Editor {
    return .{
        .context = fake.context(),
        .adapter = fake.adapter(),
        .size = .{ .width = 400, .height = 300 },
        .resize_policy = .{ .resizable = .{
            .minimum = .{ .width = 200, .height = 150 },
            .maximum = .{ .width = 800, .height = 600 },
        } },
    };
}

const MultiOperation = struct { kind: u8, id: ParameterId };

const MultiFake = struct {
    values: [2]NormalizedValue = .{ 0.25, 0.75 },
    reject_id: ?ParameterId = null,
    operations: [24]MultiOperation = undefined,
    operation_count: usize = 0,

    fn record(self: *MultiFake, kind: u8, id: ParameterId) void {
        self.operations[self.operation_count] = .{ .kind = kind, .id = id };
        self.operation_count += 1;
    }

    fn context(self: *MultiFake) Context {
        return .{ .userdata = self, .vtable = &context_vtable };
    }

    fn from(ptr: *anyopaque) *MultiFake {
        return @ptrCast(@alignCast(ptr));
    }

    fn index(id: ParameterId) ?usize {
        return switch (id) {
            10 => 0,
            20 => 1,
            else => null,
        };
    }

    fn begin(ptr: *anyopaque, id: ParameterId) Error!void {
        const self = from(ptr);
        if (index(id) == null) return error.InvalidParameter;
        self.record('b', id);
    }

    fn perform(ptr: *anyopaque, id: ParameterId, value: NormalizedValue) Error!void {
        const self = from(ptr);
        const value_index = index(id) orelse return error.InvalidParameter;
        self.record('p', id);
        if (self.reject_id == id) return error.Rejected;
        self.values[value_index] = value;
    }

    fn end(ptr: *anyopaque, id: ParameterId) void {
        from(ptr).record('e', id);
    }

    fn getValue(ptr: *anyopaque, id: ParameterId) ?NormalizedValue {
        return from(ptr).values[index(id) orelse return null];
    }

    fn getMetadata(_: *anyopaque, id: ParameterId) ?ParameterMetadata {
        _ = index(id) orelse return null;
        return .{
            .id = id,
            .name = if (id == 10) "X" else "Y",
            .short_name = if (id == 10) "X" else "Y",
            .units = "",
            .default_normalized = 0.5,
            .step_count = 0,
        };
    }

    fn formatValue(_: *anyopaque, id: ParameterId, value: NormalizedValue, buffer: []u8) Error!usize {
        _ = index(id) orelse return error.InvalidParameter;
        const text = std.fmt.bufPrint(buffer, "{d:.3}", .{value}) catch return error.Rejected;
        return text.len;
    }

    fn parseValue(_: *anyopaque, id: ParameterId, text: []const u8) Error!NormalizedValue {
        _ = index(id) orelse return error.InvalidParameter;
        return std.fmt.parseFloat(f64, text) catch return error.Rejected;
    }

    fn requestResize(_: *anyopaque, size: Size) Error!Size {
        return size;
    }

    fn repaint(_: *anyopaque) void {}

    fn contextMenu(_: *anyopaque, id: ParameterId, _: i32, _: i32) Error!void {
        _ = index(id) orelse return error.InvalidParameter;
    }

    const context_vtable = Context.VTable{
        .begin_edit = begin,
        .perform_edit = perform,
        .end_edit = end,
        .value = getValue,
        .metadata = getMetadata,
        .format = formatValue,
        .parse = parseValue,
        .request_resize = requestResize,
        .request_repaint = repaint,
        .open_context_menu = contextMenu,
    };
};

test "editor orders complete parameter gestures" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    try editor.attach(.{ .platform = .macos, .handle = null });
    try editor.beginGesture(7);
    try editor.setGestureValue(0.75);
    editor.endGesture();

    try std.testing.expectEqualStrings("bpe", fake.calls[0..fake.call_count]);
    try std.testing.expectEqual(@as(NormalizedValue, 0.75), fake.value);
}

test "rejected edits preserve the last accepted value" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    try editor.attach(.{ .platform = .macos, .handle = null });
    try editor.beginGesture(7);
    try editor.setGestureValue(0.75);
    fake.reject_edit = true;
    try std.testing.expectError(error.Rejected, editor.setGestureValue(0.25));
    try std.testing.expectEqual(@as(NormalizedValue, 0.75), editor.active_gesture.?.accepted);
    try std.testing.expectEqual(@as(NormalizedValue, 0.75), fake.value);
}

test "direct gestures sanitize normalized values and cancellation state" {
    var invalid_initial = Fake{ .value = std.math.nan(f64) };
    var gesture = try invalid_initial.context().beginGesture(7);
    try std.testing.expectEqual(@as(NormalizedValue, 0.0), gesture.initial);
    try std.testing.expectEqual(@as(NormalizedValue, 0.0), gesture.accepted);

    try gesture.set(std.math.inf(f64));
    try std.testing.expectEqual(@as(NormalizedValue, 1.0), invalid_initial.value);
    try std.testing.expectEqual(@as(NormalizedValue, 1.0), gesture.accepted);

    gesture.cancel();
    try std.testing.expectEqual(@as(NormalizedValue, 0.0), invalid_initial.value);
}

test "detach cancels an active gesture and destroys once" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    try editor.attach(.{ .platform = .macos, .handle = null });
    try editor.beginGesture(7);
    try editor.setGestureValue(0.9);
    editor.deinit();

    try std.testing.expectEqual(@as(NormalizedValue, 0.5), fake.value);
    try std.testing.expectEqual(@as(usize, 1), fake.detach_count);
    try std.testing.expectEqual(@as(usize, 1), fake.destroy_count);
}

test "host parameter changes do not start gestures" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    editor.hostParameterChanged(7, 0.25);

    try std.testing.expectEqual(@as(usize, 1), fake.parameter_change_count);
    try std.testing.expectEqual(@as(usize, 0), fake.call_count);
}

test "rejected size and scale changes preserve accepted state" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    fake.reject_resize = true;
    try std.testing.expectError(error.Rejected, editor.requestResize(.{ .width = 700, .height = 500 }));
    try std.testing.expectEqual(Size{ .width = 400, .height = 300 }, editor.size);

    fake.reject_scale = true;
    try std.testing.expectError(error.Rejected, editor.setScale(.{ .x = 2.0, .y = 2.0 }));
    try std.testing.expectEqual(Scale{}, editor.scale);
}

test "resize requests are constrained before reaching the host" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    try editor.requestResize(.{ .width = 1_000, .height = 100 });
    try std.testing.expectEqual(Size{ .width = 800, .height = 150 }, editor.size);
    try std.testing.expectEqual(editor.size, fake.last_size);
}

test "resize constraints tolerate reversed direct bounds" {
    const policy = ResizePolicy{ .resizable = .{
        .minimum = .{ .width = 800, .height = 600 },
        .maximum = .{ .width = 200, .height = 150 },
    } };
    try std.testing.expectEqual(
        Size{ .width = 800, .height = 150 },
        constrained(policy, .{ .width = 1_000, .height = 100 }),
    );
}

test "parameter attachment owns gestures and exact text entry" {
    var fake = Fake{};
    var attachment = try ParameterAttachment.init(fake.context(), 7);
    try attachment.parseAndSet("0.625 dB");
    try std.testing.expectEqual(@as(NormalizedValue, 0.625), attachment.value);
    try std.testing.expectEqualStrings("bpe", fake.calls[0..fake.call_count]);

    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0.625 dB", try attachment.format(&buffer));
}

test "multi-parameter attachment orders complete gestures" {
    var fake = MultiFake{};
    var attachment = try MultiParameterAttachment(2).init(fake.context(), .{ 10, 20 });
    try attachment.begin();
    try attachment.set(.{ 0.4, 0.6 });
    attachment.finish();

    const expected = [_]MultiOperation{
        .{ .kind = 'b', .id = 10 },
        .{ .kind = 'b', .id = 20 },
        .{ .kind = 'p', .id = 10 },
        .{ .kind = 'p', .id = 20 },
        .{ .kind = 'e', .id = 10 },
        .{ .kind = 'e', .id = 20 },
    };
    try std.testing.expectEqualSlices(@TypeOf(expected[0]), &expected, fake.operations[0..fake.operation_count]);
    try std.testing.expectEqual([2]NormalizedValue{ 0.4, 0.6 }, attachment.values());
}

test "multi-parameter attachment cancels every axis after rejection" {
    var fake = MultiFake{};
    var attachment = try MultiParameterAttachment(2).init(fake.context(), .{ 10, 20 });
    try attachment.begin();
    fake.reject_id = 20;
    try std.testing.expectError(error.Rejected, attachment.set(.{ 0.9, 0.1 }));

    try std.testing.expect(!attachment.active);
    try std.testing.expectEqual([2]NormalizedValue{ 0.25, 0.75 }, attachment.values());
    try std.testing.expectEqual([2]NormalizedValue{ 0.25, 0.75 }, fake.values);
    var end_count: usize = 0;
    for (fake.operations[0..fake.operation_count]) |operation| {
        if (operation.kind == 'e') end_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), end_count);
}

test "multi-parameter attachment rejects duplicate IDs and tracks host automation" {
    var fake = MultiFake{};
    try std.testing.expectError(
        error.InvalidParameter,
        MultiParameterAttachment(2).init(fake.context(), .{ 10, 10 }),
    );
    var attachment = try MultiParameterAttachment(2).init(fake.context(), .{ 10, 20 });
    attachment.hostChanged(20, 0.3);
    try std.testing.expectEqual([2]NormalizedValue{ 0.25, 0.3 }, attachment.values());
    try std.testing.expectEqual(@as(usize, 0), fake.operation_count);
}

test "parameter envelope attachment reuses ordered two-axis gestures" {
    var fake = MultiFake{};
    const Envelope = ParameterEnvelopeAttachment(1);
    var envelope = try Envelope.init(fake.context(), .{.{
        .point_id = 7,
        .x_parameter_id = 10,
        .y_parameter_id = 20,
    }});
    try envelope.begin(7);
    try envelope.set(.{ 0.4, 0.6 });
    envelope.finish();
    try std.testing.expectEqual([2]NormalizedValue{ 0.4, 0.6 }, envelope.pointValues(7).?);
    try std.testing.expectEqual(@as(usize, 6), fake.operation_count);
    envelope.hostChanged(20, 0.2);
    try std.testing.expectEqual([2]NormalizedValue{ 0.4, 0.2 }, envelope.pointValues(7).?);
    try std.testing.expectError(error.InvalidParameter, envelope.begin(99));
}

test "parameter attachment rejects invalid IDs and rejected values" {
    var fake = Fake{};
    try std.testing.expectError(error.InvalidParameter, ParameterAttachment.init(fake.context(), 99));

    var attachment = try ParameterAttachment.init(fake.context(), 7);
    try attachment.begin();
    fake.reject_edit = true;
    try std.testing.expectError(error.Rejected, attachment.set(0.75));
    try std.testing.expectEqual(@as(NormalizedValue, 0.5), attachment.value);
    attachment.cancel();
}

test "parameter attachment quantizes boolean integer and enum values" {
    const base = ParameterMetadata{
        .id = 1,
        .name = "Value",
        .short_name = "Value",
        .units = "",
        .default_normalized = 0,
        .step_count = 1,
        .kind = .boolean,
    };
    try std.testing.expectEqual(@as(f64, 1.0), quantized(base, 0.75));
    try std.testing.expectEqual(@as(f64, 0.0), quantized(base, 0.25));

    var integer = base;
    integer.kind = .integer;
    integer.step_count = 3;
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), quantized(integer, 0.6), 0.000001);

    var enumeration = integer;
    enumeration.kind = .enumeration;
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), quantized(enumeration, 0.4), 0.000001);
    try std.testing.expectEqual(@as(f64, 0.0), quantized(enumeration, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), quantized(enumeration, std.math.inf(f64)));
}

test "host automation updates attachments without emitting gestures" {
    var fake = Fake{};
    var attachment = try ParameterAttachment.init(fake.context(), 7);
    attachment.hostChanged(0.25);
    try std.testing.expectEqual(@as(NormalizedValue, 0.25), attachment.value);
    try std.testing.expectEqual(@as(usize, 0), fake.call_count);

    attachment.hostChanged(std.math.nan(f64));
    try std.testing.expectEqual(@as(NormalizedValue, 0.0), attachment.value);
    attachment.hostChanged(std.math.inf(f64));
    try std.testing.expectEqual(@as(NormalizedValue, 1.0), attachment.value);

    var invalid_initial = Fake{ .value = std.math.nan(f64) };
    const sanitized = try ParameterAttachment.init(invalid_initial.context(), 7);
    try std.testing.expectEqual(@as(NormalizedValue, 0.0), sanitized.value);
}

test "parameter panel builds controls from reflected IDs" {
    var fake = Fake{};
    var panel = try ParameterPanel(1).init(fake.context(), .{7});
    try std.testing.expectEqualStrings("Gain", panel.attachments[0].metadata.name);
    panel.hostChanged(7, 0.875);
    try std.testing.expectEqual(@as(NormalizedValue, 0.875), panel.attachments[0].value);
    try std.testing.expectEqual(@as(usize, 0), fake.call_count);
}
