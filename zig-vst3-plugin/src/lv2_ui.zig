//! LV2 UI ABI bindings and a bridge to the toolkit-neutral editor API.

const std = @import("std");
const gui = @import("gui.zig");
const parameters = @import("parameters.zig");
const plugin_api = @import("plugin.zig");
const process_api = @import("process.zig");

pub const ui_uri = "http://lv2plug.in/ns/extensions/ui";
pub const parent_uri = ui_uri ++ "#parent";
pub const idle_interface_uri = ui_uri ++ "#idleInterface";
pub const resize_uri = ui_uri ++ "#resize";
pub const show_interface_uri = ui_uri ++ "#showInterface";
pub const touch_uri = ui_uri ++ "#touch";
pub const request_value_uri = ui_uri ++ "#requestValue";
pub const port_map_uri = ui_uri ++ "#portMap";
pub const port_subscribe_uri = ui_uri ++ "#portSubscribe";
pub const peak_protocol_uri = ui_uri ++ "#peakProtocol";
pub const atom_event_transfer_uri =
    "http://lv2plug.in/ns/ext/atom#eventTransfer";
pub const scale_factor_uri = ui_uri ++ "#scaleFactor";
pub const update_rate_uri = ui_uri ++ "#updateRate";
pub const window_title_uri = ui_uri ++ "#windowTitle";
pub const background_color_uri = ui_uri ++ "#backgroundColor";
pub const foreground_color_uri = ui_uri ++ "#foregroundColor";
pub const options_options_uri =
    "http://lv2plug.in/ns/ext/options#options";
pub const options_interface_uri =
    "http://lv2plug.in/ns/ext/options#interface";
pub const urid_map_uri =
    "http://lv2plug.in/ns/ext/urid#map";
pub const atom_float_uri =
    "http://lv2plug.in/ns/ext/atom#Float";
pub const atom_string_uri =
    "http://lv2plug.in/ns/ext/atom#String";
pub const atom_int_uri =
    "http://lv2plug.in/ns/ext/atom#Int";
pub const programs_ui_interface_uri =
    "http://kxstudio.sf.net/ns/lv2ext/programs#UIInterface";

pub const Handle = ?*anyopaque;
pub const Controller = ?*anyopaque;
pub const Widget = ?*anyopaque;

pub const Feature = extern struct {
    URI: ?[*:0]const u8,
    data: ?*anyopaque,
};

pub const Urid = u32;

pub const UridMapFunction = *const fn (
    handle: ?*anyopaque,
    URI: [*:0]const u8,
) callconv(.c) Urid;

pub const UridMap = extern struct {
    handle: ?*anyopaque,
    map: ?UridMapFunction,
};

pub const OptionsOption = extern struct {
    context: c_int = 0,
    subject: u32 = 0,
    key: Urid = 0,
    size: u32 = 0,
    type: Urid = 0,
    value: ?*const anyopaque = null,
};

pub const OptionsStatus = u32;
pub const options_status_success: OptionsStatus = 0;
pub const options_status_unknown: OptionsStatus = 1 << 0;
pub const options_status_bad_subject: OptionsStatus = 1 << 1;
pub const options_status_bad_key: OptionsStatus = 1 << 2;
pub const options_status_bad_value: OptionsStatus = 1 << 3;

pub const OptionsInterface = extern struct {
    get: *const fn (
        instance: Handle,
        options: ?[*]align(1) OptionsOption,
    ) callconv(.c) OptionsStatus,
    set: *const fn (
        instance: Handle,
        options: ?[*]align(1) const OptionsOption,
    ) callconv(.c) OptionsStatus,
};

pub const WriteFunction = *const fn (
    controller: Controller,
    port_index: u32,
    buffer_size: u32,
    format: u32,
    buffer: ?*const anyopaque,
) callconv(.c) void;

pub const Descriptor = extern struct {
    URI: [*:0]const u8,
    instantiate: *const fn (
        descriptor: ?*const Descriptor,
        plugin_uri: ?[*:0]const u8,
        bundle_path: ?[*:0]const u8,
        write_function: ?WriteFunction,
        controller: Controller,
        widget: ?*Widget,
        features: ?[*:null]const ?*const Feature,
    ) callconv(.c) Handle,
    cleanup: *const fn (ui: Handle) callconv(.c) void,
    port_event: *const fn (
        ui: Handle,
        port_index: u32,
        buffer_size: u32,
        format: u32,
        buffer: ?*const anyopaque,
    ) callconv(.c) void,
    extension_data: *const fn (
        uri: ?[*:0]const u8,
    ) callconv(.c) ?*const anyopaque,
};

pub const IdleInterface = extern struct {
    idle: *const fn (ui: Handle) callconv(.c) c_int,
};

pub const ResizeFunction = *const fn (
    handle: Handle,
    width: c_int,
    height: c_int,
) callconv(.c) c_int;

pub const Resize = extern struct {
    handle: Handle,
    ui_resize: ?ResizeFunction,
};

pub const ResizeInterface = extern struct {
    ui_resize: *const fn (
        ui: Handle,
        width: c_int,
        height: c_int,
    ) callconv(.c) c_int,
};

pub const ShowInterface = extern struct {
    show: *const fn (ui: Handle) callconv(.c) c_int,
    hide: *const fn (ui: Handle) callconv(.c) c_int,
};

pub const Touch = extern struct {
    handle: Handle,
    touch: ?TouchFunction,
};

pub const TouchFunction = *const fn (
    handle: Handle,
    port_index: u32,
    grabbed: bool,
) callconv(.c) c_int;

pub const RequestValueStatus = c_int;
pub const request_value_success: RequestValueStatus = 0;
pub const request_value_busy: RequestValueStatus = 1;
pub const request_value_unknown: RequestValueStatus = 2;
pub const request_value_unsupported: RequestValueStatus = 3;

pub const RequestValueFunction = *const fn (
    handle: Handle,
    key: Urid,
    value_type: Urid,
    features: ?[*:null]const ?*const Feature,
) callconv(.c) RequestValueStatus;

pub const RequestValue = extern struct {
    handle: Handle,
    request: ?RequestValueFunction,
};

pub const invalid_port_index = std.math.maxInt(u32);

pub const PortIndexFunction = *const fn (
    handle: Handle,
    symbol: [*:0]const u8,
) callconv(.c) u32;

pub const PortMap = extern struct {
    handle: Handle,
    port_index: ?PortIndexFunction,
};

pub const PortSubscriptionFunction = *const fn (
    handle: Handle,
    port_index: u32,
    port_protocol: Urid,
    features: ?[*:null]const ?*const Feature,
) callconv(.c) u32;

pub const PortSubscribe = extern struct {
    handle: Handle,
    subscribe: ?PortSubscriptionFunction,
    unsubscribe: ?PortSubscriptionFunction,
};

pub const PeakData = extern struct {
    period_start: u32,
    period_size: u32,
    peak: f32,
};

pub const Atom = extern struct {
    size: u32,
    type: Urid,
};

const CheckedResize = struct {
    handle: Handle,
    ui_resize: ResizeFunction,
};

const CheckedTouch = struct {
    handle: Handle,
    touch: TouchFunction,
};

const CheckedUridMap = struct {
    handle: ?*anyopaque,
    map: UridMapFunction,
};

const CheckedRequestValue = struct {
    handle: Handle,
    request: RequestValueFunction,
};

const CheckedPortMap = struct {
    handle: Handle,
    port_index: PortIndexFunction,
};

const CheckedPortSubscribe = struct {
    handle: Handle,
    subscribe: PortSubscriptionFunction,
    unsubscribe: PortSubscriptionFunction,
};

pub const ProgramsUiInterface = extern struct {
    select_program: *const fn (
        ui: Handle,
        bank: u32,
        program: u32,
    ) callconv(.c) void,
};

pub const maximum_window_title_bytes = 255;
pub const default_background_rgba32: u32 = 0x000000ff;
pub const default_foreground_rgba32: u32 = 0xffffffff;

