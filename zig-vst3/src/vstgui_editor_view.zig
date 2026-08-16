const builtin = @import("builtin");
const std = @import("std");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_plug_view = @import("vst_plug_view.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const gui_telemetry_source = @import("gui_telemetry_source.zig");
const gui_graph = @import("zig-vst3-plugin-core").gui_graph;
const realtime_audit = @import("zig-vst3-plugin-core").realtime_audit;
const vstgui_adapter_enabled = @import("zig-vst3-gui-options").vstgui_adapter_enabled;

const Editor = opaque {};
pub const Canvas = opaque {};

const Platform = enum(c_int) {
    macos,
    windows,
    x11,
    wayland,
};

pub const FileImportEntryPoint = enum(c_int) {
    drop,
    picker,
};

pub const FileImportStatus = enum(c_int) {
    idle,
    validating,
    importing,
    ready,
    empty,
    unsupported_file,
    capacity_limit,
    invalid_path,
    cancelled,
    failed,
};

pub const FileImportFailure = enum(c_int) {
    none,
    open_failed,
    too_large,
    malformed,
    truncated,
    unsupported_format,
    cancelled,
    worker_unavailable,
};

pub const FileImportCommand = enum(c_int) {
    cancel,
    retry,
    reset,
};

pub const FileImportSnapshot = extern struct {
    status: FileImportStatus,
    failure: FileImportFailure,
    entry_point: FileImportEntryPoint,
    progress: f64,
    generation: u64,
    sample_rate: types.uint32,
    channels: types.uint32,
    sample_frames: u64,
    preview_points: types.uint32,
};

pub const Callbacks = extern struct {
    userdata: ?*anyopaque,
    begin_edit: ?*const fn (?*anyopaque, vsttypes.ParamID) callconv(.c) void = null,
    perform_edit: ?*const fn (?*anyopaque, vsttypes.ParamID, f64) callconv(.c) types.int32 = null,
    end_edit: ?*const fn (?*anyopaque, vsttypes.ParamID) callconv(.c) void = null,
    format_value: ?*const fn (?*anyopaque, vsttypes.ParamID, f64, [*c]u8, types.uint32) callconv(.c) types.int32 = null,
    parse_value: ?*const fn (?*anyopaque, vsttypes.ParamID, [*c]const u8, [*c]f64) callconv(.c) types.int32 = null,
    show_context_menu: ?*const fn (?*anyopaque, vsttypes.ParamID, types.int32, types.int32) callconv(.c) types.int32 = null,
    store_editor_index: ?*const fn (?*anyopaque, types.uint32, types.uint32) callconv(.c) types.int32 = null,
    store_editor_envelope: ?*const fn (?*anyopaque, types.uint32, ?[*]const EnvelopePoint, types.uint32) callconv(.c) types.int32 = null,
    store_editor_text: ?*const fn (?*anyopaque, types.uint32, [*c]const u8) callconv(.c) types.int32 = null,
    load_preset: ?*const fn (?*anyopaque, types.uint32) callconv(.c) types.int32 = null,
    store_editor_bool: ?*const fn (?*anyopaque, types.uint32, types.int32) callconv(.c) types.int32 = null,
    invoke_menu_action: ?*const fn (?*anyopaque, types.uint32, types.uint32, types.int32) callconv(.c) types.int32 = null,
    invoke_action: ?*const fn (?*anyopaque, types.uint32, types.uint32) callconv(.c) types.int32 = null,
    send_note: ?*const fn (?*anyopaque, types.int32, types.int32, f64, types.int32) callconv(.c) types.int32 = null,
    drop_files: ?*const fn (?*anyopaque, types.uint32, [*c]const ?[*:0]const u8, types.uint32) callconv(.c) types.int32 = null,
    import_files: ?*const fn (?*anyopaque, types.uint32, types.int32, [*c]const ?[*:0]const u8, types.uint32) callconv(.c) types.int32 = null,
    load_file_import: ?*const fn (?*anyopaque, types.uint32, [*c]FileImportSnapshot) callconv(.c) types.int32 = null,
    command_file_import: ?*const fn (?*anyopaque, types.uint32, types.int32) callconv(.c) types.int32 = null,
    load_editor_text: ?*const fn (?*anyopaque, types.uint32, [*c]u8, types.uint32) callconv(.c) types.int32 = null,
    load_progress: ?*const fn (?*anyopaque, types.uint32, [*c]ProgressSnapshot) callconv(.c) types.int32 = null,
    store_editor_scalars: ?*const fn (?*anyopaque, [*c]const types.uint32, [*c]const f64, types.uint32) callconv(.c) types.int32 = null,
};

pub const ParameterInfo = extern struct {
    title: [*:0]const u8,
    units: [*:0]const u8,
    step_count: types.int32,
    default_normalized: f64,
    tooltip: ?[*:0]const u8 = null,
    modulation_normalized: f64 = 0.0,
    has_modulation: types.int32 = 0,
};

pub const ParameterDescription = extern struct {
    parameter_id: vsttypes.ParamID,
    initial_normalized: f64,
    info: ParameterInfo,
    control_kind: ControlKind,
};

pub const ControlKind = enum(c_int) {
    linear_slider,
    rotary_knob,
    toggle,
    enum_dropdown,
    segmented_enum,
    bipolar_slider,
    decibel_slider,
};

pub const ParameterValue = extern struct {
    parameter_id: vsttypes.ParamID,
    normalized: f64,
};

pub const max_parameters = 64;
pub const max_declaration_text_bytes = 1024;
pub const max_xy_pads = 8;
pub const max_preset_browsers = 2;
pub const max_presets = 64;
pub const max_action_menus = 4;
pub const max_menu_items = 16;
pub const max_pianos = 2;
pub const max_step_sequencers = 2;
pub const max_steps = 32;
pub const max_action_buttons = 12;
pub const max_editable_labels = 8;
pub const max_progress_indicators = 4;
pub const max_file_drops = 2;
pub const max_drop_extensions = 8;
pub const max_drop_files = 8;
pub const max_meters = 8;
pub const max_graphs = 8;
pub const max_graph_points = gui_telemetry_source.maximum_graph_points;
pub const max_graph_handles = 16;
pub const max_graph_layers = 4;
pub const max_meter_sources = 16;
pub const max_assets = 16;
pub const max_groups = 8;

pub const XYPadDescription = extern struct {
    title: [*:0]const u8,
    x_parameter_id: vsttypes.ParamID,
    y_parameter_id: vsttypes.ParamID,
    x_label: [*:0]const u8,
    y_label: [*:0]const u8,
};

pub const PresetDescription = extern struct {
    preset_id: types.uint32,
    name: [*:0]const u8,
};

pub const PresetBrowserDescription = extern struct {
    title: [*:0]const u8,
    presets: [*]const PresetDescription,
    preset_count: types.uint32,
    search_state_id: types.uint32,
    selection_state_id: types.uint32,
    initial_search: [*:0]const u8,
    initial_selection: types.uint32,
};

pub const MenuItemKind = enum(c_int) {
    action,
    toggle,
    separator,
};

pub const MenuItemDescription = extern struct {
    item_id: types.uint32,
    label: ?[*:0]const u8,
    kind: MenuItemKind,
    enabled: types.int32,
    destructive: types.int32,
    checked_state_id: types.uint32,
    initial_checked: types.int32,
};

pub const ActionMenuDescription = extern struct {
    menu_id: types.uint32,
    title: [*:0]const u8,
    items: [*]const MenuItemDescription,
    item_count: types.uint32,
};

pub const ActionRole = enum(c_int) {
    primary,
    secondary,
    destructive,
};

pub const ActionIcon = enum(c_int) {
    none,
    reset,
    clear,
    reverse,
    zoom_in,
    zoom_out,
};

pub const ActionButtonDescription = extern struct {
    group_id: types.uint32,
    action_id: types.uint32,
    label: ?[*:0]const u8,
    accessible_label: [*:0]const u8,
    tooltip: ?[*:0]const u8,
    confirmation_label: ?[*:0]const u8,
    failure_label: ?[*:0]const u8,
    role: ActionRole,
    icon: ActionIcon,
    enabled: types.int32,
    success_focus_importer_id: types.uint32 = 0,
    ready_importer_id: types.uint32 = 0,
};

pub const EditableLabelDescription = extern struct {
    field_id: types.uint32,
    label: [*:0]const u8,
    accessible_label: [*:0]const u8,
    placeholder: [*:0]const u8,
    error_text: [*:0]const u8,
    initial_text: [*:0]const u8,
    maximum_bytes: types.uint32,
    enabled: types.int32,
    read_only: types.int32 = 0,
    maximum_refresh_hz: types.uint32 = 0,
};

pub const ProgressMode = enum(c_int) {
    determinate,
    indeterminate,
};

pub const ProgressState = enum(c_int) {
    idle,
    running,
    complete,
    failed,
};

pub const ProgressSnapshot = extern struct {
    mode: ProgressMode,
    state: ProgressState,
    value: f64,
    generation: u64,
};

pub const ProgressIndicatorDescription = extern struct {
    source_id: types.uint32,
    label: [*:0]const u8,
    accessible_label: [*:0]const u8,
    idle_text: [*:0]const u8,
    running_text: [*:0]const u8,
    complete_text: [*:0]const u8,
    failure_text: [*:0]const u8,
    maximum_refresh_hz: types.uint32,
};

pub const PianoDescription = extern struct {
    title: [*:0]const u8,
    first_note: types.uint32,
    note_count: types.uint32,
    channel: types.int32,
    velocity: f64,
    computer_base_pitch: types.uint32,
};

pub const StepSequencerDescription = extern struct {
    title: [*:0]const u8,
    parameter_ids: [*]const vsttypes.ParamID,
    step_count: types.uint32,
    selection_state_id: types.uint32,
    initial_selection_mask: types.uint32,
    initial_active_mask: types.uint32,
    enabled: types.int32,
    playhead_source_id: types.uint32,
    maximum_refresh_hz: types.uint32,
};

pub const FileDropDescription = extern struct {
    drop_id: types.uint32,
    title: [*:0]const u8,
    prompt: [*:0]const u8,
    extensions: [*]const [*:0]const u8,
    extension_count: types.uint32,
    maximum_files: types.uint32,
    enabled: types.int32,
    picker_label: [*:0]const u8,
    picker_title: [*:0]const u8,
};

pub const MeterKind = enum(c_int) {
    peak,
    stereo,
    gain_reduction,
};

pub const MeterDescription = extern struct {
    title: [*:0]const u8,
    kind: MeterKind,
    first_source_id: types.uint32,
    second_source_id: types.uint32,
};

const MeterCallbacks = extern struct {
    userdata: ?*anyopaque,
    load: *const fn (?*anyopaque, types.uint32) callconv(.c) f64,
};

pub const GraphScale = enum(c_int) {
    linear,
    logarithmic,
    decibels,
};

pub const GraphKind = enum(c_int) {
    transfer_function,
    envelope,
    waveform,
    spectrum,
};

pub const GraphStyleRole = enum(c_int) {
    primary,
    secondary,
    modulation,
    warning,
};

pub const GraphAxis = extern struct {
    minimum: f64,
    maximum: f64,
    scale: GraphScale = .linear,
    label: [*:0]const u8 = "",
};

pub const GraphDescription = extern struct {
    title: [*:0]const u8,
    kind: GraphKind,
    style: GraphStyleRole,
    x_axis: GraphAxis,
    y_axis: GraphAxis,
    points: ?[*]const gui_graph.Point,
    point_count: types.uint32,
    source_id: types.uint32,
    dynamic: types.int32,
    maximum_refresh_hz: types.uint32,
    editable_points: ?[*]const EnvelopePoint = null,
    editable_point_count: types.uint32 = 0,
    point_capacity: types.uint32 = 0,
    minimum_point_count: types.uint32 = 0,
    snap_x: f64 = 0.0,
    snap_y: f64 = 0.0,
    selection_state_id: types.uint32 = 0,
    envelope_state_id: types.uint32 = 0,
    initial_selected_point_id: types.uint32 = 0,
    viewport: ViewportDescription = .{},
    range_selection: RangeSelectionDescription = .{},
    handles: ?[*]const GraphHandleDescription = null,
    handle_count: types.uint32 = 0,
    parameter_driven: types.int32 = 0,
    layers: ?[*]const GraphLayerDescription = null,
    layer_count: types.uint32 = 0,
    secondary_range_selection: RangeSelectionDescription = .{},
};

pub const GraphLayerDescription = extern struct {
    style: GraphStyleRole,
    points: ?[*]const gui_graph.Point,
    point_count: types.uint32,
    source_id: types.uint32,
    kind: GraphKind = .transfer_function,
    dynamic: types.int32 = 0,
    parameter_driven: types.int32 = 0,
    has_y_axis: types.int32 = 0,
    y_axis: GraphAxis = .{ .minimum = 0.0, .maximum = 1.0 },
    disabled: types.int32 = 0,
};

pub const GraphHandleDescription = extern struct {
    handle_id: types.uint32,
    name: [*:0]const u8,
    x_parameter_id: vsttypes.ParamID,
    y_parameter_id: vsttypes.ParamID,
    x_normalized: f64,
    y_normalized: f64,
    x_step_count: types.int32 = 0,
    y_step_count: types.int32 = 0,
    has_adjustment: types.int32 = 0,
    adjustment_parameter_id: vsttypes.ParamID = 0,
    adjustment_label: [*:0]const u8 = "",
    adjustment_normalized: f64 = 0.0,
    adjustment_step: f64 = 0.01,
    has_enabled: types.int32 = 0,
    enabled_parameter_id: vsttypes.ParamID = 0,
    enabled: types.int32 = 1,
    highlight_group_index: types.uint32 = std.math.maxInt(types.uint32),
};

pub const EnvelopePoint = extern struct {
    point_id: types.uint32,
    x: f64,
    y: f64,
    x_parameter_id: vsttypes.ParamID = 0,
    y_parameter_id: vsttypes.ParamID = 0,
    parameter_mask: types.uint32 = 0,
    x_step_count: types.int32 = 0,
    y_step_count: types.int32 = 0,
};

pub const ViewportAxes = enum(c_int) {
    horizontal,
    vertical,
    both,
};

pub const ViewportDescription = extern struct {
    enabled: types.int32 = 0,
    axes: ViewportAxes = .horizontal,
    minimum_zoom: f64 = 1.0,
    maximum_zoom: f64 = 1.0,
    initial_zoom: f64 = 1.0,
    initial_x_offset: f64 = 0.0,
    initial_y_offset: f64 = 0.0,
    zoom_step: f64 = 1.25,
    scroll_step: f64 = 0.1,
    zoom_state_id: types.uint32 = 0,
    x_offset_state_id: types.uint32 = 0,
    y_offset_state_id: types.uint32 = 0,
};

pub const RangeSelectionDescription = extern struct {
    enabled: types.int32 = 0,
    initial_start: f64 = 0.0,
    initial_end: f64 = 0.0,
    minimum_span: f64 = 0.0,
    step: f64 = 0.0,
    start_state_id: types.uint32 = 0,
    end_state_id: types.uint32 = 0,
    parameter_bound: types.int32 = 0,
    start_parameter_id: types.uint32 = 0,
    end_parameter_id: types.uint32 = 0,
    start_step_count: types.int32 = 0,
    end_step_count: types.int32 = 0,
};

const GraphCallbacks = extern struct {
    userdata: ?*anyopaque,
    load: *const fn (?*anyopaque, types.uint32, [*c]gui_graph.Point, types.uint32) callconv(.c) types.uint32,
};

pub const ControllerGraphCallbacks = struct {
    userdata: ?*anyopaque,
    load: *const fn (?*anyopaque, types.uint32, [*c]gui_graph.Point, types.uint32) callconv(.c) types.uint32,
};

pub const controller_graph_source_flag: types.uint32 = 1 << 31;

pub fn cSlice(
    comptime T: type,
    pointer: [*c]T,
    length: usize,
) ?[]T {
    if (pointer == null) return null;
    return pointer[0..length];
}

pub fn cConstSlice(
    comptime T: type,
    pointer: [*c]const T,
    length: usize,
) ?[]const T {
    if (pointer == null) return null;
    return pointer[0..length];
}

pub fn cPointer(comptime T: type, pointer: [*c]T) ?*T {
    if (pointer == null) return null;
    return @ptrFromInt(@intFromPtr(pointer));
}

pub fn cStringBytes(pointer: [*c]const u8) ?[]const u8 {
    if (pointer == null) return null;
    const terminated: [*:0]const u8 = @ptrCast(pointer);
    return std.mem.span(terminated);
}

pub const AssetFormat = enum(c_int) {
    png,
    svg,
};

pub const AssetScale = enum(c_int) {
    pixel_exact,
    contain,
    cover,
    stretch,
};

pub const Asset = struct {
    id: types.uint32,
    data: []const u8,
    format: AssetFormat,
    scale: AssetScale = .contain,
};

const AssetDescription = extern struct {
    asset_id: types.uint32,
    data: [*]const u8,
    data_size: types.uint32,
    format: AssetFormat,
    scale: AssetScale,
};

pub const Fonts = extern struct {
    title_family: ?[*:0]const u8 = null,
    body_family: ?[*:0]const u8 = null,
    value_family: ?[*:0]const u8 = null,
    fallback_family: ?[*:0]const u8 = null,
};

pub const DrawingComponent = enum(c_int) {
    slider,
    knob,
    toggle,
    dropdown,
    segmented,
};

pub const DrawingState = enum(c_int) {
    normal,
    hovered,
    pressed,
    focused,
    disabled,
    editing,
};

pub const DrawRequest = extern struct {
    parameter_id: vsttypes.ParamID,
    component: DrawingComponent,
    state: DrawingState,
    normalized: f64,
    width: f64,
    height: f64,
    scale_factor: f64,
};

pub const DrawingCallbacks = extern struct {
    userdata: ?*anyopaque = null,
    draw_parameter: ?*const fn (?*anyopaque, *const DrawRequest, *Canvas) callconv(.c) types.int32 = null,
};

pub const Theme = enum(c_int) {
    default,
    alternate,
};

pub const Layout = enum(c_int) {
    adaptive,
    compact_strip,
    parameter_workspace,
    instrument_workspace,
};

pub const StyleOverride = struct {
    background: ?types.uint32 = null,
    foreground: ?types.uint32 = null,
    border: ?types.uint32 = null,
    accent: ?types.uint32 = null,
};

pub const Group = struct {
    title: [*:0]const u8,
    first_parameter: types.uint32 = 0,
    parameter_count: types.uint32 = 0,
    first_meter: types.uint32 = 0,
    meter_count: types.uint32 = 0,
    style: StyleOverride = .{},
    first_graph: types.uint32 = 0,
    graph_count: types.uint32 = 0,
    first_xy_pad: types.uint32 = 0,
    xy_pad_count: types.uint32 = 0,
};

pub const Composition = struct {
    title: ?[*:0]const u8 = null,
    groups: []const Group = &.{},
    style: StyleOverride = .{},
};

pub const Skin = struct {
    assets: []const Asset = &.{},
    fonts: Fonts = .{},
    drawing: DrawingCallbacks = .{},
    theme: Theme = .default,
    layout: Layout = .adaptive,
};

const SkinDescription = extern struct {
    assets: ?[*]const AssetDescription,
    asset_count: types.uint32,
    fonts: Fonts,
    drawing: DrawingCallbacks,
    theme: Theme,
    layout: Layout,
    editor_title: ?[*:0]const u8,
    groups: ?[*]const GroupDescription,
    group_count: types.uint32,
    editor_style: NativeStyleOverride,
};

const NativeStyleOverride = extern struct {
    mask: types.uint32,
    background_rgba: types.uint32,
    foreground_rgba: types.uint32,
    border_rgba: types.uint32,
    accent_rgba: types.uint32,
};

const GroupDescription = extern struct {
    title: [*:0]const u8,
    first_parameter: types.uint32,
    parameter_count: types.uint32,
    first_meter: types.uint32,
    meter_count: types.uint32,
    style: NativeStyleOverride,
    first_graph: types.uint32,
    graph_count: types.uint32,
    first_xy_pad: types.uint32,
    xy_pad_count: types.uint32,
};

pub const ObserverCallbacks = struct {
    userdata: *anyopaque,
    subscribe: *const fn (*anyopaque, *anyopaque) bool,
    unsubscribe: *const fn (*anyopaque, *anyopaque) void,
};

const ResizeCallbacks = extern struct {
    userdata: ?*anyopaque,
    request_resize: *const fn (?*anyopaque, types.uint32, types.uint32) callconv(.c) types.int32,
};

extern fn zig_vstgui_editor_create_with_skin(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_editor_create_configured(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    ?[*]const GraphDescription,
    types.uint32,
    GraphCallbacks,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_editor_create_full(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    ?[*]const GraphDescription,
    types.uint32,
    GraphCallbacks,
    ?[*]const XYPadDescription,
    types.uint32,
    ?[*]const PresetBrowserDescription,
    types.uint32,
    ?[*]const ActionMenuDescription,
    types.uint32,
    ?[*]const PianoDescription,
    types.uint32,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_editor_create_complete(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    ?[*]const GraphDescription,
    types.uint32,
    GraphCallbacks,
    ?[*]const XYPadDescription,
    types.uint32,
    ?[*]const PresetBrowserDescription,
    types.uint32,
    ?[*]const ActionMenuDescription,
    types.uint32,
    ?[*]const PianoDescription,
    types.uint32,
    ?[*]const StepSequencerDescription,
    types.uint32,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_editor_create_latest(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    ?[*]const GraphDescription,
    types.uint32,
    GraphCallbacks,
    ?[*]const XYPadDescription,
    types.uint32,
    ?[*]const PresetBrowserDescription,
    types.uint32,
    ?[*]const ActionMenuDescription,
    types.uint32,
    ?[*]const PianoDescription,
    types.uint32,
    ?[*]const StepSequencerDescription,
    types.uint32,
    ?[*]const FileDropDescription,
    types.uint32,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_editor_create_widgets(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    ?[*]const GraphDescription,
    types.uint32,
    GraphCallbacks,
    ?[*]const XYPadDescription,
    types.uint32,
    ?[*]const PresetBrowserDescription,
    types.uint32,
    ?[*]const ActionMenuDescription,
    types.uint32,
    ?[*]const PianoDescription,
    types.uint32,
    ?[*]const StepSequencerDescription,
    types.uint32,
    ?[*]const FileDropDescription,
    types.uint32,
    ?[*]const ActionButtonDescription,
    types.uint32,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_editor_create_components(
    [*]const ParameterDescription,
    types.uint32,
    Callbacks,
    ?[*]const MeterDescription,
    types.uint32,
    MeterCallbacks,
    ?[*]const GraphDescription,
    types.uint32,
    GraphCallbacks,
    ?[*]const XYPadDescription,
    types.uint32,
    ?[*]const PresetBrowserDescription,
    types.uint32,
    ?[*]const ActionMenuDescription,
    types.uint32,
    ?[*]const PianoDescription,
    types.uint32,
    ?[*]const StepSequencerDescription,
    types.uint32,
    ?[*]const FileDropDescription,
    types.uint32,
    ?[*]const ActionButtonDescription,
    types.uint32,
    ?[*]const EditableLabelDescription,
    types.uint32,
    ?[*]const ProgressIndicatorDescription,
    types.uint32,
    SkinDescription,
) ?*Editor;
extern fn zig_vstgui_canvas_fill_rect(*Canvas, f64, f64, f64, f64, types.uint32) void;
extern fn zig_vstgui_canvas_stroke_rect(*Canvas, f64, f64, f64, f64, types.uint32, f64) void;
extern fn zig_vstgui_canvas_fill_ellipse(*Canvas, f64, f64, f64, f64, types.uint32) void;
extern fn zig_vstgui_canvas_line(*Canvas, f64, f64, f64, f64, types.uint32, f64) void;
extern fn zig_vstgui_canvas_draw_asset(*Canvas, types.uint32, f64, f64, f64, f64, f32) types.int32;
extern fn zig_vstgui_editor_open(*Editor, ?*anyopaque, Platform) types.int32;
extern fn zig_vstgui_editor_close(*Editor) void;
extern fn zig_vstgui_editor_destroy(*Editor) void;
extern fn zig_vstgui_editor_resize(*Editor, types.uint32, types.uint32) types.int32;
extern fn zig_vstgui_editor_set_scale(*Editor, f64) types.int32;
extern fn zig_vstgui_editor_set_parameter(*Editor, vsttypes.ParamID, f64) types.int32;
extern fn zig_vstgui_editor_set_modulation(*Editor, vsttypes.ParamID, f64) types.int32;
extern fn zig_vstgui_editor_refresh_parameters(*Editor, [*]const ParameterValue, types.uint32) types.int32;
extern fn zig_vstgui_editor_key_down(*Editor, types.char16, types.int16, types.int16) types.int32;
extern fn zig_vstgui_editor_key_up(*Editor, types.char16, types.int16, types.int16) types.int32;
extern fn zig_vstgui_editor_set_focus(*Editor, types.int32) void;
extern fn zig_vstgui_editor_set_frame(*Editor, ?*iplugview.IPlugFrame) void;
extern fn zig_vstgui_editor_set_wayland_host(*Editor, ?*anyopaque) void;
extern fn zig_vstgui_editor_set_resize_callbacks(*Editor, ResizeCallbacks) void;

fn requireAdapterAbi(
    comptime condition: bool,
    comptime message: []const u8,
) void {
    if (!condition) @compileError(message);
}

pub fn verifyStructAbi(
    comptime name: []const u8,
    comptime expected: type,
    comptime actual: type,
) void {
    const expected_fields = @typeInfo(expected).@"struct".fields;
    const actual_fields = @typeInfo(actual).@"struct".fields;
    requireAdapterAbi(
        @sizeOf(expected) == @sizeOf(actual),
        name ++ " size differs",
    );
    requireAdapterAbi(
        @alignOf(expected) == @alignOf(actual),
        name ++ " alignment differs",
    );
    requireAdapterAbi(
        expected_fields.len == actual_fields.len,
        name ++ " field count differs",
    );
    inline for (expected_fields, 0..) |expected_field, index| {
        const actual_field = actual_fields[index];
        requireAdapterAbi(
            std.mem.eql(u8, expected_field.name, actual_field.name),
            name ++ " field name differs",
        );
        requireAdapterAbi(
            @offsetOf(expected, expected_field.name) ==
                @offsetOf(actual, actual_field.name),
            name ++ "." ++ expected_field.name ++ " offset differs",
        );
        requireAdapterAbi(
            @sizeOf(expected_field.type) == @sizeOf(actual_field.type) and
                @alignOf(expected_field.type) == @alignOf(actual_field.type),
            name ++ "." ++ expected_field.name ++ " field ABI differs",
        );
    }
}

pub fn verifyEnumAbi(
    comptime name: []const u8,
    comptime expected: type,
    comptime actual: type,
) void {
    requireAdapterAbi(
        @sizeOf(expected) == @sizeOf(actual) and
            @alignOf(expected) == @alignOf(actual),
        name ++ " enum ABI differs",
    );
}

pub fn verifyFunctionAbi(
    comptime name: []const u8,
    comptime expected: type,
    comptime actual: type,
) void {
    const expected_info = @typeInfo(expected).@"fn";
    const actual_info = @typeInfo(actual).@"fn";
    requireAdapterAbi(
        std.meta.activeTag(expected_info.calling_convention) ==
            std.meta.activeTag(actual_info.calling_convention),
        name ++ " calling convention differs",
    );
    requireAdapterAbi(
        expected_info.is_var_args == actual_info.is_var_args,
        name ++ " varargs contract differs",
    );
    requireAdapterAbi(
        expected_info.params.len == actual_info.params.len,
        name ++ " parameter count differs",
    );
    const expected_return = expected_info.return_type orelse
        @compileError(name ++ " expected return type is generic");
    const actual_return = actual_info.return_type orelse
        @compileError(name ++ " actual return type is generic");
    requireAdapterAbi(
        @sizeOf(expected_return) == @sizeOf(actual_return) and
            @alignOf(expected_return) == @alignOf(actual_return),
        name ++ " return ABI differs",
    );
    inline for (expected_info.params, 0..) |expected_param, index| {
        const expected_type = expected_param.type orelse
            @compileError(name ++ " expected parameter type is generic");
        const actual_type = actual_info.params[index].type orelse
            @compileError(name ++ " actual parameter type is generic");
        requireAdapterAbi(
            @sizeOf(expected_type) == @sizeOf(actual_type) and
                @alignOf(expected_type) == @alignOf(actual_type),
            name ++ " parameter ABI differs",
        );
    }
}

fn verifyValue(
    comptime name: []const u8,
    comptime expected: anytype,
    comptime actual: anytype,
) void {
    const expected_value = switch (@typeInfo(@TypeOf(expected))) {
        .@"enum" => @intFromEnum(expected),
        .int, .comptime_int => expected,
        else => @compileError(name ++ " expected value is not an integer"),
    };
    const actual_value = switch (@typeInfo(@TypeOf(actual))) {
        .@"enum" => @intFromEnum(actual),
        .int, .comptime_int => actual,
        else => @compileError(name ++ " is not an integer value"),
    };
    requireAdapterAbi(
        expected_value == actual_value,
        name ++ " value differs",
    );
}

pub fn verifyAdapterAbi(comptime adapter: type) void {
    @setEvalBranchQuota(200_000);
    inline for (.{
        .{ "ZigVstguiFileImportSnapshot", FileImportSnapshot, adapter.ZigVstguiFileImportSnapshot },
        .{ "ZigVstguiCallbacks", Callbacks, adapter.ZigVstguiCallbacks },
        .{ "ZigVstguiParameterInfo", ParameterInfo, adapter.ZigVstguiParameterInfo },
        .{ "ZigVstguiParameterDescription", ParameterDescription, adapter.ZigVstguiParameterDescription },
        .{ "ZigVstguiParameterValue", ParameterValue, adapter.ZigVstguiParameterValue },
        .{ "ZigVstguiXYPadDescription", XYPadDescription, adapter.ZigVstguiXYPadDescription },
        .{ "ZigVstguiPreset", PresetDescription, adapter.ZigVstguiPreset },
        .{ "ZigVstguiPresetBrowserDescription", PresetBrowserDescription, adapter.ZigVstguiPresetBrowserDescription },
        .{ "ZigVstguiMenuItemDescription", MenuItemDescription, adapter.ZigVstguiMenuItemDescription },
        .{ "ZigVstguiActionMenuDescription", ActionMenuDescription, adapter.ZigVstguiActionMenuDescription },
        .{ "ZigVstguiActionButtonDescription", ActionButtonDescription, adapter.ZigVstguiActionButtonDescription },
        .{ "ZigVstguiEditableLabelDescription", EditableLabelDescription, adapter.ZigVstguiEditableLabelDescription },
        .{ "ZigVstguiProgressSnapshot", ProgressSnapshot, adapter.ZigVstguiProgressSnapshot },
        .{ "ZigVstguiProgressIndicatorDescription", ProgressIndicatorDescription, adapter.ZigVstguiProgressIndicatorDescription },
        .{ "ZigVstguiPianoDescription", PianoDescription, adapter.ZigVstguiPianoDescription },
        .{ "ZigVstguiStepSequencerDescription", StepSequencerDescription, adapter.ZigVstguiStepSequencerDescription },
        .{ "ZigVstguiFileDropDescription", FileDropDescription, adapter.ZigVstguiFileDropDescription },
        .{ "ZigVstguiMeterDescription", MeterDescription, adapter.ZigVstguiMeterDescription },
        .{ "ZigVstguiMeterCallbacks", MeterCallbacks, adapter.ZigVstguiMeterCallbacks },
        .{ "ZigVstguiGraphPoint", gui_graph.Point, adapter.ZigVstguiGraphPoint },
        .{ "ZigVstguiGraphAxis", GraphAxis, adapter.ZigVstguiGraphAxis },
        .{ "ZigVstguiEnvelopePoint", EnvelopePoint, adapter.ZigVstguiEnvelopePoint },
        .{ "ZigVstguiViewportDescription", ViewportDescription, adapter.ZigVstguiViewportDescription },
        .{ "ZigVstguiRangeSelectionDescription", RangeSelectionDescription, adapter.ZigVstguiRangeSelectionDescription },
        .{ "ZigVstguiGraphDescription", GraphDescription, adapter.ZigVstguiGraphDescription },
        .{ "ZigVstguiGraphLayerDescription", GraphLayerDescription, adapter.ZigVstguiGraphLayerDescription },
        .{ "ZigVstguiGraphHandleDescription", GraphHandleDescription, adapter.ZigVstguiGraphHandleDescription },
        .{ "ZigVstguiGraphCallbacks", GraphCallbacks, adapter.ZigVstguiGraphCallbacks },
        .{ "ZigVstguiAssetDescription", AssetDescription, adapter.ZigVstguiAssetDescription },
        .{ "ZigVstguiFontDescription", Fonts, adapter.ZigVstguiFontDescription },
        .{ "ZigVstguiDrawRequest", DrawRequest, adapter.ZigVstguiDrawRequest },
        .{ "ZigVstguiDrawingCallbacks", DrawingCallbacks, adapter.ZigVstguiDrawingCallbacks },
        .{ "ZigVstguiStyleOverride", NativeStyleOverride, adapter.ZigVstguiStyleOverride },
        .{ "ZigVstguiGroupDescription", GroupDescription, adapter.ZigVstguiGroupDescription },
        .{ "ZigVstguiSkinDescription", SkinDescription, adapter.ZigVstguiSkinDescription },
        .{ "ZigVstguiResizeCallbacks", ResizeCallbacks, adapter.ZigVstguiResizeCallbacks },
    }) |mapping| verifyStructAbi(mapping[0], mapping[1], mapping[2]);

    inline for (.{
        .{ "ZigVstguiFileImportEntryPoint", FileImportEntryPoint, adapter.ZigVstguiFileImportEntryPoint },
        .{ "ZigVstguiFileImportStatus", FileImportStatus, adapter.ZigVstguiFileImportStatus },
        .{ "ZigVstguiFileImportFailure", FileImportFailure, adapter.ZigVstguiFileImportFailure },
        .{ "ZigVstguiFileImportCommand", FileImportCommand, adapter.ZigVstguiFileImportCommand },
        .{ "ZigVstguiControlKind", ControlKind, adapter.ZigVstguiControlKind },
        .{ "ZigVstguiMenuItemKind", MenuItemKind, adapter.ZigVstguiMenuItemKind },
        .{ "ZigVstguiActionRole", ActionRole, adapter.ZigVstguiActionRole },
        .{ "ZigVstguiActionIcon", ActionIcon, adapter.ZigVstguiActionIcon },
        .{ "ZigVstguiProgressMode", ProgressMode, adapter.ZigVstguiProgressMode },
        .{ "ZigVstguiProgressState", ProgressState, adapter.ZigVstguiProgressState },
        .{ "ZigVstguiMeterKind", MeterKind, adapter.ZigVstguiMeterKind },
        .{ "ZigVstguiGraphScale", GraphScale, adapter.ZigVstguiGraphScale },
        .{ "ZigVstguiGraphKind", GraphKind, adapter.ZigVstguiGraphKind },
        .{ "ZigVstguiGraphStyleRole", GraphStyleRole, adapter.ZigVstguiGraphStyleRole },
        .{ "ZigVstguiViewportAxes", ViewportAxes, adapter.ZigVstguiViewportAxes },
        .{ "ZigVstguiAssetFormat", AssetFormat, adapter.ZigVstguiAssetFormat },
        .{ "ZigVstguiAssetScale", AssetScale, adapter.ZigVstguiAssetScale },
        .{ "ZigVstguiDrawingComponent", DrawingComponent, adapter.ZigVstguiDrawingComponent },
        .{ "ZigVstguiDrawingState", DrawingState, adapter.ZigVstguiDrawingState },
        .{ "ZigVstguiThemeKind", Theme, adapter.ZigVstguiThemeKind },
        .{ "ZigVstguiLayoutKind", Layout, adapter.ZigVstguiLayoutKind },
        .{ "ZigVstguiPlatform", Platform, adapter.ZigVstguiPlatform },
    }) |mapping| verifyEnumAbi(mapping[0], mapping[1], mapping[2]);

    inline for (.{
        .{ "ZIG_VSTGUI_MAX_PARAMETERS", max_parameters, adapter.ZIG_VSTGUI_MAX_PARAMETERS },
        .{ "ZIG_VSTGUI_MAX_DECLARATION_TEXT_BYTES", max_declaration_text_bytes, adapter.ZIG_VSTGUI_MAX_DECLARATION_TEXT_BYTES },
        .{ "ZIG_VSTGUI_MAX_XY_PADS", max_xy_pads, adapter.ZIG_VSTGUI_MAX_XY_PADS },
        .{ "ZIG_VSTGUI_MAX_PRESET_BROWSERS", max_preset_browsers, adapter.ZIG_VSTGUI_MAX_PRESET_BROWSERS },
        .{ "ZIG_VSTGUI_MAX_PRESETS", max_presets, adapter.ZIG_VSTGUI_MAX_PRESETS },
        .{ "ZIG_VSTGUI_MAX_ACTION_MENUS", max_action_menus, adapter.ZIG_VSTGUI_MAX_ACTION_MENUS },
        .{ "ZIG_VSTGUI_MAX_MENU_ITEMS", max_menu_items, adapter.ZIG_VSTGUI_MAX_MENU_ITEMS },
        .{ "ZIG_VSTGUI_MAX_PIANOS", max_pianos, adapter.ZIG_VSTGUI_MAX_PIANOS },
        .{ "ZIG_VSTGUI_MAX_STEP_SEQUENCERS", max_step_sequencers, adapter.ZIG_VSTGUI_MAX_STEP_SEQUENCERS },
        .{ "ZIG_VSTGUI_MAX_STEPS", max_steps, adapter.ZIG_VSTGUI_MAX_STEPS },
        .{ "ZIG_VSTGUI_MAX_ACTION_BUTTONS", max_action_buttons, adapter.ZIG_VSTGUI_MAX_ACTION_BUTTONS },
        .{ "ZIG_VSTGUI_MAX_EDITABLE_LABELS", max_editable_labels, adapter.ZIG_VSTGUI_MAX_EDITABLE_LABELS },
        .{ "ZIG_VSTGUI_MAX_PROGRESS_INDICATORS", max_progress_indicators, adapter.ZIG_VSTGUI_MAX_PROGRESS_INDICATORS },
        .{ "ZIG_VSTGUI_MAX_FILE_DROPS", max_file_drops, adapter.ZIG_VSTGUI_MAX_FILE_DROPS },
        .{ "ZIG_VSTGUI_MAX_DROP_EXTENSIONS", max_drop_extensions, adapter.ZIG_VSTGUI_MAX_DROP_EXTENSIONS },
        .{ "ZIG_VSTGUI_MAX_DROP_FILES", max_drop_files, adapter.ZIG_VSTGUI_MAX_DROP_FILES },
        .{ "ZIG_VSTGUI_MAX_METERS", max_meters, adapter.ZIG_VSTGUI_MAX_METERS },
        .{ "ZIG_VSTGUI_MAX_GRAPHS", max_graphs, adapter.ZIG_VSTGUI_MAX_GRAPHS },
        .{ "ZIG_VSTGUI_MAX_GRAPH_POINTS", max_graph_points, adapter.ZIG_VSTGUI_MAX_GRAPH_POINTS },
        .{ "ZIG_VSTGUI_MAX_GRAPH_HANDLES", max_graph_handles, adapter.ZIG_VSTGUI_MAX_GRAPH_HANDLES },
        .{ "ZIG_VSTGUI_MAX_GRAPH_LAYERS", max_graph_layers, adapter.ZIG_VSTGUI_MAX_GRAPH_LAYERS },
        .{ "ZIG_VSTGUI_MAX_ASSETS", max_assets, adapter.ZIG_VSTGUI_MAX_ASSETS },
        .{ "ZIG_VSTGUI_MAX_GROUPS", max_groups, adapter.ZIG_VSTGUI_MAX_GROUPS },
    }) |mapping| verifyValue(mapping[0], mapping[1], mapping[2]);

    inline for (.{
        .{ "ZIG_VSTGUI_FILE_IMPORT_DROP", FileImportEntryPoint.drop, adapter.ZIG_VSTGUI_FILE_IMPORT_DROP },
        .{ "ZIG_VSTGUI_FILE_IMPORT_PICKER", FileImportEntryPoint.picker, adapter.ZIG_VSTGUI_FILE_IMPORT_PICKER },
        .{ "ZIG_VSTGUI_FILE_IMPORT_IDLE", FileImportStatus.idle, adapter.ZIG_VSTGUI_FILE_IMPORT_IDLE },
        .{ "ZIG_VSTGUI_FILE_IMPORT_VALIDATING", FileImportStatus.validating, adapter.ZIG_VSTGUI_FILE_IMPORT_VALIDATING },
        .{ "ZIG_VSTGUI_FILE_IMPORT_IMPORTING", FileImportStatus.importing, adapter.ZIG_VSTGUI_FILE_IMPORT_IMPORTING },
        .{ "ZIG_VSTGUI_FILE_IMPORT_READY", FileImportStatus.ready, adapter.ZIG_VSTGUI_FILE_IMPORT_READY },
        .{ "ZIG_VSTGUI_FILE_IMPORT_EMPTY", FileImportStatus.empty, adapter.ZIG_VSTGUI_FILE_IMPORT_EMPTY },
        .{ "ZIG_VSTGUI_FILE_IMPORT_UNSUPPORTED_FILE", FileImportStatus.unsupported_file, adapter.ZIG_VSTGUI_FILE_IMPORT_UNSUPPORTED_FILE },
        .{ "ZIG_VSTGUI_FILE_IMPORT_CAPACITY_LIMIT", FileImportStatus.capacity_limit, adapter.ZIG_VSTGUI_FILE_IMPORT_CAPACITY_LIMIT },
        .{ "ZIG_VSTGUI_FILE_IMPORT_INVALID_PATH", FileImportStatus.invalid_path, adapter.ZIG_VSTGUI_FILE_IMPORT_INVALID_PATH },
        .{ "ZIG_VSTGUI_FILE_IMPORT_CANCELLED", FileImportStatus.cancelled, adapter.ZIG_VSTGUI_FILE_IMPORT_CANCELLED },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILED", FileImportStatus.failed, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILED },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE", FileImportFailure.none, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_OPEN", FileImportFailure.open_failed, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_OPEN },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_TOO_LARGE", FileImportFailure.too_large, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_TOO_LARGE },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_MALFORMED", FileImportFailure.malformed, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_MALFORMED },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_TRUNCATED", FileImportFailure.truncated, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_TRUNCATED },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_UNSUPPORTED_FORMAT", FileImportFailure.unsupported_format, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_UNSUPPORTED_FORMAT },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_CANCELLED", FileImportFailure.cancelled, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_CANCELLED },
        .{ "ZIG_VSTGUI_FILE_IMPORT_FAILURE_WORKER_UNAVAILABLE", FileImportFailure.worker_unavailable, adapter.ZIG_VSTGUI_FILE_IMPORT_FAILURE_WORKER_UNAVAILABLE },
        .{ "ZIG_VSTGUI_FILE_IMPORT_CANCEL", FileImportCommand.cancel, adapter.ZIG_VSTGUI_FILE_IMPORT_CANCEL },
        .{ "ZIG_VSTGUI_FILE_IMPORT_RETRY", FileImportCommand.retry, adapter.ZIG_VSTGUI_FILE_IMPORT_RETRY },
        .{ "ZIG_VSTGUI_FILE_IMPORT_RESET", FileImportCommand.reset, adapter.ZIG_VSTGUI_FILE_IMPORT_RESET },
        .{ "ZIG_VSTGUI_CONTROL_LINEAR_SLIDER", ControlKind.linear_slider, adapter.ZIG_VSTGUI_CONTROL_LINEAR_SLIDER },
        .{ "ZIG_VSTGUI_CONTROL_ROTARY_KNOB", ControlKind.rotary_knob, adapter.ZIG_VSTGUI_CONTROL_ROTARY_KNOB },
        .{ "ZIG_VSTGUI_CONTROL_TOGGLE", ControlKind.toggle, adapter.ZIG_VSTGUI_CONTROL_TOGGLE },
        .{ "ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN", ControlKind.enum_dropdown, adapter.ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN },
        .{ "ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM", ControlKind.segmented_enum, adapter.ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM },
        .{ "ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER", ControlKind.bipolar_slider, adapter.ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER },
        .{ "ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER", ControlKind.decibel_slider, adapter.ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER },
        .{ "ZIG_VSTGUI_MENU_ACTION", MenuItemKind.action, adapter.ZIG_VSTGUI_MENU_ACTION },
        .{ "ZIG_VSTGUI_MENU_TOGGLE", MenuItemKind.toggle, adapter.ZIG_VSTGUI_MENU_TOGGLE },
        .{ "ZIG_VSTGUI_MENU_SEPARATOR", MenuItemKind.separator, adapter.ZIG_VSTGUI_MENU_SEPARATOR },
        .{ "ZIG_VSTGUI_ACTION_PRIMARY", ActionRole.primary, adapter.ZIG_VSTGUI_ACTION_PRIMARY },
        .{ "ZIG_VSTGUI_ACTION_SECONDARY", ActionRole.secondary, adapter.ZIG_VSTGUI_ACTION_SECONDARY },
        .{ "ZIG_VSTGUI_ACTION_DESTRUCTIVE", ActionRole.destructive, adapter.ZIG_VSTGUI_ACTION_DESTRUCTIVE },
        .{ "ZIG_VSTGUI_ACTION_ICON_NONE", ActionIcon.none, adapter.ZIG_VSTGUI_ACTION_ICON_NONE },
        .{ "ZIG_VSTGUI_ACTION_ICON_RESET", ActionIcon.reset, adapter.ZIG_VSTGUI_ACTION_ICON_RESET },
        .{ "ZIG_VSTGUI_ACTION_ICON_CLEAR", ActionIcon.clear, adapter.ZIG_VSTGUI_ACTION_ICON_CLEAR },
        .{ "ZIG_VSTGUI_ACTION_ICON_REVERSE", ActionIcon.reverse, adapter.ZIG_VSTGUI_ACTION_ICON_REVERSE },
        .{ "ZIG_VSTGUI_ACTION_ICON_ZOOM_IN", ActionIcon.zoom_in, adapter.ZIG_VSTGUI_ACTION_ICON_ZOOM_IN },
        .{ "ZIG_VSTGUI_ACTION_ICON_ZOOM_OUT", ActionIcon.zoom_out, adapter.ZIG_VSTGUI_ACTION_ICON_ZOOM_OUT },
        .{ "ZIG_VSTGUI_PROGRESS_DETERMINATE", ProgressMode.determinate, adapter.ZIG_VSTGUI_PROGRESS_DETERMINATE },
        .{ "ZIG_VSTGUI_PROGRESS_INDETERMINATE", ProgressMode.indeterminate, adapter.ZIG_VSTGUI_PROGRESS_INDETERMINATE },
        .{ "ZIG_VSTGUI_PROGRESS_IDLE", ProgressState.idle, adapter.ZIG_VSTGUI_PROGRESS_IDLE },
        .{ "ZIG_VSTGUI_PROGRESS_RUNNING", ProgressState.running, adapter.ZIG_VSTGUI_PROGRESS_RUNNING },
        .{ "ZIG_VSTGUI_PROGRESS_COMPLETE", ProgressState.complete, adapter.ZIG_VSTGUI_PROGRESS_COMPLETE },
        .{ "ZIG_VSTGUI_PROGRESS_FAILED", ProgressState.failed, adapter.ZIG_VSTGUI_PROGRESS_FAILED },
        .{ "ZIG_VSTGUI_METER_PEAK", MeterKind.peak, adapter.ZIG_VSTGUI_METER_PEAK },
        .{ "ZIG_VSTGUI_METER_STEREO", MeterKind.stereo, adapter.ZIG_VSTGUI_METER_STEREO },
        .{ "ZIG_VSTGUI_METER_GAIN_REDUCTION", MeterKind.gain_reduction, adapter.ZIG_VSTGUI_METER_GAIN_REDUCTION },
        .{ "ZIG_VSTGUI_GRAPH_LINEAR", GraphScale.linear, adapter.ZIG_VSTGUI_GRAPH_LINEAR },
        .{ "ZIG_VSTGUI_GRAPH_LOGARITHMIC", GraphScale.logarithmic, adapter.ZIG_VSTGUI_GRAPH_LOGARITHMIC },
        .{ "ZIG_VSTGUI_GRAPH_DECIBELS", GraphScale.decibels, adapter.ZIG_VSTGUI_GRAPH_DECIBELS },
        .{ "ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION", GraphKind.transfer_function, adapter.ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION },
        .{ "ZIG_VSTGUI_GRAPH_ENVELOPE", GraphKind.envelope, adapter.ZIG_VSTGUI_GRAPH_ENVELOPE },
        .{ "ZIG_VSTGUI_GRAPH_WAVEFORM", GraphKind.waveform, adapter.ZIG_VSTGUI_GRAPH_WAVEFORM },
        .{ "ZIG_VSTGUI_GRAPH_SPECTRUM", GraphKind.spectrum, adapter.ZIG_VSTGUI_GRAPH_SPECTRUM },
        .{ "ZIG_VSTGUI_GRAPH_PRIMARY", GraphStyleRole.primary, adapter.ZIG_VSTGUI_GRAPH_PRIMARY },
        .{ "ZIG_VSTGUI_GRAPH_SECONDARY", GraphStyleRole.secondary, adapter.ZIG_VSTGUI_GRAPH_SECONDARY },
        .{ "ZIG_VSTGUI_GRAPH_MODULATION", GraphStyleRole.modulation, adapter.ZIG_VSTGUI_GRAPH_MODULATION },
        .{ "ZIG_VSTGUI_GRAPH_WARNING", GraphStyleRole.warning, adapter.ZIG_VSTGUI_GRAPH_WARNING },
        .{ "ZIG_VSTGUI_VIEWPORT_HORIZONTAL", ViewportAxes.horizontal, adapter.ZIG_VSTGUI_VIEWPORT_HORIZONTAL },
        .{ "ZIG_VSTGUI_VIEWPORT_VERTICAL", ViewportAxes.vertical, adapter.ZIG_VSTGUI_VIEWPORT_VERTICAL },
        .{ "ZIG_VSTGUI_VIEWPORT_BOTH", ViewportAxes.both, adapter.ZIG_VSTGUI_VIEWPORT_BOTH },
        .{ "ZIG_VSTGUI_ASSET_PNG", AssetFormat.png, adapter.ZIG_VSTGUI_ASSET_PNG },
        .{ "ZIG_VSTGUI_ASSET_SVG", AssetFormat.svg, adapter.ZIG_VSTGUI_ASSET_SVG },
        .{ "ZIG_VSTGUI_ASSET_PIXEL_EXACT", AssetScale.pixel_exact, adapter.ZIG_VSTGUI_ASSET_PIXEL_EXACT },
        .{ "ZIG_VSTGUI_ASSET_CONTAIN", AssetScale.contain, adapter.ZIG_VSTGUI_ASSET_CONTAIN },
        .{ "ZIG_VSTGUI_ASSET_COVER", AssetScale.cover, adapter.ZIG_VSTGUI_ASSET_COVER },
        .{ "ZIG_VSTGUI_ASSET_STRETCH", AssetScale.stretch, adapter.ZIG_VSTGUI_ASSET_STRETCH },
        .{ "ZIG_VSTGUI_DRAW_SLIDER", DrawingComponent.slider, adapter.ZIG_VSTGUI_DRAW_SLIDER },
        .{ "ZIG_VSTGUI_DRAW_KNOB", DrawingComponent.knob, adapter.ZIG_VSTGUI_DRAW_KNOB },
        .{ "ZIG_VSTGUI_DRAW_TOGGLE", DrawingComponent.toggle, adapter.ZIG_VSTGUI_DRAW_TOGGLE },
        .{ "ZIG_VSTGUI_DRAW_DROPDOWN", DrawingComponent.dropdown, adapter.ZIG_VSTGUI_DRAW_DROPDOWN },
        .{ "ZIG_VSTGUI_DRAW_SEGMENTED", DrawingComponent.segmented, adapter.ZIG_VSTGUI_DRAW_SEGMENTED },
        .{ "ZIG_VSTGUI_DRAW_NORMAL", DrawingState.normal, adapter.ZIG_VSTGUI_DRAW_NORMAL },
        .{ "ZIG_VSTGUI_DRAW_HOVERED", DrawingState.hovered, adapter.ZIG_VSTGUI_DRAW_HOVERED },
        .{ "ZIG_VSTGUI_DRAW_PRESSED", DrawingState.pressed, adapter.ZIG_VSTGUI_DRAW_PRESSED },
        .{ "ZIG_VSTGUI_DRAW_FOCUSED", DrawingState.focused, adapter.ZIG_VSTGUI_DRAW_FOCUSED },
        .{ "ZIG_VSTGUI_DRAW_DISABLED", DrawingState.disabled, adapter.ZIG_VSTGUI_DRAW_DISABLED },
        .{ "ZIG_VSTGUI_DRAW_EDITING", DrawingState.editing, adapter.ZIG_VSTGUI_DRAW_EDITING },
        .{ "ZIG_VSTGUI_THEME_DEFAULT", Theme.default, adapter.ZIG_VSTGUI_THEME_DEFAULT },
        .{ "ZIG_VSTGUI_THEME_ALTERNATE", Theme.alternate, adapter.ZIG_VSTGUI_THEME_ALTERNATE },
        .{ "ZIG_VSTGUI_LAYOUT_ADAPTIVE", Layout.adaptive, adapter.ZIG_VSTGUI_LAYOUT_ADAPTIVE },
        .{ "ZIG_VSTGUI_LAYOUT_COMPACT_STRIP", Layout.compact_strip, adapter.ZIG_VSTGUI_LAYOUT_COMPACT_STRIP },
        .{ "ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE", Layout.parameter_workspace, adapter.ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE },
        .{ "ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE", Layout.instrument_workspace, adapter.ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE },
        .{ "ZIG_VSTGUI_PLATFORM_MACOS", Platform.macos, adapter.ZIG_VSTGUI_PLATFORM_MACOS },
        .{ "ZIG_VSTGUI_PLATFORM_WINDOWS", Platform.windows, adapter.ZIG_VSTGUI_PLATFORM_WINDOWS },
        .{ "ZIG_VSTGUI_PLATFORM_X11", Platform.x11, adapter.ZIG_VSTGUI_PLATFORM_X11 },
        .{ "ZIG_VSTGUI_PLATFORM_WAYLAND", Platform.wayland, adapter.ZIG_VSTGUI_PLATFORM_WAYLAND },
    }) |mapping| verifyValue(mapping[0], mapping[1], mapping[2]);

    verifyValue("ZIG_VSTGUI_STYLE_BACKGROUND", 1 << 0, adapter.ZIG_VSTGUI_STYLE_BACKGROUND);
    verifyValue("ZIG_VSTGUI_STYLE_FOREGROUND", 1 << 1, adapter.ZIG_VSTGUI_STYLE_FOREGROUND);
    verifyValue("ZIG_VSTGUI_STYLE_BORDER", 1 << 2, adapter.ZIG_VSTGUI_STYLE_BORDER);
    verifyValue("ZIG_VSTGUI_STYLE_ACCENT", 1 << 3, adapter.ZIG_VSTGUI_STYLE_ACCENT);

    inline for (.{
        .{ "zig_vstgui_editor_create_with_skin", @TypeOf(zig_vstgui_editor_create_with_skin), @TypeOf(adapter.zig_vstgui_editor_create_with_skin) },
        .{ "zig_vstgui_editor_create_configured", @TypeOf(zig_vstgui_editor_create_configured), @TypeOf(adapter.zig_vstgui_editor_create_configured) },
        .{ "zig_vstgui_editor_create_full", @TypeOf(zig_vstgui_editor_create_full), @TypeOf(adapter.zig_vstgui_editor_create_full) },
        .{ "zig_vstgui_editor_create_complete", @TypeOf(zig_vstgui_editor_create_complete), @TypeOf(adapter.zig_vstgui_editor_create_complete) },
        .{ "zig_vstgui_editor_create_latest", @TypeOf(zig_vstgui_editor_create_latest), @TypeOf(adapter.zig_vstgui_editor_create_latest) },
        .{ "zig_vstgui_editor_create_widgets", @TypeOf(zig_vstgui_editor_create_widgets), @TypeOf(adapter.zig_vstgui_editor_create_widgets) },
        .{ "zig_vstgui_editor_create_components", @TypeOf(zig_vstgui_editor_create_components), @TypeOf(adapter.zig_vstgui_editor_create_components) },
        .{ "zig_vstgui_canvas_fill_rect", @TypeOf(zig_vstgui_canvas_fill_rect), @TypeOf(adapter.zig_vstgui_canvas_fill_rect) },
        .{ "zig_vstgui_canvas_stroke_rect", @TypeOf(zig_vstgui_canvas_stroke_rect), @TypeOf(adapter.zig_vstgui_canvas_stroke_rect) },
        .{ "zig_vstgui_canvas_fill_ellipse", @TypeOf(zig_vstgui_canvas_fill_ellipse), @TypeOf(adapter.zig_vstgui_canvas_fill_ellipse) },
        .{ "zig_vstgui_canvas_line", @TypeOf(zig_vstgui_canvas_line), @TypeOf(adapter.zig_vstgui_canvas_line) },
        .{ "zig_vstgui_canvas_draw_asset", @TypeOf(zig_vstgui_canvas_draw_asset), @TypeOf(adapter.zig_vstgui_canvas_draw_asset) },
        .{ "zig_vstgui_editor_open", @TypeOf(zig_vstgui_editor_open), @TypeOf(adapter.zig_vstgui_editor_open) },
        .{ "zig_vstgui_editor_close", @TypeOf(zig_vstgui_editor_close), @TypeOf(adapter.zig_vstgui_editor_close) },
        .{ "zig_vstgui_editor_destroy", @TypeOf(zig_vstgui_editor_destroy), @TypeOf(adapter.zig_vstgui_editor_destroy) },
        .{ "zig_vstgui_editor_resize", @TypeOf(zig_vstgui_editor_resize), @TypeOf(adapter.zig_vstgui_editor_resize) },
        .{ "zig_vstgui_editor_set_scale", @TypeOf(zig_vstgui_editor_set_scale), @TypeOf(adapter.zig_vstgui_editor_set_scale) },
        .{ "zig_vstgui_editor_set_parameter", @TypeOf(zig_vstgui_editor_set_parameter), @TypeOf(adapter.zig_vstgui_editor_set_parameter) },
        .{ "zig_vstgui_editor_set_modulation", @TypeOf(zig_vstgui_editor_set_modulation), @TypeOf(adapter.zig_vstgui_editor_set_modulation) },
        .{ "zig_vstgui_editor_refresh_parameters", @TypeOf(zig_vstgui_editor_refresh_parameters), @TypeOf(adapter.zig_vstgui_editor_refresh_parameters) },
        .{ "zig_vstgui_editor_key_down", @TypeOf(zig_vstgui_editor_key_down), @TypeOf(adapter.zig_vstgui_editor_key_down) },
        .{ "zig_vstgui_editor_key_up", @TypeOf(zig_vstgui_editor_key_up), @TypeOf(adapter.zig_vstgui_editor_key_up) },
        .{ "zig_vstgui_editor_set_focus", @TypeOf(zig_vstgui_editor_set_focus), @TypeOf(adapter.zig_vstgui_editor_set_focus) },
        .{ "zig_vstgui_editor_set_frame", @TypeOf(zig_vstgui_editor_set_frame), @TypeOf(adapter.zig_vstgui_editor_set_frame) },
        .{ "zig_vstgui_editor_set_wayland_host", @TypeOf(zig_vstgui_editor_set_wayland_host), @TypeOf(adapter.zig_vstgui_editor_set_wayland_host) },
        .{ "zig_vstgui_editor_set_resize_callbacks", @TypeOf(zig_vstgui_editor_set_resize_callbacks), @TypeOf(adapter.zig_vstgui_editor_set_resize_callbacks) },
    }) |mapping| verifyFunctionAbi(mapping[0], mapping[1], mapping[2]);
}

const Binding = struct {
    editor: *Editor,
    controller: *ivsteditcontroller.IEditController,
    observer_callbacks: ObserverCallbacks,
    telemetry: *TelemetryState,
    attached: bool = false,
    has_preset_browser: bool = false,
    minimum_width: types.int32 = 320,
    minimum_height: types.int32 = 240,
    maximum_width: types.int32 = 1_000,
    maximum_height: types.int32 = 700,
    logical_width: types.int32 = 400,
    logical_height: types.int32 = 300,
    content_scale: f32 = 1.0,
};

fn scaledDimension(logical: types.int32, scale: f32) ?types.int32 {
    const scaled = @as(f64, @floatFromInt(logical)) * @as(f64, scale);
    if (!std.math.isFinite(scaled) or scaled < 1 or scaled > std.math.maxInt(types.int32)) return null;
    return @intFromFloat(@floor(scaled));
}

fn logicalDimension(physical: types.int32, scale: f32) ?types.int32 {
    if (physical < 0 or !std.math.isFinite(scale) or scale <= 0) return null;
    const logical = @as(f64, @floatFromInt(physical)) / @as(f64, scale);
    if (!std.math.isFinite(logical) or logical > std.math.maxInt(types.int32)) return null;
    return @intFromFloat(@round(logical));
}

fn rectDimension(start: types.int32, end: types.int32) ?types.int32 {
    const dimension = @as(i64, end) - @as(i64, start);
    if (dimension < 1 or dimension > std.math.maxInt(types.int32)) return null;
    return @intCast(dimension);
}

fn rectEnd(start: types.int32, dimension: types.int32) ?types.int32 {
    if (dimension < 1) return null;
    return std.math.cast(types.int32, @as(i64, start) + @as(i64, dimension));
}

fn nativeFocusState(raw: types.TBool) ?types.int32 {
    return switch (raw) {
        0 => 0,
        1 => 1,
        else => null,
    };
}

const TelemetryState = struct {
    source: ?gui_telemetry_source.RetainedSource,
    provider: ?TelemetrySourceProvider,
    controller_graph: ControllerGraphCallbacks,
    is_open: bool = false,

    fn acquire(self: *TelemetryState) void {
        if (self.source != null) return;
        const provider = self.provider orelse return;
        self.source = provider.retain(provider.userdata);
        if (self.is_open) {
            if (self.source) |source| source.editorOpened();
        }
    }

    fn opened(self: *TelemetryState) void {
        if (self.is_open) return;
        self.is_open = true;
        const had_source = self.source != null;
        self.acquire();
        if (!had_source) return;
        if (self.source) |source| source.editorOpened();
    }

    fn closed(self: *TelemetryState) void {
        if (!self.is_open) return;
        if (self.source) |source| source.editorClosed();
        self.is_open = false;
    }

    fn release(self: *TelemetryState) void {
        if (self.source) |source| source.release();
        self.source = null;
    }
};

pub const TelemetrySourceProvider = struct {
    userdata: *anyopaque,
    retain: *const fn (*anyopaque) ?gui_telemetry_source.RetainedSource,
};

fn binding(self: anytype) ?*Binding {
    return @ptrCast(@alignCast(self.context orelse return null));
}

const View = vst_plug_view.PlugView(2, struct {
    pub fn attached(self: anytype, parent: ?*anyopaque, platform_type: types.FIDString) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        const platform: Platform = if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeNSView)))
            .macos
        else if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeHWND)))
            .windows
        else if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID)))
            .x11
        else if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID)))
            .wayland
        else
            return types.kResultFalse;
        if (zig_vstgui_editor_open(state.editor, parent, platform) != 0) {
            std.log.err("VSTGUI editor attachment failed for {s}", .{@tagName(platform)});
            return types.kResultFalse;
        }
        if (!state.attached) {
            state.telemetry.opened();
            state.attached = true;
        }
        return types.kResultOk;
    }

    pub fn removed(self: anytype) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        if (state.attached) {
            state.telemetry.closed();
            state.attached = false;
        }
        zig_vstgui_editor_close(state.editor);
        return types.kResultOk;
    }

    pub fn onSize(self: anytype, rect: *iplugview.ViewRect) types.tresult {
        const width = rectDimension(rect.left, rect.right) orelse return types.kResultFalse;
        const height = rectDimension(rect.top, rect.bottom) orelse return types.kResultFalse;
        const state = binding(self) orelse return types.kResultFalse;
        const minimum_width = scaledDimension(state.minimum_width, state.content_scale) orelse return types.kResultFalse;
        const minimum_height = scaledDimension(state.minimum_height, state.content_scale) orelse return types.kResultFalse;
        const maximum_width = scaledDimension(state.maximum_width, state.content_scale) orelse return types.kResultFalse;
        const maximum_height = scaledDimension(state.maximum_height, state.content_scale) orelse return types.kResultFalse;
        if (width < minimum_width or height < minimum_height or
            width > maximum_width or height > maximum_height) return types.kResultFalse;
        const logical_width = logicalDimension(width, state.content_scale) orelse return types.kResultFalse;
        const logical_height = logicalDimension(height, state.content_scale) orelse return types.kResultFalse;
        if (zig_vstgui_editor_resize(state.editor, @intCast(logical_width), @intCast(logical_height)) != 0) {
            std.log.err("VSTGUI editor rejected logical size {d}x{d}", .{ logical_width, logical_height });
            return types.kResultFalse;
        }
        state.logical_width = logical_width;
        state.logical_height = logical_height;
        return types.kResultOk;
    }

    pub fn onKeyDown(self: anytype, key: types.char16, key_code: types.int16, modifiers: types.int16) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        return if (zig_vstgui_editor_key_down(state.editor, key, key_code, modifiers) == 0)
            types.kResultOk
        else
            types.kResultFalse;
    }

    pub fn onKeyUp(self: anytype, key: types.char16, key_code: types.int16, modifiers: types.int16) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        if (zig_vstgui_editor_key_up(state.editor, key, key_code, modifiers) == 0) return types.kResultOk;
        return switch (key_code) {
            iplugview.VirtualKeyCode.tab,
            iplugview.VirtualKeyCode.end,
            iplugview.VirtualKeyCode.home,
            iplugview.VirtualKeyCode.left,
            iplugview.VirtualKeyCode.up,
            iplugview.VirtualKeyCode.right,
            iplugview.VirtualKeyCode.down,
            => types.kResultOk,
            else => types.kResultFalse,
        };
    }

    pub fn onFocus(self: anytype, state: types.TBool) types.tresult {
        const editor_state = binding(self) orelse return types.kResultFalse;
        const focus_state = nativeFocusState(state) orelse return types.kInvalidArgument;
        zig_vstgui_editor_set_focus(editor_state.editor, focus_state);
        return types.kResultOk;
    }

    pub fn checkSizeConstraint(self: anytype, rect: *iplugview.ViewRect) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        const minimum_width = scaledDimension(state.minimum_width, state.content_scale) orelse return types.kResultFalse;
        const minimum_height = scaledDimension(state.minimum_height, state.content_scale) orelse return types.kResultFalse;
        const maximum_width = scaledDimension(state.maximum_width, state.content_scale) orelse return types.kResultFalse;
        const maximum_height = scaledDimension(state.maximum_height, state.content_scale) orelse return types.kResultFalse;
        const raw_width = @as(i64, rect.right) - @as(i64, rect.left);
        const raw_height = @as(i64, rect.bottom) - @as(i64, rect.top);
        const width: types.int32 = @intCast(std.math.clamp(raw_width, minimum_width, maximum_width));
        const height: types.int32 = @intCast(std.math.clamp(raw_height, minimum_height, maximum_height));
        rect.right = rectEnd(rect.left, width) orelse return types.kInvalidArgument;
        rect.bottom = rectEnd(rect.top, height) orelse return types.kInvalidArgument;
        return types.kResultOk;
    }

    pub fn setContentScaleFactor(self: anytype, factor: f32) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        const scaled_width = scaledDimension(state.logical_width, factor) orelse return types.kInvalidArgument;
        const scaled_height = scaledDimension(state.logical_height, factor) orelse return types.kInvalidArgument;
        if (zig_vstgui_editor_set_scale(state.editor, factor) != 0) {
            std.log.err("VSTGUI editor rejected content scale {d}", .{factor});
            return types.kResultFalse;
        }
        const previous_scale = state.content_scale;
        const previous_rect = self.rect;
        const scaled_right = rectEnd(self.rect.left, scaled_width) orelse return types.kInvalidArgument;
        const scaled_bottom = rectEnd(self.rect.top, scaled_height) orelse return types.kInvalidArgument;
        state.content_scale = factor;
        self.rect.right = scaled_right;
        self.rect.bottom = scaled_bottom;
        if (self.frame) |frame| {
            const result = frame.vtable.resizeView(frame, &self.iface, &self.rect);
            if (result != types.kResultOk) {
                self.rect = previous_rect;
                state.content_scale = previous_scale;
                _ = zig_vstgui_editor_set_scale(state.editor, previous_scale);
                return result;
            }
        }
        return types.kResultOk;
    }

    pub fn setFrame(self: anytype, frame: ?*iplugview.IPlugFrame) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        zig_vstgui_editor_set_frame(state.editor, frame);
        return types.kResultOk;
    }

    pub fn destroy(self: anytype) void {
        if (self.context) |context| {
            const state: *Binding = @ptrCast(@alignCast(context));
            if (state.attached) state.telemetry.closed();
            state.observer_callbacks.unsubscribe(state.observer_callbacks.userdata, state.editor);
            zig_vstgui_editor_destroy(state.editor);
            _ = state.controller.vtable.release(state.controller);
            state.telemetry.release();
            std.heap.page_allocator.destroy(state.telemetry);
            std.heap.page_allocator.destroy(state);
            self.context = null;
        }
    }
});

