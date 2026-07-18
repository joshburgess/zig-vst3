const builtin = @import("builtin");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const iwaylandframe = @import("pluginterfaces/gui/iwaylandframe.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");
const vst_plug_view = @import("vst_plug_view.zig");
const vstgui_editor_view = @import("vstgui_editor_view.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const vstgui_adapter_enabled = @import("zig-vst3-gui-options").vstgui_adapter_enabled;
const gui_graph = @import("zig-vst3-plugin-core").gui_graph;
const gui_file_drop = @import("zig-vst3-plugin-core").gui_file_drop;
const editor_state = @import("zig-vst3-plugin-core").editor_state;

const ProtocolView = vst_plug_view.PlugView(4, struct {});

pub const Parameter = struct {
    id: vsttypes.ParamID,
    title: [*:0]const u8,
    units: [*:0]const u8 = "",
    step_count: types.int32,
    default_normalized: f64,
    control_kind: vstgui_editor_view.ControlKind = .linear_slider,
    tooltip: ?[*:0]const u8 = null,
    modulation_normalized: ?f64 = null,
};

pub const Meter = struct {
    title: [*:0]const u8,
    kind: vstgui_editor_view.MeterKind,
    first_source_id: types.uint32,
    second_source_id: types.uint32 = 0,
};

pub const GraphPoint = gui_graph.Point;
pub const EnvelopePoint = vstgui_editor_view.EnvelopePoint;
pub const GraphScale = vstgui_editor_view.GraphScale;
pub const GraphKind = vstgui_editor_view.GraphKind;
pub const GraphStyleRole = vstgui_editor_view.GraphStyleRole;
pub const GraphSource = enum {
    component,
    controller,
};

pub const GraphAxis = struct {
    minimum: f64,
    maximum: f64,
    scale: GraphScale = .linear,
    label: [*:0]const u8 = "",
};

pub const Graph = struct {
    title: [*:0]const u8,
    kind: GraphKind,
    style: GraphStyleRole = .primary,
    x_axis: GraphAxis,
    y_axis: GraphAxis,
    points: []const GraphPoint = &.{},
    source_id: types.uint32 = 0,
    source: GraphSource = .component,
    dynamic: bool = false,
    maximum_refresh_hz: types.uint32 = 30,
    editable_points: []const EnvelopePoint = &.{},
    point_capacity: types.uint32 = 0,
    minimum_point_count: types.uint32 = 0,
    snap_x: f64 = 0.0,
    snap_y: f64 = 0.0,
    selection_state_id: u32 = 0,
    envelope_state_id: u32 = 0,
};

pub const XYPad = struct {
    title: [*:0]const u8,
    x_parameter_id: vsttypes.ParamID,
    y_parameter_id: vsttypes.ParamID,
    x_label: [*:0]const u8 = "X",
    y_label: [*:0]const u8 = "Y",
};

pub const Preset = struct {
    id: u32,
    name: [*:0]const u8,
};

pub const PresetBrowser = struct {
    title: [*:0]const u8 = "Presets",
    presets: []const Preset,
    search_state_id: u32,
    selection_state_id: u32,
};

pub const MenuItemKind = vstgui_editor_view.MenuItemKind;

pub const MenuItem = struct {
    id: u32 = 0,
    label: ?[*:0]const u8 = null,
    kind: MenuItemKind = .action,
    enabled: bool = true,
    destructive: bool = false,
    checked_state_id: u32 = 0,
};

pub const ActionMenu = struct {
    id: u32,
    title: [*:0]const u8,
    items: []const MenuItem,
};

pub const ActionRole = vstgui_editor_view.ActionRole;
pub const ActionIcon = vstgui_editor_view.ActionIcon;

pub const ActionButton = struct {
    group_id: u32,
    id: u32,
    label: ?[*:0]const u8 = null,
    accessible_label: [*:0]const u8,
    tooltip: ?[*:0]const u8 = null,
    confirmation_label: ?[*:0]const u8 = null,
    failure_label: ?[*:0]const u8 = null,
    role: ActionRole = .secondary,
    icon: ActionIcon = .none,
    enabled: bool = true,
};

pub const ActionButtonError = error{
    InvalidId,
    EmptyAccessibleLabel,
    MissingPresentation,
    InvalidOptionalLabel,
    MissingDestructiveConfirmation,
    DuplicateAction,
    MultiplePrimaryActions,
    UnsafeDestructiveGrouping,
};

pub fn validateActionButtons(actions: []const ActionButton) ActionButtonError!void {
    var primary_count: usize = 0;
    for (actions, 0..) |action, index| {
        if (action.group_id == 0 or action.id == 0) return error.InvalidId;
        if (std.mem.span(action.accessible_label).len == 0) return error.EmptyAccessibleLabel;
        if (action.label == null and action.icon == .none) return error.MissingPresentation;
        if (action.label) |label| if (std.mem.span(label).len == 0) return error.InvalidOptionalLabel;
        if (action.tooltip) |tooltip| if (std.mem.span(tooltip).len == 0) return error.InvalidOptionalLabel;
        if (action.confirmation_label) |label| if (std.mem.span(label).len == 0) return error.InvalidOptionalLabel;
        if (action.failure_label) |label| if (std.mem.span(label).len == 0) return error.InvalidOptionalLabel;
        if (action.role == .destructive and action.confirmation_label == null) {
            return error.MissingDestructiveConfirmation;
        }
        if (action.role == .primary) {
            primary_count += 1;
            if (primary_count > 1) return error.MultiplePrimaryActions;
        }
        for (actions[0..index]) |previous| {
            if (previous.group_id == action.group_id and previous.id == action.id) return error.DuplicateAction;
            if (previous.group_id == action.group_id and
                ((previous.role == .primary and action.role == .destructive) or
                    (previous.role == .destructive and action.role == .primary)))
            {
                return error.UnsafeDestructiveGrouping;
            }
        }
    }
}

pub const Piano = struct {
    title: [*:0]const u8 = "Keyboard",
    first_note: u8 = 48,
    note_count: u8 = 24,
    channel: u8 = 0,
    velocity: f64 = 0.8,
    computer_base_pitch: u8 = 60,
};

pub const StepSequencer = struct {
    title: [*:0]const u8 = "Step Sequencer",
    step_parameter_ids: []const vsttypes.ParamID,
    selection_state_id: u32,
    enabled: bool = true,
    playhead_source_id: u32 = 0,
    maximum_refresh_hz: u32 = 30,
};

pub const FileImporter = struct {
    id: u32,
    title: [*:0]const u8 = "Import Files",
    prompt: [*:0]const u8 = "Drop files here",
    picker_label: [*:0]const u8 = "Choose Audio File",
    picker_title: [*:0]const u8 = "Choose Audio File",
    extensions: []const [*:0]const u8,
    maximum_files: u32 = 1,
    enabled: bool = true,
};
pub const FileDrop = FileImporter;

pub const FileImporterError = error{
    InvalidId,
    EmptyLabel,
    InvalidExtensionCount,
    InvalidExtension,
    DuplicateExtension,
    InvalidFileLimit,
};

pub fn validateFileImporter(importer: FileImporter) FileImporterError!void {
    if (importer.id == 0) return error.InvalidId;
    if (std.mem.span(importer.title).len == 0 or std.mem.span(importer.prompt).len == 0 or
        std.mem.span(importer.picker_label).len == 0 or std.mem.span(importer.picker_title).len == 0)
    {
        return error.EmptyLabel;
    }
    if (importer.extensions.len == 0 or importer.extensions.len > vstgui_editor_view.max_drop_extensions) {
        return error.InvalidExtensionCount;
    }
    if (importer.maximum_files == 0 or importer.maximum_files > vstgui_editor_view.max_drop_files) {
        return error.InvalidFileLimit;
    }
    for (importer.extensions, 0..) |extension, index| {
        const value = std.mem.span(extension);
        if (value.len < 2 or value.len > gui_file_drop.maximum_extension_bytes or value[0] != '.') {
            return error.InvalidExtension;
        }
        for (importer.extensions[0..index]) |previous| {
            if (std.ascii.eqlIgnoreCase(std.mem.span(previous), value)) return error.DuplicateExtension;
        }
    }
}

pub const Asset = vstgui_editor_view.Asset;
pub const AssetFormat = vstgui_editor_view.AssetFormat;
pub const AssetScale = vstgui_editor_view.AssetScale;
pub const Canvas = vstgui_editor_view.Canvas;
pub const DrawingCallbacks = vstgui_editor_view.DrawingCallbacks;
pub const DrawingComponent = vstgui_editor_view.DrawingComponent;
pub const DrawingState = vstgui_editor_view.DrawingState;
pub const DrawRequest = vstgui_editor_view.DrawRequest;
pub const Fonts = vstgui_editor_view.Fonts;
pub const Skin = vstgui_editor_view.Skin;
pub const Theme = vstgui_editor_view.Theme;
pub const Layout = vstgui_editor_view.Layout;
pub const StyleOverride = vstgui_editor_view.StyleOverride;
pub const Group = vstgui_editor_view.Group;
pub const Composition = vstgui_editor_view.Composition;

pub const EditorDescription = struct {
    parameters: []const Parameter,
    meters: []const Meter = &.{},
    graphs: []const Graph = &.{},
    xy_pads: []const XYPad = &.{},
    preset_browsers: []const PresetBrowser = &.{},
    action_menus: []const ActionMenu = &.{},
    action_buttons: []const ActionButton = &.{},
    pianos: []const Piano = &.{},
    step_sequencers: []const StepSequencer = &.{},
    file_importers: []const FileImporter = &.{},
    file_drops: []const FileDrop = &.{},
    skin: Skin = .{},
    composition: Composition = .{},
};
pub const drawAsset = vstgui_editor_view.drawAsset;
pub const fillEllipse = vstgui_editor_view.fillEllipse;
pub const fillRect = vstgui_editor_view.fillRect;
pub const line = vstgui_editor_view.line;
pub const strokeRect = vstgui_editor_view.strokeRect;

pub fn createView(comptime Controller: type, controller: *ivsteditcontroller.IEditController, name: types.FIDString, parameter: Parameter) ?*iplugview.IPlugView {
    return createMultiView(Controller, controller, name, &.{parameter});
}

pub fn createMultiView(comptime Controller: type, controller: *ivsteditcontroller.IEditController, name: types.FIDString, parameters: []const Parameter) ?*iplugview.IPlugView {
    return createMultiViewWithMeters(Controller, controller, name, parameters, &.{});
}

pub fn createMultiViewWithMeters(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    parameters: []const Parameter,
    meters: []const Meter,
) ?*iplugview.IPlugView {
    return createMultiViewWithSkin(Controller, controller, name, parameters, meters, .{});
}

pub fn createMultiViewWithSkin(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    parameters: []const Parameter,
    meters: []const Meter,
    skin: Skin,
) ?*iplugview.IPlugView {
    return createConfiguredView(
        Controller,
        controller,
        name,
        parameters,
        meters,
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        skin,
        .{},
    );
}

pub fn createEditor(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    description: EditorDescription,
) ?*iplugview.IPlugView {
    if (description.file_importers.len != 0 and description.file_drops.len != 0) return null;
    const file_importers = if (description.file_importers.len != 0)
        description.file_importers
    else
        description.file_drops;
    return createConfiguredView(
        Controller,
        controller,
        name,
        description.parameters,
        description.meters,
        description.graphs,
        description.xy_pads,
        description.preset_browsers,
        description.action_menus,
        description.action_buttons,
        description.pianos,
        description.step_sequencers,
        file_importers,
        description.skin,
        description.composition,
    );
}

fn createConfiguredView(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    parameters: []const Parameter,
    meters: []const Meter,
    graphs: []const Graph,
    xy_pads: []const XYPad,
    preset_browsers: []const PresetBrowser,
    action_menus: []const ActionMenu,
    action_buttons: []const ActionButton,
    pianos: []const Piano,
    step_sequencers: []const StepSequencer,
    file_importers: []const FileImporter,
    skin: Skin,
    composition: Composition,
) ?*iplugview.IPlugView {
    if (!std.mem.eql(u8, std.mem.span(name), std.mem.span(ivsteditcontroller.ViewType.kEditor))) return null;
    if (comptime vstgui_adapter_enabled) {
        const Bridge = NativeBridge(Controller);
        var wayland_host: ?*anyopaque = null;
        if (comptime builtin.os.tag == .linux) {
            _ = Controller.createHostInstance(
                controller,
                &iwaylandframe.iwayland_host_iid,
                &iwaylandframe.iwayland_host_iid,
                &wayland_host,
            );
        }
        defer if (wayland_host) |host| {
            const iface: *iwaylandframe.IWaylandHost = @ptrCast(@alignCast(host));
            _ = iface.vtable.release(iface);
        };
        if (parameters.len == 0 or parameters.len > vstgui_editor_view.max_parameters or
            preset_browsers.len > vstgui_editor_view.max_preset_browsers or
            action_menus.len > vstgui_editor_view.max_action_menus or
            action_buttons.len > vstgui_editor_view.max_action_buttons or
            pianos.len > vstgui_editor_view.max_pianos or
            step_sequencers.len > vstgui_editor_view.max_step_sequencers) return null;
        if (file_importers.len > vstgui_editor_view.max_file_drops) return null;
        if (comptime !Controller.hasPresetLoader) {
            if (preset_browsers.len > 0) return null;
        }
        if (comptime !Controller.hasMenuActionHandler) {
            if (action_menus.len > 0) return null;
        }
        if (comptime !Controller.hasActionHandler) {
            if (action_buttons.len > 0) return null;
        }
        validateActionButtons(action_buttons) catch return null;
        if (comptime !Controller.hasFileDropHandler) {
            if (file_importers.len > 0) return null;
        }
        var bindings: [vstgui_editor_view.max_parameters]vstgui_editor_view.ParameterInfoBinding = undefined;
        for (parameters, 0..) |parameter, index| {
            bindings[index] = .{ .id = parameter.id, .control_kind = parameter.control_kind, .info = .{
                .title = parameter.title,
                .units = parameter.units,
                .step_count = parameter.step_count,
                .default_normalized = parameter.default_normalized,
                .tooltip = parameter.tooltip,
                .modulation_normalized = parameter.modulation_normalized orelse 0.0,
                .has_modulation = if (parameter.modulation_normalized != null) 1 else 0,
            } };
        }
        if (meters.len > vstgui_editor_view.max_meters) return null;
        var meter_descriptions: [vstgui_editor_view.max_meters]vstgui_editor_view.MeterDescription = undefined;
        for (meters, 0..) |meter, index| {
            meter_descriptions[index] = .{
                .title = meter.title,
                .kind = meter.kind,
                .first_source_id = meter.first_source_id,
                .second_source_id = meter.second_source_id,
            };
        }
        if (graphs.len > vstgui_editor_view.max_graphs) return null;
        var graph_descriptions: [vstgui_editor_view.max_graphs]vstgui_editor_view.GraphDescription = undefined;
        var persisted_points: [vstgui_editor_view.max_graphs][editor_state.maximum_envelope_points]EnvelopePoint = undefined;
        for (graphs, 0..) |graph, index| {
            var editable_points = graph.editable_points;
            var initial_selected_point_id: u32 = 0;
            if (comptime Controller.hasEditorState) {
                const state = Controller.editorState(controller);
                if (graph.envelope_state_id != 0) {
                    const value = state.get(graph.envelope_state_id) orelse return null;
                    const envelope = switch (value) {
                        .envelope => |stored| stored,
                        else => return null,
                    };
                    for (envelope.slice(), 0..) |point, point_index| {
                        var restored = EnvelopePoint{ .point_id = point.id, .x = point.x, .y = point.y };
                        for (graph.editable_points) |declared| {
                            if (declared.point_id == point.id) {
                                restored.x_parameter_id = declared.x_parameter_id;
                                restored.y_parameter_id = declared.y_parameter_id;
                                restored.parameter_mask = declared.parameter_mask;
                                restored.x_step_count = declared.x_step_count;
                                restored.y_step_count = declared.y_step_count;
                                break;
                            }
                        }
                        persisted_points[index][point_index] = restored;
                    }
                    editable_points = persisted_points[index][0..envelope.len];
                }
                if (graph.selection_state_id != 0) {
                    const value = state.get(graph.selection_state_id) orelse return null;
                    initial_selected_point_id = switch (value) {
                        .point_id => |id| id,
                        .index => |id| id,
                        else => return null,
                    };
                }
            } else if (graph.selection_state_id != 0 or graph.envelope_state_id != 0) return null;
            if (graph.points.len > vstgui_editor_view.max_graph_points or
                editable_points.len > vstgui_editor_view.max_graph_points or
                (graph.dynamic and graph.source_id & vstgui_editor_view.controller_graph_source_flag != 0) or
                graph.x_axis.maximum <= graph.x_axis.minimum or graph.y_axis.maximum <= graph.y_axis.minimum or
                (graph.dynamic and (graph.maximum_refresh_hz == 0 or graph.maximum_refresh_hz > 60)) or
                (graph.point_capacity == 0 and (graph.editable_points.len > 0 or graph.minimum_point_count > 0 or
                    graph.snap_x != 0.0 or graph.snap_y != 0.0)) or
                (graph.point_capacity > 0 and (graph.kind != .envelope or graph.dynamic or graph.points.len > 0 or
                    graph.point_capacity > vstgui_editor_view.max_graph_points or
                    editable_points.len > graph.point_capacity or
                    graph.minimum_point_count > editable_points.len or
                    !std.math.isFinite(graph.snap_x) or !std.math.isFinite(graph.snap_y) or
                    graph.snap_x < 0.0 or graph.snap_y < 0.0))) return null;
            for (editable_points, 0..) |point, point_index| {
                if (point.point_id == 0 or !std.math.isFinite(point.x) or !std.math.isFinite(point.y) or
                    point.parameter_mask & ~@as(types.uint32, 3) != 0 or
                    point.x_step_count < 0 or point.y_step_count < 0 or
                    (point.parameter_mask != 0 and (point.parameter_mask != 3 or
                        point.x_parameter_id == point.y_parameter_id)) or
                    point.x < graph.x_axis.minimum or point.x > graph.x_axis.maximum or
                    point.y < graph.y_axis.minimum or point.y > graph.y_axis.maximum or
                    (point_index > 0 and editable_points[point_index - 1].x > point.x)) return null;
                for (editable_points[0..point_index]) |previous| {
                    if (previous.point_id == point.point_id) return null;
                }
                if (point.parameter_mask == 3) {
                    var found_x = false;
                    var found_y = false;
                    for (parameters) |parameter| {
                        found_x = found_x or parameter.id == point.x_parameter_id;
                        found_y = found_y or parameter.id == point.y_parameter_id;
                    }
                    if (!found_x or !found_y) return null;
                }
            }
            graph_descriptions[index] = .{
                .title = graph.title,
                .kind = graph.kind,
                .style = graph.style,
                .x_axis = .{
                    .minimum = graph.x_axis.minimum,
                    .maximum = graph.x_axis.maximum,
                    .scale = graph.x_axis.scale,
                    .label = graph.x_axis.label,
                },
                .y_axis = .{
                    .minimum = graph.y_axis.minimum,
                    .maximum = graph.y_axis.maximum,
                    .scale = graph.y_axis.scale,
                    .label = graph.y_axis.label,
                },
                .points = if (graph.points.len == 0) null else graph.points.ptr,
                .point_count = @intCast(graph.points.len),
                .source_id = graph.source_id | if (graph.source == .controller)
                    vstgui_editor_view.controller_graph_source_flag
                else
                    0,
                .dynamic = @intFromBool(graph.dynamic),
                .maximum_refresh_hz = graph.maximum_refresh_hz,
                .editable_points = if (editable_points.len == 0) null else editable_points.ptr,
                .editable_point_count = @intCast(editable_points.len),
                .point_capacity = graph.point_capacity,
                .minimum_point_count = graph.minimum_point_count,
                .snap_x = graph.snap_x,
                .snap_y = graph.snap_y,
                .selection_state_id = graph.selection_state_id,
                .envelope_state_id = graph.envelope_state_id,
                .initial_selected_point_id = initial_selected_point_id,
            };
        }
        if (xy_pads.len > vstgui_editor_view.max_xy_pads) return null;
        var xy_pad_descriptions: [vstgui_editor_view.max_xy_pads]vstgui_editor_view.XYPadDescription = undefined;
        for (xy_pads, 0..) |xy_pad, index| {
            if (xy_pad.x_parameter_id == xy_pad.y_parameter_id) return null;
            var found_x = false;
            var found_y = false;
            for (parameters) |parameter| {
                found_x = found_x or parameter.id == xy_pad.x_parameter_id;
                found_y = found_y or parameter.id == xy_pad.y_parameter_id;
            }
            if (!found_x or !found_y) return null;
            xy_pad_descriptions[index] = .{
                .title = xy_pad.title,
                .x_parameter_id = xy_pad.x_parameter_id,
                .y_parameter_id = xy_pad.y_parameter_id,
                .x_label = xy_pad.x_label,
                .y_label = xy_pad.y_label,
            };
        }
        var preset_descriptions: [vstgui_editor_view.max_preset_browsers][vstgui_editor_view.max_presets]vstgui_editor_view.PresetDescription = undefined;
        var browser_descriptions: [vstgui_editor_view.max_preset_browsers]vstgui_editor_view.PresetBrowserDescription = undefined;
        var initial_search: [vstgui_editor_view.max_preset_browsers][editor_state.maximum_text_bytes + 1]u8 = @splat(@splat(0));
        for (preset_browsers, 0..) |browser, browser_index| {
            if (browser.presets.len == 0 or browser.presets.len > vstgui_editor_view.max_presets or
                browser.search_state_id == 0 or browser.selection_state_id == 0 or
                browser.search_state_id == browser.selection_state_id) return null;
            var initial_selection: u32 = 0;
            if (comptime Controller.hasEditorState) {
                const state = Controller.editorState(controller);
                const search_value = state.get(browser.search_state_id) orelse return null;
                const search = switch (search_value) {
                    .text => |text| text,
                    else => return null,
                };
                @memcpy(initial_search[browser_index][0..search.len], search.slice());
                const selection_value = state.get(browser.selection_state_id) orelse return null;
                initial_selection = switch (selection_value) {
                    .index => |id| id,
                    .point_id => |id| id,
                    else => return null,
                };
            } else return null;
            for (browser.presets, 0..) |preset, preset_index| {
                if (preset.id == 0) return null;
                for (browser.presets[0..preset_index]) |previous| if (previous.id == preset.id) return null;
                preset_descriptions[browser_index][preset_index] = .{ .preset_id = preset.id, .name = preset.name };
            }
            browser_descriptions[browser_index] = .{
                .title = browser.title,
                .presets = &preset_descriptions[browser_index],
                .preset_count = @intCast(browser.presets.len),
                .search_state_id = browser.search_state_id,
                .selection_state_id = browser.selection_state_id,
                .initial_search = @ptrCast(&initial_search[browser_index]),
                .initial_selection = initial_selection,
            };
        }
        var menu_items: [vstgui_editor_view.max_action_menus][vstgui_editor_view.max_menu_items]vstgui_editor_view.MenuItemDescription = undefined;
        var menu_descriptions: [vstgui_editor_view.max_action_menus]vstgui_editor_view.ActionMenuDescription = undefined;
        for (action_menus, 0..) |menu, menu_index| {
            if (menu.id == 0 or std.mem.span(menu.title).len == 0 or menu.items.len == 0 or
                menu.items.len > vstgui_editor_view.max_menu_items) return null;
            for (action_menus[0..menu_index]) |previous| if (previous.id == menu.id) return null;
            for (menu.items, 0..) |item, item_index| {
                var checked = false;
                switch (item.kind) {
                    .separator => {
                        if (item.id != 0 or item.label != null or item.destructive or
                            item.checked_state_id != 0) return null;
                    },
                    .action => {
                        if (item.id == 0 or item.label == null or std.mem.span(item.label.?).len == 0 or
                            item.checked_state_id != 0) return null;
                    },
                    .toggle => {
                        if (item.id == 0 or item.label == null or std.mem.span(item.label.?).len == 0 or
                            item.checked_state_id == 0 or item.destructive) return null;
                        if (comptime Controller.hasEditorState) {
                            checked = switch (Controller.editorState(controller).get(item.checked_state_id) orelse return null) {
                                .boolean => |value| value,
                                else => return null,
                            };
                        } else return null;
                    },
                }
                if (item.kind != .separator) {
                    for (menu.items[0..item_index]) |previous| {
                        if (previous.kind != .separator and previous.id == item.id) return null;
                    }
                }
                menu_items[menu_index][item_index] = .{
                    .item_id = item.id,
                    .label = item.label,
                    .kind = item.kind,
                    .enabled = @intFromBool(item.kind != .separator and item.enabled),
                    .destructive = @intFromBool(item.destructive),
                    .checked_state_id = item.checked_state_id,
                    .initial_checked = @intFromBool(checked),
                };
            }
            menu_descriptions[menu_index] = .{
                .menu_id = menu.id,
                .title = menu.title,
                .items = &menu_items[menu_index],
                .item_count = @intCast(menu.items.len),
            };
        }
        var piano_descriptions: [vstgui_editor_view.max_pianos]vstgui_editor_view.PianoDescription = undefined;
        for (pianos, 0..) |piano, index| {
            if (std.mem.span(piano.title).len == 0 or piano.note_count == 0 or piano.note_count > 48 or
                @as(usize, piano.first_note) + @as(usize, piano.note_count) > 128 or
                piano.channel > 15 or !std.math.isFinite(piano.velocity) or
                piano.velocity <= 0.0 or piano.velocity > 1.0) return null;
            piano_descriptions[index] = .{
                .title = piano.title,
                .first_note = piano.first_note,
                .note_count = piano.note_count,
                .channel = piano.channel,
                .velocity = piano.velocity,
                .computer_base_pitch = piano.computer_base_pitch,
            };
        }
        var step_parameter_ids: [vstgui_editor_view.max_step_sequencers][vstgui_editor_view.max_steps]vsttypes.ParamID = undefined;
        var step_sequencer_descriptions: [vstgui_editor_view.max_step_sequencers]vstgui_editor_view.StepSequencerDescription = undefined;
        for (step_sequencers, 0..) |sequencer, sequencer_index| {
            if (std.mem.span(sequencer.title).len == 0 or sequencer.step_parameter_ids.len == 0 or
                sequencer.step_parameter_ids.len > vstgui_editor_view.max_steps or sequencer.selection_state_id == 0 or
                (sequencer.playhead_source_id != 0 and
                    (sequencer.maximum_refresh_hz == 0 or sequencer.maximum_refresh_hz > 60))) return null;
            var initial_selection: u32 = 0;
            if (comptime Controller.hasEditorState) {
                initial_selection = switch (Controller.editorState(controller).get(sequencer.selection_state_id) orelse return null) {
                    .index => |value| value,
                    else => return null,
                };
            } else return null;
            const valid_mask: u32 = if (sequencer.step_parameter_ids.len == 32)
                std.math.maxInt(u32)
            else
                (@as(u32, 1) << @intCast(sequencer.step_parameter_ids.len)) - 1;
            if (initial_selection & ~valid_mask != 0) return null;
            var initial_active: u32 = 0;
            for (sequencer.step_parameter_ids, 0..) |parameter_id, step| {
                var found = false;
                const parameter_count = controller.vtable.getParameterCount(controller);
                var parameter_index: types.int32 = 0;
                while (parameter_index < parameter_count) : (parameter_index += 1) {
                    var info: ivsteditcontroller.ParameterInfo = undefined;
                    if (controller.vtable.getParameterInfo(controller, parameter_index, &info) != types.kResultOk) return null;
                    if (info.id != parameter_id) continue;
                    if (info.stepCount != 1) return null;
                    found = true;
                    break;
                }
                if (!found) return null;
                for (sequencer.step_parameter_ids[0..step]) |previous| if (previous == parameter_id) return null;
                step_parameter_ids[sequencer_index][step] = parameter_id;
                if (controller.vtable.getParamNormalized(controller, parameter_id) >= 0.5) {
                    initial_active |= @as(u32, 1) << @intCast(step);
                }
            }
            step_sequencer_descriptions[sequencer_index] = .{
                .title = sequencer.title,
                .parameter_ids = &step_parameter_ids[sequencer_index],
                .step_count = @intCast(sequencer.step_parameter_ids.len),
                .selection_state_id = sequencer.selection_state_id,
                .initial_selection_mask = initial_selection,
                .initial_active_mask = initial_active,
                .enabled = @intFromBool(sequencer.enabled),
                .playhead_source_id = sequencer.playhead_source_id,
                .maximum_refresh_hz = sequencer.maximum_refresh_hz,
            };
        }
        var file_drop_descriptions: [vstgui_editor_view.max_file_drops]vstgui_editor_view.FileDropDescription = undefined;
        for (file_importers, 0..) |drop, index| {
            validateFileImporter(drop) catch return null;
            for (file_importers[0..index]) |previous| if (previous.id == drop.id) return null;
            file_drop_descriptions[index] = .{
                .drop_id = drop.id,
                .title = drop.title,
                .prompt = drop.prompt,
                .picker_label = drop.picker_label,
                .picker_title = drop.picker_title,
                .extensions = drop.extensions.ptr,
                .extension_count = @intCast(drop.extensions.len),
                .maximum_files = drop.maximum_files,
                .enabled = @intFromBool(drop.enabled),
            };
        }
        var action_button_descriptions: [vstgui_editor_view.max_action_buttons]vstgui_editor_view.ActionButtonDescription = undefined;
        for (action_buttons, 0..) |action, index| {
            action_button_descriptions[index] = .{
                .group_id = action.group_id,
                .action_id = action.id,
                .label = action.label,
                .accessible_label = action.accessible_label,
                .tooltip = action.tooltip,
                .confirmation_label = action.confirmation_label,
                .failure_label = action.failure_label,
                .role = action.role,
                .icon = action.icon,
                .enabled = @intFromBool(action.enabled),
            };
        }
        const telemetry_source = if (comptime @hasDecl(Controller, "retainGuiTelemetry"))
            Controller.retainGuiTelemetry(controller)
        else
            null;
        return vstgui_editor_view.create(controller, bindings[0..parameters.len], meter_descriptions[0..meters.len], graph_descriptions[0..graphs.len], xy_pad_descriptions[0..xy_pads.len], browser_descriptions[0..preset_browsers.len], menu_descriptions[0..action_menus.len], piano_descriptions[0..pianos.len], step_sequencer_descriptions[0..step_sequencers.len], file_drop_descriptions[0..file_importers.len], action_button_descriptions[0..action_buttons.len], skin, composition, .{
            .userdata = controller,
            .begin_edit = Bridge.beginEdit,
            .perform_edit = Bridge.performEdit,
            .end_edit = Bridge.endEdit,
            .format_value = Bridge.formatValue,
            .parse_value = Bridge.parseValue,
            .show_context_menu = Bridge.showContextMenu,
            .store_editor_index = Bridge.storeEditorIndex,
            .store_editor_envelope = Bridge.storeEditorEnvelope,
            .store_editor_text = Bridge.storeEditorText,
            .load_preset = Bridge.loadPreset,
            .store_editor_bool = Bridge.storeEditorBool,
            .invoke_menu_action = Bridge.invokeMenuAction,
            .invoke_action = Bridge.invokeAction,
            .send_note = Bridge.sendNote,
            .drop_files = Bridge.dropFiles,
            .import_files = Bridge.importFiles,
            .load_file_import = Bridge.loadFileImport,
            .command_file_import = Bridge.commandFileImport,
        }, .{
            .userdata = controller,
            .subscribe = Bridge.subscribe,
            .unsubscribe = Bridge.unsubscribe,
        }, wayland_host, telemetry_source, .{
            .userdata = controller,
            .load = Bridge.loadGuiGraph,
        });
    }

    const view = ProtocolView.create() orelse return null;
    if (view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView) != types.kResultOk or
        view.addPlatform(iplugview.PlatformType.kPlatformTypeHWND) != types.kResultOk or
        view.addPlatform(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID) != types.kResultOk or
        view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID) != types.kResultOk)
    {
        _ = view.iface.vtable.release(&view.iface);
        return null;
    }
    return view.asInterface();
}