/// Builds one LV2 UI descriptor around a toolkit-neutral `gui.Editor`.
///
/// `Backend.create` constructs the editor. `Backend.widget` returns its native
/// child widget after attachment. Backends may also provide `idle`, `show`, and
/// `hide` hooks that accept a `gui.Adapter`.
pub fn Adapter(
    comptime Plugin: type,
    comptime CoreAdapter: type,
    comptime plugin_uri: [:0]const u8,
    comptime descriptor_uri: [:0]const u8,
    comptime initial_parameters: Plugin.Params,
    comptime platform: gui.Platform,
    comptime Backend: type,
) type {
    const Spec = plugin_api.PluginSpec(Plugin);
    const ParameterSet = parameters.ParameterSet(Plugin.Params);
    const parameter_set = ParameterSet.init(initial_parameters);
    const parameter_count = ParameterSet.count;
    const has_programs =
        @hasDecl(CoreAdapter, "programs_enabled") and
        CoreAdapter.programs_enabled;
    if (!@hasDecl(Backend, "create") or !@hasDecl(Backend, "widget"))
        @compileError("an LV2 UI backend requires create and widget declarations");
    if (CoreAdapter.parameters != parameter_count)
        @compileError("LV2 core and UI parameter counts must match");
    if (Plugin.name.len > maximum_window_title_bytes)
        @compileError("LV2 UI window title exceeds 255 bytes");

    return struct {
        const Self = @This();

        const PeakSubscription = struct {
            port_index: u32 = invalid_port_index,
            source_id: u32 = 0,
            delivery: gui.HostPeakDelivery = .dynamic,
        };

        const AtomNotification = struct {
            port_index: u32 = invalid_port_index,
            atom_type: Urid = 0,
            source_id: u32 = 0,
        };

        const Instance = struct {
            write_function: WriteFunction,
            controller: Controller,
            resize: ?CheckedResize,
            touch: ?CheckedTouch,
            urid_map: ?CheckedUridMap,
            request_value: ?CheckedRequestValue,
            port_map: ?CheckedPortMap,
            port_subscribe: ?CheckedPortSubscribe,
            peak_protocol: Urid,
            peak_subscriptions: [gui.maximum_host_peak_subscriptions]PeakSubscription,
            peak_subscription_count: usize,
            atom_event_protocol: Urid,
            atom_notifications: [gui.maximum_host_atom_notifications]AtomNotification,
            atom_notification_count: usize,
            atom_write_buffer: [@sizeOf(Atom) + gui.maximum_plugin_atom_body_bytes]u8 align(8),
            atom_write_active: bool,
            scale_key: Urid,
            update_rate_key: Urid,
            window_title_key: Urid,
            background_color_key: Urid,
            foreground_color_key: Urid,
            atom_float_type: Urid,
            atom_string_type: Urid,
            atom_int_type: Urid,
            scale: f32,
            update_rate_hz: f32,
            window_title: [maximum_window_title_bytes + 1]u8,
            window_title_len: usize,
            background_rgba32: u32,
            foreground_rgba32: u32,
            values: [parameter_count]f64,
            editor: gui.Editor,

            fn context(self: *Instance) gui.Context {
                return .{
                    .userdata = self,
                    .vtable = &context_vtable,
                };
            }
        };

        pub const descriptor = Descriptor{
            .URI = descriptor_uri.ptr,
            .instantiate = instantiate,
            .cleanup = cleanup,
            .port_event = portEvent,
            .extension_data = extensionData,
        };

        pub const idle_interface = IdleInterface{ .idle = idle };
        pub const resize_interface = ResizeInterface{
            .ui_resize = hostResize,
        };
        pub const show_interface = ShowInterface{
            .show = show,
            .hide = hide,
        };
        pub const programs_ui_interface = ProgramsUiInterface{
            .select_program = selectProgram,
        };
        pub const options_interface = OptionsInterface{
            .get = getOptions,
            .set = setOptions,
        };

        pub fn descriptorAt(index: u32) ?*const Descriptor {
            return if (index == 0) &descriptor else null;
        }

        pub fn instanceFromHandle(handle: Handle) ?*Instance {
            const raw = handle orelse return null;
            return instanceFromRaw(raw);
        }

        fn instanceFromRaw(raw: *anyopaque) ?*Instance {
            if (@intFromPtr(raw) % @alignOf(Instance) != 0) return null;
            return @ptrCast(@alignCast(raw));
        }

        fn instantiate(
            raw_descriptor: ?*const Descriptor,
            raw_plugin_uri: ?[*:0]const u8,
            raw_bundle_path: ?[*:0]const u8,
            write_function: ?WriteFunction,
            controller: Controller,
            widget: ?*Widget,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) Handle {
            _ = raw_descriptor orelse return null;
            const requested_plugin_uri =
                raw_plugin_uri orelse return null;
            _ = raw_bundle_path orelse return null;
            if (!cStringEquals(requested_plugin_uri, plugin_uri))
                return null;
            const write = write_function orelse return null;
            const widget_out = widget orelse return null;
            if (features == null) return null;
            if (!featureListValid(features)) return null;
            if (featureUriCount(features, parent_uri) != 1)
                return null;
            const parent_feature = findFeature(features, parent_uri) orelse
                return null;
            const parent = parent_feature.data orelse return null;
            const ui_options = readUiOptions(features) catch return null;
            const urid_map = checkedUridMap(features);
            const peak_protocol = if (featureUriCount(features, peak_protocol_uri) == 1) if (urid_map) |map|
                map.map(map.handle, peak_protocol_uri)
            else
                0 else 0;
            const mapped_atom_event_protocol = if (featureUriCount(
                features,
                atom_event_transfer_uri,
            ) == 1) if (urid_map) |map|
                map.map(map.handle, atom_event_transfer_uri)
            else
                0 else 0;
            const atom_event_protocol = if (mapped_atom_event_protocol !=
                peak_protocol)
                mapped_atom_event_protocol
            else
                0;

            const allocator = std.heap.page_allocator;
            const instance = allocator.create(Instance) catch return null;
            instance.* = .{
                .write_function = write,
                .controller = controller,
                .resize = checkedResize(features),
                .touch = checkedTouch(features),
                .urid_map = urid_map,
                .request_value = checkedRequestValue(features),
                .port_map = checkedPortMap(features),
                .port_subscribe = checkedPortSubscribe(features),
                .peak_protocol = peak_protocol,
                .peak_subscriptions = @splat(.{}),
                .peak_subscription_count = 0,
                .atom_event_protocol = atom_event_protocol,
                .atom_notifications = @splat(.{}),
                .atom_notification_count = 0,
                .atom_write_buffer = @splat(0),
                .atom_write_active = false,
                .scale_key = ui_options.scale_key,
                .update_rate_key = ui_options.update_rate_key,
                .window_title_key = ui_options.window_title_key,
                .background_color_key = ui_options.background_color_key,
                .foreground_color_key = ui_options.foreground_color_key,
                .atom_float_type = ui_options.atom_float_type,
                .atom_string_type = ui_options.atom_string_type,
                .atom_int_type = ui_options.atom_int_type,
                .scale = ui_options.scale orelse 1.0,
                .update_rate_hz = ui_options.update_rate_hz orelse 60.0,
                .window_title = @splat(0),
                .window_title_len = Plugin.name.len,
                .background_rgba32 = ui_options.background_rgba32 orelse
                    default_background_rgba32,
                .foreground_rgba32 = ui_options.foreground_rgba32 orelse
                    default_foreground_rgba32,
                .values = initialValues(),
                .editor = undefined,
            };
            @memcpy(
                instance.window_title[0..Plugin.name.len],
                Plugin.name,
            );
            if (ui_options.window_title) |title| {
                @memset(&instance.window_title, 0);
                @memcpy(instance.window_title[0..title.len], title);
                instance.window_title_len = title.len;
            }
            instance.editor = Backend.create(instance.context()) catch {
                releaseHostNotifications(instance);
                allocator.destroy(instance);
                return null;
            };
            instance.editor.attach(.{
                .platform = platform,
                .handle = parent,
            }) catch {
                releaseHostNotifications(instance);
                instance.editor.deinit();
                allocator.destroy(instance);
                return null;
            };
            if (ui_options.scale) |scale| {
                instance.editor.setScale(.{
                    .x = scale,
                    .y = scale,
                }) catch {
                    releaseHostNotifications(instance);
                    instance.editor.deinit();
                    allocator.destroy(instance);
                    return null;
                };
            }
            if (@hasDecl(Backend, "updateRate"))
                Backend.updateRate(
                    instance.editor.adapter,
                    instance.update_rate_hz,
                );
            if (@hasDecl(Backend, "windowTitle"))
                Backend.windowTitle(
                    instance.editor.adapter,
                    instance.window_title[0..instance.window_title_len],
                );
            if (@hasDecl(Backend, "backgroundColor"))
                Backend.backgroundColor(
                    instance.editor.adapter,
                    instance.background_rgba32,
                );
            if (@hasDecl(Backend, "foregroundColor"))
                Backend.foregroundColor(
                    instance.editor.adapter,
                    instance.foreground_rgba32,
                );
            widget_out.* = Backend.widget(instance.editor.adapter) orelse {
                releaseHostNotifications(instance);
                instance.editor.deinit();
                allocator.destroy(instance);
                return null;
            };
            return instance;
        }

        fn cleanup(handle: Handle) callconv(.c) void {
            const instance = instanceFromHandle(handle) orelse return;
            releaseHostNotifications(instance);
            instance.editor.deinit();
            std.heap.page_allocator.destroy(instance);
        }

        fn portEvent(
            handle: Handle,
            port_index: u32,
            buffer_size: u32,
            event_format: u32,
            buffer: ?*const anyopaque,
        ) callconv(.c) void {
            const instance = instanceFromHandle(handle) orelse return;
            const raw = buffer orelse return;
            if (event_format == instance.peak_protocol and
                event_format != 0)
            {
                if (buffer_size != @sizeOf(PeakData)) return;
                const subscription = peakSubscription(
                    instance,
                    port_index,
                ) orelse return;
                const peak_data =
                    @as(*align(1) const PeakData, @ptrCast(raw)).*;
                instance.editor.hostPeakMeasurement(.{
                    .source_id = subscription.source_id,
                    .period_start = peak_data.period_start,
                    .period_size = peak_data.period_size,
                    .peak = peak_data.peak,
                });
                return;
            }
            if (event_format == instance.atom_event_protocol and
                event_format != 0)
            {
                if (buffer_size < @sizeOf(Atom)) return;
                const atom = @as(*align(1) const Atom, @ptrCast(raw)).*;
                if (atom.type == 0 or
                    atom.size > gui.maximum_host_atom_body_bytes)
                    return;
                const total_size = std.math.add(
                    usize,
                    @sizeOf(Atom),
                    atom.size,
                ) catch return;
                if (total_size != buffer_size) return;
                const notification = atomNotification(
                    instance,
                    port_index,
                    atom.type,
                ) orelse return;
                const bytes: [*]align(1) const u8 = @ptrCast(raw);
                instance.editor.hostAtomMessage(.{
                    .source_id = notification.source_id,
                    .body = bytes[@sizeOf(Atom)..total_size],
                });
                return;
            }
            if (event_format != 0 or buffer_size != @sizeOf(f32)) return;
            const parameter_index = parameterIndex(port_index) orelse return;
            const plain: f32 = @as(*align(1) const f32, @ptrCast(raw)).*;
            if (!std.math.isFinite(plain)) return;
            const normalized =
                parameter_set.normalizedFromPlain(parameter_index, plain) orelse
                return;
            if (!std.math.isFinite(normalized)) return;
            const normalized_value =
                std.math.clamp(normalized, 0.0, 1.0);
            instance.values[parameter_index] = normalized_value;
            const id = parameter_set.id(parameter_index) orelse return;
            instance.editor.hostParameterChanged(id, normalized_value);
        }

        fn extensionData(
            raw_uri: ?[*:0]const u8,
        ) callconv(.c) ?*const anyopaque {
            const uri = raw_uri orelse return null;
            if (cStringEquals(uri, idle_interface_uri))
                return &idle_interface;
            if (cStringEquals(uri, resize_uri))
                return &resize_interface;
            if (cStringEquals(uri, show_interface_uri))
                return &show_interface;
            if (cStringEquals(uri, options_interface_uri))
                return &options_interface;
            if (comptime has_programs) {
                if (cStringEquals(uri, programs_ui_interface_uri))
                    return &programs_ui_interface;
            }
            return null;
        }

        fn getOptions(
            handle: Handle,
            raw_options: ?[*]align(1) OptionsOption,
        ) callconv(.c) OptionsStatus {
            const instance = instanceFromHandle(handle) orelse
                return options_status_unknown;
            const unaligned_options = raw_options orelse
                return options_status_unknown;
            if (@intFromPtr(unaligned_options) % @alignOf(OptionsOption) != 0)
                return options_status_unknown;
            const options: [*]OptionsOption =
                @alignCast(unaligned_options);
            var status = options_status_success;
            var terminated = false;
            for (0..256) |index| {
                const option = options[index];
                if (option.key == 0 and option.value == null) {
                    terminated = true;
                    break;
                }
                if (option.context != 0) {
                    status |= options_status_bad_subject;
                    continue;
                }
                if (option.size != 0 or option.type != 0 or
                    option.value != null)
                {
                    status |= options_status_bad_value;
                    continue;
                }
                if ((instance.scale_key == 0 or
                    option.key != instance.scale_key) and
                    (instance.update_rate_key == 0 or
                        option.key != instance.update_rate_key) and
                    (instance.window_title_key == 0 or
                        option.key != instance.window_title_key) and
                    (instance.background_color_key == 0 or
                        option.key != instance.background_color_key) and
                    (instance.foreground_color_key == 0 or
                        option.key != instance.foreground_color_key))
                {
                    status |= options_status_bad_key;
                    continue;
                }
            }
            if (!terminated) status |= options_status_unknown;
            if (status != options_status_success) return status;
            for (0..256) |index| {
                const option = &options[index];
                if (option.key == 0 and option.value == null) break;
                if (instance.window_title_key != 0 and
                    option.key == instance.window_title_key)
                {
                    option.size = @intCast(instance.window_title_len + 1);
                    option.type = instance.atom_string_type;
                    option.value = &instance.window_title;
                } else if (instance.background_color_key != 0 and
                    option.key == instance.background_color_key)
                {
                    option.size = @sizeOf(i32);
                    option.type = instance.atom_int_type;
                    option.value = &instance.background_rgba32;
                } else if (instance.foreground_color_key != 0 and
                    option.key == instance.foreground_color_key)
                {
                    option.size = @sizeOf(i32);
                    option.type = instance.atom_int_type;
                    option.value = &instance.foreground_rgba32;
                } else {
                    option.size = @sizeOf(f32);
                    option.type = instance.atom_float_type;
                    option.value = if (option.key == instance.scale_key)
                        &instance.scale
                    else
                        &instance.update_rate_hz;
                }
            }
            return options_status_success;
        }

        fn setOptions(
            handle: Handle,
            raw_options: ?[*]align(1) const OptionsOption,
        ) callconv(.c) OptionsStatus {
            const instance = instanceFromHandle(handle) orelse
                return options_status_unknown;
            const unaligned_options = raw_options orelse
                return options_status_unknown;
            if (@intFromPtr(unaligned_options) % @alignOf(OptionsOption) != 0)
                return options_status_unknown;
            const options: [*]const OptionsOption =
                @alignCast(unaligned_options);
            var scale: ?f32 = null;
            var update_rate_hz: ?f32 = null;
            var window_title: ?[]const u8 = null;
            var background_rgba32: ?u32 = null;
            var foreground_rgba32: ?u32 = null;
            var status = options_status_success;
            var terminated = false;
            for (0..256) |index| {
                const option = options[index];
                if (option.key == 0 and option.value == null) {
                    terminated = true;
                    break;
                }
                if (option.context != 0) {
                    status |= options_status_bad_subject;
                    continue;
                }
                if (option.key == instance.window_title_key) {
                    if (window_title != null) {
                        status |= options_status_bad_value;
                        continue;
                    }
                    window_title = readWindowTitleOption(
                        option,
                        instance.atom_string_type,
                    ) catch {
                        status |= options_status_bad_value;
                        continue;
                    };
                    continue;
                }
                const color_destination: ?*?u32 =
                    if (instance.background_color_key != 0 and
                    option.key == instance.background_color_key)
                        &background_rgba32
                    else if (instance.foreground_color_key != 0 and
                    option.key == instance.foreground_color_key)
                        &foreground_rgba32
                    else
                        null;
                if (color_destination) |destination| {
                    if (destination.* != null or
                        option.size != @sizeOf(i32) or
                        option.type != instance.atom_int_type)
                    {
                        status |= options_status_bad_value;
                        continue;
                    }
                    const raw = option.value orelse {
                        status |= options_status_bad_value;
                        continue;
                    };
                    destination.* = @bitCast(
                        @as(*align(1) const i32, @ptrCast(raw)).*,
                    );
                    continue;
                }
                const destination =
                    if (instance.scale_key != 0 and
                    option.key == instance.scale_key)
                        &scale
                    else if (instance.update_rate_key != 0 and
                    option.key == instance.update_rate_key)
                        &update_rate_hz
                    else {
                        status |= options_status_bad_key;
                        continue;
                    };
                if (destination.* != null or
                    option.size != @sizeOf(f32) or
                    option.type != instance.atom_float_type)
                {
                    status |= options_status_bad_value;
                    continue;
                }
                const raw = option.value orelse {
                    status |= options_status_bad_value;
                    continue;
                };
                const option_value =
                    @as(*align(1) const f32, @ptrCast(raw)).*;
                if (!std.math.isFinite(option_value) or
                    option_value <= 0.0)
                {
                    status |= options_status_bad_value;
                    continue;
                }
                destination.* = option_value;
            }
            if (!terminated) status |= options_status_unknown;
            if (status != options_status_success) return status;
            if (scale) |next_scale| {
                instance.editor.setScale(.{
                    .x = next_scale,
                    .y = next_scale,
                }) catch return options_status_unknown;
            }
            if (update_rate_hz) |next_rate| {
                if (@hasDecl(Backend, "updateRate"))
                    Backend.updateRate(instance.editor.adapter, next_rate);
                instance.update_rate_hz = next_rate;
            }
            if (window_title) |title| {
                @memset(&instance.window_title, 0);
                @memcpy(instance.window_title[0..title.len], title);
                instance.window_title_len = title.len;
                if (@hasDecl(Backend, "windowTitle"))
                    Backend.windowTitle(
                        instance.editor.adapter,
                        instance.window_title[0..title.len],
                    );
            }
            if (background_rgba32) |color| {
                if (@hasDecl(Backend, "backgroundColor"))
                    Backend.backgroundColor(instance.editor.adapter, color);
                instance.background_rgba32 = color;
            }
            if (foreground_rgba32) |color| {
                if (@hasDecl(Backend, "foregroundColor"))
                    Backend.foregroundColor(instance.editor.adapter, color);
                instance.foreground_rgba32 = color;
            }
            if (scale) |next_scale| instance.scale = next_scale;
            return options_status_success;
        }

        fn selectProgram(
            handle: Handle,
            bank: u32,
            program: u32,
        ) callconv(.c) void {
            const instance = instanceFromHandle(handle) orelse return;
            if (bank > std.math.maxInt(i32)) return;
            const list = Spec.unit_config.program_lists;
            for (list) |program_list| {
                if (program_list.id != @as(i32, @intCast(bank)))
                    continue;
                const program_index: usize = @intCast(program);
                if (program_index >= program_list.programs.len) return;
                const item = program_list.programs[program_index];
                for (item.parameters) |parameter| {
                    const index = parameter_set.indexOfId(
                        parameter.parameter_id,
                    ) orelse continue;
                    instance.values[index] = parameter.normalized;
                    instance.editor.hostParameterChanged(
                        parameter.parameter_id,
                        parameter.normalized,
                    );
                }
                return;
            }
        }

        fn idle(handle: Handle) callconv(.c) c_int {
            const instance = instanceFromHandle(handle) orelse return 1;
            if (@hasDecl(Backend, "idle"))
                return @intFromBool(!Backend.idle(instance.editor.adapter));
            return 0;
        }

        fn hostResize(
            handle: Handle,
            width: c_int,
            height: c_int,
        ) callconv(.c) c_int {
            const instance = instanceFromHandle(handle) orelse return 1;
            const size = sizeFromHost(width, height) orelse return 1;
            instance.editor.hostResize(size) catch return 1;
            return 0;
        }

        fn show(handle: Handle) callconv(.c) c_int {
            const instance = instanceFromHandle(handle) orelse return 1;
            if (@hasDecl(Backend, "show"))
                Backend.show(instance.editor.adapter) catch return 1;
            return 0;
        }

        fn hide(handle: Handle) callconv(.c) c_int {
            const instance = instanceFromHandle(handle) orelse return 1;
            if (@hasDecl(Backend, "hide"))
                Backend.hide(instance.editor.adapter) catch return 1;
            return 0;
        }

        fn beginEdit(raw: *anyopaque, id: u32) gui.Error!void {
            const instance = instanceFromRaw(raw) orelse
                return error.Rejected;
            const index = parameter_set.indexOfId(id) orelse
                return error.InvalidParameter;
            if (instance.touch) |touch| {
                const port = CoreAdapter.controlPort(index) orelse
                    return error.InvalidParameter;
                if (touch.touch(
                    touch.handle,
                    @intCast(port),
                    true,
                ) != 0) return error.Rejected;
            }
        }

        fn performEdit(
            raw: *anyopaque,
            id: u32,
            normalized: f64,
        ) gui.Error!void {
            const instance = instanceFromRaw(raw) orelse
                return error.Rejected;
            const index = parameter_set.indexOfId(id) orelse
                return error.InvalidParameter;
            if (!std.math.isFinite(normalized) or
                normalized < 0.0 or normalized > 1.0)
                return error.Rejected;
            const plain = parameter_set.plainFromNormalized(
                index,
                normalized,
            ) orelse return error.InvalidParameter;
            if (!std.math.isFinite(plain) or
                plain < -std.math.floatMax(f32) or
                plain > std.math.floatMax(f32))
                return error.Rejected;
            const plain_value: f32 = @floatCast(plain);
            const port = CoreAdapter.controlPort(index) orelse
                return error.InvalidParameter;
            instance.write_function(
                instance.controller,
                @intCast(port),
                @sizeOf(f32),
                0,
                &plain_value,
            );
            instance.values[index] = normalized;
        }

        fn endEdit(raw: *anyopaque, id: u32) void {
            const instance = instanceFromRaw(raw) orelse return;
            const index = parameter_set.indexOfId(id) orelse return;
            const touch = instance.touch orelse return;
            const port = CoreAdapter.controlPort(index) orelse return;
            _ = touch.touch(touch.handle, @intCast(port), false);
        }

        fn value(raw: *anyopaque, id: u32) ?f64 {
            const instance = instanceFromRaw(raw) orelse return null;
            const index = parameter_set.indexOfId(id) orelse return null;
            return instance.values[index];
        }

        fn metadata(_: *anyopaque, id: u32) ?gui.ParameterMetadata {
            const index = parameter_set.indexOfId(id) orelse return null;
            const steps = parameter_set.stepCount(index) orelse return null;
            return .{
                .id = id,
                .name = parameter_set.name(index) orelse return null,
                .short_name = parameter_set.shortName(index) orelse
                    return null,
                .units = parameter_set.units(index) orelse return null,
                .minimum_plain = parameter_set.plainMinimum(index) orelse
                    return null,
                .maximum_plain = parameter_set.plainMaximum(index) orelse
                    return null,
                .default_normalized = parameter_set.defaultNormalized(index) orelse return null,
                .step_count = steps,
                .kind = if (parameter_set.isList(index) orelse false)
                    .enumeration
                else if (steps == 1)
                    .boolean
                else if (steps > 1)
                    .integer
                else
                    .float,
            };
        }

        fn format(
            _: *anyopaque,
            id: u32,
            normalized: f64,
            buffer: []u8,
        ) gui.Error!usize {
            const text = parameter_set.formatPlainById(
                id,
                normalized,
                buffer,
            ) catch return error.Rejected;
            return text.len;
        }

        fn parse(
            _: *anyopaque,
            id: u32,
            text: []const u8,
        ) gui.Error!f64 {
            return parameter_set.parsePlainById(id, text) catch
                return error.Rejected;
        }

        fn requestResize(raw: *anyopaque, requested: gui.Size) gui.Error!gui.Size {
            const instance = instanceFromRaw(raw) orelse
                return error.Rejected;
            const resize = instance.resize orelse return error.Rejected;
            if (requested.width > std.math.maxInt(c_int) or
                requested.height > std.math.maxInt(c_int))
                return error.Rejected;
            if (resize.ui_resize(
                resize.handle,
                @intCast(requested.width),
                @intCast(requested.height),
            ) != 0) return error.Rejected;
            return requested;
        }

        fn requestRepaint(_: *anyopaque) void {}

        fn openContextMenu(
            _: *anyopaque,
            _: u32,
            _: i32,
            _: i32,
        ) gui.Error!void {
            return error.Rejected;
        }

        fn requestHostValue(
            raw: *anyopaque,
            request: gui.HostValueRequest,
        ) gui.HostValueRequestStatus {
            const instance = instanceFromRaw(raw) orelse return .unsupported;
            const host_request = instance.request_value orelse
                return .unsupported;
            const map = instance.urid_map orelse return .unsupported;
            const key = map.map(map.handle, request.key_uri.ptr);
            if (key == 0) return .unknown;
            const value_type = if (request.value_type_uri) |uri| blk: {
                const mapped = map.map(map.handle, uri.ptr);
                if (mapped == 0) return .unsupported;
                break :blk mapped;
            } else 0;
            return switch (host_request.request(
                host_request.handle,
                key,
                value_type,
                null,
            )) {
                request_value_success => .accepted,
                request_value_busy => .busy,
                request_value_unknown => .unknown,
                request_value_unsupported => .unsupported,
                else => .unsupported,
            };
        }

        fn subscribeHostPeak(
            raw: *anyopaque,
            subscription: gui.HostPeakSubscription,
        ) gui.HostSubscriptionStatus {
            const instance = instanceFromRaw(raw) orelse return .unsupported;
            const port_map = instance.port_map orelse return .unsupported;
            if (instance.peak_protocol == 0) return .unsupported;
            const port_index = port_map.port_index(
                port_map.handle,
                subscription.port_symbol.ptr,
            );
            if (port_index == invalid_port_index) return .rejected;
            if (peakSubscription(instance, port_index)) |existing| {
                return if (existing.source_id == subscription.source_id and
                    existing.delivery == subscription.delivery)
                    .accepted
                else
                    .rejected;
            }
            for (instance.peak_subscriptions[0..instance.peak_subscription_count]) |existing| {
                if (existing.source_id == subscription.source_id)
                    return .rejected;
            }
            if (instance.peak_subscription_count >=
                instance.peak_subscriptions.len)
                return .full;
            if (subscription.delivery == .dynamic) {
                const host = instance.port_subscribe orelse
                    return .unsupported;
                if (host.subscribe(
                    host.handle,
                    port_index,
                    instance.peak_protocol,
                    null,
                ) != 0) return .rejected;
            }
            instance.peak_subscriptions[
                instance.peak_subscription_count
            ] = .{
                .port_index = port_index,
                .source_id = subscription.source_id,
                .delivery = subscription.delivery,
            };
            instance.peak_subscription_count += 1;
            return .accepted;
        }

        fn unsubscribeHostPeak(
            raw: *anyopaque,
            subscription: gui.HostPeakSubscription,
        ) gui.HostSubscriptionStatus {
            const instance = instanceFromRaw(raw) orelse return .unsupported;
            const port_map = instance.port_map orelse return .unsupported;
            if (instance.peak_protocol == 0) return .unsupported;
            const port_index = port_map.port_index(
                port_map.handle,
                subscription.port_symbol.ptr,
            );
            if (port_index == invalid_port_index) return .rejected;
            const index = peakSubscriptionIndex(
                instance,
                port_index,
            ) orelse return .rejected;
            if (instance.peak_subscriptions[index].source_id !=
                subscription.source_id or
                instance.peak_subscriptions[index].delivery !=
                    subscription.delivery)
                return .rejected;
            if (subscription.delivery == .dynamic) {
                const host = instance.port_subscribe orelse
                    return .unsupported;
                if (host.unsubscribe(
                    host.handle,
                    port_index,
                    instance.peak_protocol,
                    null,
                ) != 0) return .rejected;
            }
            removePeakSubscription(instance, index);
            return .accepted;
        }

        fn registerHostAtomNotification(
            raw: *anyopaque,
            notification: gui.HostAtomNotification,
        ) gui.HostSubscriptionStatus {
            const instance = instanceFromRaw(raw) orelse return .unsupported;
            const port_map = instance.port_map orelse return .unsupported;
            const map = instance.urid_map orelse return .unsupported;
            if (instance.atom_event_protocol == 0) return .unsupported;
            const port_index = port_map.port_index(
                port_map.handle,
                notification.port_symbol.ptr,
            );
            if (port_index == invalid_port_index) return .rejected;
            const atom_type = map.map(
                map.handle,
                notification.atom_type_uri.ptr,
            );
            if (atom_type == 0) return .rejected;
            if (atomNotification(instance, port_index, atom_type)) |existing| {
                return if (existing.source_id == notification.source_id)
                    .accepted
                else
                    .rejected;
            }
            for (instance.atom_notifications[0..instance.atom_notification_count]) |existing| {
                if (existing.source_id == notification.source_id)
                    return .rejected;
            }
            if (instance.atom_notification_count >=
                instance.atom_notifications.len)
                return .full;
            instance.atom_notifications[
                instance.atom_notification_count
            ] = .{
                .port_index = port_index,
                .atom_type = atom_type,
                .source_id = notification.source_id,
            };
            instance.atom_notification_count += 1;
            return .accepted;
        }

        fn unregisterHostAtomNotification(
            raw: *anyopaque,
            notification: gui.HostAtomNotification,
        ) gui.HostSubscriptionStatus {
            const instance = instanceFromRaw(raw) orelse return .unsupported;
            const port_map = instance.port_map orelse return .unsupported;
            const map = instance.urid_map orelse return .unsupported;
            if (instance.atom_event_protocol == 0) return .unsupported;
            const port_index = port_map.port_index(
                port_map.handle,
                notification.port_symbol.ptr,
            );
            if (port_index == invalid_port_index) return .rejected;
            const atom_type = map.map(
                map.handle,
                notification.atom_type_uri.ptr,
            );
            if (atom_type == 0) return .rejected;
            const index = atomNotificationIndex(
                instance,
                port_index,
                atom_type,
            ) orelse return .rejected;
            if (instance.atom_notifications[index].source_id !=
                notification.source_id)
                return .rejected;
            removeAtomNotification(instance, index);
            return .accepted;
        }

        fn sendPluginAtomMessage(
            raw: *anyopaque,
            message: gui.PluginAtomMessage,
        ) gui.PluginMessageStatus {
            const instance = instanceFromRaw(raw) orelse return .unsupported;
            const port_map = instance.port_map orelse return .unsupported;
            const map = instance.urid_map orelse return .unsupported;
            if (instance.atom_event_protocol == 0) return .unsupported;
            if (instance.atom_write_active) return .rejected;
            if (message.body.len > gui.maximum_plugin_atom_body_bytes)
                return .rejected;
            const port_index = port_map.port_index(
                port_map.handle,
                message.port_symbol.ptr,
            );
            if (port_index == invalid_port_index) return .rejected;
            const atom_type = map.map(
                map.handle,
                message.atom_type_uri.ptr,
            );
            if (atom_type == 0) return .rejected;
            const total_size = std.math.add(
                usize,
                @sizeOf(Atom),
                message.body.len,
            ) catch return .rejected;
            const atom: *Atom = @ptrCast(&instance.atom_write_buffer);
            atom.* = .{
                .size = @intCast(message.body.len),
                .type = atom_type,
            };
            @memcpy(
                instance.atom_write_buffer[@sizeOf(Atom)..total_size],
                message.body,
            );
            instance.atom_write_active = true;
            defer instance.atom_write_active = false;
            defer @memset(instance.atom_write_buffer[0..total_size], 0);
            instance.write_function(
                instance.controller,
                port_index,
                @intCast(total_size),
                instance.atom_event_protocol,
                &instance.atom_write_buffer,
            );
            return .accepted;
        }

        const context_vtable = gui.Context.VTable{
            .begin_edit = beginEdit,
            .perform_edit = performEdit,
            .end_edit = endEdit,
            .value = value,
            .metadata = metadata,
            .format = format,
            .parse = parse,
            .request_resize = requestResize,
            .request_repaint = requestRepaint,
            .open_context_menu = openContextMenu,
            .request_host_value = requestHostValue,
            .subscribe_host_peak = subscribeHostPeak,
            .unsubscribe_host_peak = unsubscribeHostPeak,
            .register_host_atom_notification = registerHostAtomNotification,
            .unregister_host_atom_notification = unregisterHostAtomNotification,
            .send_plugin_atom_message = sendPluginAtomMessage,
        };

        fn peakSubscriptionIndex(
            instance: *const Instance,
            port_index: u32,
        ) ?usize {
            for (
                instance.peak_subscriptions[0..instance.peak_subscription_count],
                0..,
            ) |subscription, index| {
                if (subscription.port_index == port_index) return index;
            }
            return null;
        }

        fn peakSubscription(
            instance: *const Instance,
            port_index: u32,
        ) ?PeakSubscription {
            const index = peakSubscriptionIndex(instance, port_index) orelse
                return null;
            return instance.peak_subscriptions[index];
        }

        fn removePeakSubscription(
            instance: *Instance,
            index: usize,
        ) void {
            const last = instance.peak_subscription_count - 1;
            if (index < last) {
                std.mem.copyForwards(
                    PeakSubscription,
                    instance.peak_subscriptions[index..last],
                    instance.peak_subscriptions[index + 1 .. last + 1],
                );
            }
            instance.peak_subscriptions[last] = .{};
            instance.peak_subscription_count = last;
        }

        fn releaseHostNotifications(instance: *Instance) void {
            if (instance.port_subscribe) |host| {
                if (instance.peak_protocol != 0) {
                    for (instance.peak_subscriptions[0..instance.peak_subscription_count]) |subscription| {
                        if (subscription.delivery != .dynamic) continue;
                        _ = host.unsubscribe(
                            host.handle,
                            subscription.port_index,
                            instance.peak_protocol,
                            null,
                        );
                    }
                }
            }
            @memset(&instance.peak_subscriptions, .{});
            instance.peak_subscription_count = 0;
            @memset(&instance.atom_notifications, .{});
            instance.atom_notification_count = 0;
        }

        fn atomNotificationIndex(
            instance: *const Instance,
            port_index: u32,
            atom_type: Urid,
        ) ?usize {
            for (
                instance.atom_notifications[0..instance.atom_notification_count],
                0..,
            ) |notification, index| {
                if (notification.port_index == port_index and
                    notification.atom_type == atom_type)
                    return index;
            }
            return null;
        }

        fn atomNotification(
            instance: *const Instance,
            port_index: u32,
            atom_type: Urid,
        ) ?AtomNotification {
            const index = atomNotificationIndex(
                instance,
                port_index,
                atom_type,
            ) orelse return null;
            return instance.atom_notifications[index];
        }

        fn removeAtomNotification(
            instance: *Instance,
            index: usize,
        ) void {
            const last = instance.atom_notification_count - 1;
            if (index < last) {
                std.mem.copyForwards(
                    AtomNotification,
                    instance.atom_notifications[index..last],
                    instance.atom_notifications[index + 1 .. last + 1],
                );
            }
            instance.atom_notifications[last] = .{};
            instance.atom_notification_count = last;
        }

        fn parameterIndex(port_index: u32) ?usize {
            if (port_index < CoreAdapter.control_input_port_start)
                return null;
            const index =
                @as(usize, port_index) - CoreAdapter.control_input_port_start;
            return if (index < parameter_count) index else null;
        }

        fn initialValues() [parameter_count]f64 {
            var result: [parameter_count]f64 = undefined;
            for (&result, 0..) |*entry, index|
                entry.* = parameter_set.defaultNormalized(index) orelse 0.0;
            return result;
        }
    };
}