test "editor view retains both Linux platform protocols" {
    var view: View = .{};
    try std.testing.expectEqual(
        types.kResultOk,
        view.addPlatform(
            iplugview.PlatformType.kPlatformTypeX11EmbedWindowID,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        view.addPlatform(
            iplugview.PlatformType.kPlatformTypeWaylandSurfaceID,
        ),
    );
    try std.testing.expectEqual(@as(types.uint32, 2), view.platform_count);
}

pub fn create(
    controller: *ivsteditcontroller.IEditController,
    parameters: []const ParameterInfoBinding,
    meters: []const MeterDescription,
    graphs: []const GraphDescription,
    xy_pads: []const XYPadDescription,
    preset_browsers: []const PresetBrowserDescription,
    action_menus: []const ActionMenuDescription,
    pianos: []const PianoDescription,
    step_sequencers: []const StepSequencerDescription,
    file_drops: []const FileDropDescription,
    action_buttons: []const ActionButtonDescription,
    editable_labels: []const EditableLabelDescription,
    progress_indicators: []const ProgressIndicatorDescription,
    skin: Skin,
    composition: Composition,
    callbacks: Callbacks,
    observer_callbacks: ObserverCallbacks,
    wayland_host: ?*anyopaque,
    telemetry_provider: ?TelemetrySourceProvider,
    controller_graph: ControllerGraphCallbacks,
) ?*iplugview.IPlugView {
    const gui_allowed = realtime_audit.observe(.gui_call);
    const allocation_allowed = realtime_audit.observe(.allocation);
    if (!gui_allowed or !allocation_allowed) return null;
    if (builtin.os.tag != .macos and builtin.os.tag != .windows and builtin.os.tag != .linux) {
        return null;
    }
    if (parameters.len == 0 or parameters.len > max_parameters or
        meters.len > max_meters or graphs.len > max_graphs or xy_pads.len > max_xy_pads or
        preset_browsers.len > max_preset_browsers or action_menus.len > max_action_menus or pianos.len > max_pianos or
        step_sequencers.len > max_step_sequencers or
        file_drops.len > max_file_drops or action_buttons.len > max_action_buttons or
        editable_labels.len > max_editable_labels or progress_indicators.len > max_progress_indicators or
        skin.assets.len > max_assets or composition.groups.len > max_groups)
    {
        return null;
    }
    var descriptions: [max_parameters]ParameterDescription = undefined;
    for (parameters, 0..) |parameter, index| {
        descriptions[index] = .{
            .parameter_id = parameter.id,
            .initial_normalized = controller.vtable.getParamNormalized(controller, parameter.id),
            .info = parameter.info,
            .control_kind = parameter.control_kind,
        };
    }
    var assets: [max_assets]AssetDescription = undefined;
    for (skin.assets, 0..) |asset, index| {
        if (asset.data.len == 0 or asset.data.len > std.math.maxInt(types.uint32)) {
            return null;
        }
        assets[index] = .{
            .asset_id = asset.id,
            .data = asset.data.ptr,
            .data_size = @intCast(asset.data.len),
            .format = asset.format,
            .scale = asset.scale,
        };
    }
    var groups: [max_groups]GroupDescription = undefined;
    for (composition.groups, 0..) |group, index| {
        groups[index] = .{
            .title = group.title,
            .first_parameter = group.first_parameter,
            .parameter_count = group.parameter_count,
            .first_meter = group.first_meter,
            .meter_count = group.meter_count,
            .style = nativeStyle(group.style),
            .first_graph = group.first_graph,
            .graph_count = group.graph_count,
            .first_xy_pad = group.first_xy_pad,
            .xy_pad_count = group.xy_pad_count,
        };
    }
    const telemetry = std.heap.page_allocator.create(TelemetryState) catch {
        return null;
    };
    telemetry.* = .{ .source = null, .provider = telemetry_provider, .controller_graph = controller_graph };
    const editor = zig_vstgui_editor_create_components(
        &descriptions,
        @intCast(parameters.len),
        callbacks,
        if (meters.len == 0) null else meters.ptr,
        @intCast(meters.len),
        .{ .userdata = telemetry, .load = loadMeter },
        if (graphs.len == 0) null else graphs.ptr,
        @intCast(graphs.len),
        .{ .userdata = telemetry, .load = loadGraph },
        if (xy_pads.len == 0) null else xy_pads.ptr,
        @intCast(xy_pads.len),
        if (preset_browsers.len == 0) null else preset_browsers.ptr,
        @intCast(preset_browsers.len),
        if (action_menus.len == 0) null else action_menus.ptr,
        @intCast(action_menus.len),
        if (pianos.len == 0) null else pianos.ptr,
        @intCast(pianos.len),
        if (step_sequencers.len == 0) null else step_sequencers.ptr,
        @intCast(step_sequencers.len),
        if (file_drops.len == 0) null else file_drops.ptr,
        @intCast(file_drops.len),
        if (action_buttons.len == 0) null else action_buttons.ptr,
        @intCast(action_buttons.len),
        if (editable_labels.len == 0) null else editable_labels.ptr,
        @intCast(editable_labels.len),
        if (progress_indicators.len == 0) null else progress_indicators.ptr,
        @intCast(progress_indicators.len),
        .{
            .assets = if (skin.assets.len == 0) null else &assets,
            .asset_count = @intCast(skin.assets.len),
            .fonts = skin.fonts,
            .drawing = skin.drawing,
            .theme = skin.theme,
            .layout = skin.layout,
            .editor_title = composition.title,
            .groups = if (composition.groups.len == 0) null else &groups,
            .group_count = @intCast(composition.groups.len),
            .editor_style = nativeStyle(composition.style),
        },
    ) orelse {
        telemetry.release();
        std.heap.page_allocator.destroy(telemetry);
        return null;
    };
    zig_vstgui_editor_set_wayland_host(editor, wayland_host);
    const state = std.heap.page_allocator.create(Binding) catch {
        zig_vstgui_editor_destroy(editor);
        telemetry.release();
        std.heap.page_allocator.destroy(telemetry);
        return null;
    };
    state.* = .{
        .editor = editor,
        .controller = controller,
        .observer_callbacks = observer_callbacks,
        .telemetry = telemetry,
        .has_preset_browser = preset_browsers.len > 0,
        .minimum_width = if (skin.layout == .parameter_workspace) 400 else if (preset_browsers.len > 0) 480 else 320,
        .minimum_height = if (skin.layout == .parameter_workspace) 360 else if (preset_browsers.len > 0) 480 else 240,
        .logical_width = if (skin.layout == .parameter_workspace or preset_browsers.len > 0) 720 else 400,
        .logical_height = if (skin.layout == .parameter_workspace) 660 else if (preset_browsers.len > 0) 600 else 300,
    };
    if (!observer_callbacks.subscribe(observer_callbacks.userdata, editor)) {
        std.heap.page_allocator.destroy(state);
        telemetry.release();
        std.heap.page_allocator.destroy(telemetry);
        zig_vstgui_editor_destroy(editor);
        return null;
    }
    const view = View.create() orelse {
        observer_callbacks.unsubscribe(observer_callbacks.userdata, editor);
        std.heap.page_allocator.destroy(state);
        telemetry.release();
        std.heap.page_allocator.destroy(telemetry);
        zig_vstgui_editor_destroy(editor);
        return null;
    };
    if (skin.layout == .parameter_workspace) {
        view.rect.right = 720;
        view.rect.bottom = 660;
    } else if (preset_browsers.len > 0) {
        view.rect.right = 720;
        view.rect.bottom = 600;
    }
    view.context = state;
    zig_vstgui_editor_set_resize_callbacks(editor, .{
        .userdata = view,
        .request_resize = requestEditorResize,
    });
    _ = controller.vtable.addRef(controller);
    const platform_result = switch (builtin.os.tag) {
        .macos => view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView),
        .windows => view.addPlatform(iplugview.PlatformType.kPlatformTypeHWND),
        .linux => blk: {
            if (view.addPlatform(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID) != types.kResultOk) break :blk types.kResultFalse;
            break :blk view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID);
        },
        else => types.kResultFalse,
    };
    if (platform_result != types.kResultOk) {
        _ = view.iface.vtable.release(&view.iface);
        return null;
    }
    return view.asInterface();
}

