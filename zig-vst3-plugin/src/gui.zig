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

pub const maximum_host_value_uri_bytes = 4096;

pub const HostValueRequest = struct {
    key_uri: [:0]const u8,
    value_type_uri: ?[:0]const u8 = null,
};

pub const HostValueRequestStatus = enum {
    accepted,
    busy,
    unknown,
    unsupported,
};

pub const maximum_host_port_symbol_bytes = 255;
pub const maximum_host_peak_subscriptions = 16;
pub const maximum_host_atom_notifications = 16;
pub const maximum_host_atom_body_bytes = 64 * 1024;
pub const maximum_plugin_atom_body_bytes = 64 * 1024;

pub const HostPeakDelivery = enum {
    dynamic,
    static,
};

pub const HostPeakSubscription = struct {
    port_symbol: [:0]const u8,
    source_id: u32,
    delivery: HostPeakDelivery = .dynamic,
};

pub const HostSubscriptionStatus = enum {
    accepted,
    unsupported,
    rejected,
    full,
};

pub const HostPeakMeasurement = struct {
    source_id: u32,
    period_start: u32,
    period_size: u32,
    peak: f32,

    pub fn valid(self: HostPeakMeasurement) bool {
        return self.period_size > 0 and
            std.math.isFinite(self.peak) and self.peak >= 0.0;
    }
};

pub const HostAtomNotification = struct {
    port_symbol: [:0]const u8,
    atom_type_uri: [:0]const u8,
    source_id: u32,
};

pub const HostAtomMessage = struct {
    source_id: u32,
    body: []const u8,

    pub fn valid(self: HostAtomMessage) bool {
        return self.body.len <= maximum_host_atom_body_bytes;
    }
};

pub const PluginMessageStatus = enum {
    accepted,
    unsupported,
    rejected,
};

pub const PluginAtomMessage = struct {
    port_symbol: [:0]const u8,
    atom_type_uri: [:0]const u8,
    body: []const u8,
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
        request_host_value: ?*const fn (*anyopaque, HostValueRequest) HostValueRequestStatus = null,
        subscribe_host_peak: ?*const fn (*anyopaque, HostPeakSubscription) HostSubscriptionStatus = null,
        unsubscribe_host_peak: ?*const fn (*anyopaque, HostPeakSubscription) HostSubscriptionStatus = null,
        register_host_atom_notification: ?*const fn (*anyopaque, HostAtomNotification) HostSubscriptionStatus = null,
        unregister_host_atom_notification: ?*const fn (*anyopaque, HostAtomNotification) HostSubscriptionStatus = null,
        send_plugin_atom_message: ?*const fn (*anyopaque, PluginAtomMessage) PluginMessageStatus = null,
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

    pub fn requestHostValue(
        self: Context,
        request: HostValueRequest,
    ) Error!HostValueRequestStatus {
        if (!validHostValueUri(request.key_uri))
            return error.InvalidParameter;
        if (request.value_type_uri) |value_type_uri| {
            if (!validHostValueUri(value_type_uri))
                return error.InvalidParameter;
        }
        const callback = self.vtable.request_host_value orelse
            return .unsupported;
        return callback(self.userdata, request);
    }

    pub fn subscribeHostPeak(
        self: Context,
        subscription: HostPeakSubscription,
    ) Error!HostSubscriptionStatus {
        if (!validHostPortSymbol(subscription.port_symbol))
            return error.InvalidParameter;
        const callback = self.vtable.subscribe_host_peak orelse
            return .unsupported;
        return callback(self.userdata, subscription);
    }

    pub fn unsubscribeHostPeak(
        self: Context,
        subscription: HostPeakSubscription,
    ) Error!HostSubscriptionStatus {
        if (!validHostPortSymbol(subscription.port_symbol))
            return error.InvalidParameter;
        const callback = self.vtable.unsubscribe_host_peak orelse
            return .unsupported;
        return callback(self.userdata, subscription);
    }

    pub fn registerHostAtomNotification(
        self: Context,
        notification: HostAtomNotification,
    ) Error!HostSubscriptionStatus {
        if (!validHostPortSymbol(notification.port_symbol) or
            !validHostValueUri(notification.atom_type_uri))
            return error.InvalidParameter;
        const callback = self.vtable.register_host_atom_notification orelse
            return .unsupported;
        return callback(self.userdata, notification);
    }

    pub fn unregisterHostAtomNotification(
        self: Context,
        notification: HostAtomNotification,
    ) Error!HostSubscriptionStatus {
        if (!validHostPortSymbol(notification.port_symbol) or
            !validHostValueUri(notification.atom_type_uri))
            return error.InvalidParameter;
        const callback = self.vtable.unregister_host_atom_notification orelse
            return .unsupported;
        return callback(self.userdata, notification);
    }

    pub fn sendPluginAtomMessage(
        self: Context,
        message: PluginAtomMessage,
    ) Error!PluginMessageStatus {
        if (!validHostPortSymbol(message.port_symbol) or
            !validHostValueUri(message.atom_type_uri) or
            message.body.len > maximum_plugin_atom_body_bytes)
            return error.InvalidParameter;
        const callback = self.vtable.send_plugin_atom_message orelse
            return .unsupported;
        return callback(self.userdata, message);
    }
};