fn findFeature(
    features: ?[*:null]const ?*const Feature,
    wanted_uri: []const u8,
) ?*const Feature {
    if (!featureListValid(features)) return null;
    const list = features orelse return null;
    for (0..256) |index| {
        const feature = list[index] orelse return null;
        if (@intFromPtr(feature) % @alignOf(Feature) != 0)
            continue;
        const uri = feature.URI orelse continue;
        if (cStringEquals(uri, wanted_uri))
            return feature;
    }
    return null;
}

fn featureUriCount(
    features: ?[*:null]const ?*const Feature,
    wanted_uri: []const u8,
) usize {
    if (!featureListValid(features)) return 0;
    const list = features orelse return 0;
    var count: usize = 0;
    for (0..256) |index| {
        const feature = list[index] orelse return count;
        if (@intFromPtr(feature) % @alignOf(Feature) != 0)
            continue;
        const uri = feature.URI orelse continue;
        if (cStringEquals(uri, wanted_uri))
            count += 1;
    }
    return count;
}

fn featureListValid(
    features: ?[*:null]const ?*const Feature,
) bool {
    const list = features orelse return true;
    if (@intFromPtr(list) % @alignOf(?*const Feature) != 0)
        return false;
    for (0..256) |index| {
        const feature = list[index] orelse return true;
        if (@intFromPtr(feature) % @alignOf(Feature) != 0)
            return false;
        if (feature.URI == null) return false;
    }
    return false;
}