fn NativeBridge(comptime Controller: type) type {
    return struct {
        fn controller(userdata: ?*anyopaque) ?*ivsteditcontroller.IEditController {
            return @ptrCast(@alignCast(userdata orelse return null));
        }

        fn beginEdit(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID) callconv(.c) void {
            _ = Controller.beginEdit(controller(userdata) orelse return, parameter_id);
        }

        fn performEdit(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, value: f64) callconv(.c) types.int32 {
            return Controller.performEdit(controller(userdata) orelse return types.kResultFalse, parameter_id, value);
        }

        fn endEdit(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID) callconv(.c) void {
            _ = Controller.endEdit(controller(userdata) orelse return, parameter_id);
        }

        fn formatValue(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, value: f64, output: [*]u8, capacity: types.uint32) callconv(.c) types.int32 {
            if (capacity == 0) return -1;
            var utf16: vsttypes.String128 = @splat(0);
            const iface = controller(userdata) orelse return -1;
            if (iface.vtable.getParamStringByValue(iface, parameter_id, value, &utf16) != types.kResultOk) return -1;
            const end = std.mem.indexOfScalar(vsttypes.TChar, &utf16, 0) orelse utf16.len;
            const available: usize = @intCast(capacity - 1);
            const written = std.unicode.utf16LeToUtf8(output[0..available], utf16[0..end]) catch return -1;
            output[written] = 0;
            return @intCast(written);
        }

        fn parseValue(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, text: [*:0]const u8, normalized: *f64) callconv(.c) types.int32 {
            var utf16: vsttypes.String128 = @splat(0);
            const written = std.unicode.utf8ToUtf16Le(utf16[0 .. utf16.len - 1], std.mem.span(text)) catch return -1;
            utf16[written] = 0;
            const iface = controller(userdata) orelse return -1;
            return if (iface.vtable.getParamValueByString(iface, parameter_id, &utf16, normalized) == types.kResultOk) 0 else -1;
        }

        fn showContextMenu(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, x: types.int32, y: types.int32) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            const menu = Controller.createContextMenu(iface, null, &parameter_id) orelse return -1;
            defer _ = menu.vtable.release(menu);
            return if (menu.vtable.popup(menu, @intCast(@max(0, x)), @intCast(@max(0, y))) == types.kResultOk) 0 else -1;
        }

        fn storeEditorIndex(userdata: ?*anyopaque, field_id: u32, value: u32) callconv(.c) types.int32 {
            if (comptime !Controller.hasEditorState) return -1;
            const iface = controller(userdata) orelse return -1;
            Controller.editorState(iface).setUnsigned(field_id, value) catch return -1;
            return 0;
        }

        fn storeEditorEnvelope(userdata: ?*anyopaque, field_id: u32, points: [*]const EnvelopePoint, count: u32) callconv(.c) types.int32 {
            if (comptime !Controller.hasEditorState) return -1;
            if (count > editor_state.maximum_envelope_points) return -1;
            var stored: [editor_state.maximum_envelope_points]editor_state.Point = undefined;
            for (points[0..count], 0..) |point, index| stored[index] = .{ .id = point.point_id, .x = point.x, .y = point.y };
            const envelope = editor_state.Envelope.init(stored[0..count]) catch return -1;
            const iface = controller(userdata) orelse return -1;
            Controller.editorState(iface).set(field_id, .{ .envelope = envelope }) catch return -1;
            return 0;
        }

        fn storeEditorText(userdata: ?*anyopaque, field_id: u32, text: [*:0]const u8) callconv(.c) types.int32 {
            if (comptime !Controller.hasEditorState) return -1;
            const value = editor_state.Text.init(std.mem.span(text)) catch return -1;
            const iface = controller(userdata) orelse return -1;
            Controller.editorState(iface).set(field_id, .{ .text = value }) catch return -1;
            return 0;
        }

        fn loadPreset(userdata: ?*anyopaque, preset_id: u32) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            return if (Controller.loadPreset(iface, preset_id) == types.kResultOk) 0 else -1;
        }

        fn storeEditorBool(userdata: ?*anyopaque, field_id: u32, value: types.int32) callconv(.c) types.int32 {
            if (comptime !Controller.hasEditorState) return -1;
            const iface = controller(userdata) orelse return -1;
            Controller.editorState(iface).set(field_id, .{ .boolean = value != 0 }) catch return -1;
            return 0;
        }

        fn invokeMenuAction(
            userdata: ?*anyopaque,
            menu_id: u32,
            item_id: u32,
            checked: types.int32,
        ) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            return if (Controller.performMenuAction(iface, menu_id, item_id, checked != 0) == types.kResultOk) 0 else -1;
        }

        fn invokeAction(
            userdata: ?*anyopaque,
            group_id: u32,
            action_id: u32,
        ) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            const result = Controller.performAction(iface, group_id, action_id);
            return if (result == types.kResultOk) 0 else -1;
        }

        fn dropFiles(
            userdata: ?*anyopaque,
            drop_id: types.uint32,
            paths: [*]const [*:0]const u8,
            count: types.uint32,
        ) callconv(.c) types.int32 {
            if (count == 0 or count > vstgui_editor_view.max_drop_files) return -1;
            const iface = controller(userdata) orelse return -1;
            var slices: [vstgui_editor_view.max_drop_files][]const u8 = undefined;
            for (0..count) |index| slices[index] = std.mem.span(paths[index]);
            return if (Controller.handleFileDrop(iface, drop_id, slices[0..count]) == types.kResultOk) 0 else -1;
        }

        fn importFiles(
            userdata: ?*anyopaque,
            drop_id: types.uint32,
            entry_point: vstgui_editor_view.FileImportEntryPoint,
            paths: [*]const [*:0]const u8,
            count: types.uint32,
        ) callconv(.c) types.int32 {
            if (count == 0 or count > vstgui_editor_view.max_drop_files) return -1;
            const iface = controller(userdata) orelse return -1;
            var slices: [vstgui_editor_view.max_drop_files][]const u8 = undefined;
            for (0..count) |index| slices[index] = std.mem.span(paths[index]);
            return if (Controller.handleFileImport(
                iface,
                drop_id,
                @enumFromInt(@intFromEnum(entry_point)),
                slices[0..count],
            ) == types.kResultOk) 0 else -1;
        }

        fn loadFileImport(
            userdata: ?*anyopaque,
            drop_id: types.uint32,
            output: *vstgui_editor_view.FileImportSnapshot,
        ) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            const snapshot = Controller.loadFileImport(iface, drop_id) orelse return -1;
            output.* = .{
                .status = @enumFromInt(@intFromEnum(snapshot.import.status)),
                .failure = @enumFromInt(@intFromEnum(snapshot.failure)),
                .entry_point = @enumFromInt(@intFromEnum(snapshot.import.entry_point)),
                .progress = snapshot.import.progress(),
                .generation = snapshot.import.generation,
                .sample_rate = snapshot.sample_rate,
                .channels = snapshot.channels,
                .sample_frames = snapshot.sample_frames,
                .preview_points = @intCast(snapshot.preview_points),
            };
            return 0;
        }

        fn commandFileImport(
            userdata: ?*anyopaque,
            drop_id: types.uint32,
            command: vstgui_editor_view.FileImportCommand,
        ) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            return if (Controller.performFileImportCommand(
                iface,
                drop_id,
                @enumFromInt(@intFromEnum(command)),
            ) == types.kResultOk) 0 else -1;
        }

        fn loadGuiGraph(
            userdata: ?*anyopaque,
            source_id: types.uint32,
            output: [*]gui_graph.Point,
            capacity: types.uint32,
        ) callconv(.c) types.uint32 {
            const iface = controller(userdata) orelse return 0;
            return @intCast(Controller.loadGuiGraph(iface, source_id, output[0..capacity]));
        }

        fn sendNote(
            userdata: ?*anyopaque,
            channel: types.int32,
            pitch: types.int32,
            velocity: f64,
            pressed: types.int32,
        ) callconv(.c) types.int32 {
            if (channel < 0 or channel > 15 or pitch < 0 or pitch > 127) return -1;
            const iface = controller(userdata) orelse return -1;
            return if (Controller.sendGuiNote(iface, .{
                .channel = @intCast(channel),
                .pitch = @intCast(pitch),
                .velocity = velocity,
                .pressed = pressed != 0,
            }) == types.kResultOk) 0 else -1;
        }

        fn subscribe(userdata: *anyopaque, editor: *anyopaque) bool {
            const iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(userdata));
            return Controller.addParameterObserver(iface, .{ .userdata = editor, .changed = parameterChanged });
        }

        fn unsubscribe(userdata: *anyopaque, editor: *anyopaque) void {
            const iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(userdata));
            Controller.removeParameterObserver(iface, editor);
        }

        fn parameterChanged(editor: *anyopaque, parameter_id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) void {
            vstgui_editor_view.setParameter(editor, parameter_id, value);
        }
    };
}

