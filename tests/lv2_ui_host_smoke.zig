const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const ui = core.lv2.ui;
const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const ui.Descriptor;
const RequestValueProbeFunction = *const fn (
    widget: ui.Widget,
    include_type: bool,
) callconv(.c) c_int;
const PeakProbe = extern struct {
    subscription_status: c_int,
    peak_count: u32,
    source_id: u32,
    period_start: u32,
    period_size: u32,
    peak: f32,
};
const PeakProbeFunction = *const fn (
    widget: ui.Widget,
    result: ?*PeakProbe,
) callconv(.c) bool;
const RegisterStaticPeakFunction = *const fn (
    widget: ui.Widget,
) callconv(.c) c_int;
const AtomProbe = extern struct {
    registration_status: c_int,
    message_count: u32,
    source_id: u32,
    body_size: u32,
    body: [32]u8,
};
const AtomProbeFunction = *const fn (
    widget: ui.Widget,
    result: ?*AtomProbe,
) callconv(.c) bool;
const SendAtomFunction = *const fn (
    widget: ui.Widget,
) callconv(.c) c_int;

const sample_path_uri =
    "https://zig-vst3.dev/tests/lv2-ui-probe#samplePath";
const atom_path_uri = "http://lv2plug.in/ns/ext/atom#Path";
const status_uri =
    "https://zig-vst3.dev/tests/lv2-ui-probe#status";
const command_uri =
    "https://zig-vst3.dev/tests/lv2-ui-probe#command";