fn nativeStyle(style: StyleOverride) NativeStyleOverride {
    var mask: types.uint32 = 0;
    if (style.background != null) mask |= 1 << 0;
    if (style.foreground != null) mask |= 1 << 1;
    if (style.border != null) mask |= 1 << 2;
    if (style.accent != null) mask |= 1 << 3;
    return .{
        .mask = mask,
        .background_rgba = style.background orelse 0,
        .foreground_rgba = style.foreground orelse 0,
        .border_rgba = style.border orelse 0,
        .accent_rgba = style.accent orelse 0,
    };
}

fn loadMeter(userdata: ?*anyopaque, source_id: types.uint32) callconv(.c) f64 {
    const state: *TelemetryState = @ptrCast(@alignCast(userdata orelse return 0.0));
    state.acquire();
    const source = state.source orelse return 0.0;
    return source.load(source_id);
}

fn loadGraph(
    userdata: ?*anyopaque,
    source_id: types.uint32,
    output: [*c]gui_graph.Point,
    capacity: types.uint32,
) callconv(.c) types.uint32 {
    const state: *TelemetryState = @ptrCast(@alignCast(userdata orelse return 0));
    if (capacity == 0) return 0;
    const output_slice = cSlice(
        gui_graph.Point,
        output,
        capacity,
    ) orelse return 0;
    if (source_id & controller_graph_source_flag != 0) {
        const count = state.controller_graph.load(
            state.controller_graph.userdata,
            source_id & ~controller_graph_source_flag,
            output_slice.ptr,
            capacity,
        );
        return @min(count, capacity);
    }
    state.acquire();
    const source = state.source orelse return 0;
    return @intCast(source.loadGraph(source_id, output_slice));
}

