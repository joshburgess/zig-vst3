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
const gui_progress = @import("zig-vst3-plugin-core").gui_progress;
const gui_range_selection = @import("zig-vst3-plugin-core").gui_range_selection;
const gui_viewport = @import("zig-vst3-plugin-core").gui_viewport;
const gui_telemetry_source = @import("gui_telemetry_source.zig");
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
pub const GraphHandle = struct {
    id: u32,
    name: [*:0]const u8,
    x_parameter_id: vsttypes.ParamID,
    y_parameter_id: vsttypes.ParamID,
    x_step_count: types.int32 = 0,
    y_step_count: types.int32 = 0,
    adjustment_parameter_id: ?vsttypes.ParamID = null,
    adjustment_label: [*:0]const u8 = "",
    adjustment_step: f64 = 0.01,
    enabled_parameter_id: ?vsttypes.ParamID = null,
    highlight_group_index: ?u32 = null,
};
pub const GraphLayer = struct {
    style: GraphStyleRole = .secondary,
    kind: GraphKind = .transfer_function,
    points: []const GraphPoint = &.{},
    source_id: types.uint32 = 0,
    source: GraphSource = .component,
    dynamic: bool = false,
    parameter_driven: bool = false,
    y_axis: ?GraphAxis = null,
    disabled: bool = false,
};
pub const GraphScale = vstgui_editor_view.GraphScale;
pub const GraphKind = vstgui_editor_view.GraphKind;
pub const GraphStyleRole = vstgui_editor_view.GraphStyleRole;
pub const GraphSource = enum {
    component,
    controller,
};

fn validGraphAxis(axis: GraphAxis) bool {
    return std.math.isFinite(axis.minimum) and
        std.math.isFinite(axis.maximum) and
        axis.maximum > axis.minimum and
        (axis.scale != .logarithmic or axis.minimum > 0.0);
}

pub const ViewportAxes = gui_viewport.Axes;
pub const RangeSelectionHandle = gui_range_selection.Handle;

pub const Viewport = struct {
    axes: ViewportAxes = .horizontal,
    minimum_zoom: f64 = 1.0,
    maximum_zoom: f64 = 32.0,
    initial_zoom: f64 = 1.0,
    initial_x_offset: f64 = 0.0,
    initial_y_offset: f64 = 0.0,
    zoom_step: f64 = 1.25,
    scroll_step: f64 = 0.1,
    zoom_state_id: u32 = 0,
    x_offset_state_id: u32 = 0,
    y_offset_state_id: u32 = 0,

    pub fn config(self: Viewport) gui_viewport.Config {
        return .{
            .axes = self.axes,
            .minimum_zoom = self.minimum_zoom,
            .maximum_zoom = self.maximum_zoom,
            .initial_zoom = self.initial_zoom,
            .initial_x_offset = self.initial_x_offset,
            .initial_y_offset = self.initial_y_offset,
            .zoom_step = self.zoom_step,
            .scroll_step = self.scroll_step,
        };
    }

    pub fn validate(self: Viewport) !void {
        try self.config().validate();
        if (!self.axes.includesHorizontal() and self.x_offset_state_id != 0) return error.InvalidViewportStateField;
        if (!self.axes.includesVertical() and self.y_offset_state_id != 0) return error.InvalidViewportStateField;
        const ids = [_]u32{ self.zoom_state_id, self.x_offset_state_id, self.y_offset_state_id };
        for (ids, 0..) |id, index| {
            if (id == 0) continue;
            for (ids[0..index]) |previous| {
                if (previous == id) return error.DuplicateViewportStateField;
            }
        }
    }
};