fn cStringEquals(value: [*:0]const u8, expected: []const u8) bool {
    for (expected, 0..) |byte, index| {
        const actual = value[index];
        if (actual == 0 or actual != byte) return false;
    }
    return value[expected.len] == 0;
}

fn featureData(
    comptime T: type,
    features: ?[*:null]const ?*const Feature,
    wanted_uri: []const u8,
) ?*const T {
    const feature = findFeature(features, wanted_uri) orelse return null;
    const data = feature.data orelse return null;
    if (@intFromPtr(data) % @alignOf(T) != 0) return null;
    return @ptrCast(@alignCast(data));
}

fn checkedResize(
    features: ?[*:null]const ?*const Feature,
) ?CheckedResize {
    if (featureUriCount(features, resize_uri) != 1) return null;
    const raw = featureData(Resize, features, resize_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .ui_resize = raw.ui_resize orelse return null,
    };
}

fn checkedTouch(
    features: ?[*:null]const ?*const Feature,
) ?CheckedTouch {
    if (featureUriCount(features, touch_uri) != 1) return null;
    const raw = featureData(Touch, features, touch_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .touch = raw.touch orelse return null,
    };
}

fn checkedUridMap(
    features: ?[*:null]const ?*const Feature,
) ?CheckedUridMap {
    if (featureUriCount(features, urid_map_uri) != 1) return null;
    const raw = featureData(UridMap, features, urid_map_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .map = raw.map orelse return null,
    };
}

fn checkedRequestValue(
    features: ?[*:null]const ?*const Feature,
) ?CheckedRequestValue {
    if (featureUriCount(features, request_value_uri) != 1) return null;
    const raw = featureData(RequestValue, features, request_value_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .request = raw.request orelse return null,
    };
}

fn checkedPortMap(
    features: ?[*:null]const ?*const Feature,
) ?CheckedPortMap {
    if (featureUriCount(features, port_map_uri) != 1) return null;
    const raw = featureData(PortMap, features, port_map_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .port_index = raw.port_index orelse return null,
    };
}

fn checkedPortSubscribe(
    features: ?[*:null]const ?*const Feature,
) ?CheckedPortSubscribe {
    if (featureUriCount(features, port_subscribe_uri) != 1) return null;
    const raw = featureData(PortSubscribe, features, port_subscribe_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .subscribe = raw.subscribe orelse return null,
        .unsubscribe = raw.unsubscribe orelse return null,
    };
}