fn requestEditorResize(userdata: ?*anyopaque, width: types.uint32, height: types.uint32) callconv(.c) types.int32 {
    const view: *View = @ptrCast(@alignCast(userdata orelse return -1));
    const state = binding(view) orelse return -1;
    const logical_width = std.math.cast(types.int32, width) orelse return -1;
    const logical_height = std.math.cast(types.int32, height) orelse return -1;
    const physical_width = scaledDimension(logical_width, state.content_scale) orelse return -1;
    const physical_height = scaledDimension(logical_height, state.content_scale) orelse return -1;
    const result = view.requestResize(.{
        .left = 0,
        .top = 0,
        .right = physical_width,
        .bottom = physical_height,
    });
    if (result != types.kResultOk) {
        std.log.err("host rejected VSTGUI editor resize {d}x{d}", .{ width, height });
        return -1;
    }
    return 0;
}

pub const ParameterInfoBinding = struct {
    id: vsttypes.ParamID,
    info: ParameterInfo,
    control_kind: ControlKind,
};

pub fn setParameter(observer_userdata: *anyopaque, parameter_id: vsttypes.ParamID, value: f64) void {
    const editor: *Editor = @ptrCast(@alignCast(observer_userdata));
    _ = zig_vstgui_editor_set_parameter(editor, parameter_id, value);
}