const Host = struct {
    writes: usize = 0,
    touches: usize = 0,
    releases: usize = 0,
    resize_requests: usize = 0,
    value_requests: usize = 0,
    requested_key: ui.Urid = 0,
    requested_type: ui.Urid = 0,
    request_status: ui.RequestValueStatus = ui.request_value_success,
    subscriptions: usize = 0,
    unsubscriptions: usize = 0,
    subscribed_port: u32 = ui.invalid_port_index,
    subscribed_protocol: ui.Urid = 0,
    subscription_status: u32 = 0,
    last_value: f32 = 0.0,
    atom_writes: usize = 0,
    atom_write_port: u32 = ui.invalid_port_index,
    atom_write_format: ui.Urid = 0,
    atom_write_type: ui.Urid = 0,
    atom_write_body: [32]u8 = @splat(0),
    atom_write_body_len: usize = 0,
    reentrant_widget: ui.Widget = null,
    reentrant_send_atom: ?SendAtomFunction = null,
    reentrant_status: ?c_int = null,

    fn map(
        _: ?*anyopaque,
        uri: [*:0]const u8,
    ) callconv(.c) ui.Urid {
        const value = std.mem.span(uri);
        if (std.mem.eql(u8, value, ui.scale_factor_uri)) return 139;
        if (std.mem.eql(u8, value, ui.update_rate_uri)) return 140;
        if (std.mem.eql(u8, value, ui.window_title_uri)) return 141;
        if (std.mem.eql(u8, value, ui.background_color_uri)) return 142;
        if (std.mem.eql(u8, value, ui.foreground_color_uri)) return 143;
        if (std.mem.eql(u8, value, ui.atom_float_uri)) return 47;
        if (std.mem.eql(u8, value, ui.atom_string_uri)) return 48;
        if (std.mem.eql(u8, value, ui.atom_int_uri)) return 49;
        if (std.mem.eql(u8, value, sample_path_uri)) return 150;
        if (std.mem.eql(u8, value, atom_path_uri)) return 51;
        if (std.mem.eql(u8, value, ui.peak_protocol_uri)) return 152;
        if (std.mem.eql(u8, value, ui.atom_event_transfer_uri)) return 153;
        if (std.mem.eql(u8, value, status_uri)) return 154;
        if (std.mem.eql(u8, value, command_uri)) return 155;
        return 0;
    }

    fn portIndex(
        _: ui.Handle,
        symbol: [*:0]const u8,
    ) callconv(.c) u32 {
        const value = std.mem.span(symbol);
        if (std.mem.eql(u8, value, "audio_in")) return 0;
        if (std.mem.eql(u8, value, "midi_input")) return 2;
        if (std.mem.eql(u8, value, "midi_output")) return 3;
        return ui.invalid_port_index;
    }

    fn subscribe(
        handle: ui.Handle,
        port_index: u32,
        protocol: ui.Urid,
        features: ?[*:null]const ?*const ui.Feature,
    ) callconv(.c) u32 {
        const raw_host = handle orelse return 1;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (features != null) return 1;
        self.subscriptions += 1;
        self.subscribed_port = port_index;
        self.subscribed_protocol = protocol;
        return self.subscription_status;
    }

    fn unsubscribe(
        handle: ui.Handle,
        port_index: u32,
        protocol: ui.Urid,
        features: ?[*:null]const ?*const ui.Feature,
    ) callconv(.c) u32 {
        const raw_host = handle orelse return 1;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (features != null) return 1;
        self.unsubscriptions += 1;
        self.subscribed_port = port_index;
        self.subscribed_protocol = protocol;
        return self.subscription_status;
    }

    fn requestValue(
        handle: ui.Handle,
        key: ui.Urid,
        value_type: ui.Urid,
        features: ?[*:null]const ?*const ui.Feature,
    ) callconv(.c) ui.RequestValueStatus {
        const raw_host = handle orelse return ui.request_value_unsupported;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (features != null) return ui.request_value_unsupported;
        self.value_requests += 1;
        self.requested_key = key;
        self.requested_type = value_type;
        return self.request_status;
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
        const raw_value = buffer orelse return;
        if (port == 4 and size == @sizeOf(f32) and format == 0) {
            self.last_value =
                @as(*align(1) const f32, @ptrCast(raw_value)).*;
            self.writes += 1;
            return;
        }
        if (port != 2 or format != 153 or size < @sizeOf(ui.Atom))
            return;
        const atom = @as(*align(1) const ui.Atom, @ptrCast(raw_value)).*;
        const total_size = std.math.add(
            usize,
            @sizeOf(ui.Atom),
            atom.size,
        ) catch return;
        if (total_size != size or atom.size > self.atom_write_body.len)
            return;
        const bytes: [*]align(1) const u8 = @ptrCast(raw_value);
        self.atom_writes += 1;
        self.atom_write_port = port;
        self.atom_write_format = format;
        self.atom_write_type = atom.type;
        @memset(&self.atom_write_body, 0);
        @memcpy(
            self.atom_write_body[0..atom.size],
            bytes[@sizeOf(ui.Atom)..total_size],
        );
        self.atom_write_body_len = atom.size;
        if (self.reentrant_send_atom) |send| {
            self.reentrant_send_atom = null;
            self.reentrant_status = send(self.reentrant_widget);
        }
    }

    fn touch(
        handle: ui.Handle,
        port: u32,
        grabbed: bool,
    ) callconv(.c) c_int {
        const raw_host = handle orelse return 1;
        const self: *@This() = @ptrCast(@alignCast(raw_host));
        if (port != 4) return 1;
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
    const request_value_probe = library.lookup(
        RequestValueProbeFunction,
        "lv2_ui_probe_request_value",
    ) orelse return error.MissingRequestValueProbe;
    const peak_probe = library.lookup(
        PeakProbeFunction,
        "lv2_ui_probe_peak",
    ) orelse return error.MissingPeakProbe;
    const register_static_peak = library.lookup(
        RegisterStaticPeakFunction,
        "lv2_ui_probe_register_static_peak",
    ) orelse return error.MissingStaticPeakProbe;
    const atom_probe = library.lookup(
        AtomProbeFunction,
        "lv2_ui_probe_atom",
    ) orelse return error.MissingAtomProbe;
    const send_atom = library.lookup(
        SendAtomFunction,
        "lv2_ui_probe_send_atom",
    ) orelse return error.MissingSendAtomProbe;
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
    var null_touch = ui.Touch{
        .handle = null,
        .touch = null,
    };
    const null_touch_feature = ui.Feature{
        .URI = ui.touch_uri,
        .data = &null_touch,
    };
    var null_resize = ui.Resize{
        .handle = null,
        .ui_resize = null,
    };
    const null_resize_feature = ui.Feature{
        .URI = ui.resize_uri,
        .data = &null_resize,
    };
    var urid_map = ui.UridMap{
        .handle = null,
        .map = Host.map,
    };
    var map_feature = ui.Feature{
        .URI = ui.urid_map_uri,
        .data = &urid_map,
    };
    var request_value = ui.RequestValue{
        .handle = &host,
        .request = Host.requestValue,
    };
    var request_value_feature = ui.Feature{
        .URI = ui.request_value_uri,
        .data = &request_value,
    };
    var port_map = ui.PortMap{
        .handle = &host,
        .port_index = Host.portIndex,
    };
    var port_map_feature = ui.Feature{
        .URI = ui.port_map_uri,
        .data = &port_map,
    };
    var port_subscribe = ui.PortSubscribe{
        .handle = &host,
        .subscribe = Host.subscribe,
        .unsubscribe = Host.unsubscribe,
    };
    var port_subscribe_feature = ui.Feature{
        .URI = ui.port_subscribe_uri,
        .data = &port_subscribe,
    };
    var peak_protocol_feature = ui.Feature{
        .URI = ui.peak_protocol_uri,
        .data = null,
    };
    var atom_event_protocol_feature = ui.Feature{
        .URI = ui.atom_event_transfer_uri,
        .data = null,
    };
    var null_urid_map = ui.UridMap{
        .handle = null,
        .map = null,
    };
    const null_map_feature = ui.Feature{
        .URI = ui.urid_map_uri,
        .data = &null_urid_map,
    };
    const initial_scale: f32 = 1.25;
    const initial_update_rate_hz: f32 = 30.0;
    const initial_window_title = "Dynamic UI Probe";
    const initial_background: i32 = @bitCast(@as(u32, 0x182838ff));
    const initial_foreground: i32 = @bitCast(@as(u32, 0xd8e8f8ff));
    const initial_options = [_]ui.OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &initial_scale,
        },
        .{
            .key = 140,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &initial_update_rate_hz,
        },
        .{
            .key = 141,
            .size = initial_window_title.len + 1,
            .type = 48,
            .value = initial_window_title.ptr,
        },
        .{
            .key = 142,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &initial_background,
        },
        .{
            .key = 143,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &initial_foreground,
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
        &request_value_feature,
        &port_map_feature,
        &port_subscribe_feature,
        &peak_protocol_feature,
        &atom_event_protocol_feature,
        &options_feature,
    };
    const null_uri_feature = ui.Feature{
        .URI = null,
        .data = null,
    };
    const null_uri_features = [_:null]?*const ui.Feature{
        &null_uri_feature,
        &parent_feature,
    };
    var misaligned_record_features = [_:null]?*const ui.Feature{
        null,
        &parent_feature,
    };
    const misaligned_feature_address: usize = 1;
    @memcpy(
        std.mem.asBytes(&misaligned_record_features[0]),
        std.mem.asBytes(&misaligned_feature_address),
    );
    var widget: ui.Widget = null;
    const null_map_features = [_:null]?*const ui.Feature{
        &parent_feature,
        &null_map_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &null_map_features,
    ) != null) return error.NullUridMapCallbackAccepted;
    const null_optional_callback_features =
        [_:null]?*const ui.Feature{
            &parent_feature,
            &null_touch_feature,
            &null_resize_feature,
        };
    const null_optional_callback_handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        null_optional_callback_features[0..].ptr,
    ) orelse return error.NullOptionalCallbackUiRejected;
    var unsupported_peak: PeakProbe = undefined;
    if (!peak_probe(widget, &unsupported_peak) or
        unsupported_peak.subscription_status !=
            @intFromEnum(core.gui.HostSubscriptionStatus.unsupported))
        return error.MissingPeakFeaturesEnabled;
    var unsupported_atom: AtomProbe = undefined;
    if (!atom_probe(widget, &unsupported_atom) or
        unsupported_atom.registration_status !=
            @intFromEnum(core.gui.HostSubscriptionStatus.unsupported))
        return error.MissingAtomFeaturesEnabled;
    if (send_atom(widget) !=
        @intFromEnum(core.gui.PluginMessageStatus.unsupported))
        return error.MissingAtomFeaturesEnabledOutbound;
    descriptor.cleanup(null_optional_callback_handle);
    if (descriptor.instantiate(
        null,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &features,
    ) != null) return error.NullDescriptorAccepted;
    if (descriptor.instantiate(
        descriptor,
        null,
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &features,
    ) != null) return error.NullPluginUriAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        null,
        Host.write,
        &host,
        &widget,
        &features,
    ) != null) return error.NullBundlePathAccepted;
    const static_features = [_:null]?*const ui.Feature{
        &parent_feature,
        &map_feature,
        &port_map_feature,
        &peak_protocol_feature,
    };
    const static_subscriptions_before = host.subscriptions;
    const static_unsubscriptions_before = host.unsubscriptions;
    var static_widget: ui.Widget = null;
    const static_handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &static_widget,
        &static_features,
    ) orelse return error.StaticPeakInstantiationFailed;
    if (register_static_peak(static_widget) !=
        @intFromEnum(core.gui.HostSubscriptionStatus.accepted))
        return error.StaticPeakRegistrationFailed;
    if (host.subscriptions != static_subscriptions_before)
        return error.StaticPeakCalledDynamicSubscribe;
    const static_peak_data = ui.PeakData{
        .period_start = 256,
        .period_size = 64,
        .peak = 0.625,
    };
    descriptor.port_event(
        static_handle,
        0,
        @sizeOf(ui.PeakData),
        152,
        &static_peak_data,
    );
    var static_peak_result: PeakProbe = undefined;
    if (!peak_probe(static_widget, &static_peak_result) or
        static_peak_result.peak_count != 1 or
        static_peak_result.source_id != 31 or
        static_peak_result.period_start != 256 or
        static_peak_result.period_size != 64 or
        static_peak_result.peak != 0.625)
        return error.StaticPeakDeliveryMismatch;
    descriptor.cleanup(static_handle);
    if (host.unsubscriptions != static_unsubscriptions_before)
        return error.StaticPeakCalledDynamicUnsubscribe;
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
    if (host.subscriptions != 1 or host.subscribed_port != 0 or
        host.subscribed_protocol != 152)
        return error.PeakSubscriptionMismatch;
    var peak_result: PeakProbe = undefined;
    if (!peak_probe(widget, &peak_result))
        return error.PeakProbeFailed;
    if (peak_result.subscription_status !=
        @intFromEnum(core.gui.HostSubscriptionStatus.accepted))
        return error.PeakSubscriptionStatusMismatch;
    const peak_data = ui.PeakData{
        .period_start = 1024,
        .period_size = 128,
        .peak = 0.875,
    };
    descriptor.port_event(
        handle,
        0,
        @sizeOf(ui.PeakData),
        152,
        &peak_data,
    );
    if (!peak_probe(widget, &peak_result) or peak_result.peak_count != 1 or
        peak_result.source_id != 29 or peak_result.period_start != 1024 or
        peak_result.period_size != 128 or peak_result.peak != 0.875)
        return error.PeakDeliveryMismatch;
    const malformed_peak = ui.PeakData{
        .period_start = 1152,
        .period_size = 0,
        .peak = 1.0,
    };
    descriptor.port_event(
        handle,
        0,
        @sizeOf(ui.PeakData),
        152,
        &malformed_peak,
    );
    descriptor.port_event(handle, 0, 1, 152, &peak_data);
    descriptor.port_event(
        handle,
        1,
        @sizeOf(ui.PeakData),
        152,
        &peak_data,
    );
    if (!peak_probe(widget, &peak_result) or peak_result.peak_count != 1)
        return error.MalformedPeakDelivered;
    var atom_result: AtomProbe = undefined;
    if (!atom_probe(widget, &atom_result) or
        atom_result.registration_status !=
            @intFromEnum(core.gui.HostSubscriptionStatus.accepted))
        return error.AtomRegistrationFailed;
    const AtomPacket = extern struct {
        atom: ui.Atom,
        body: [4]u8,
    };
    const atom_packet = AtomPacket{
        .atom = .{ .size = 4, .type = 154 },
        .body = .{ 2, 4, 6, 8 },
    };
    descriptor.port_event(
        handle,
        3,
        @sizeOf(AtomPacket),
        153,
        &atom_packet,
    );
    if (!atom_probe(widget, &atom_result) or
        atom_result.message_count != 1 or
        atom_result.source_id != 37 or
        atom_result.body_size != atom_packet.body.len or
        !std.mem.eql(
            u8,
            atom_result.body[0..atom_result.body_size],
            &atom_packet.body,
        )) return error.AtomDeliveryMismatch;
    host.reentrant_widget = widget;
    host.reentrant_send_atom = send_atom;
    if (send_atom(widget) !=
        @intFromEnum(core.gui.PluginMessageStatus.accepted))
        return error.AtomWriteFailed;
    if (host.reentrant_status !=
        @intFromEnum(core.gui.PluginMessageStatus.rejected))
        return error.ReentrantAtomWriteAccepted;
    if (host.atom_writes != 1 or host.atom_write_port != 2 or
        host.atom_write_format != 153 or host.atom_write_type != 155 or
        host.atom_write_body_len != 4 or
        !std.mem.eql(
            u8,
            host.atom_write_body[0..host.atom_write_body_len],
            &.{ 8, 6, 4, 2 },
        )) return error.AtomWriteMismatch;

    const cleanup_subscriptions = host.subscriptions;
    const cleanup_unsubscriptions = host.unsubscriptions;
    var cleanup_widget: ui.Widget = null;
    const cleanup_handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &cleanup_widget,
        &features,
    ) orelse return error.CleanupProbeInstantiationFailed;
    if (host.subscriptions != cleanup_subscriptions + 1)
        return error.CleanupProbeSubscriptionMissing;
    descriptor.cleanup(cleanup_handle);
    if (host.unsubscriptions != cleanup_unsubscriptions + 1 or
        host.subscribed_port != 0 or host.subscribed_protocol != 152)
        return error.PeakSubscriptionCleanupMissing;
    if (request_value_probe(widget, true) !=
        ui.request_value_success)
        return error.RequestValueFailed;
    if (host.value_requests != 1 or host.requested_key != 150 or
        host.requested_type != 51)
        return error.RequestValueMappingMismatch;
    host.request_status = ui.request_value_busy;
    if (request_value_probe(widget, false) != ui.request_value_busy)
        return error.RequestValueBusyStatusMismatch;
    if (host.value_requests != 2 or host.requested_key != 150 or
        host.requested_type != 0)
        return error.UntypedRequestValueMappingMismatch;
    host.request_status = 99;
    if (request_value_probe(widget, true) !=
        ui.request_value_unsupported)
        return error.RequestValueUnknownStatusAccepted;
    host.request_status = ui.request_value_success;

    if (descriptor.extension_data(null) != null)
        return error.NullExtensionUriAccepted;
    if (descriptor.extension_data(
        "http://lv2plug.in/ns/ext/options#interface/hostile-tail",
    ) != null) return error.ExtensionUriPrefixAccepted;
    const options_ptr = descriptor.extension_data(
        ui.options_interface_uri,
    ) orelse return error.MissingOptionsInterface;
    const runtime_options: *const ui.OptionsInterface =
        @ptrCast(@alignCast(options_ptr));
    if (runtime_options.get(handle, null) !=
        ui.options_status_unknown)
        return error.NullScaleQueryAccepted;
    if (runtime_options.set(handle, null) !=
        ui.options_status_unknown)
        return error.NullScaleUpdateAccepted;
    var misaligned_option_storage: [@sizeOf(ui.OptionsOption) * 2 + 1]u8 align(@alignOf(ui.OptionsOption)) =
        undefined;
    const misaligned_option_address =
        @intFromPtr(&misaligned_option_storage[1]);
    var misaligned_query: ?[*]ui.OptionsOption = null;
    @memcpy(
        std.mem.asBytes(&misaligned_query),
        std.mem.asBytes(&misaligned_option_address),
    );
    if (runtime_options.get(handle, misaligned_query) !=
        ui.options_status_unknown)
        return error.MisalignedScaleQueryAccepted;
    var misaligned_update: ?[*]const ui.OptionsOption = null;
    @memcpy(
        std.mem.asBytes(&misaligned_update),
        std.mem.asBytes(&misaligned_option_address),
    );
    if (runtime_options.set(handle, misaligned_update) !=
        ui.options_status_unknown)
        return error.MisalignedScaleUpdateAccepted;
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
    var update_rate_query = [_]ui.OptionsOption{
        .{ .key = 140 },
        .{},
    };
    if (runtime_options.get(handle, &update_rate_query) !=
        ui.options_status_success)
        return error.UpdateRateQueryFailed;
    const queried_update_rate = update_rate_query[0].value orelse
        return error.MissingUpdateRateValue;
    if (@as(
        *align(1) const f32,
        @ptrCast(queried_update_rate),
    ).* != 30.0) return error.InvalidInitialUpdateRate;
    var window_title_query = [_]ui.OptionsOption{
        .{ .key = 141 },
        .{},
    };
    if (runtime_options.get(handle, &window_title_query) !=
        ui.options_status_success)
        return error.WindowTitleQueryFailed;
    const queried_window_title = window_title_query[0].value orelse
        return error.MissingWindowTitleValue;
    const queried_title_bytes: [*]const u8 =
        @ptrCast(queried_window_title);
    if (!std.mem.eql(
        u8,
        queried_title_bytes[0..initial_window_title.len],
        initial_window_title,
    )) return error.InvalidInitialWindowTitle;
    var color_query = [_]ui.OptionsOption{
        .{ .key = 142 },
        .{ .key = 143 },
        .{},
    };
    if (runtime_options.get(handle, &color_query) !=
        ui.options_status_success)
        return error.ColorQueryFailed;
    const queried_background = color_query[0].value orelse
        return error.MissingBackgroundColor;
    const queried_foreground = color_query[1].value orelse
        return error.MissingForegroundColor;
    if (@as(*align(1) const u32, @ptrCast(queried_background)).* !=
        0x182838ff)
        return error.InvalidInitialBackgroundColor;
    if (@as(*align(1) const u32, @ptrCast(queried_foreground)).* !=
        0xd8e8f8ff)
        return error.InvalidInitialForegroundColor;
    var mixed_scale_query = [_]ui.OptionsOption{
        .{ .key = 139 },
        .{ .key = 999 },
        .{},
    };
    if (runtime_options.get(handle, &mixed_scale_query) !=
        ui.options_status_bad_key)
        return error.MixedScaleQueryStatusMismatch;
    if (mixed_scale_query[0].size != 0 or
        mixed_scale_query[0].type != 0 or
        mixed_scale_query[0].value != null)
        return error.MixedScaleQueryPartiallyWritten;
    var unterminated_scale_queries: [256]ui.OptionsOption =
        @splat(.{ .key = 139 });
    if (runtime_options.get(handle, &unterminated_scale_queries) !=
        ui.options_status_unknown)
        return error.UnterminatedScaleQueryStatusMismatch;
    if (unterminated_scale_queries[0].size != 0 or
        unterminated_scale_queries[
            unterminated_scale_queries.len - 1
        ].size != 0)
        return error.UnterminatedScaleQueryPartiallyWritten;
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
    const next_update_rate_hz: f32 = 45.0;
    const update_rate_update = [_]ui.OptionsOption{
        .{
            .key = 140,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &next_update_rate_hz,
        },
        .{},
    };
    if (runtime_options.set(handle, &update_rate_update) !=
        ui.options_status_success)
        return error.UpdateRateUpdateFailed;
    update_rate_query[0] = .{ .key = 140 };
    if (runtime_options.get(handle, &update_rate_query) !=
        ui.options_status_success)
        return error.UpdatedRateQueryFailed;
    const updated_rate = update_rate_query[0].value orelse
        return error.MissingUpdatedRateValue;
    if (@as(*align(1) const f32, @ptrCast(updated_rate)).* != 45.0)
        return error.InvalidUpdatedRate;
    const next_window_title = "Updated Dynamic UI";
    const window_title_update = [_]ui.OptionsOption{
        .{
            .key = 141,
            .size = next_window_title.len + 1,
            .type = 48,
            .value = next_window_title.ptr,
        },
        .{},
    };
    if (runtime_options.set(handle, &window_title_update) !=
        ui.options_status_success)
        return error.WindowTitleUpdateFailed;
    window_title_query[0] = .{ .key = 141 };
    if (runtime_options.get(handle, &window_title_query) !=
        ui.options_status_success)
        return error.UpdatedWindowTitleQueryFailed;
    const updated_window_title = window_title_query[0].value orelse
        return error.MissingUpdatedWindowTitleValue;
    const updated_title_bytes: [*]const u8 =
        @ptrCast(updated_window_title);
    if (!std.mem.eql(
        u8,
        updated_title_bytes[0..next_window_title.len],
        next_window_title,
    )) return error.InvalidUpdatedWindowTitle;
    const next_background: i32 = @bitCast(@as(u32, 0x405060ff));
    const next_foreground: i32 = @bitCast(@as(u32, 0xc0d0e0ff));
    const color_update = [_]ui.OptionsOption{
        .{
            .key = 142,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &next_background,
        },
        .{
            .key = 143,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &next_foreground,
        },
        .{},
    };
    if (runtime_options.set(handle, &color_update) !=
        ui.options_status_success)
        return error.ColorUpdateFailed;
    color_query[0] = .{ .key = 142 };
    color_query[1] = .{ .key = 143 };
    if (runtime_options.get(handle, &color_query) !=
        ui.options_status_success)
        return error.UpdatedColorQueryFailed;
    const updated_background = color_query[0].value orelse
        return error.MissingUpdatedBackgroundColor;
    const updated_foreground = color_query[1].value orelse
        return error.MissingUpdatedForegroundColor;
    if (@as(*align(1) const u32, @ptrCast(updated_background)).* !=
        0x405060ff)
        return error.InvalidUpdatedBackgroundColor;
    if (@as(*align(1) const u32, @ptrCast(updated_foreground)).* !=
        0xc0d0e0ff)
        return error.InvalidUpdatedForegroundColor;

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
    descriptor.port_event(handle, 4, @sizeOf(f32), 0, &plain);
    descriptor.port_event(handle, 4, 1, 0, &plain);
    descriptor.port_event(handle, 4, @sizeOf(f32), 1, &plain);
    const second_plain: f32 = 0.75;
    descriptor.port_event(
        second_handle,
        4,
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
            4,
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
        4,
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
        "https://zig-vst3.dev/tests/lv2-ui-probe/hostile-tail",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &features,
    ) != null) return error.PluginUriPrefixAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        null,
        &host,
        &widget,
        &features,
    ) != null) return error.MissingWriteFunctionAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &null_uri_features,
    ) != null) return error.MissingFeatureUriAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &misaligned_record_features,
    ) != null) return error.MisalignedFeatureRecordAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        null,
    ) != null) return error.NullFeatureListAccepted;
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
    const null_parent_feature = ui.Feature{
        .URI = ui.parent_uri,
        .data = null,
    };
    const null_parent_features =
        [_:null]?*const ui.Feature{&null_parent_feature};
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &null_parent_features,
    ) != null) return error.NullParentAccepted;
    const duplicate_parent_feature = ui.Feature{
        .URI = ui.parent_uri,
        .data = &host,
    };
    const duplicate_parent_features = [_:null]?*const ui.Feature{
        &parent_feature,
        &duplicate_parent_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &duplicate_parent_features,
    ) != null) return error.DuplicateParentAccepted;
    const duplicate_map_feature = ui.Feature{
        .URI = ui.urid_map_uri,
        .data = &urid_map,
    };
    const duplicate_map_features = [_:null]?*const ui.Feature{
        &parent_feature,
        &map_feature,
        &duplicate_map_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &duplicate_map_features,
    ) != null) return error.DuplicateUridMapAccepted;
    const duplicate_options_feature = ui.Feature{
        .URI = ui.options_options_uri,
        .data = @constCast(&initial_options),
    };
    const duplicate_option_features = [_:null]?*const ui.Feature{
        &parent_feature,
        &map_feature,
        &options_feature,
        &duplicate_options_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &duplicate_option_features,
    ) != null) return error.DuplicateOptionsFeatureAccepted;
    const duplicate_request_value_feature = ui.Feature{
        .URI = ui.request_value_uri,
        .data = &request_value,
    };
    const duplicate_request_value_features =
        [_:null]?*const ui.Feature{
            &parent_feature,
            &map_feature,
            &request_value_feature,
            &duplicate_request_value_feature,
        };
    var duplicate_request_widget: ui.Widget = null;
    const duplicate_request_handle = descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &duplicate_request_widget,
        &duplicate_request_value_features,
    ) orelse return error.DuplicateRequestValueUiRejected;
    defer descriptor.cleanup(duplicate_request_handle);
    if (request_value_probe(duplicate_request_widget, true) !=
        ui.request_value_unsupported)
        return error.DuplicateRequestValueFeatureEnabled;
    var unterminated_features: [256]?*const ui.Feature =
        @splat(&parent_feature);
    const unterminated_list: ?[*:null]const ?*const ui.Feature =
        @ptrCast(&unterminated_features);
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        unterminated_list,
    ) != null) return error.UnterminatedFeatureListAccepted;
    const missing_uri_feature = ui.Feature{
        .URI = null,
        .data = null,
    };
    const missing_uri_features = [_:null]?*const ui.Feature{
        &missing_uri_feature,
        &parent_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/tests/lv2-ui-probe",
        "/tmp/lv2-ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &missing_uri_features,
    ) != null) return error.MissingFeatureUriAccepted;
}