pub const RangeSelection = struct {
    initial_start: f64 = 0.0,
    initial_end: f64 = 1.0,
    minimum_span: f64 = 0.0,
    step: f64 = 0.01,
    start_state_id: u32 = 0,
    end_state_id: u32 = 0,
    start_parameter_id: ?vsttypes.ParamID = null,
    end_parameter_id: ?vsttypes.ParamID = null,

    pub fn config(self: RangeSelection, axis: GraphAxis) gui_range_selection.Config {
        return .{
            .minimum = axis.minimum,
            .maximum = axis.maximum,
            .initial_start = self.initial_start,
            .initial_end = self.initial_end,
            .minimum_span = self.minimum_span,
            .step = self.step,
        };
    }

    pub fn validate(self: RangeSelection, axis: GraphAxis) !void {
        try self.config(axis).validate();
        if ((self.start_state_id == 0) != (self.end_state_id == 0)) return error.IncompleteRangeSelectionState;
        if (self.start_state_id != 0 and self.start_state_id == self.end_state_id) {
            return error.DuplicateRangeSelectionStateField;
        }
        if ((self.start_parameter_id == null) != (self.end_parameter_id == null)) {
            return error.IncompleteRangeSelectionParameters;
        }
        if (self.start_parameter_id != null and self.start_parameter_id == self.end_parameter_id) {
            return error.DuplicateRangeSelectionParameter;
        }
        if (self.start_state_id != 0 and self.start_parameter_id != null) {
            return error.ConflictingRangeSelectionPersistence;
        }
    }
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
    viewport: ?Viewport = null,
    range_selection: ?RangeSelection = null,
    secondary_range_selection: ?RangeSelection = null,
    handles: []const GraphHandle = &.{},
    parameter_driven: bool = false,
    layers: []const GraphLayer = &.{},
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
    success_focus_importer_id: u32 = 0,
    ready_importer_id: u32 = 0,
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

fn validActionImporterTargets(actions: []const ActionButton, importers: []const FileImporter) bool {
    for (actions) |action| {
        const targets = [_]u32{ action.success_focus_importer_id, action.ready_importer_id };
        for (targets) |target| {
            if (target == 0) continue;
            for (importers) |importer| {
                if (importer.id == target) break;
            } else return false;
        }
    }
    return true;
}

pub const EditableLabel = struct {
    field_id: u32,
    label: [*:0]const u8,
    accessible_label: [*:0]const u8,
    placeholder: [*:0]const u8 = "",
    error_text: [*:0]const u8 = "Value was not accepted",
    maximum_bytes: u32 = editor_state.maximum_text_bytes,
    enabled: bool = true,
    read_only: bool = false,
    maximum_refresh_hz: u32 = 10,
};

pub const EditableLabelError = error{
    InvalidFieldId,
    EmptyLabel,
    InvalidMaximumBytes,
    InvalidRefreshRate,
    DuplicateFieldId,
};

pub fn validateEditableLabels(labels: []const EditableLabel) EditableLabelError!void {
    for (labels, 0..) |label, index| {
        if (label.field_id == 0) return error.InvalidFieldId;
        if (std.mem.span(label.label).len == 0 or std.mem.span(label.accessible_label).len == 0 or
            std.mem.span(label.error_text).len == 0) return error.EmptyLabel;
        if (label.maximum_bytes == 0 or label.maximum_bytes > editor_state.maximum_text_bytes) {
            return error.InvalidMaximumBytes;
        }
        if (label.read_only and (label.maximum_refresh_hz == 0 or label.maximum_refresh_hz > 60)) {
            return error.InvalidRefreshRate;
        }
        for (labels[0..index]) |previous| {
            if (previous.field_id == label.field_id) return error.DuplicateFieldId;
        }
    }
}

pub const ProgressMode = gui_progress.Mode;
pub const ProgressState = gui_progress.State;
pub const ProgressSnapshot = gui_progress.Snapshot;

pub const ProgressIndicator = struct {
    source_id: u32,
    label: [*:0]const u8,
    accessible_label: [*:0]const u8,
    idle_text: [*:0]const u8 = "Waiting",
    running_text: [*:0]const u8 = "Working",
    complete_text: [*:0]const u8 = "Complete",
    failure_text: [*:0]const u8 = "Could not finish",
    maximum_refresh_hz: u32 = 20,
};

pub const ProgressIndicatorError = error{
    InvalidSourceId,
    EmptyLabel,
    InvalidRefreshRate,
    DuplicateSourceId,
};

pub fn validateProgressIndicators(indicators: []const ProgressIndicator) ProgressIndicatorError!void {
    for (indicators, 0..) |indicator, index| {
        if (indicator.source_id == 0) return error.InvalidSourceId;
        if (std.mem.span(indicator.label).len == 0 or std.mem.span(indicator.accessible_label).len == 0 or
            std.mem.span(indicator.idle_text).len == 0 or std.mem.span(indicator.running_text).len == 0 or
            std.mem.span(indicator.complete_text).len == 0 or std.mem.span(indicator.failure_text).len == 0)
        {
            return error.EmptyLabel;
        }
        if (indicator.maximum_refresh_hz == 0 or indicator.maximum_refresh_hz > 60) {
            return error.InvalidRefreshRate;
        }
        for (indicators[0..index]) |previous| {
            if (previous.source_id == indicator.source_id) return error.DuplicateSourceId;
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
    editable_labels: []const EditableLabel = &.{},
    progress_indicators: []const ProgressIndicator = &.{},
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
        description.editable_labels,
        description.progress_indicators,
        description.pianos,
        description.step_sequencers,
        file_importers,
        description.skin,
        description.composition,
    );
}

fn makeRangeSelectionDescription(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    selection: ?RangeSelection,
    axis: GraphAxis,
    parameters: []const Parameter,
) !vstgui_editor_view.RangeSelectionDescription {
    const value = selection orelse return .{};
    try value.validate(axis);
    var config = value.config(axis);
    if (comptime Controller.hasEditorState) {
        const state = Controller.editorState(controller);
        if (value.start_state_id != 0) {
            const restored_start = switch (state.get(value.start_state_id) orelse return error.InvalidRangeSelectionState) {
                .scalar => |stored| stored,
                else => return error.InvalidRangeSelectionState,
            };
            const restored_end = switch (state.get(value.end_state_id) orelse return error.InvalidRangeSelectionState) {
                .scalar => |stored| stored,
                else => return error.InvalidRangeSelectionState,
            };
            config.initial_start = std.math.clamp(restored_start, config.minimum, config.maximum - config.minimum_span);
            config.initial_end = std.math.clamp(restored_end, config.initial_start + config.minimum_span, config.maximum);
        }
    } else if (value.start_state_id != 0) return error.MissingEditorState;

    var parameter_bound = false;
    var start_parameter_id: vsttypes.ParamID = 0;
    var end_parameter_id: vsttypes.ParamID = 0;
    var start_step_count: types.int32 = 0;
    var end_step_count: types.int32 = 0;
    if (value.start_parameter_id) |start_id| {
        const end_id = value.end_parameter_id.?;
        var found_start = false;
        var found_end = false;
        for (parameters) |parameter| {
            if (parameter.id == start_id) {
                found_start = true;
                start_step_count = parameter.step_count;
            }
            if (parameter.id == end_id) {
                found_end = true;
                end_step_count = parameter.step_count;
            }
        }
        if (!found_start or !found_end) return error.UnknownRangeSelectionParameter;
        const axis_span = axis.maximum - axis.minimum;
        config.initial_start = axis.minimum + Controller.getNormalized(controller, start_id) * axis_span;
        config.initial_end = axis.minimum + Controller.getNormalized(controller, end_id) * axis_span;
        parameter_bound = true;
        start_parameter_id = start_id;
        end_parameter_id = end_id;
    }
    try config.validate();
    return .{
        .enabled = 1,
        .initial_start = config.initial_start,
        .initial_end = config.initial_end,
        .minimum_span = config.minimum_span,
        .step = config.step,
        .start_state_id = value.start_state_id,
        .end_state_id = value.end_state_id,
        .parameter_bound = @intFromBool(parameter_bound),
        .start_parameter_id = start_parameter_id,
        .end_parameter_id = end_parameter_id,
        .start_step_count = start_step_count,
        .end_step_count = end_step_count,
    };
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
    editable_labels: []const EditableLabel,
    progress_indicators: []const ProgressIndicator,
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
            editable_labels.len > vstgui_editor_view.max_editable_labels or
            progress_indicators.len > vstgui_editor_view.max_progress_indicators or
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
        if (!validActionImporterTargets(action_buttons, file_importers)) return null;
        if (comptime !Controller.hasEditorState) {
            if (editable_labels.len > 0) return null;
        }
        if (comptime !Controller.hasGuiProgressSource) {
            if (progress_indicators.len > 0) return null;
        }
        validateEditableLabels(editable_labels) catch return null;
        validateProgressIndicators(progress_indicators) catch return null;
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
        var graph_handles: [vstgui_editor_view.max_graphs][vstgui_editor_view.max_graph_handles]vstgui_editor_view.GraphHandleDescription = undefined;
        var graph_layers: [vstgui_editor_view.max_graphs][vstgui_editor_view.max_graph_layers]vstgui_editor_view.GraphLayerDescription = undefined;
        for (graphs, 0..) |graph, index| {
            var editable_points = graph.editable_points;
            var initial_selected_point_id: u32 = 0;
            var viewport_description = vstgui_editor_view.ViewportDescription{};
            const range_selection_description = makeRangeSelectionDescription(
                Controller,
                controller,
                graph.range_selection,
                graph.x_axis,
                parameters,
            ) catch return null;
            const secondary_range_selection_description = makeRangeSelectionDescription(
                Controller,
                controller,
                graph.secondary_range_selection,
                graph.x_axis,
                parameters,
            ) catch return null;
            const has_persistent_viewport = if (graph.viewport) |viewport|
                viewport.zoom_state_id != 0 or viewport.x_offset_state_id != 0 or viewport.y_offset_state_id != 0
            else
                false;
            const has_persistent_range_selection = range_selection_description.start_state_id != 0 or
                secondary_range_selection_description.start_state_id != 0;
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
            } else if (graph.selection_state_id != 0 or graph.envelope_state_id != 0 or
                has_persistent_viewport or has_persistent_range_selection) return null;
            if (graph.viewport) |viewport| {
                viewport.validate() catch return null;
                var config = viewport.config();
                if (comptime Controller.hasEditorState) {
                    const state = Controller.editorState(controller);
                    if (viewport.zoom_state_id != 0) {
                        config.initial_zoom = switch (state.get(viewport.zoom_state_id) orelse return null) {
                            .scalar => |value| std.math.clamp(value, config.minimum_zoom, config.maximum_zoom),
                            else => return null,
                        };
                    }
                    const maximum_offset = 1.0 - 1.0 / config.initial_zoom;
                    if (viewport.x_offset_state_id != 0) {
                        config.initial_x_offset = switch (state.get(viewport.x_offset_state_id) orelse return null) {
                            .scalar => |value| std.math.clamp(value, 0.0, maximum_offset),
                            else => return null,
                        };
                    }
                    if (viewport.y_offset_state_id != 0) {
                        config.initial_y_offset = switch (state.get(viewport.y_offset_state_id) orelse return null) {
                            .scalar => |value| std.math.clamp(value, 0.0, maximum_offset),
                            else => return null,
                        };
                    }
                }
                config.validate() catch return null;
                viewport_description = .{
                    .enabled = 1,
                    .axes = @enumFromInt(@intFromEnum(config.axes)),
                    .minimum_zoom = config.minimum_zoom,
                    .maximum_zoom = config.maximum_zoom,
                    .initial_zoom = config.initial_zoom,
                    .initial_x_offset = config.initial_x_offset,
                    .initial_y_offset = config.initial_y_offset,
                    .zoom_step = config.zoom_step,
                    .scroll_step = config.scroll_step,
                    .zoom_state_id = viewport.zoom_state_id,
                    .x_offset_state_id = viewport.x_offset_state_id,
                    .y_offset_state_id = viewport.y_offset_state_id,
                };
            }
            const persistent_scalar_ids = [_]u32{
                viewport_description.zoom_state_id,
                viewport_description.x_offset_state_id,
                viewport_description.y_offset_state_id,
                range_selection_description.start_state_id,
                range_selection_description.end_state_id,
                secondary_range_selection_description.start_state_id,
                secondary_range_selection_description.end_state_id,
            };
            for (persistent_scalar_ids, 0..) |field_id, field_index| {
                if (field_id == 0) continue;
                for (persistent_scalar_ids[0..field_index]) |previous| {
                    if (previous == field_id) return null;
                }
            }
            if (range_selection_description.parameter_bound != 0 and
                secondary_range_selection_description.parameter_bound != 0)
            {
                const primary_parameter_ids = [_]vsttypes.ParamID{
                    range_selection_description.start_parameter_id,
                    range_selection_description.end_parameter_id,
                };
                const secondary_parameter_ids = [_]vsttypes.ParamID{
                    secondary_range_selection_description.start_parameter_id,
                    secondary_range_selection_description.end_parameter_id,
                };
                for (primary_parameter_ids) |primary_id| {
                    for (secondary_parameter_ids) |secondary_id| {
                        if (primary_id == secondary_id) return null;
                    }
                }
            }
            var has_dynamic_layer = false;
            for (graph.layers) |layer| has_dynamic_layer = has_dynamic_layer or (layer.dynamic and !layer.disabled);
            if (graph.points.len > vstgui_editor_view.max_graph_points or
                editable_points.len > vstgui_editor_view.max_graph_points or
                graph.handles.len > vstgui_editor_view.max_graph_handles or
                graph.layers.len > vstgui_editor_view.max_graph_layers or
                (graph.parameter_driven and (graph.dynamic or graph.source != .controller)) or
                (graph.source_id & vstgui_editor_view.controller_graph_source_flag != 0) or
                !validGraphAxis(graph.x_axis) or !validGraphAxis(graph.y_axis) or
                ((graph.range_selection != null or graph.secondary_range_selection != null) and
                    (graph.point_capacity > 0 or graph.handles.len > 0)) or
                (graph.point_capacity > 0 and graph.handles.len > 0) or
                ((graph.dynamic or has_dynamic_layer) and
                    (graph.maximum_refresh_hz == 0 or graph.maximum_refresh_hz > 60)) or
                (graph.point_capacity == 0 and (graph.editable_points.len > 0 or graph.minimum_point_count > 0 or
                    graph.snap_x != 0.0 or graph.snap_y != 0.0)) or
                (graph.point_capacity > 0 and (graph.kind != .envelope or graph.dynamic or graph.points.len > 0 or
                    graph.point_capacity > vstgui_editor_view.max_graph_points or
                    editable_points.len > graph.point_capacity or
                    graph.minimum_point_count > editable_points.len or
                    !std.math.isFinite(graph.snap_x) or !std.math.isFinite(graph.snap_y) or
                    graph.snap_x < 0.0 or graph.snap_y < 0.0))) return null;
            for (graph.layers, 0..) |layer, layer_index| {
                if (layer.points.len > vstgui_editor_view.max_graph_points or
                    layer.source_id & vstgui_editor_view.controller_graph_source_flag != 0 or
                    (layer.dynamic and layer.parameter_driven) or
                    ((layer.dynamic or layer.parameter_driven) and layer.points.len != 0) or
                    (!layer.dynamic and !layer.parameter_driven and layer.points.len == 0) or
                    (layer.parameter_driven and layer.source != .controller) or
                    (layer.dynamic and layer.source != .component) or
                    (layer.y_axis != null and !validGraphAxis(layer.y_axis.?))) return null;
                if (layer.dynamic or layer.parameter_driven) {
                    const encoded_source = layer.source_id | if (layer.source == .controller)
                        vstgui_editor_view.controller_graph_source_flag
                    else
                        0;
                    const graph_source = graph.source_id | if (graph.source == .controller)
                        vstgui_editor_view.controller_graph_source_flag
                    else
                        0;
                    if ((graph.dynamic or graph.parameter_driven) and encoded_source == graph_source) return null;
                    for (graph.layers[0..layer_index]) |previous| {
                        if (!previous.dynamic and !previous.parameter_driven) continue;
                        const previous_source = previous.source_id | if (previous.source == .controller)
                            vstgui_editor_view.controller_graph_source_flag
                        else
                            0;
                        if (previous_source == encoded_source) return null;
                    }
                }
                graph_layers[index][layer_index] = .{
                    .style = layer.style,
                    .points = if (layer.points.len == 0) null else layer.points.ptr,
                    .point_count = @intCast(layer.points.len),
                    .source_id = layer.source_id | if (layer.source == .controller)
                        vstgui_editor_view.controller_graph_source_flag
                    else
                        0,
                    .kind = layer.kind,
                    .dynamic = @intFromBool(layer.dynamic),
                    .parameter_driven = @intFromBool(layer.parameter_driven),
                    .has_y_axis = @intFromBool(layer.y_axis != null),
                    .y_axis = if (layer.y_axis) |axis| .{
                        .minimum = axis.minimum,
                        .maximum = axis.maximum,
                        .scale = axis.scale,
                        .label = axis.label,
                    } else .{ .minimum = 0.0, .maximum = 1.0 },
                    .disabled = @intFromBool(layer.disabled),
                };
            }
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
            for (graph.handles, 0..) |handle, handle_index| {
                if (handle.id == 0 or std.mem.span(handle.name).len == 0 or
                    handle.x_parameter_id == handle.y_parameter_id or
                    handle.x_step_count < 0 or handle.y_step_count < 0 or
                    !std.math.isFinite(handle.adjustment_step) or handle.adjustment_step <= 0.0) return null;
                if (handle.highlight_group_index) |group_index| {
                    if (group_index >= composition.groups.len) return null;
                }
                for (graph.handles[0..handle_index]) |previous| {
                    if (previous.id == handle.id) return null;
                }
                var found_x = false;
                var found_y = false;
                var found_adjustment = handle.adjustment_parameter_id == null;
                var found_enabled = handle.enabled_parameter_id == null;
                for (parameters) |parameter| {
                    found_x = found_x or parameter.id == handle.x_parameter_id;
                    found_y = found_y or parameter.id == handle.y_parameter_id;
                    if (handle.adjustment_parameter_id) |parameter_id| {
                        found_adjustment = found_adjustment or parameter.id == parameter_id;
                    }
                    if (handle.enabled_parameter_id) |parameter_id| {
                        found_enabled = found_enabled or parameter.id == parameter_id;
                    }
                }
                if (!found_x or !found_y or !found_adjustment or !found_enabled) return null;
                if (handle.adjustment_parameter_id) |parameter_id| {
                    if (parameter_id == handle.x_parameter_id or parameter_id == handle.y_parameter_id) return null;
                }
                if (handle.enabled_parameter_id) |parameter_id| {
                    if (parameter_id == handle.x_parameter_id or parameter_id == handle.y_parameter_id or
                        (handle.adjustment_parameter_id != null and parameter_id == handle.adjustment_parameter_id.?)) return null;
                }
                graph_handles[index][handle_index] = .{
                    .handle_id = handle.id,
                    .name = handle.name,
                    .x_parameter_id = handle.x_parameter_id,
                    .y_parameter_id = handle.y_parameter_id,
                    .x_normalized = Controller.getNormalized(controller, handle.x_parameter_id),
                    .y_normalized = Controller.getNormalized(controller, handle.y_parameter_id),
                    .x_step_count = handle.x_step_count,
                    .y_step_count = handle.y_step_count,
                    .has_adjustment = @intFromBool(handle.adjustment_parameter_id != null),
                    .adjustment_parameter_id = handle.adjustment_parameter_id orelse 0,
                    .adjustment_label = handle.adjustment_label,
                    .adjustment_normalized = if (handle.adjustment_parameter_id) |parameter_id|
                        Controller.getNormalized(controller, parameter_id)
                    else
                        0.0,
                    .adjustment_step = handle.adjustment_step,
                    .has_enabled = @intFromBool(handle.enabled_parameter_id != null),
                    .enabled_parameter_id = handle.enabled_parameter_id orelse 0,
                    .enabled = if (handle.enabled_parameter_id) |parameter_id|
                        @intFromBool(Controller.getNormalized(controller, parameter_id) >= 0.5)
                    else
                        1,
                    .highlight_group_index = handle.highlight_group_index orelse std.math.maxInt(types.uint32),
                };
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
                .viewport = viewport_description,
                .range_selection = range_selection_description,
                .handles = if (graph.handles.len == 0) null else &graph_handles[index],
                .handle_count = @intCast(graph.handles.len),
                .parameter_driven = @intFromBool(graph.parameter_driven),
                .layers = if (graph.layers.len == 0) null else &graph_layers[index],
                .layer_count = @intCast(graph.layers.len),
                .secondary_range_selection = secondary_range_selection_description,
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
                .success_focus_importer_id = action.success_focus_importer_id,
                .ready_importer_id = action.ready_importer_id,
            };
        }
        var editable_label_descriptions: [vstgui_editor_view.max_editable_labels]vstgui_editor_view.EditableLabelDescription = undefined;
        var editable_label_text: [vstgui_editor_view.max_editable_labels][editor_state.maximum_text_bytes + 1]u8 = @splat(@splat(0));
        if (comptime Controller.hasEditorState) {
            for (editable_labels, 0..) |label, index| {
                const stored = switch (Controller.editorState(controller).get(label.field_id) orelse return null) {
                    .text => |value| value,
                    else => return null,
                };
                if (stored.len > label.maximum_bytes) return null;
                @memcpy(editable_label_text[index][0..stored.len], stored.slice());
                editable_label_descriptions[index] = .{
                    .field_id = label.field_id,
                    .label = label.label,
                    .accessible_label = label.accessible_label,
                    .placeholder = label.placeholder,
                    .error_text = label.error_text,
                    .initial_text = @ptrCast(&editable_label_text[index]),
                    .maximum_bytes = label.maximum_bytes,
                    .enabled = @intFromBool(label.enabled),
                    .read_only = @intFromBool(label.read_only),
                    .maximum_refresh_hz = if (label.read_only) label.maximum_refresh_hz else 0,
                };
            }
        }
        var progress_descriptions: [vstgui_editor_view.max_progress_indicators]vstgui_editor_view.ProgressIndicatorDescription = undefined;
        for (progress_indicators, 0..) |progress, index| {
            progress_descriptions[index] = .{
                .source_id = progress.source_id,
                .label = progress.label,
                .accessible_label = progress.accessible_label,
                .idle_text = progress.idle_text,
                .running_text = progress.running_text,
                .complete_text = progress.complete_text,
                .failure_text = progress.failure_text,
                .maximum_refresh_hz = progress.maximum_refresh_hz,
            };
        }
        const telemetry_provider: ?vstgui_editor_view.TelemetrySourceProvider = if (comptime @hasDecl(Controller, "retainGuiTelemetry"))
            .{ .userdata = controller, .retain = Bridge.retainGuiTelemetry }
        else
            null;
        return vstgui_editor_view.create(controller, bindings[0..parameters.len], meter_descriptions[0..meters.len], graph_descriptions[0..graphs.len], xy_pad_descriptions[0..xy_pads.len], browser_descriptions[0..preset_browsers.len], menu_descriptions[0..action_menus.len], piano_descriptions[0..pianos.len], step_sequencer_descriptions[0..step_sequencers.len], file_drop_descriptions[0..file_importers.len], action_button_descriptions[0..action_buttons.len], editable_label_descriptions[0..editable_labels.len], progress_descriptions[0..progress_indicators.len], skin, composition, .{
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
            .load_editor_text = Bridge.loadEditorText,
            .load_progress = Bridge.loadProgress,
            .store_editor_scalars = Bridge.storeEditorScalars,
        }, .{
            .userdata = controller,
            .subscribe = Bridge.subscribe,
            .unsubscribe = Bridge.unsubscribe,
        }, wayland_host, telemetry_provider, .{
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

        fn retainGuiTelemetry(userdata: *anyopaque) ?gui_telemetry_source.RetainedSource {
            return Controller.retainGuiTelemetry(@ptrCast(@alignCast(userdata)));
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
            const iface = controller(userdata) orelse return -1;
            const bytes = std.mem.span(text);
            if (Controller.validateEditorText(iface, field_id, bytes) != types.kResultOk) return -1;
            const value = editor_state.Text.init(bytes) catch return -1;
            Controller.editorState(iface).set(field_id, .{ .text = value }) catch return -1;
            return 0;
        }

        fn loadEditorText(
            userdata: ?*anyopaque,
            field_id: u32,
            output: [*]u8,
            capacity: u32,
        ) callconv(.c) types.int32 {
            if (comptime !Controller.hasEditorState) return -1;
            if (capacity == 0) return -1;
            const iface = controller(userdata) orelse return -1;
            const value = Controller.editorState(iface).get(field_id) orelse return -1;
            const stored = switch (value) {
                .text => |text| text,
                else => return -1,
            };
            if (stored.len >= capacity) return -1;
            @memcpy(output[0..stored.len], stored.slice());
            output[stored.len] = 0;
            return @intCast(stored.len);
        }

        fn loadProgress(
            userdata: ?*anyopaque,
            source_id: u32,
            output: *vstgui_editor_view.ProgressSnapshot,
        ) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            const snapshot = Controller.loadGuiProgress(iface, source_id) orelse return -1;
            snapshot.validate() catch return -1;
            output.* = .{
                .mode = @enumFromInt(@intFromEnum(snapshot.mode)),
                .state = @enumFromInt(@intFromEnum(snapshot.state)),
                .value = snapshot.value,
                .generation = snapshot.generation,
            };
            return 0;
        }

        fn storeEditorScalars(
            userdata: ?*anyopaque,
            field_ids: [*]const u32,
            values: [*]const f64,
            count: u32,
        ) callconv(.c) types.int32 {
            if (comptime !Controller.hasEditorState) return -1;
            if (count == 0 or count > 3) return -1;
            const iface = controller(userdata) orelse return -1;
            const state = Controller.editorState(iface);
            for (field_ids[0..count], values[0..count]) |field_id, value| {
                if (field_id == 0 or !std.math.isFinite(value)) return -1;
                const current = state.get(field_id) orelse return -1;
                if (current.kind() != .scalar) return -1;
            }
            for (field_ids[0..count], values[0..count]) |field_id, value| {
                state.set(field_id, .{ .scalar = value }) catch return -1;
            }
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
            snapshot.validate() catch return -1;
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

test "action buttons target declared file importers" {
    const importers = [_]FileImporter{
        .{ .id = 9, .extensions = &.{".wav"} },
    };
    try std.testing.expect(validActionImporterTargets(&.{.{
        .group_id = 1,
        .id = 1,
        .label = "Clear",
        .accessible_label = "Clear",
        .success_focus_importer_id = 9,
        .ready_importer_id = 9,
    }}, &importers));
    try std.testing.expect(!validActionImporterTargets(&.{.{
        .group_id = 1,
        .id = 1,
        .label = "Clear",
        .accessible_label = "Clear",
        .success_focus_importer_id = 10,
    }}, &importers));
    try std.testing.expect(!validActionImporterTargets(&.{.{
        .group_id = 1,
        .id = 1,
        .label = "Trim",
        .accessible_label = "Trim",
        .ready_importer_id = 10,
    }}, &importers));
}

test "editable labels enforce bounded persistent text fields" {
    try validateEditableLabels(&.{.{
        .field_id = 1,
        .label = "IR Name",
        .accessible_label = "Impulse response name",
        .maximum_bytes = 64,
    }});
    try std.testing.expectError(error.InvalidFieldId, validateEditableLabels(&.{.{
        .field_id = 0,
        .label = "Name",
        .accessible_label = "Name",
    }}));
    try std.testing.expectError(error.InvalidMaximumBytes, validateEditableLabels(&.{.{
        .field_id = 1,
        .label = "Name",
        .accessible_label = "Name",
        .maximum_bytes = editor_state.maximum_text_bytes + 1,
    }}));
    try std.testing.expectError(error.DuplicateFieldId, validateEditableLabels(&.{
        .{ .field_id = 1, .label = "One", .accessible_label = "One" },
        .{ .field_id = 1, .label = "Two", .accessible_label = "Two" },
    }));
    try std.testing.expectError(error.InvalidRefreshRate, validateEditableLabels(&.{.{
        .field_id = 1,
        .label = "Live",
        .accessible_label = "Live value",
        .read_only = true,
        .maximum_refresh_hz = 61,
    }}));
}

test "progress indicators require bounded unique sources and readable states" {
    try validateProgressIndicators(&.{.{
        .source_id = 1,
        .label = "Import",
        .accessible_label = "Import progress",
    }});
    try std.testing.expectError(error.InvalidSourceId, validateProgressIndicators(&.{.{
        .source_id = 0,
        .label = "Import",
        .accessible_label = "Import progress",
    }}));
    try std.testing.expectError(error.InvalidRefreshRate, validateProgressIndicators(&.{.{
        .source_id = 1,
        .label = "Import",
        .accessible_label = "Import progress",
        .maximum_refresh_hz = 61,
    }}));
    try std.testing.expectError(error.DuplicateSourceId, validateProgressIndicators(&.{
        .{ .source_id = 1, .label = "One", .accessible_label = "One" },
        .{ .source_id = 1, .label = "Two", .accessible_label = "Two" },
    }));
}

test "graph viewports validate bounded transforms and persistent fields" {
    try (Viewport{
        .maximum_zoom = 64.0,
        .zoom_state_id = 10,
        .x_offset_state_id = 11,
    }).validate();
    try std.testing.expectError(error.InvalidZoomRange, (Viewport{ .minimum_zoom = 0.5 }).validate());
    try std.testing.expectError(error.InvalidViewportStateField, (Viewport{
        .axes = .horizontal,
        .y_offset_state_id = 12,
    }).validate());
    try std.testing.expectError(error.DuplicateViewportStateField, (Viewport{
        .zoom_state_id = 10,
        .x_offset_state_id = 10,
    }).validate());
}

test "graph range selections validate bounds and paired state fields" {
    const axis = GraphAxis{ .minimum = 0.0, .maximum = 1.0 };
    try (RangeSelection{
        .initial_start = 0.2,
        .initial_end = 0.8,
        .minimum_span = 0.1,
        .step = 0.01,
        .start_state_id = 20,
        .end_state_id = 21,
    }).validate(axis);
    try std.testing.expectError(error.InvalidRangeSelectionSpan, (RangeSelection{
        .initial_start = 0.2,
        .initial_end = 0.25,
        .minimum_span = 0.1,
    }).validate(axis));
    try std.testing.expectError(error.IncompleteRangeSelectionState, (RangeSelection{
        .start_state_id = 20,
    }).validate(axis));
    try std.testing.expectError(error.DuplicateRangeSelectionStateField, (RangeSelection{
        .start_state_id = 20,
        .end_state_id = 20,
    }).validate(axis));
    try (RangeSelection{
        .start_parameter_id = 4,
        .end_parameter_id = 5,
    }).validate(axis);
    try std.testing.expectError(error.IncompleteRangeSelectionParameters, (RangeSelection{
        .start_parameter_id = 4,
    }).validate(axis));
    try std.testing.expectError(error.DuplicateRangeSelectionParameter, (RangeSelection{
        .start_parameter_id = 4,
        .end_parameter_id = 4,
    }).validate(axis));
    try std.testing.expectError(error.ConflictingRangeSelectionPersistence, (RangeSelection{
        .start_state_id = 20,
        .end_state_id = 21,
        .start_parameter_id = 4,
        .end_parameter_id = 5,
    }).validate(axis));
}

test "graph axes reject non-finite and invalid logarithmic ranges" {
    try std.testing.expect(validGraphAxis(.{ .minimum = -24.0, .maximum = 24.0, .scale = .decibels }));
    try std.testing.expect(validGraphAxis(.{ .minimum = 20.0, .maximum = 20_000.0, .scale = .logarithmic }));
    try std.testing.expect(!validGraphAxis(.{ .minimum = std.math.nan(f64), .maximum = 1.0 }));
    try std.testing.expect(!validGraphAxis(.{ .minimum = 0.0, .maximum = std.math.inf(f64) }));
    try std.testing.expect(!validGraphAxis(.{ .minimum = 1.0, .maximum = 1.0 }));
    try std.testing.expect(!validGraphAxis(.{ .minimum = 0.0, .maximum = 20_000.0, .scale = .logarithmic }));
}