pub fn refreshParameters(observer_userdata: *anyopaque, parameters: []const ParameterValue) bool {
    if (parameters.len > max_parameters) return false;
    const editor: *Editor = @ptrCast(@alignCast(observer_userdata));
    return zig_vstgui_editor_refresh_parameters(editor, parameters.ptr, @intCast(parameters.len)) == 0;
}

pub fn fillRect(canvas: *Canvas, left: f64, top: f64, right: f64, bottom: f64, rgba: types.uint32) void {
    if (comptime vstgui_adapter_enabled) {
        zig_vstgui_canvas_fill_rect(canvas, left, top, right, bottom, rgba);
    }
}

pub fn strokeRect(
    canvas: *Canvas,
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
    rgba: types.uint32,
    width: f64,
) void {
    if (comptime vstgui_adapter_enabled) {
        zig_vstgui_canvas_stroke_rect(canvas, left, top, right, bottom, rgba, width);
    }
}

pub fn fillEllipse(canvas: *Canvas, left: f64, top: f64, right: f64, bottom: f64, rgba: types.uint32) void {
    if (comptime vstgui_adapter_enabled) {
        zig_vstgui_canvas_fill_ellipse(canvas, left, top, right, bottom, rgba);
    }
}

pub fn line(
    canvas: *Canvas,
    start_x: f64,
    start_y: f64,
    end_x: f64,
    end_y: f64,
    rgba: types.uint32,
    width: f64,
) void {
    if (comptime vstgui_adapter_enabled) {
        zig_vstgui_canvas_line(canvas, start_x, start_y, end_x, end_y, rgba, width);
    }
}

