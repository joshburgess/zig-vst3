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
pub const scale_factor_uri = ui_uri ++ "#scaleFactor";
pub const options_options_uri =
    "http://lv2plug.in/ns/ext/options#options";
pub const options_interface_uri =
    "http://lv2plug.in/ns/ext/options#interface";
pub const urid_map_uri =
    "http://lv2plug.in/ns/ext/urid#map";
pub const atom_float_uri =
    "http://lv2plug.in/ns/ext/atom#Float";
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
        options: ?[*]OptionsOption,
    ) callconv(.c) OptionsStatus,
    set: *const fn (
        instance: Handle,
        options: ?[*]const OptionsOption,
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

const CheckedResize = struct {
    handle: Handle,
    ui_resize: ResizeFunction,
};

const CheckedTouch = struct {
    handle: Handle,
    touch: TouchFunction,
};

pub const ProgramsUiInterface = extern struct {
    select_program: *const fn (
        ui: Handle,
        bank: u32,
        program: u32,
    ) callconv(.c) void,
};

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

    return struct {
        const Self = @This();

        const Instance = struct {
            write_function: WriteFunction,
            controller: Controller,
            resize: ?CheckedResize,
            touch: ?CheckedTouch,
            scale_key: Urid,
            atom_float_type: Urid,
            scale: f32,
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
            if (!std.mem.eql(
                u8,
                std.mem.span(requested_plugin_uri),
                plugin_uri,
            )) return null;
            const write = write_function orelse return null;
            const widget_out = widget orelse return null;
            const parent_feature = findFeature(features, parent_uri) orelse
                return null;
            const parent = parent_feature.data orelse return null;
            const scale_options = readScaleOptions(features) catch return null;

            const allocator = std.heap.page_allocator;
            const instance = allocator.create(Instance) catch return null;
            instance.* = .{
                .write_function = write,
                .controller = controller,
                .resize = checkedResize(features),
                .touch = checkedTouch(features),
                .scale_key = scale_options.key,
                .atom_float_type = scale_options.atom_float_type,
                .scale = scale_options.value orelse 1.0,
                .values = initialValues(),
                .editor = undefined,
            };
            instance.editor = Backend.create(instance.context()) catch {
                allocator.destroy(instance);
                return null;
            };
            instance.editor.attach(.{
                .platform = platform,
                .handle = parent,
            }) catch {
                instance.editor.deinit();
                allocator.destroy(instance);
                return null;
            };
            if (scale_options.value) |scale| {
                instance.editor.setScale(.{
                    .x = scale,
                    .y = scale,
                }) catch {
                    instance.editor.deinit();
                    allocator.destroy(instance);
                    return null;
                };
            }
            widget_out.* = Backend.widget(instance.editor.adapter) orelse {
                instance.editor.deinit();
                allocator.destroy(instance);
                return null;
            };
            return instance;
        }

        fn cleanup(handle: Handle) callconv(.c) void {
            const instance = instanceFromHandle(handle) orelse return;
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
            if (event_format != 0 or buffer_size != @sizeOf(f32)) return;
            const raw = buffer orelse return;
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
            const requested = std.mem.span(uri);
            if (std.mem.eql(u8, requested, idle_interface_uri))
                return &idle_interface;
            if (std.mem.eql(u8, requested, resize_uri))
                return &resize_interface;
            if (std.mem.eql(u8, requested, show_interface_uri))
                return &show_interface;
            if (std.mem.eql(u8, requested, options_interface_uri))
                return &options_interface;
            if (comptime has_programs) {
                if (std.mem.eql(
                    u8,
                    requested,
                    programs_ui_interface_uri,
                )) return &programs_ui_interface;
            }
            return null;
        }

        fn getOptions(
            handle: Handle,
            raw_options: ?[*]OptionsOption,
        ) callconv(.c) OptionsStatus {
            const instance = instanceFromHandle(handle) orelse
                return options_status_unknown;
            const options = raw_options orelse
                return options_status_unknown;
            var status = options_status_success;
            var terminated = false;
            for (0..256) |index| {
                const option = &options[index];
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
                if (instance.scale_key == 0 or
                    option.key != instance.scale_key)
                {
                    status |= options_status_bad_key;
                    continue;
                }
                option.size = @sizeOf(f32);
                option.type = instance.atom_float_type;
                option.value = &instance.scale;
            }
            if (!terminated) status |= options_status_unknown;
            return status;
        }

        fn setOptions(
            handle: Handle,
            raw_options: ?[*]const OptionsOption,
        ) callconv(.c) OptionsStatus {
            const instance = instanceFromHandle(handle) orelse
                return options_status_unknown;
            const options = raw_options orelse
                return options_status_unknown;
            var scale: ?f32 = null;
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
                if (instance.scale_key == 0 or
                    option.key != instance.scale_key)
                {
                    status |= options_status_bad_key;
                    continue;
                }
                if (scale != null or
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
                const option_scale =
                    @as(*align(1) const f32, @ptrCast(raw)).*;
                if (!std.math.isFinite(option_scale) or option_scale <= 0.0) {
                    status |= options_status_bad_value;
                    continue;
                }
                scale = option_scale;
            }
            if (!terminated) status |= options_status_unknown;
            if (status != options_status_success) return status;
            const next_scale = scale orelse return options_status_success;
            instance.editor.setScale(.{
                .x = next_scale,
                .y = next_scale,
            }) catch return options_status_unknown;
            instance.scale = next_scale;
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
        };

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
    const list = features orelse return null;
    if (@intFromPtr(list) % @alignOf(?*const Feature) != 0)
        return null;
    for (0..256) |index| {
        const feature = list[index] orelse return null;
        if (@intFromPtr(feature) % @alignOf(Feature) != 0)
            continue;
        const uri = feature.URI orelse continue;
        if (std.mem.eql(u8, std.mem.span(uri), wanted_uri))
            return feature;
    }
    return null;
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
    const raw = featureData(Touch, features, touch_uri) orelse
        return null;
    return .{
        .handle = raw.handle,
        .touch = raw.touch orelse return null,
    };
}

fn sizeFromHost(width: c_int, height: c_int) ?gui.Size {
    if (width <= 0 or height <= 0) return null;
    return .{
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

const ScaleOptions = struct {
    key: Urid = 0,
    atom_float_type: Urid = 0,
    value: ?f32 = null,
};

fn readScaleOptions(
    features: ?[*:null]const ?*const Feature,
) !ScaleOptions {
    const map = featureData(UridMap, features, urid_map_uri) orelse {
        if (findFeature(features, options_options_uri) != null)
            return error.InvalidOptions;
        return .{};
    };
    const map_uri = map.map orelse return error.InvalidOptions;
    const scale_key = map_uri(map.handle, scale_factor_uri);
    const float_type = map_uri(map.handle, atom_float_uri);
    if (scale_key == 0 or float_type == 0)
        return error.InvalidOptions;
    var result = ScaleOptions{
        .key = scale_key,
        .atom_float_type = float_type,
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
        if (option.context != 0 or option.key != scale_key)
            continue;
        if (result.value != null or option.size != @sizeOf(f32) or
            option.type != float_type)
            return error.InvalidOptions;
        const raw = option.value orelse return error.InvalidOptions;
        const value = @as(*align(1) const f32, @ptrCast(raw)).*;
        if (!std.math.isFinite(value) or value <= 0.0)
            return error.InvalidOptions;
        result.value = value;
    }
    return error.InvalidOptions;
}

test "LV2 UI feature lookup is bounded and validates resize dimensions" {
    const parent = Feature{
        .URI = parent_uri,
        .data = null,
    };
    const list = [_:null]?*const Feature{&parent};
    try std.testing.expect(findFeature(&list, parent_uri) == &parent);
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
    try std.testing.expect(
        findFeature(records[0..].ptr, parent_uri) == &parent,
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
    try std.testing.expect(sizeFromHost(640, 480) != null);
    try std.testing.expect(sizeFromHost(0, 480) == null);
    try std.testing.expect(sizeFromHost(640, -1) == null);
}

test "LV2 UI scale option validates host data transactionally" {
    const Host = struct {
        fn map(
            _: ?*anyopaque,
            uri: [*:0]const u8,
        ) callconv(.c) Urid {
            const value = std.mem.span(uri);
            if (std.mem.eql(u8, value, scale_factor_uri)) return 139;
            if (std.mem.eql(u8, value, atom_float_uri)) return 47;
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
    const options = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &scale,
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
    try std.testing.expectEqual(
        @as(?f32, 2.0),
        (try readScaleOptions(&features)).value,
    );

    urid_map.map = null;
    try std.testing.expectError(
        error.InvalidOptions,
        readScaleOptions(&features),
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
        readScaleOptions(&features),
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
        readScaleOptions(&features),
    );

    var misaligned_storage: [@sizeOf(OptionsOption) + 1]u8 align(@alignOf(OptionsOption)) =
        undefined;
    options_feature.data = @ptrCast(&misaligned_storage[1]);
    try std.testing.expectError(
        error.InvalidOptions,
        readScaleOptions(&features),
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
            idle_count: usize = 0,
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
        last_plain: f32 = 0.0,

        fn map(
            _: ?*anyopaque,
            uri: [*:0]const u8,
        ) callconv(.c) Urid {
            const value = std.mem.span(uri);
            if (std.mem.eql(u8, value, scale_factor_uri)) return 139;
            if (std.mem.eql(u8, value, atom_float_uri)) return 47;
            return 0;
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
            if (port != 2 or size != @sizeOf(f32) or format_id != 0)
                return;
            const raw = buffer orelse return;
            self.last_plain =
                @as(*align(1) const f32, @ptrCast(raw)).*;
            self.writes += 1;
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
    var urid_map = UridMap{
        .handle = null,
        .map = Host.map,
    };
    const map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const scale_factor: f32 = 1.5;
    const options = [_]OptionsOption{
        .{
            .key = 139,
            .size = @sizeOf(f32),
            .type = 47,
            .value = &scale_factor,
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
        &map_feature,
        &options_feature,
    };
    var widget: Widget = null;
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
    try std.testing.expect(widget != null);
    try std.testing.expectEqual(@as(usize, 1), Backend.create_count);

    const instance = Ui.instanceFromHandle(handle) orelse
        return error.UiInstantiationFailed;
    const backend = Backend.state(instance.editor.adapter.userdata);
    try std.testing.expectEqual(
        gui.Scale{ .x = 1.5, .y = 1.5 },
        backend.scale,
    );
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