fn validHostPortSymbol(symbol: [:0]const u8) bool {
    if (symbol.len == 0 or symbol.len > maximum_host_port_symbol_bytes or
        std.mem.indexOfScalar(u8, symbol, 0) != null)
        return false;
    if (!std.ascii.isAlphabetic(symbol[0]) and symbol[0] != '_')
        return false;
    for (symbol[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_')
            return false;
    }
    return true;
}

fn validHostValueUri(uri: [:0]const u8) bool {
    if (uri.len == 0 or uri.len > maximum_host_value_uri_bytes)
        return false;
    if (std.mem.indexOfScalar(u8, uri, 0) != null)
        return false;
    const colon = std.mem.indexOfScalar(u8, uri, ':') orelse return false;
    if (colon == 0 or !std.ascii.isAlphabetic(uri[0])) return false;
    for (uri[1..colon]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '+' and byte != '-' and byte != '.')
            return false;
    }
    var index: usize = 0;
    while (index < uri.len) {
        const byte = uri[index];
        if (byte <= 0x20 or byte >= 0x7f or
            byte == '<' or byte == '>' or byte == '"' or byte == '\\' or
            byte == '{' or byte == '}' or byte == '|' or byte == '^' or
            byte == '`')
            return false;
        if (byte == '%') {
            if (uri.len - index < 3 or
                !std.ascii.isHex(uri[index + 1]) or
                !std.ascii.isHex(uri[index + 2]))
                return false;
            index += 3;
            continue;
        }
        index += 1;
    }
    return true;
}

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
        host_peak_measurement: ?*const fn (*anyopaque, HostPeakMeasurement) void = null,
        host_atom_message: ?*const fn (*anyopaque, HostAtomMessage) void = null,
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

    pub fn hostPeakMeasurement(
        self: *Editor,
        measurement: HostPeakMeasurement,
    ) void {
        if (!measurement.valid()) return;
        const callback = self.adapter.vtable.host_peak_measurement orelse
            return;
        callback(self.adapter.userdata, measurement);
    }

    pub fn hostAtomMessage(self: *Editor, message: HostAtomMessage) void {
        if (!message.valid()) return;
        const callback = self.adapter.vtable.host_atom_message orelse
            return;
        callback(self.adapter.userdata, message);
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
    host_value_request_count: usize = 0,
    host_value_key_length: usize = 0,
    host_value_type_length: usize = 0,
    host_value_status: HostValueRequestStatus = .accepted,
    host_subscription_count: usize = 0,
    host_unsubscription_count: usize = 0,
    host_subscription_source: u32 = 0,
    host_subscription_delivery: HostPeakDelivery = .dynamic,
    host_subscription_symbol_length: usize = 0,
    host_subscription_status: HostSubscriptionStatus = .accepted,
    host_peak_count: usize = 0,
    host_peak: HostPeakMeasurement = .{
        .source_id = 0,
        .period_start = 0,
        .period_size = 1,
        .peak = 0.0,
    },
    host_atom_registration_count: usize = 0,
    host_atom_unregistration_count: usize = 0,
    host_atom_source: u32 = 0,
    host_atom_symbol_length: usize = 0,
    host_atom_type_length: usize = 0,
    host_atom_count: usize = 0,
    host_atom_body_length: usize = 0,
    plugin_atom_count: usize = 0,
    plugin_atom_symbol_length: usize = 0,
    plugin_atom_type_length: usize = 0,
    plugin_atom_body_length: usize = 0,
    plugin_message_status: PluginMessageStatus = .accepted,
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

    fn requestHostValue(
        ptr: *anyopaque,
        request: HostValueRequest,
    ) HostValueRequestStatus {
        const self = from(ptr);
        self.host_value_request_count += 1;
        self.host_value_key_length = request.key_uri.len;
        self.host_value_type_length = if (request.value_type_uri) |uri|
            uri.len
        else
            0;
        return self.host_value_status;
    }

    fn subscribeHostPeak(
        ptr: *anyopaque,
        subscription: HostPeakSubscription,
    ) HostSubscriptionStatus {
        const self = from(ptr);
        self.host_subscription_count += 1;
        self.host_subscription_source = subscription.source_id;
        self.host_subscription_delivery = subscription.delivery;
        self.host_subscription_symbol_length = subscription.port_symbol.len;
        return self.host_subscription_status;
    }

    fn unsubscribeHostPeak(
        ptr: *anyopaque,
        subscription: HostPeakSubscription,
    ) HostSubscriptionStatus {
        const self = from(ptr);
        self.host_unsubscription_count += 1;
        self.host_subscription_source = subscription.source_id;
        self.host_subscription_delivery = subscription.delivery;
        self.host_subscription_symbol_length = subscription.port_symbol.len;
        return self.host_subscription_status;
    }

    fn registerHostAtomNotification(
        ptr: *anyopaque,
        notification: HostAtomNotification,
    ) HostSubscriptionStatus {
        const self = from(ptr);
        self.host_atom_registration_count += 1;
        self.host_atom_source = notification.source_id;
        self.host_atom_symbol_length = notification.port_symbol.len;
        self.host_atom_type_length = notification.atom_type_uri.len;
        return self.host_subscription_status;
    }

    fn unregisterHostAtomNotification(
        ptr: *anyopaque,
        notification: HostAtomNotification,
    ) HostSubscriptionStatus {
        const self = from(ptr);
        self.host_atom_unregistration_count += 1;
        self.host_atom_source = notification.source_id;
        self.host_atom_symbol_length = notification.port_symbol.len;
        self.host_atom_type_length = notification.atom_type_uri.len;
        return self.host_subscription_status;
    }

    fn sendPluginAtomMessage(
        ptr: *anyopaque,
        message: PluginAtomMessage,
    ) PluginMessageStatus {
        const self = from(ptr);
        self.plugin_atom_count += 1;
        self.plugin_atom_symbol_length = message.port_symbol.len;
        self.plugin_atom_type_length = message.atom_type_uri.len;
        self.plugin_atom_body_length = message.body.len;
        return self.plugin_message_status;
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

    fn hostPeakMeasurement(
        ptr: *anyopaque,
        measurement: HostPeakMeasurement,
    ) void {
        const self = from(ptr);
        self.host_peak_count += 1;
        self.host_peak = measurement;
    }

    fn hostAtomMessage(ptr: *anyopaque, message: HostAtomMessage) void {
        const self = from(ptr);
        self.host_atom_count += 1;
        self.host_atom_source = message.source_id;
        self.host_atom_body_length = message.body.len;
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
        .request_host_value = requestHostValue,
        .subscribe_host_peak = subscribeHostPeak,
        .unsubscribe_host_peak = unsubscribeHostPeak,
        .register_host_atom_notification = registerHostAtomNotification,
        .unregister_host_atom_notification = unregisterHostAtomNotification,
        .send_plugin_atom_message = sendPluginAtomMessage,
    };

    const adapter_vtable = Adapter.VTable{
        .attach = attach,
        .detach = detach,
        .resize = resize,
        .scale = setScale,
        .focus = focus,
        .parameter_changed = parameterChanged,
        .host_peak_measurement = hostPeakMeasurement,
        .host_atom_message = hostAtomMessage,
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

test "host value requests validate URIs before dispatch" {
    var fake = Fake{};
    const context = fake.context();
    const key_uri = "https://example.test/parameters/sample";
    const type_uri = "http://lv2plug.in/ns/ext/atom#Path";
    try std.testing.expectEqual(
        HostValueRequestStatus.accepted,
        try context.requestHostValue(.{
            .key_uri = key_uri,
            .value_type_uri = type_uri,
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.host_value_request_count);
    try std.testing.expectEqual(key_uri.len, fake.host_value_key_length);
    try std.testing.expectEqual(type_uri.len, fake.host_value_type_length);

    fake.host_value_status = .busy;
    try std.testing.expectEqual(
        HostValueRequestStatus.busy,
        try context.requestHostValue(.{ .key_uri = key_uri }),
    );
    try std.testing.expectEqual(@as(usize, 2), fake.host_value_request_count);

    try std.testing.expectError(
        error.InvalidParameter,
        context.requestHostValue(.{ .key_uri = "missing-scheme" }),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.requestHostValue(.{ .key_uri = "urn:bad\x00tail" }),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.requestHostValue(.{ .key_uri = "urn:bad%2" }),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.requestHostValue(.{ .key_uri = "urn:bad|tail" }),
    );
    var oversized: [maximum_host_value_uri_bytes + 1:0]u8 = @splat('a');
    oversized[1] = ':';
    try std.testing.expectError(
        error.InvalidParameter,
        context.requestHostValue(.{ .key_uri = &oversized }),
    );
    try std.testing.expectEqual(@as(usize, 2), fake.host_value_request_count);

    var multi = MultiFake{};
    try std.testing.expectEqual(
        HostValueRequestStatus.unsupported,
        try multi.context().requestHostValue(.{ .key_uri = key_uri }),
    );
}

test "host peak subscriptions validate symbols before dispatch" {
    var fake = Fake{};
    const context = fake.context();
    const subscription = HostPeakSubscription{
        .port_symbol = "audio_in",
        .source_id = 17,
    };
    try std.testing.expectEqual(
        HostSubscriptionStatus.accepted,
        try context.subscribeHostPeak(subscription),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.host_subscription_count);
    try std.testing.expectEqual(@as(u32, 17), fake.host_subscription_source);
    try std.testing.expectEqual(
        HostPeakDelivery.dynamic,
        fake.host_subscription_delivery,
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        fake.host_subscription_symbol_length,
    );
    fake.host_subscription_status = .rejected;
    try std.testing.expectEqual(
        HostSubscriptionStatus.rejected,
        try context.unsubscribeHostPeak(subscription),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.host_unsubscription_count);
    const static_subscription = HostPeakSubscription{
        .port_symbol = "audio_out",
        .source_id = 18,
        .delivery = .static,
    };
    try std.testing.expectEqual(
        HostSubscriptionStatus.rejected,
        try context.subscribeHostPeak(static_subscription),
    );
    try std.testing.expectEqual(
        HostPeakDelivery.static,
        fake.host_subscription_delivery,
    );

    inline for (.{ "", "1audio", "audio-in", "audio\x00in" }) |symbol| {
        try std.testing.expectError(
            error.InvalidParameter,
            context.subscribeHostPeak(.{
                .port_symbol = symbol,
                .source_id = 1,
            }),
        );
    }
    var oversized: [maximum_host_port_symbol_bytes + 1:0]u8 =
        @splat('a');
    try std.testing.expectError(
        error.InvalidParameter,
        context.unsubscribeHostPeak(.{
            .port_symbol = &oversized,
            .source_id = 1,
        }),
    );
    try std.testing.expectEqual(@as(usize, 2), fake.host_subscription_count);
    try std.testing.expectEqual(@as(usize, 1), fake.host_unsubscription_count);

    var multi = MultiFake{};
    try std.testing.expectEqual(
        HostSubscriptionStatus.unsupported,
        try multi.context().subscribeHostPeak(subscription),
    );
    try std.testing.expectEqual(
        HostSubscriptionStatus.unsupported,
        try multi.context().unsubscribeHostPeak(subscription),
    );
}

test "editor contains malformed host peak measurements" {
    var fake = Fake{};
    var editor = fakeEditor(&fake);
    const measurement = HostPeakMeasurement{
        .source_id = 23,
        .period_start = 100,
        .period_size = 64,
        .peak = 1.25,
    };
    editor.hostPeakMeasurement(measurement);
    try std.testing.expectEqual(@as(usize, 1), fake.host_peak_count);
    try std.testing.expectEqual(measurement, fake.host_peak);

    editor.hostPeakMeasurement(.{
        .source_id = 23,
        .period_start = 100,
        .period_size = 0,
        .peak = 1.0,
    });
    editor.hostPeakMeasurement(.{
        .source_id = 23,
        .period_start = 100,
        .period_size = 64,
        .peak = -0.01,
    });
    editor.hostPeakMeasurement(.{
        .source_id = 23,
        .period_start = 100,
        .period_size = 64,
        .peak = std.math.nan(f32),
    });
    editor.hostPeakMeasurement(.{
        .source_id = 23,
        .period_start = 100,
        .period_size = 64,
        .peak = std.math.inf(f32),
    });
    try std.testing.expectEqual(@as(usize, 1), fake.host_peak_count);
}

test "Atom messages validate registration and bounded bidirectional delivery" {
    var fake = Fake{};
    const context = fake.context();
    const notification = HostAtomNotification{
        .port_symbol = "events_out",
        .atom_type_uri = "https://example.test/messages#status",
        .source_id = 41,
    };
    try std.testing.expectEqual(
        HostSubscriptionStatus.accepted,
        try context.registerHostAtomNotification(notification),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        fake.host_atom_registration_count,
    );
    try std.testing.expectEqual(@as(u32, 41), fake.host_atom_source);
    try std.testing.expectEqual(
        HostSubscriptionStatus.accepted,
        try context.unregisterHostAtomNotification(notification),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        fake.host_atom_unregistration_count,
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.registerHostAtomNotification(.{
            .port_symbol = "events-out",
            .atom_type_uri = notification.atom_type_uri,
            .source_id = 1,
        }),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.registerHostAtomNotification(.{
            .port_symbol = notification.port_symbol,
            .atom_type_uri = "relative-type",
            .source_id = 1,
        }),
    );

    var editor = fakeEditor(&fake);
    const body = [_]u8{ 1, 2, 3, 4 };
    editor.hostAtomMessage(.{ .source_id = 41, .body = &body });
    try std.testing.expectEqual(@as(usize, 1), fake.host_atom_count);
    try std.testing.expectEqual(@as(usize, body.len), fake.host_atom_body_length);
    var oversized: [maximum_host_atom_body_bytes + 1]u8 = undefined;
    editor.hostAtomMessage(.{ .source_id = 41, .body = &oversized });
    try std.testing.expectEqual(@as(usize, 1), fake.host_atom_count);

    const plugin_message = PluginAtomMessage{
        .port_symbol = "events_in",
        .atom_type_uri = "https://example.test/messages#command",
        .body = &body,
    };
    try std.testing.expectEqual(
        PluginMessageStatus.accepted,
        try context.sendPluginAtomMessage(plugin_message),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.plugin_atom_count);
    try std.testing.expectEqual(
        plugin_message.port_symbol.len,
        fake.plugin_atom_symbol_length,
    );
    try std.testing.expectEqual(
        plugin_message.atom_type_uri.len,
        fake.plugin_atom_type_length,
    );
    try std.testing.expectEqual(body.len, fake.plugin_atom_body_length);
    try std.testing.expectError(
        error.InvalidParameter,
        context.sendPluginAtomMessage(.{
            .port_symbol = "events-in",
            .atom_type_uri = plugin_message.atom_type_uri,
            .body = &body,
        }),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.sendPluginAtomMessage(.{
            .port_symbol = plugin_message.port_symbol,
            .atom_type_uri = "relative-type",
            .body = &body,
        }),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        context.sendPluginAtomMessage(.{
            .port_symbol = plugin_message.port_symbol,
            .atom_type_uri = plugin_message.atom_type_uri,
            .body = &oversized,
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.plugin_atom_count);

    var multi = MultiFake{};
    try std.testing.expectEqual(
        HostSubscriptionStatus.unsupported,
        try multi.context().registerHostAtomNotification(notification),
    );
    try std.testing.expectEqual(
        PluginMessageStatus.unsupported,
        try multi.context().sendPluginAtomMessage(plugin_message),
    );
}

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