pub fn drawAsset(
    canvas: *Canvas,
    asset_id: types.uint32,
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
    alpha: f32,
) bool {
    if (comptime vstgui_adapter_enabled) {
        return zig_vstgui_canvas_draw_asset(canvas, asset_id, left, top, right, bottom, alpha) == 0;
    }
    return false;
}

test "view rectangle arithmetic rejects invalid and overflowing coordinates" {
    try std.testing.expectEqual(@as(?types.int32, 640), rectDimension(10, 650));
    try std.testing.expectEqual(@as(?types.int32, null), rectDimension(10, 10));
    try std.testing.expectEqual(@as(?types.int32, null), rectDimension(10, 9));
    try std.testing.expectEqual(
        @as(?types.int32, null),
        rectDimension(std.math.minInt(types.int32), std.math.maxInt(types.int32)),
    );

    try std.testing.expectEqual(@as(?types.int32, 650), rectEnd(10, 640));
    try std.testing.expectEqual(@as(?types.int32, null), rectEnd(10, 0));
    try std.testing.expectEqual(
        @as(?types.int32, null),
        rectEnd(std.math.maxInt(types.int32), 1),
    );
}

test "native callback pointer helpers reject null" {
    try std.testing.expect(cSlice(u8, null, 1) == null);
    try std.testing.expect(cConstSlice(u8, null, 1) == null);
    try std.testing.expect(cPointer(u8, null) == null);
    try std.testing.expect(cStringBytes(null) == null);

    var bytes = [_]u8{ 1, 2 };
    try std.testing.expectEqualSlices(
        u8,
        &bytes,
        cSlice(u8, &bytes, bytes.len).?,
    );
    try std.testing.expect(cPointer(u8, &bytes).? == &bytes[0]);
    try std.testing.expectEqualSlices(
        u8,
        &bytes,
        cConstSlice(u8, &bytes, bytes.len).?,
    );
    try std.testing.expectEqualStrings(
        "value",
        cStringBytes("value").?,
    );
}