test "file importer declaration validates bounded picker and drop configuration" {
    try validateFileImporter(.{ .id = 1, .extensions = &.{ ".wav", ".aiff" }, .maximum_files = 2 });
    try std.testing.expectError(error.InvalidId, validateFileImporter(.{ .id = 0, .extensions = &.{".wav"} }));
    try std.testing.expectError(error.InvalidExtension, validateFileImporter(.{ .id = 1, .extensions = &.{"wav"} }));
    try std.testing.expectError(error.DuplicateExtension, validateFileImporter(.{ .id = 1, .extensions = &.{ ".wav", ".WAV" } }));
    try std.testing.expectError(error.InvalidFileLimit, validateFileImporter(.{ .id = 1, .extensions = &.{".wav"}, .maximum_files = 0 }));
}

test "action buttons require one dominant action and safe destructive grouping" {
    try validateActionButtons(&.{
        .{ .group_id = 1, .id = 1, .label = "Apply", .accessible_label = "Apply changes", .role = .primary },
        .{ .group_id = 2, .id = 2, .icon = .clear, .accessible_label = "Clear", .role = .destructive, .confirmation_label = "Confirm Clear" },
    });
    try std.testing.expectError(error.MissingPresentation, validateActionButtons(&.{
        .{ .group_id = 1, .id = 1, .accessible_label = "Invisible" },
    }));
    try std.testing.expectError(error.MultiplePrimaryActions, validateActionButtons(&.{
        .{ .group_id = 1, .id = 1, .label = "One", .accessible_label = "One", .role = .primary },
        .{ .group_id = 2, .id = 2, .label = "Two", .accessible_label = "Two", .role = .primary },
    }));
    try std.testing.expectError(error.MissingDestructiveConfirmation, validateActionButtons(&.{
        .{ .group_id = 1, .id = 1, .label = "Clear", .accessible_label = "Clear", .role = .destructive },
    }));
    try std.testing.expectError(error.UnsafeDestructiveGrouping, validateActionButtons(&.{
        .{ .group_id = 1, .id = 1, .label = "Apply", .accessible_label = "Apply", .role = .primary },
        .{ .group_id = 1, .id = 2, .label = "Clear", .accessible_label = "Clear", .role = .destructive, .confirmation_label = "Confirm Clear" },
    }));
}