fn sizeFromHost(width: c_int, height: c_int) ?gui.Size {
    if (width <= 0 or height <= 0) return null;
    return .{
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

const UiOptions = struct {
    scale_key: Urid = 0,
    update_rate_key: Urid = 0,
    window_title_key: Urid = 0,
    background_color_key: Urid = 0,
    foreground_color_key: Urid = 0,
    atom_float_type: Urid = 0,
    atom_string_type: Urid = 0,
    atom_int_type: Urid = 0,
    scale: ?f32 = null,
    update_rate_hz: ?f32 = null,
    window_title: ?[]const u8 = null,
    background_rgba32: ?u32 = null,
    foreground_rgba32: ?u32 = null,
};

fn readUiOptions(
    features: ?[*:null]const ?*const Feature,
) !UiOptions {
    if (featureUriCount(features, urid_map_uri) > 1 or
        featureUriCount(features, options_options_uri) > 1)
        return error.InvalidOptions;
    const map = featureData(UridMap, features, urid_map_uri) orelse {
        if (findFeature(features, options_options_uri) != null)
            return error.InvalidOptions;
        return .{};
    };
    const map_uri = map.map orelse return error.InvalidOptions;
    const scale_key = map_uri(map.handle, scale_factor_uri);
    const update_rate_key = map_uri(map.handle, update_rate_uri);
    const window_title_key = map_uri(map.handle, window_title_uri);
    const background_color_key = map_uri(map.handle, background_color_uri);
    const foreground_color_key = map_uri(map.handle, foreground_color_uri);
    const float_type = map_uri(map.handle, atom_float_uri);
    const string_type = map_uri(map.handle, atom_string_uri);
    const int_type = map_uri(map.handle, atom_int_uri);
    const mapped_urids = [_]Urid{
        scale_key,
        update_rate_key,
        window_title_key,
        background_color_key,
        foreground_color_key,
        float_type,
        string_type,
        int_type,
    };
    for (mapped_urids, 0..) |urid, index| {
        if (urid == 0) return error.InvalidOptions;
        for (mapped_urids[index + 1 ..]) |other| {
            if (urid == other) return error.InvalidOptions;
        }
    }
    var result = UiOptions{
        .scale_key = scale_key,
        .update_rate_key = update_rate_key,
        .window_title_key = window_title_key,
        .background_color_key = background_color_key,
        .foreground_color_key = foreground_color_key,
        .atom_float_type = float_type,
        .atom_string_type = string_type,
        .atom_int_type = int_type,
    };
    const options_feature =
        findFeature(features, options_options_uri) orelse return result;
    const options_data = options_feature.data orelse
        return error.InvalidOptions;
    if (@intFromPtr(options_data) % @alignOf(OptionsOption) != 0)
        return error.InvalidOptions;
    const options: [*]const OptionsOption =
        @ptrCast(@alignCast(options_data));
    for (0..256) |index| {
        const option = options[index];
        if (option.key == 0 and option.value == null)
            return result;
        if (option.key == 0)
            return error.InvalidOptions;
        if (option.context != 0 or
            (option.key != scale_key and option.key != update_rate_key and
                option.key != window_title_key and
                option.key != background_color_key and
                option.key != foreground_color_key))
            continue;
        if (option.key == window_title_key) {
            if (result.window_title != null)
                return error.InvalidOptions;
            result.window_title = try readWindowTitleOption(
                option,
                string_type,
            );
            continue;
        }
        const color_destination: ?*?u32 =
            if (option.key == background_color_key)
                &result.background_rgba32
            else if (option.key == foreground_color_key)
                &result.foreground_rgba32
            else
                null;
        if (color_destination) |destination| {
            if (destination.* != null or option.size != @sizeOf(i32) or
                option.type != int_type)
                return error.InvalidOptions;
            const raw = option.value orelse return error.InvalidOptions;
            destination.* = @bitCast(
                @as(*align(1) const i32, @ptrCast(raw)).*,
            );
            continue;
        }
        const destination = if (option.key == scale_key)
            &result.scale
        else
            &result.update_rate_hz;
        if (destination.* != null or option.size != @sizeOf(f32) or
            option.type != float_type)
            return error.InvalidOptions;
        const raw = option.value orelse return error.InvalidOptions;
        const value = @as(*align(1) const f32, @ptrCast(raw)).*;
        if (!std.math.isFinite(value) or value <= 0.0)
            return error.InvalidOptions;
        destination.* = value;
    }
    return error.InvalidOptions;
}

fn readWindowTitleOption(
    option: OptionsOption,
    atom_string_type: Urid,
) ![]const u8 {
    const size: usize = option.size;
    if (option.type != atom_string_type or size == 0 or
        size > maximum_window_title_bytes + 1)
        return error.InvalidOptions;
    const raw = option.value orelse return error.InvalidOptions;
    const bytes: [*]const u8 = @ptrCast(raw);
    const value = bytes[0..size];
    if (value[value.len - 1] != 0)
        return error.InvalidOptions;
    const title = value[0 .. value.len - 1];
    if (std.mem.indexOfScalar(u8, title, 0) != null or
        !std.unicode.utf8ValidateSlice(title))
        return error.InvalidOptions;
    return title;
}

test "LV2 UI feature lookup is bounded and validates resize dimensions" {
    const Callbacks = struct {
        fn resize(
            _: Handle,
            _: c_int,
            _: c_int,
        ) callconv(.c) c_int {
            return 0;
        }

        fn touch(
            _: Handle,
            _: u32,
            _: bool,
        ) callconv(.c) c_int {
            return 0;
        }

        fn requestValue(
            _: Handle,
            _: Urid,
            _: Urid,
            _: ?[*:null]const ?*const Feature,
        ) callconv(.c) RequestValueStatus {
            return request_value_success;
        }

        fn portIndex(
            _: Handle,
            _: [*:0]const u8,
        ) callconv(.c) u32 {
            return 0;
        }

        fn subscribe(
            _: Handle,
            _: u32,
            _: Urid,
            _: ?[*:null]const ?*const Feature,
        ) callconv(.c) u32 {
            return 0;
        }
    };
    const parent = Feature{
        .URI = parent_uri,
        .data = null,
    };
    const list = [_:null]?*const Feature{&parent};
    try std.testing.expect(findFeature(&list, parent_uri) == &parent);
    try std.testing.expectEqual(
        @as(usize, 1),
        featureUriCount(&list, parent_uri),
    );
    try std.testing.expect(findFeature(&list, resize_uri) == null);
    var records = [_:null]?*const Feature{
        null,
        &parent,
    };
    const misaligned_address: usize = 1;
    @memcpy(
        std.mem.asBytes(&records[0]),
        std.mem.asBytes(&misaligned_address),
    );
    try std.testing.expect(!featureListValid(records[0..].ptr));
    try std.testing.expect(
        findFeature(records[0..].ptr, parent_uri) == null,
    );
    const missing_uri = Feature{ .URI = null, .data = null };
    const missing_uri_list = [_:null]?*const Feature{
        &missing_uri,
        &parent,
    };
    try std.testing.expect(!featureListValid(&missing_uri_list));
    try std.testing.expect(
        findFeature(&missing_uri_list, parent_uri) == null,
    );
    var list_storage: [@sizeOf(?*const Feature) * 2 + 1]u8 align(@alignOf(?*const Feature)) = @splat(0);
    var misaligned_list: ?[*:null]const ?*const Feature = null;
    const list_address = @intFromPtr(&list_storage[1]);
    @memcpy(
        std.mem.asBytes(&misaligned_list),
        std.mem.asBytes(&list_address),
    );
    try std.testing.expect(
        findFeature(misaligned_list, parent_uri) == null,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        featureUriCount(misaligned_list, parent_uri),
    );
    var unterminated: [256]?*const Feature = @splat(&parent);
    const unterminated_list: ?[*:null]const ?*const Feature =
        @ptrCast(&unterminated);
    try std.testing.expect(!featureListValid(unterminated_list));
    try std.testing.expect(
        findFeature(unterminated_list, parent_uri) == null,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        featureUriCount(unterminated_list, parent_uri),
    );
    var storage: [@sizeOf(Resize) + 1]u8 align(@alignOf(Resize)) = undefined;
    const resize = Feature{
        .URI = resize_uri,
        .data = @ptrCast(&storage[1]),
    };
    const malformed = [_:null]?*const Feature{&resize};
    try std.testing.expect(
        featureData(Resize, &malformed, resize_uri) == null,
    );
    var null_resize = Resize{
        .handle = null,
        .ui_resize = null,
    };
    const null_resize_feature = Feature{
        .URI = resize_uri,
        .data = &null_resize,
    };
    const null_resize_features =
        [_:null]?*const Feature{&null_resize_feature};
    try std.testing.expect(
        checkedResize(&null_resize_features) == null,
    );
    var null_touch = Touch{
        .handle = null,
        .touch = null,
    };
    const null_touch_feature = Feature{
        .URI = touch_uri,
        .data = &null_touch,
    };
    const null_touch_features =
        [_:null]?*const Feature{&null_touch_feature};
    try std.testing.expect(
        checkedTouch(&null_touch_features) == null,
    );
    const valid_resize = Resize{
        .handle = null,
        .ui_resize = Callbacks.resize,
    };
    const valid_resize_feature = Feature{
        .URI = resize_uri,
        .data = @constCast(&valid_resize),
    };
    const duplicate_resize_features = [_:null]?*const Feature{
        &valid_resize_feature,
        &valid_resize_feature,
    };
    try std.testing.expect(
        checkedResize(&duplicate_resize_features) == null,
    );
    const valid_touch = Touch{
        .handle = null,
        .touch = Callbacks.touch,
    };
    const valid_touch_feature = Feature{
        .URI = touch_uri,
        .data = @constCast(&valid_touch),
    };
    const duplicate_touch_features = [_:null]?*const Feature{
        &valid_touch_feature,
        &valid_touch_feature,
    };
    try std.testing.expect(
        checkedTouch(&duplicate_touch_features) == null,
    );
    var null_request_value = RequestValue{
        .handle = null,
        .request = null,
    };
    const null_request_feature = Feature{
        .URI = request_value_uri,
        .data = &null_request_value,
    };
    const null_request_features =
        [_:null]?*const Feature{&null_request_feature};
    try std.testing.expect(
        checkedRequestValue(&null_request_features) == null,
    );
    const valid_request_value = RequestValue{
        .handle = null,
        .request = Callbacks.requestValue,
    };
    const valid_request_feature = Feature{
        .URI = request_value_uri,
        .data = @constCast(&valid_request_value),
    };
    const valid_request_features =
        [_:null]?*const Feature{&valid_request_feature};
    try std.testing.expect(
        checkedRequestValue(&valid_request_features) != null,
    );
    const duplicate_request_features = [_:null]?*const Feature{
        &valid_request_feature,
        &valid_request_feature,
    };
    try std.testing.expect(
        checkedRequestValue(&duplicate_request_features) == null,
    );
    var null_port_map = PortMap{
        .handle = null,
        .port_index = null,
    };
    const null_port_map_feature = Feature{
        .URI = port_map_uri,
        .data = &null_port_map,
    };
    const null_port_map_features =
        [_:null]?*const Feature{&null_port_map_feature};
    try std.testing.expect(
        checkedPortMap(&null_port_map_features) == null,
    );
    const valid_port_map = PortMap{
        .handle = null,
        .port_index = Callbacks.portIndex,
    };
    const valid_port_map_feature = Feature{
        .URI = port_map_uri,
        .data = @constCast(&valid_port_map),
    };
    const valid_port_map_features =
        [_:null]?*const Feature{&valid_port_map_feature};
    try std.testing.expect(
        checkedPortMap(&valid_port_map_features) != null,
    );
    const duplicate_port_map_features = [_:null]?*const Feature{
        &valid_port_map_feature,
        &valid_port_map_feature,
    };
    try std.testing.expect(
        checkedPortMap(&duplicate_port_map_features) == null,
    );
    var null_port_subscribe = PortSubscribe{
        .handle = null,
        .subscribe = null,
        .unsubscribe = Callbacks.subscribe,
    };
    const null_port_subscribe_feature = Feature{
        .URI = port_subscribe_uri,
        .data = &null_port_subscribe,
    };
    const null_port_subscribe_features =
        [_:null]?*const Feature{&null_port_subscribe_feature};
    try std.testing.expect(
        checkedPortSubscribe(&null_port_subscribe_features) == null,
    );
    null_port_subscribe.subscribe = Callbacks.subscribe;
    null_port_subscribe.unsubscribe = null;
    try std.testing.expect(
        checkedPortSubscribe(&null_port_subscribe_features) == null,
    );
    const valid_port_subscribe = PortSubscribe{
        .handle = null,
        .subscribe = Callbacks.subscribe,
        .unsubscribe = Callbacks.subscribe,
    };
    const valid_port_subscribe_feature = Feature{
        .URI = port_subscribe_uri,
        .data = @constCast(&valid_port_subscribe),
    };
    const valid_port_subscribe_features =
        [_:null]?*const Feature{&valid_port_subscribe_feature};
    try std.testing.expect(
        checkedPortSubscribe(&valid_port_subscribe_features) != null,
    );
    const duplicate_port_subscribe_features = [_:null]?*const Feature{
        &valid_port_subscribe_feature,
        &valid_port_subscribe_feature,
    };
    try std.testing.expect(
        checkedPortSubscribe(&duplicate_port_subscribe_features) == null,
    );
    try std.testing.expect(sizeFromHost(640, 480) != null);
    try std.testing.expect(sizeFromHost(0, 480) == null);
    try std.testing.expect(sizeFromHost(640, -1) == null);
}

test "LV2 UI URI comparison stops at the expected boundary" {
    try std.testing.expect(cStringEquals(parent_uri, parent_uri));
    try std.testing.expect(!cStringEquals("http:\x00ignored", parent_uri));
    try std.testing.expect(!cStringEquals(
        "http://lv2plug.in/ns/extensions/ui#parent/hostile-tail",
        parent_uri,
    ));
    try std.testing.expect(cStringEquals("", ""));
}

test "LV2 UI options validate host data transactionally" {
    const Host = struct {
        fn map(
            _: ?*anyopaque,
            uri: [*:0]const u8,
        ) callconv(.c) Urid {
            const value = std.mem.span(uri);
            if (std.mem.eql(u8, value, scale_factor_uri)) return 139;
            if (std.mem.eql(u8, value, update_rate_uri)) return 140;
            if (std.mem.eql(u8, value, window_title_uri)) return 141;
            if (std.mem.eql(u8, value, background_color_uri)) return 142;
            if (std.mem.eql(u8, value, foreground_color_uri)) return 143;
            if (std.mem.eql(u8, value, atom_float_uri)) return 47;
            if (std.mem.eql(u8, value, atom_string_uri)) return 48;
            if (std.mem.eql(u8, value, atom_int_uri)) return 49;
            return 0;
        }
    };
    var urid_map = UridMap{
        .handle = null,
        .map = Host.map,
    };
    const map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const scale: f32 = 2.0;
    const update_rate_hz: f32 = 30.0;
    const window_title = "Host title";
    const background_rgba32: i32 = @bitCast(@as(u32, 0x102030ff));
    const foreground_rgba32: i32 = @bitCast(@as(u32, 0xf0e0d0ff));
    const options = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &scale,
        },
        .{
            .key = 140,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &update_rate_hz,
        },
        .{
            .key = 141,
            .size = window_title.len + 1,
            .type = 48,
            .value = window_title.ptr,
        },
        .{
            .key = 142,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &background_rgba32,
        },
        .{
            .key = 143,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &foreground_rgba32,
        },
        .{},
    };
    var options_feature = Feature{
        .URI = options_options_uri,
        .data = @constCast(&options),
    };
    const features = [_:null]?*const Feature{
        &map_feature,
        &options_feature,
    };
    const parsed = try readUiOptions(&features);
    try std.testing.expectEqual(@as(?f32, 2.0), parsed.scale);
    try std.testing.expectEqual(
        @as(?f32, 30.0),
        parsed.update_rate_hz,
    );
    try std.testing.expectEqualStrings(
        window_title,
        parsed.window_title orelse return error.MissingWindowTitle,
    );
    try std.testing.expectEqual(
        @as(?u32, 0x102030ff),
        parsed.background_rgba32,
    );
    try std.testing.expectEqual(
        @as(?u32, 0xf0e0d0ff),
        parsed.foreground_rgba32,
    );

    const duplicate_map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const duplicate_map_features = [_:null]?*const Feature{
        &map_feature,
        &duplicate_map_feature,
        &options_feature,
    };
    try std.testing.expectError(
        error.InvalidOptions,
        readUiOptions(&duplicate_map_features),
    );
    const duplicate_options_feature = Feature{
        .URI = options_options_uri,
        .data = @constCast(&options),
    };
    const duplicate_option_features = [_:null]?*const Feature{
        &map_feature,
        &options_feature,
        &duplicate_options_feature,
    };
    try std.testing.expectError(
        error.InvalidOptions,
        readUiOptions(&duplicate_option_features),
    );

    urid_map.map = null;
    try std.testing.expectError(
        error.InvalidOptions,
        readUiOptions(&features),
    );
    urid_map.map = Host.map;

    const duplicate_options = [_]OptionsOption{
        options[0],
        options[0],
        .{},
    };
    options_feature.data = @constCast(&duplicate_options);
    try std.testing.expectError(
        error.InvalidOptions,
        readUiOptions(&features),
    );

    const invalid_scale: f32 = 0.0;
    const invalid_options = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &invalid_scale,
        },
        .{},
    };
    options_feature.data = @constCast(&invalid_options);
    try std.testing.expectError(
        error.InvalidOptions,
        readUiOptions(&features),
    );

    var misaligned_storage: [@sizeOf(OptionsOption) + 1]u8 align(@alignOf(OptionsOption)) =
        undefined;
    options_feature.data = @ptrCast(&misaligned_storage[1]);
    try std.testing.expectError(
        error.InvalidOptions,
        readUiOptions(&features),
    );
}