test "native focus state rejects malformed booleans" {
    try std.testing.expectEqual(@as(?types.int32, 0), nativeFocusState(0));
    try std.testing.expectEqual(@as(?types.int32, 1), nativeFocusState(1));
    try std.testing.expectEqual(@as(?types.int32, null), nativeFocusState(2));
    try std.testing.expectEqual(@as(?types.int32, null), nativeFocusState(std.math.maxInt(types.TBool)));
}

test "controller graph callback count is bounded by output capacity" {
    const Callback = struct {
        fn load(
            _: ?*anyopaque,
            _: types.uint32,
            _: [*c]gui_graph.Point,
            _: types.uint32,
        ) callconv(.c) types.uint32 {
            return std.math.maxInt(types.uint32);
        }
    };
    var state = TelemetryState{
        .source = null,
        .provider = null,
        .controller_graph = .{
            .userdata = null,
            .load = Callback.load,
        },
    };
    var output: [2]gui_graph.Point = undefined;
    try std.testing.expectEqual(
        @as(types.uint32, output.len),
        loadGraph(
            &state,
            controller_graph_source_flag,
            &output,
            output.len,
        ),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 0),
        loadGraph(
            &state,
            controller_graph_source_flag,
            null,
            output.len,
        ),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 0),
        loadGraph(
            &state,
            controller_graph_source_flag,
            null,
            0,
        ),
    );
}

test "telemetry source can connect after the editor opens" {
    const MockSource = struct {
        iface: gui_telemetry_source.Interface,
        available: bool = false,
        references: u32 = 1,
        opened_count: u32 = 0,
        closed_count: u32 = 0,

        const vtable = gui_telemetry_source.VTable{
            .queryInterface = queryInterface,
            .addRef = addRef,
            .release = release,
            .load = load,
            .editorOpened = editorOpened,
            .editorClosed = editorClosed,
            .loadGraph = @This().loadGraph,
            .loadText = @This().loadText,
        };

        fn owner(ptr: *anyopaque) *@This() {
            return @ptrCast(@alignCast(ptr));
        }

        fn queryInterface(_: *anyopaque, _: [*c]const @import("tuid.zig").TUID, out_raw: [*c]?*anyopaque) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *?*anyopaque = @ptrCast(out_raw);
            out.* = null;
            return types.kNoInterface;
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.references += 1;
            return self.references;
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.references -= 1;
            return self.references;
        }

        fn load(_: *anyopaque, _: types.uint32) callconv(.c) f64 {
            return 0.0;
        }

        fn editorOpened(ptr: *anyopaque) callconv(.c) void {
            owner(ptr).opened_count += 1;
        }

        fn editorClosed(ptr: *anyopaque) callconv(.c) void {
            owner(ptr).closed_count += 1;
        }

        fn loadGraph(_: *anyopaque, _: types.uint32, output: [*c]gui_graph.Point, _: types.uint32) callconv(.c) types.uint32 {
            if (output == null) return 0;
            return 0;
        }

        fn loadText(_: *anyopaque, _: types.uint32, output: [*c]u8, _: types.uint32) callconv(.c) types.uint32 {
            if (output == null) return 0;
            return 0;
        }

        fn retain(ptr: *anyopaque) ?gui_telemetry_source.RetainedSource {
            const self = owner(ptr);
            if (!self.available) return null;
            _ = addRef(&self.iface);
            return .{ .iface = &self.iface };
        }
    };

    var mock = MockSource{ .iface = .{ .vtable = &MockSource.vtable } };
    var state = TelemetryState{
        .source = null,
        .provider = .{ .userdata = &mock, .retain = MockSource.retain },
        .controller_graph = undefined,
    };

    state.opened();
    try std.testing.expectEqual(@as(u32, 0), mock.opened_count);
    mock.available = true;
    state.acquire();
    try std.testing.expectEqual(@as(u32, 1), mock.opened_count);
    try std.testing.expectEqual(@as(u32, 2), mock.references);
    state.closed();
    try std.testing.expectEqual(@as(u32, 1), mock.closed_count);
    state.release();
    try std.testing.expectEqual(@as(u32, 1), mock.references);
}