test "LV2 UI adapter bridges lifecycle automation touch idle and resize" {
    const Plugin = struct {
        pub const name = "UI Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: parameters.FloatParam = .{
                .id = 7,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };
        pub const units: @import("units.zig").Config = .{
            .program_lists = &.{.{
                .id = 17,
                .name = "Factory",
                .programs = &.{.{
                    .name = "Forward",
                    .parameters = &.{
                        .{ .parameter_id = 7, .normalized = 0.8 },
                    },
                }},
            }},
        };

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Core = struct {
        pub const parameters = 1;
        pub const control_input_port_start = 2;
        pub const programs_enabled = true;

        pub fn controlPort(index: usize) ?usize {
            return if (index == 0) 2 else null;
        }
    };
    const Backend = struct {
        var create_count: usize = 0;

        const State = struct {
            attached: bool = false,
            parameter: f64 = 0.5,
            size: gui.Size = .{ .width = 320, .height = 200 },
            scale: gui.Scale = .{},
            update_rate_hz: f32 = 0.0,
            window_title: [maximum_window_title_bytes]u8 = @splat(0),
            window_title_len: usize = 0,
            background_rgba32: u32 = 0,
            foreground_rgba32: u32 = 0,
            idle_count: usize = 0,
            peak_count: usize = 0,
            peak: gui.HostPeakMeasurement = .{
                .source_id = 0,
                .period_start = 0,
                .period_size = 1,
                .peak = 0.0,
            },
            atom_count: usize = 0,
            atom_source_id: u32 = 0,
            atom_body: [32]u8 = @splat(0),
            atom_body_len: usize = 0,
        };

        pub fn create(context: gui.Context) gui.Error!gui.Editor {
            create_count += 1;
            const backend_state = std.heap.page_allocator.create(State) catch
                return error.Rejected;
            backend_state.* = .{};
            return .{
                .context = context,
                .adapter = .{
                    .userdata = backend_state,
                    .vtable = &vtable,
                },
                .size = .{ .width = 320, .height = 200 },
                .resize_policy = .{
                    .resizable = .{
                        .minimum = .{ .width = 160, .height = 100 },
                        .maximum = .{ .width = 800, .height = 600 },
                    },
                },
            };
        }

        pub fn widget(adapter: gui.Adapter) ?*anyopaque {
            return adapter.userdata;
        }

        pub fn idle(adapter: gui.Adapter) bool {
            state(adapter.userdata).idle_count += 1;
            return true;
        }

        pub fn updateRate(adapter: gui.Adapter, value: f32) void {
            state(adapter.userdata).update_rate_hz = value;
        }

        pub fn windowTitle(adapter: gui.Adapter, title: []const u8) void {
            const backend = state(adapter.userdata);
            @memset(&backend.window_title, 0);
            @memcpy(backend.window_title[0..title.len], title);
            backend.window_title_len = title.len;
        }

        pub fn backgroundColor(adapter: gui.Adapter, color: u32) void {
            state(adapter.userdata).background_rgba32 = color;
        }

        pub fn foregroundColor(adapter: gui.Adapter, color: u32) void {
            state(adapter.userdata).foreground_rgba32 = color;
        }

        fn state(raw: *anyopaque) *State {
            return @ptrCast(@alignCast(raw));
        }

        fn attach(
            raw: *anyopaque,
            _: gui.NativeParent,
            _: gui.Size,
            _: gui.Scale,
        ) gui.Error!void {
            state(raw).attached = true;
        }

        fn detach(raw: *anyopaque) void {
            state(raw).attached = false;
        }

        fn resize(raw: *anyopaque, new_size: gui.Size) gui.Error!void {
            state(raw).size = new_size;
        }

        fn scale(raw: *anyopaque, value: gui.Scale) gui.Error!void {
            if (value.x == 3.0 or value.y == 3.0)
                return error.Rejected;
            state(raw).scale = value;
        }
        fn focus(_: *anyopaque, _: bool) void {}

        fn parameterChanged(
            raw: *anyopaque,
            _: u32,
            normalized: f64,
        ) void {
            state(raw).parameter = normalized;
        }

        fn hostPeakMeasurement(
            raw: *anyopaque,
            measurement: gui.HostPeakMeasurement,
        ) void {
            const backend = state(raw);
            backend.peak_count += 1;
            backend.peak = measurement;
        }

        fn hostAtomMessage(
            raw: *anyopaque,
            message: gui.HostAtomMessage,
        ) void {
            const backend = state(raw);
            if (message.body.len > backend.atom_body.len) return;
            backend.atom_count += 1;
            backend.atom_source_id = message.source_id;
            @memset(&backend.atom_body, 0);
            @memcpy(backend.atom_body[0..message.body.len], message.body);
            backend.atom_body_len = message.body.len;
        }

        fn destroy(raw: *anyopaque) void {
            std.heap.page_allocator.destroy(state(raw));
        }

        const vtable = gui.Adapter.VTable{
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
    const Ui = Adapter(
        Plugin,
        Core,
        "https://example.test/ui-probe",
        "https://example.test/ui-probe#ui",
        .{},
        .x11,
        Backend,
    );
    const CoreWithoutPrograms = struct {
        pub const parameters = 1;
        pub const control_input_port_start = 2;
        pub const programs_enabled = false;

        pub fn controlPort(index: usize) ?usize {
            return if (index == 0) 2 else null;
        }
    };
    const UiWithoutPrograms = Adapter(
        Plugin,
        CoreWithoutPrograms,
        "https://example.test/ui-probe-without-programs",
        "https://example.test/ui-probe-without-programs#ui",
        .{},
        .x11,
        Backend,
    );
    try std.testing.expect(
        UiWithoutPrograms.descriptor.extension_data(
            programs_ui_interface_uri,
        ) == null,
    );
    const Host = struct {
        writes: usize = 0,
        touched: usize = 0,
        released: usize = 0,
        resized: usize = 0,
        value_requests: usize = 0,
        requested_key: Urid = 0,
        requested_type: Urid = 0,
        request_status: RequestValueStatus = request_value_success,
        subscriptions: usize = 0,
        unsubscriptions: usize = 0,
        subscribed_port: u32 = invalid_port_index,
        subscribed_protocol: Urid = 0,
        subscription_status: u32 = 0,
        last_plain: f32 = 0.0,
        atom_write_count: usize = 0,
        atom_write_port: u32 = invalid_port_index,
        atom_write_format: Urid = 0,
        atom_write_type: Urid = 0,
        atom_write_body: [32]u8 = @splat(0),
        atom_write_body_len: usize = 0,
        reentrant_context: ?gui.Context = null,
        reentrant_status: ?gui.PluginMessageStatus = null,

        fn map(
            _: ?*anyopaque,
            uri: [*:0]const u8,
        ) callconv(.c) Urid {
            const value = std.mem.span(uri);
            if (std.mem.eql(u8, value, scale_factor_uri)) return 139;
            if (std.mem.eql(u8, value, update_rate_uri)) return 140;
            if (std.mem.eql(u8, value, window_title_uri)) return 141;
            if (std.mem.eql(u8, value, background_color_uri)) return 142;
            if (std.mem.eql(u8, value, foreground_color_uri)) return 143;
            if (std.mem.eql(u8, value, atom_float_uri)) return 47;
            if (std.mem.eql(u8, value, atom_string_uri)) return 48;
            if (std.mem.eql(u8, value, atom_int_uri)) return 49;
            if (std.mem.eql(u8, value, peak_protocol_uri)) return 152;
            if (std.mem.eql(u8, value, atom_event_transfer_uri)) return 153;
            if (std.mem.eql(
                u8,
                value,
                "https://example.test/messages#status",
            )) return 154;
            if (std.mem.eql(
                u8,
                value,
                "https://example.test/messages#command",
            )) return 155;
            const atom_type_prefix = "https://example.test/messages/type/";
            if (std.mem.startsWith(u8, value, atom_type_prefix)) {
                const index = std.fmt.parseInt(
                    u32,
                    value[atom_type_prefix.len..],
                    10,
                ) catch return 0;
                if (index <= gui.maximum_host_atom_notifications)
                    return 200 + index;
            }
            if (std.mem.eql(
                u8,
                value,
                "https://example.test/parameters/sample",
            )) return 150;
            if (std.mem.eql(
                u8,
                value,
                "http://lv2plug.in/ns/ext/atom#Path",
            )) return 51;
            return 0;
        }

        fn requestValue(
            handle: Handle,
            key: Urid,
            value_type: Urid,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) RequestValueStatus {
            const self: *@This() =
                @ptrCast(@alignCast(handle orelse
                    return request_value_unsupported));
            if (features != null) return request_value_unsupported;
            self.value_requests += 1;
            self.requested_key = key;
            self.requested_type = value_type;
            return self.request_status;
        }

        fn portIndex(
            _: Handle,
            symbol: [*:0]const u8,
        ) callconv(.c) u32 {
            const value = std.mem.span(symbol);
            if (std.mem.eql(u8, value, "audio_in")) return 0;
            if (std.mem.eql(u8, value, "audio_out")) return 1;
            if (std.mem.eql(u8, value, "events_output")) return 3;
            if (std.mem.eql(u8, value, "events_input")) return 4;
            if (std.mem.startsWith(u8, value, "peak_")) {
                const index = std.fmt.parseInt(
                    u32,
                    value["peak_".len..],
                    10,
                ) catch return invalid_port_index;
                if (index <= gui.maximum_host_peak_subscriptions)
                    return 100 + index;
            }
            return invalid_port_index;
        }

        fn subscribe(
            handle: Handle,
            port_index: u32,
            protocol: Urid,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) u32 {
            const self: *@This() = @ptrCast(@alignCast(
                handle orelse return 1,
            ));
            if (features != null) return 1;
            self.subscriptions += 1;
            self.subscribed_port = port_index;
            self.subscribed_protocol = protocol;
            return self.subscription_status;
        }

        fn unsubscribe(
            handle: Handle,
            port_index: u32,
            protocol: Urid,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) u32 {
            const self: *@This() = @ptrCast(@alignCast(
                handle orelse return 1,
            ));
            if (features != null) return 1;
            self.unsubscriptions += 1;
            self.subscribed_port = port_index;
            self.subscribed_protocol = protocol;
            return self.subscription_status;
        }

        fn write(
            controller: Controller,
            port: u32,
            size: u32,
            format_id: u32,
            buffer: ?*const anyopaque,
        ) callconv(.c) void {
            const self: *@This() =
                @ptrCast(@alignCast(controller orelse return));
            const raw = buffer orelse return;
            if (port == 2 and size == @sizeOf(f32) and format_id == 0) {
                self.last_plain =
                    @as(*align(1) const f32, @ptrCast(raw)).*;
                self.writes += 1;
                return;
            }
            if (port != 4 or format_id != 153 or size < @sizeOf(Atom))
                return;
            const atom = @as(*align(1) const Atom, @ptrCast(raw)).*;
            const total_size = std.math.add(
                usize,
                @sizeOf(Atom),
                atom.size,
            ) catch return;
            if (total_size != size or
                atom.size > gui.maximum_plugin_atom_body_bytes)
                return;
            const bytes: [*]align(1) const u8 = @ptrCast(raw);
            self.atom_write_count += 1;
            self.atom_write_port = port;
            self.atom_write_format = format_id;
            self.atom_write_type = atom.type;
            @memset(&self.atom_write_body, 0);
            const copied_body_size = @min(
                @as(usize, atom.size),
                self.atom_write_body.len,
            );
            @memcpy(
                self.atom_write_body[0..copied_body_size],
                bytes[@sizeOf(Atom) .. @sizeOf(Atom) + copied_body_size],
            );
            self.atom_write_body_len = atom.size;
            if (self.reentrant_context) |context| {
                self.reentrant_context = null;
                const nested_body = [_]u8{0xa5};
                self.reentrant_status = context.sendPluginAtomMessage(.{
                    .port_symbol = "events_input",
                    .atom_type_uri = "https://example.test/messages#command",
                    .body = &nested_body,
                }) catch .rejected;
            }
        }

        fn touch(
            handle: Handle,
            port: u32,
            grabbed: bool,
        ) callconv(.c) c_int {
            const self: *@This() =
                @ptrCast(@alignCast(handle orelse return 1));
            if (port != 2) return 1;
            if (grabbed)
                self.touched += 1
            else
                self.released += 1;
            return 0;
        }

        fn resize(
            handle: Handle,
            width: c_int,
            height: c_int,
        ) callconv(.c) c_int {
            const self: *@This() =
                @ptrCast(@alignCast(handle orelse return 1));
            if (width <= 0 or height <= 0) return 1;
            self.resized += 1;
            return 0;
        }
    };

    var host = Host{};
    const parent_feature = Feature{
        .URI = parent_uri,
        .data = &host,
    };
    const touch = Touch{
        .handle = &host,
        .touch = Host.touch,
    };
    const touch_feature = Feature{
        .URI = touch_uri,
        .data = @constCast(&touch),
    };
    const resize = Resize{
        .handle = &host,
        .ui_resize = Host.resize,
    };
    const resize_feature = Feature{
        .URI = resize_uri,
        .data = @constCast(&resize),
    };
    const request_value = RequestValue{
        .handle = &host,
        .request = Host.requestValue,
    };
    const request_value_feature = Feature{
        .URI = request_value_uri,
        .data = @constCast(&request_value),
    };
    const port_map = PortMap{
        .handle = &host,
        .port_index = Host.portIndex,
    };
    const port_map_feature = Feature{
        .URI = port_map_uri,
        .data = @constCast(&port_map),
    };
    const port_subscribe = PortSubscribe{
        .handle = &host,
        .subscribe = Host.subscribe,
        .unsubscribe = Host.unsubscribe,
    };
    const port_subscribe_feature = Feature{
        .URI = port_subscribe_uri,
        .data = @constCast(&port_subscribe),
    };
    const peak_protocol_feature = Feature{
        .URI = peak_protocol_uri,
        .data = null,
    };
    const atom_event_protocol_feature = Feature{
        .URI = atom_event_transfer_uri,
        .data = null,
    };
    var urid_map = UridMap{
        .handle = null,
        .map = Host.map,
    };
    const map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const scale_factor: f32 = 1.5;
    const update_rate_hz: f32 = 30.0;
    const window_title = "UI Probe Window";
    const background_rgba32: i32 = @bitCast(@as(u32, 0x112233ff));
    const foreground_rgba32: i32 = @bitCast(@as(u32, 0xeeddccff));
    const options = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &scale_factor,
        },
        .{
            .key = 140,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &update_rate_hz,
        },
        .{
            .key = 141,
            .size = window_title.len + 1,
            .type = 48,
            .value = window_title.ptr,
        },
        .{
            .key = 142,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &background_rgba32,
        },
        .{
            .key = 143,
            .size = @sizeOf(i32),
            .type = 49,
            .value = &foreground_rgba32,
        },
        .{},
    };
    const options_feature = Feature{
        .URI = options_options_uri,
        .data = @constCast(&options),
    };
    const features = [_:null]?*const Feature{
        &parent_feature,
        &touch_feature,
        &resize_feature,
        &request_value_feature,
        &port_map_feature,
        &port_subscribe_feature,
        &peak_protocol_feature,
        &atom_event_protocol_feature,
        &map_feature,
        &options_feature,
    };
    var widget: Widget = null;
    try std.testing.expect(Ui.descriptor.instantiate(
        &Ui.descriptor,
        "https://example.test/ui-probe",
        "/tmp/ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        null,
    ) == null);
    const null_parent_feature = Feature{
        .URI = parent_uri,
        .data = null,
    };
    const null_parent_features =
        [_:null]?*const Feature{&null_parent_feature};
    Backend.create_count = 0;
    try std.testing.expect(Ui.descriptor.instantiate(
        &Ui.descriptor,
        "https://example.test/ui-probe",
        "/tmp/ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &null_parent_features,
    ) == null);
    try std.testing.expectEqual(@as(usize, 0), Backend.create_count);
    const duplicate_parent_feature = Feature{
        .URI = parent_uri,
        .data = &host,
    };
    const duplicate_parent_features = [_:null]?*const Feature{
        &parent_feature,
        &duplicate_parent_feature,
    };
    try std.testing.expect(Ui.descriptor.instantiate(
        &Ui.descriptor,
        "https://example.test/ui-probe",
        "/tmp/ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &duplicate_parent_features,
    ) == null);
    try std.testing.expectEqual(@as(usize, 0), Backend.create_count);
    var unterminated_features: [256]?*const Feature =
        @splat(&parent_feature);
    const unterminated_list: ?[*:null]const ?*const Feature =
        @ptrCast(&unterminated_features);
    try std.testing.expect(Ui.descriptor.instantiate(
        &Ui.descriptor,
        "https://example.test/ui-probe",
        "/tmp/ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        unterminated_list,
    ) == null);
    try std.testing.expectEqual(@as(usize, 0), Backend.create_count);
    const missing_uri_feature = Feature{ .URI = null, .data = null };
    const missing_uri_features = [_:null]?*const Feature{
        &missing_uri_feature,
        &parent_feature,
    };
    try std.testing.expect(Ui.descriptor.instantiate(
        &Ui.descriptor,
        "https://example.test/ui-probe",
        "/tmp/ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &missing_uri_features,
    ) == null);
    try std.testing.expectEqual(@as(usize, 0), Backend.create_count);
    const handle = Ui.descriptor.instantiate(
        &Ui.descriptor,
        "https://example.test/ui-probe",
        "/tmp/ui-probe.lv2",
        Host.write,
        &host,
        &widget,
        &features,
    ) orelse return error.UiInstantiationFailed;
    defer Ui.descriptor.cleanup(handle);
    const instance = Ui.instanceFromHandle(handle) orelse
        return error.MissingUiInstance;
    try std.testing.expectEqual(
        gui.HostValueRequestStatus.accepted,
        try instance.editor.context.requestHostValue(.{
            .key_uri = "https://example.test/parameters/sample",
            .value_type_uri = "http://lv2plug.in/ns/ext/atom#Path",
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), host.value_requests);
    try std.testing.expectEqual(@as(Urid, 150), host.requested_key);
    try std.testing.expectEqual(@as(Urid, 51), host.requested_type);
    host.request_status = request_value_busy;
    try std.testing.expectEqual(
        gui.HostValueRequestStatus.busy,
        try instance.editor.context.requestHostValue(.{
            .key_uri = "https://example.test/parameters/sample",
        }),
    );
    try std.testing.expectEqual(@as(Urid, 0), host.requested_type);
    host.request_status = 99;
    try std.testing.expectEqual(
        gui.HostValueRequestStatus.unsupported,
        try instance.editor.context.requestHostValue(.{
            .key_uri = "https://example.test/parameters/sample",
        }),
    );
    try std.testing.expectEqual(
        gui.HostValueRequestStatus.unknown,
        try instance.editor.context.requestHostValue(.{
            .key_uri = "https://example.test/parameters/unknown",
        }),
    );
    try std.testing.expectEqual(
        gui.HostValueRequestStatus.unsupported,
        try instance.editor.context.requestHostValue(.{
            .key_uri = "https://example.test/parameters/sample",
            .value_type_uri = "https://example.test/types/unknown",
        }),
    );
    const peak_subscription = gui.HostPeakSubscription{
        .port_symbol = "audio_in",
        .source_id = 19,
    };
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.subscribeHostPeak(peak_subscription),
    );
    try std.testing.expectEqual(@as(usize, 1), host.subscriptions);
    try std.testing.expectEqual(@as(u32, 0), host.subscribed_port);
    try std.testing.expectEqual(@as(Urid, 152), host.subscribed_protocol);
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.subscribeHostPeak(peak_subscription),
    );
    try std.testing.expectEqual(@as(usize, 1), host.subscriptions);
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.rejected,
        try instance.editor.context.subscribeHostPeak(.{
            .port_symbol = "audio_in",
            .source_id = 20,
        }),
    );
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.rejected,
        try instance.editor.context.subscribeHostPeak(.{
            .port_symbol = "audio_out",
            .source_id = 19,
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), host.subscriptions);
    const second_peak_subscription = gui.HostPeakSubscription{
        .port_symbol = "audio_out",
        .source_id = 20,
    };
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.subscribeHostPeak(
            second_peak_subscription,
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), host.subscriptions);
    const peak_data = PeakData{
        .period_start = 512,
        .period_size = 64,
        .peak = 1.125,
    };
    Ui.descriptor.port_event(
        handle,
        0,
        @sizeOf(PeakData),
        152,
        &peak_data,
    );
    try std.testing.expect(widget != null);
    try std.testing.expectEqual(@as(usize, 1), Backend.create_count);

    const backend = Backend.state(instance.editor.adapter.userdata);
    try std.testing.expectEqual(@as(usize, 1), backend.peak_count);
    try std.testing.expectEqual(
        gui.HostPeakMeasurement{
            .source_id = 19,
            .period_start = 512,
            .period_size = 64,
            .peak = 1.125,
        },
        backend.peak,
    );
    const malformed_peak = PeakData{
        .period_start = 576,
        .period_size = 0,
        .peak = 1.0,
    };
    Ui.descriptor.port_event(
        handle,
        0,
        @sizeOf(PeakData),
        152,
        &malformed_peak,
    );
    const infinite_peak = PeakData{
        .period_start = 576,
        .period_size = 64,
        .peak = std.math.inf(f32),
    };
    Ui.descriptor.port_event(
        handle,
        0,
        @sizeOf(PeakData),
        152,
        &infinite_peak,
    );
    Ui.descriptor.port_event(handle, 0, 1, 152, &peak_data);
    Ui.descriptor.port_event(handle, 9, @sizeOf(PeakData), 152, &peak_data);
    try std.testing.expectEqual(@as(usize, 1), backend.peak_count);
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.unsubscribeHostPeak(peak_subscription),
    );
    try std.testing.expectEqual(@as(usize, 1), host.unsubscriptions);
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.rejected,
        try instance.editor.context.unsubscribeHostPeak(peak_subscription),
    );
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.unsubscribeHostPeak(
            second_peak_subscription,
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), host.unsubscriptions);
    const static_peak_subscription = gui.HostPeakSubscription{
        .port_symbol = "audio_in",
        .source_id = 21,
        .delivery = .static,
    };
    const subscriptions_before_static = host.subscriptions;
    const unsubscriptions_before_static = host.unsubscriptions;
    const retained_port_subscribe = instance.port_subscribe;
    instance.port_subscribe = null;
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.subscribeHostPeak(
            static_peak_subscription,
        ),
    );
    try std.testing.expectEqual(
        subscriptions_before_static,
        host.subscriptions,
    );
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.unsupported,
        try instance.editor.context.subscribeHostPeak(.{
            .port_symbol = "audio_out",
            .source_id = 22,
        }),
    );
    Ui.descriptor.port_event(
        handle,
        0,
        @sizeOf(PeakData),
        152,
        &peak_data,
    );
    try std.testing.expectEqual(@as(usize, 2), backend.peak_count);
    try std.testing.expectEqual(@as(u32, 21), backend.peak.source_id);
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.unsubscribeHostPeak(
            static_peak_subscription,
        ),
    );
    try std.testing.expectEqual(
        unsubscriptions_before_static,
        host.unsubscriptions,
    );
    instance.port_subscribe = retained_port_subscribe;
    const bounded_subscriptions = [_]gui.HostPeakSubscription{
        .{ .port_symbol = "peak_0", .source_id = 100 },
        .{ .port_symbol = "peak_1", .source_id = 101 },
        .{ .port_symbol = "peak_2", .source_id = 102 },
        .{ .port_symbol = "peak_3", .source_id = 103 },
        .{ .port_symbol = "peak_4", .source_id = 104 },
        .{ .port_symbol = "peak_5", .source_id = 105 },
        .{ .port_symbol = "peak_6", .source_id = 106 },
        .{ .port_symbol = "peak_7", .source_id = 107 },
        .{ .port_symbol = "peak_8", .source_id = 108 },
        .{ .port_symbol = "peak_9", .source_id = 109 },
        .{ .port_symbol = "peak_10", .source_id = 110 },
        .{ .port_symbol = "peak_11", .source_id = 111 },
        .{ .port_symbol = "peak_12", .source_id = 112 },
        .{ .port_symbol = "peak_13", .source_id = 113 },
        .{ .port_symbol = "peak_14", .source_id = 114 },
        .{ .port_symbol = "peak_15", .source_id = 115 },
    };
    host.subscription_status = 1;
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.rejected,
        try instance.editor.context.subscribeHostPeak(
            bounded_subscriptions[0],
        ),
    );
    const subscriptions_before_capacity = host.subscriptions;
    host.subscription_status = 0;
    for (bounded_subscriptions) |subscription| {
        try std.testing.expectEqual(
            gui.HostSubscriptionStatus.accepted,
            try instance.editor.context.subscribeHostPeak(subscription),
        );
    }
    try std.testing.expectEqual(
        subscriptions_before_capacity + bounded_subscriptions.len,
        host.subscriptions,
    );
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.full,
        try instance.editor.context.subscribeHostPeak(.{
            .port_symbol = "peak_16",
            .source_id = 116,
        }),
    );
    try std.testing.expectEqual(
        subscriptions_before_capacity + bounded_subscriptions.len,
        host.subscriptions,
    );
    host.subscription_status = 1;
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.rejected,
        try instance.editor.context.unsubscribeHostPeak(
            bounded_subscriptions[0],
        ),
    );
    host.subscription_status = 0;
    for (bounded_subscriptions) |subscription| {
        try std.testing.expectEqual(
            gui.HostSubscriptionStatus.accepted,
            try instance.editor.context.unsubscribeHostPeak(subscription),
        );
    }
    const atom_notification = gui.HostAtomNotification{
        .port_symbol = "events_output",
        .atom_type_uri = "https://example.test/messages#status",
        .source_id = 31,
    };
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.registerHostAtomNotification(
            atom_notification,
        ),
    );
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.registerHostAtomNotification(
            atom_notification,
        ),
    );
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.rejected,
        try instance.editor.context.registerHostAtomNotification(.{
            .port_symbol = "events_output",
            .atom_type_uri = "https://example.test/messages#status",
            .source_id = 32,
        }),
    );
    const AtomPacket = extern struct {
        atom: Atom,
        body: [4]u8,
    };
    var atom_packet = AtomPacket{
        .atom = .{ .size = 4, .type = 154 },
        .body = .{ 1, 3, 5, 7 },
    };
    Ui.descriptor.port_event(
        handle,
        3,
        @sizeOf(AtomPacket),
        153,
        &atom_packet,
    );
    try std.testing.expectEqual(@as(usize, 1), backend.atom_count);
    try std.testing.expectEqual(@as(u32, 31), backend.atom_source_id);
    try std.testing.expectEqualSlices(
        u8,
        &atom_packet.body,
        backend.atom_body[0..backend.atom_body_len],
    );
    Ui.descriptor.port_event(handle, 3, @sizeOf(Atom) - 1, 153, &atom_packet);
    atom_packet.atom.type = 0;
    Ui.descriptor.port_event(handle, 3, @sizeOf(AtomPacket), 153, &atom_packet);
    atom_packet.atom = .{ .size = 3, .type = 154 };
    Ui.descriptor.port_event(handle, 3, @sizeOf(AtomPacket), 153, &atom_packet);
    atom_packet.atom = .{
        .size = gui.maximum_host_atom_body_bytes + 1,
        .type = 154,
    };
    Ui.descriptor.port_event(handle, 3, @sizeOf(Atom), 153, &atom_packet);
    atom_packet.atom = .{ .size = 4, .type = 155 };
    Ui.descriptor.port_event(handle, 3, @sizeOf(AtomPacket), 153, &atom_packet);
    atom_packet.atom.type = 154;
    Ui.descriptor.port_event(handle, 4, @sizeOf(AtomPacket), 153, &atom_packet);
    Ui.descriptor.port_event(handle, 3, @sizeOf(AtomPacket), 152, &atom_packet);
    try std.testing.expectEqual(@as(usize, 1), backend.atom_count);
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.accepted,
        try instance.editor.context.unregisterHostAtomNotification(
            atom_notification,
        ),
    );
    Ui.descriptor.port_event(handle, 3, @sizeOf(AtomPacket), 153, &atom_packet);
    try std.testing.expectEqual(@as(usize, 1), backend.atom_count);
    const bounded_atom_notifications = [_]gui.HostAtomNotification{
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/0", .source_id = 200 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/1", .source_id = 201 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/2", .source_id = 202 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/3", .source_id = 203 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/4", .source_id = 204 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/5", .source_id = 205 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/6", .source_id = 206 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/7", .source_id = 207 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/8", .source_id = 208 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/9", .source_id = 209 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/10", .source_id = 210 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/11", .source_id = 211 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/12", .source_id = 212 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/13", .source_id = 213 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/14", .source_id = 214 },
        .{ .port_symbol = "events_output", .atom_type_uri = "https://example.test/messages/type/15", .source_id = 215 },
    };
    for (bounded_atom_notifications) |notification| {
        try std.testing.expectEqual(
            gui.HostSubscriptionStatus.accepted,
            try instance.editor.context.registerHostAtomNotification(
                notification,
            ),
        );
    }
    try std.testing.expectEqual(
        gui.HostSubscriptionStatus.full,
        try instance.editor.context.registerHostAtomNotification(.{
            .port_symbol = "events_output",
            .atom_type_uri = "https://example.test/messages/type/16",
            .source_id = 216,
        }),
    );
    for (bounded_atom_notifications) |notification| {
        try std.testing.expectEqual(
            gui.HostSubscriptionStatus.accepted,
            try instance.editor.context.unregisterHostAtomNotification(
                notification,
            ),
        );
    }
    const command_body = [_]u8{ 9, 7, 5, 3 };
    try std.testing.expectEqual(
        gui.PluginMessageStatus.accepted,
        try instance.editor.context.sendPluginAtomMessage(.{
            .port_symbol = "events_input",
            .atom_type_uri = "https://example.test/messages#command",
            .body = &command_body,
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), host.atom_write_count);
    try std.testing.expectEqual(@as(u32, 4), host.atom_write_port);
    try std.testing.expectEqual(@as(Urid, 153), host.atom_write_format);
    try std.testing.expectEqual(@as(Urid, 155), host.atom_write_type);
    try std.testing.expectEqualSlices(
        u8,
        &command_body,
        host.atom_write_body[0..host.atom_write_body_len],
    );
    for (instance.atom_write_buffer) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    var maximum_command_body: [gui.maximum_plugin_atom_body_bytes]u8 =
        @splat(0x5a);
    try std.testing.expectEqual(
        gui.PluginMessageStatus.accepted,
        try instance.editor.context.sendPluginAtomMessage(.{
            .port_symbol = "events_input",
            .atom_type_uri = "https://example.test/messages#command",
            .body = &maximum_command_body,
        }),
    );
    try std.testing.expectEqual(@as(usize, 2), host.atom_write_count);
    try std.testing.expectEqual(
        gui.maximum_plugin_atom_body_bytes,
        host.atom_write_body_len,
    );
    for (host.atom_write_body) |byte|
        try std.testing.expectEqual(@as(u8, 0x5a), byte);
    for (instance.atom_write_buffer) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    host.reentrant_context = instance.editor.context;
    try std.testing.expectEqual(
        gui.PluginMessageStatus.accepted,
        try instance.editor.context.sendPluginAtomMessage(.{
            .port_symbol = "events_input",
            .atom_type_uri = "https://example.test/messages#command",
            .body = &command_body,
        }),
    );
    try std.testing.expectEqual(
        gui.PluginMessageStatus.rejected,
        host.reentrant_status orelse return error.MissingReentrantStatus,
    );
    try std.testing.expectEqual(@as(usize, 3), host.atom_write_count);
    try std.testing.expectEqualSlices(
        u8,
        &command_body,
        host.atom_write_body[0..host.atom_write_body_len],
    );
    for (instance.atom_write_buffer) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqual(
        gui.PluginMessageStatus.rejected,
        try instance.editor.context.sendPluginAtomMessage(.{
            .port_symbol = "missing_input",
            .atom_type_uri = "https://example.test/messages#command",
            .body = &command_body,
        }),
    );
    try std.testing.expectEqual(
        gui.PluginMessageStatus.rejected,
        try instance.editor.context.sendPluginAtomMessage(.{
            .port_symbol = "events_input",
            .atom_type_uri = "https://example.test/messages#unknown",
            .body = &command_body,
        }),
    );
    const retained_atom_event_protocol = instance.atom_event_protocol;
    instance.atom_event_protocol = 0;
    try std.testing.expectEqual(
        gui.PluginMessageStatus.unsupported,
        try instance.editor.context.sendPluginAtomMessage(.{
            .port_symbol = "events_input",
            .atom_type_uri = "https://example.test/messages#command",
            .body = &command_body,
        }),
    );
    instance.atom_event_protocol = retained_atom_event_protocol;
    try std.testing.expectEqual(@as(usize, 3), host.atom_write_count);
    try std.testing.expectEqual(
        gui.Scale{ .x = 1.5, .y = 1.5 },
        backend.scale,
    );
    try std.testing.expectEqual(@as(f32, 30.0), backend.update_rate_hz);
    try std.testing.expectEqualStrings(
        window_title,
        backend.window_title[0..backend.window_title_len],
    );
    try std.testing.expectEqual(@as(u32, 0x112233ff), backend.background_rgba32);
    try std.testing.expectEqual(@as(u32, 0xeeddccff), backend.foreground_rgba32);
    try std.testing.expect(Ui.descriptor.extension_data(null) == null);
    const options_ptr = Ui.descriptor.extension_data(
        options_interface_uri,
    ) orelse return error.MissingOptionsInterface;
    const runtime_options: *const OptionsInterface =
        @ptrCast(@alignCast(options_ptr));
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.get(handle, null),
    );
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.set(handle, null),
    );
    var misaligned_option_storage: [@sizeOf(OptionsOption) * 2 + 1]u8 align(@alignOf(OptionsOption)) =
        undefined;
    const misaligned_option_address =
        @intFromPtr(&misaligned_option_storage[1]);
    const misaligned_query: ?[*]align(1) OptionsOption =
        @ptrFromInt(misaligned_option_address);
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.get(handle, misaligned_query),
    );
    const misaligned_update: ?[*]align(1) const OptionsOption =
        @ptrFromInt(misaligned_option_address);
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.set(handle, misaligned_update),
    );
    var scale_query = [_]OptionsOption{
        .{ .key = 139 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.get(handle, &scale_query),
    );
    try std.testing.expectEqual(@as(u32, @sizeOf(f32)), scale_query[0].size);
    try std.testing.expectEqual(@as(Urid, 47), scale_query[0].type);
    const queried_scale = scale_query[0].value orelse
        return error.MissingScaleValue;
    try std.testing.expectEqual(
        @as(f32, 1.5),
        @as(*align(1) const f32, @ptrCast(queried_scale)).*,
    );
    var update_rate_query = [_]OptionsOption{
        .{ .key = 140 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.get(handle, &update_rate_query),
    );
    try std.testing.expectEqual(
        @as(u32, @sizeOf(f32)),
        update_rate_query[0].size,
    );
    try std.testing.expectEqual(
        @as(Urid, 47),
        update_rate_query[0].type,
    );
    const queried_update_rate = update_rate_query[0].value orelse
        return error.MissingUpdateRateValue;
    try std.testing.expectEqual(
        @as(f32, 30.0),
        @as(*align(1) const f32, @ptrCast(queried_update_rate)).*,
    );
    var window_title_query = [_]OptionsOption{
        .{ .key = 141 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.get(handle, &window_title_query),
    );
    try std.testing.expectEqual(
        @as(u32, window_title.len + 1),
        window_title_query[0].size,
    );
    try std.testing.expectEqual(@as(Urid, 48), window_title_query[0].type);
    const queried_window_title = window_title_query[0].value orelse
        return error.MissingWindowTitleValue;
    try std.testing.expectEqualStrings(
        window_title,
        @as([*]const u8, @ptrCast(queried_window_title))[0..window_title.len],
    );
    var color_query = [_]OptionsOption{
        .{ .key = 142 },
        .{ .key = 143 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.get(handle, &color_query),
    );
    try std.testing.expectEqual(@as(Urid, 49), color_query[0].type);
    try std.testing.expectEqual(@as(Urid, 49), color_query[1].type);
    const queried_background = color_query[0].value orelse
        return error.MissingBackgroundColor;
    const queried_foreground = color_query[1].value orelse
        return error.MissingForegroundColor;
    try std.testing.expectEqual(
        @as(u32, 0x112233ff),
        @as(*align(1) const u32, @ptrCast(queried_background)).*,
    );
    try std.testing.expectEqual(
        @as(u32, 0xeeddccff),
        @as(*align(1) const u32, @ptrCast(queried_foreground)).*,
    );
    var mixed_scale_query = [_]OptionsOption{
        .{ .key = 139 },
        .{ .key = 999 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_key,
        runtime_options.get(handle, &mixed_scale_query),
    );
    try std.testing.expectEqual(@as(u32, 0), mixed_scale_query[0].size);
    try std.testing.expectEqual(@as(Urid, 0), mixed_scale_query[0].type);
    try std.testing.expect(mixed_scale_query[0].value == null);
    var unterminated_scale_queries: [256]OptionsOption =
        @splat(.{ .key = 139 });
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.get(handle, &unterminated_scale_queries),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        unterminated_scale_queries[0].size,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        unterminated_scale_queries[
            unterminated_scale_queries.len - 1
        ].size,
    );

    const next_scale: f32 = 2.0;
    const scale_update = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &next_scale,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &scale_update),
    );
    try std.testing.expectEqual(
        gui.Scale{ .x = 2.0, .y = 2.0 },
        backend.scale,
    );
    const next_update_rate_hz: f32 = 45.0;
    const update_rate_update = [_]OptionsOption{
        .{
            .key = 140,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &next_update_rate_hz,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &update_rate_update),
    );
    try std.testing.expectEqual(@as(f32, 45.0), backend.update_rate_hz);
    const next_window_title = "Updated UI Probe";
    const window_title_update = [_]OptionsOption{
        .{
            .key = 141,
            .size = next_window_title.len + 1,
            .type = 48,
            .value = next_window_title.ptr,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &window_title_update),
    );
    try std.testing.expectEqualStrings(
        next_window_title,
        backend.window_title[0..backend.window_title_len],
    );
    const next_background: i32 = @bitCast(@as(u32, 0x445566ff));
    const next_foreground: i32 = @bitCast(@as(u32, 0xaabbccff));
    const color_update = [_]OptionsOption{
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
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &color_update),
    );
    try std.testing.expectEqual(@as(u32, 0x445566ff), backend.background_rgba32);
    try std.testing.expectEqual(@as(u32, 0xaabbccff), backend.foreground_rgba32);

    const invalid_scale: f32 = 0.0;
    const rejected_update = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &invalid_scale,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &rejected_update),
    );
    try std.testing.expectEqual(
        gui.Scale{ .x = 2.0, .y = 2.0 },
        backend.scale,
    );
    try std.testing.expectEqual(@as(f32, 45.0), backend.update_rate_hz);
    const candidate_scale: f32 = 2.5;
    const invalid_update_rate_hz: f32 = 0.0;
    const mixed_rejected_update = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &candidate_scale,
        },
        .{
            .key = 140,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &invalid_update_rate_hz,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &mixed_rejected_update),
    );
    try std.testing.expectEqual(
        gui.Scale{ .x = 2.0, .y = 2.0 },
        backend.scale,
    );
    try std.testing.expectEqual(@as(f32, 45.0), backend.update_rate_hz);

    const unterminated_window_title = [_]u8{ 'b', 'a', 'd' };
    const rejected_unterminated_title = [_]OptionsOption{
        .{
            .key = 141,
            .size = unterminated_window_title.len,
            .type = 48,
            .value = &unterminated_window_title,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &rejected_unterminated_title),
    );
    try std.testing.expectEqualStrings(
        next_window_title,
        backend.window_title[0..backend.window_title_len],
    );

    const interior_nul_window_title = [_]u8{ 'b', 0, 'a', 'd', 0 };
    const candidate_scale_with_bad_title: f32 = 2.5;
    const rejected_interior_nul_title = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &candidate_scale_with_bad_title,
        },
        .{
            .key = 141,
            .size = interior_nul_window_title.len,
            .type = 48,
            .value = &interior_nul_window_title,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &rejected_interior_nul_title),
    );
    try std.testing.expectEqual(
        gui.Scale{ .x = 2.0, .y = 2.0 },
        backend.scale,
    );
    try std.testing.expectEqualStrings(
        next_window_title,
        backend.window_title[0..backend.window_title_len],
    );

    const invalid_color_value: i32 = @bitCast(@as(u32, 0x010203ff));
    const candidate_scale_with_bad_color: f32 = 2.75;
    const rejected_color_type = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &candidate_scale_with_bad_color,
        },
        .{
            .key = 142,
            .size = @sizeOf(i32),
            .type = 47,
            .value = &invalid_color_value,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &rejected_color_type),
    );
    try std.testing.expectEqual(
        gui.Scale{ .x = 2.0, .y = 2.0 },
        backend.scale,
    );
    try std.testing.expectEqual(@as(u32, 0x445566ff), backend.background_rgba32);

    const rejected_backend_scale: f32 = 3.0;
    const rejected_backend_update = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &rejected_backend_scale,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.set(handle, &rejected_backend_update),
    );
    try std.testing.expectEqual(
        gui.Scale{ .x = 2.0, .y = 2.0 },
        backend.scale,
    );
    scale_query[0] = .{ .key = 139 };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.get(handle, &scale_query),
    );
    const retained_scale = scale_query[0].value orelse
        return error.MissingScaleValue;
    try std.testing.expectEqual(
        @as(f32, 2.0),
        @as(*align(1) const f32, @ptrCast(retained_scale)).*,
    );
    try instance.editor.beginGesture(7);
    try instance.editor.setGestureValue(0.75);
    instance.editor.endGesture();
    try std.testing.expectEqual(@as(usize, 1), host.writes);
    try std.testing.expectEqual(@as(usize, 1), host.touched);
    try std.testing.expectEqual(@as(usize, 1), host.released);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.5),
        host.last_plain,
        0.0001,
    );

    const plain: f32 = 0.5;
    Ui.descriptor.port_event(handle, 2, @sizeOf(f32), 0, &plain);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        backend.parameter,
        0.0001,
    );

    const programs_ptr = Ui.descriptor.extension_data(
        programs_ui_interface_uri,
    ) orelse return error.MissingProgramsUiInterface;
    const programs: *const ProgramsUiInterface =
        @ptrCast(@alignCast(programs_ptr));
    programs.select_program(handle, 17, 0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.8),
        backend.parameter,
        0.0001,
    );
    programs.select_program(handle, 99, 0);
    programs.select_program(handle, 17, 99);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.8),
        backend.parameter,
        0.0001,
    );
    const misaligned: Handle = @ptrFromInt(@intFromPtr(handle) + 1);
    programs.select_program(misaligned, 17, 0);
    const misaligned_raw = misaligned orelse
        return error.MissingMisalignedHandle;
    const context_api = instance.editor.context.vtable;
    try std.testing.expectError(
        error.Rejected,
        context_api.begin_edit(misaligned_raw, 7),
    );
    try std.testing.expectError(
        error.Rejected,
        context_api.perform_edit(misaligned_raw, 7, 0.5),
    );
    context_api.end_edit(misaligned_raw, 7);
    try std.testing.expect(context_api.value(misaligned_raw, 7) == null);
    try std.testing.expectError(
        error.Rejected,
        context_api.request_resize(
            misaligned_raw,
            .{ .width = 640, .height = 480 },
        ),
    );

    try instance.editor.requestResize(.{ .width = 640, .height = 480 });
    try std.testing.expectEqual(@as(usize, 1), host.resized);
    try std.testing.expectEqual(
        gui.Size{ .width = 640, .height = 480 },
        backend.size,
    );

    const idle_ptr = Ui.descriptor.extension_data(idle_interface_uri) orelse
        return error.MissingIdleInterface;
    const idle_api: *const IdleInterface =
        @ptrCast(@alignCast(idle_ptr));
    try std.testing.expectEqual(@as(c_int, 0), idle_api.idle(handle));
    try std.testing.expectEqual(@as(usize, 1), backend.idle_count);

    const resize_ptr = Ui.descriptor.extension_data(resize_uri) orelse
        return error.MissingResizeInterface;
    const resize_api: *const ResizeInterface =
        @ptrCast(@alignCast(resize_ptr));
    try std.testing.expectEqual(
        @as(c_int, 0),
        resize_api.ui_resize(handle, 500, 300),
    );
    try std.testing.expectEqual(
        gui.Size{ .width = 500, .height = 300 },
        backend.size,
    );
}
