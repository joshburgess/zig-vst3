const builtin = @import("builtin");
const std = @import("std");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_plug_view = @import("vst_plug_view.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const gui_telemetry_source = @import("gui_telemetry_source.zig");
const gui_graph = @import("zig-vst3-plugin-core").gui_graph;
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
    begin_edit: *const fn (?*anyopaque, vsttypes.ParamID) callconv(.c) void,
    perform_edit: *const fn (?*anyopaque, vsttypes.ParamID, f64) callconv(.c) types.int32,
    end_edit: *const fn (?*anyopaque, vsttypes.ParamID) callconv(.c) void,
    format_value: *const fn (?*anyopaque, vsttypes.ParamID, f64, [*]u8, types.uint32) callconv(.c) types.int32,
    parse_value: *const fn (?*anyopaque, vsttypes.ParamID, [*:0]const u8, *f64) callconv(.c) types.int32,
    show_context_menu: *const fn (?*anyopaque, vsttypes.ParamID, types.int32, types.int32) callconv(.c) types.int32,
    store_editor_index: *const fn (?*anyopaque, types.uint32, types.uint32) callconv(.c) types.int32,
    store_editor_envelope: *const fn (?*anyopaque, types.uint32, [*]const EnvelopePoint, types.uint32) callconv(.c) types.int32,
    store_editor_text: *const fn (?*anyopaque, types.uint32, [*:0]const u8) callconv(.c) types.int32,
    load_preset: *const fn (?*anyopaque, types.uint32) callconv(.c) types.int32,
    store_editor_bool: *const fn (?*anyopaque, types.uint32, types.int32) callconv(.c) types.int32,
    invoke_menu_action: *const fn (?*anyopaque, types.uint32, types.uint32, types.int32) callconv(.c) types.int32,
    invoke_action: *const fn (?*anyopaque, types.uint32, types.uint32) callconv(.c) types.int32,
    send_note: *const fn (?*anyopaque, types.int32, types.int32, f64, types.int32) callconv(.c) types.int32,
    drop_files: *const fn (?*anyopaque, types.uint32, [*]const [*:0]const u8, types.uint32) callconv(.c) types.int32,
    import_files: *const fn (?*anyopaque, types.uint32, FileImportEntryPoint, [*]const [*:0]const u8, types.uint32) callconv(.c) types.int32,
    load_file_import: *const fn (?*anyopaque, types.uint32, *FileImportSnapshot) callconv(.c) types.int32,
    command_file_import: *const fn (?*anyopaque, types.uint32, FileImportCommand) callconv(.c) types.int32,
    load_editor_text: *const fn (?*anyopaque, types.uint32, [*]u8, types.uint32) callconv(.c) types.int32,
    load_progress: *const fn (?*anyopaque, types.uint32, *ProgressSnapshot) callconv(.c) types.int32,
    store_editor_scalars: *const fn (?*anyopaque, [*]const types.uint32, [*]const f64, types.uint32) callconv(.c) types.int32,
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
pub const max_graph_points = 256;
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
};

pub const GraphLayerDescription = extern struct {
    style: GraphStyleRole,
    points: ?[*]const gui_graph.Point,
    point_count: types.uint32,
    source_id: types.uint32,
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
};

const GraphCallbacks = extern struct {
    userdata: ?*anyopaque,
    load: *const fn (?*anyopaque, types.uint32, [*]gui_graph.Point, types.uint32) callconv(.c) types.uint32,
};

pub const ControllerGraphCallbacks = struct {
    userdata: ?*anyopaque,
    load: *const fn (?*anyopaque, types.uint32, [*]gui_graph.Point, types.uint32) callconv(.c) types.uint32,
};

pub const controller_graph_source_flag: types.uint32 = 1 << 31;

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

const Binding = struct {
    editor: *Editor,
    controller: *ivsteditcontroller.IEditController,
    observer_callbacks: ObserverCallbacks,
    telemetry: *TelemetryState,
    attached: bool = false,
    has_preset_browser: bool = false,
};

const TelemetryState = struct {
    source: ?gui_telemetry_source.RetainedSource,
    controller_graph: ControllerGraphCallbacks,

    fn opened(self: *TelemetryState) void {
        if (self.source) |source| source.editorOpened();
    }

    fn closed(self: *TelemetryState) void {
        if (self.source) |source| source.editorClosed();
    }

    fn release(self: *TelemetryState) void {
        if (self.source) |source| source.release();
        self.source = null;
    }
};

fn binding(self: anytype) ?*Binding {
    return @ptrCast(@alignCast(self.context orelse return null));
}

const View = vst_plug_view.PlugView(1, struct {
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
        const width = rect.right - rect.left;
        const height = rect.bottom - rect.top;
        const state = binding(self) orelse return types.kResultFalse;
        const minimum_width: types.int32 = if (state.has_preset_browser) 480 else 320;
        const minimum_height: types.int32 = if (state.has_preset_browser) 480 else 240;
        if (width < minimum_width or height < minimum_height) return types.kResultFalse;
        if (zig_vstgui_editor_resize(state.editor, @intCast(width), @intCast(height)) != 0) {
            std.log.err("VSTGUI editor rejected size {d}x{d}", .{ width, height });
            return types.kResultFalse;
        }
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
        zig_vstgui_editor_set_focus(editor_state.editor, state);
        return types.kResultOk;
    }

    pub fn checkSizeConstraint(self: anytype, rect: *iplugview.ViewRect) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        const minimum_width: types.int32 = if (state.has_preset_browser) 480 else 320;
        const minimum_height: types.int32 = if (state.has_preset_browser) 480 else 240;
        rect.right = std.math.clamp(rect.right, minimum_width, 1_000);
        rect.bottom = std.math.clamp(rect.bottom, minimum_height, 700);
        return types.kResultOk;
    }

    pub fn setContentScaleFactor(self: anytype, factor: f32) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        if (zig_vstgui_editor_set_scale(state.editor, factor) != 0) {
            std.log.err("VSTGUI editor rejected content scale {d}", .{factor});
            return types.kResultFalse;
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
    telemetry_source: ?gui_telemetry_source.RetainedSource,
    controller_graph: ControllerGraphCallbacks,
) ?*iplugview.IPlugView {
    if (builtin.os.tag != .macos and builtin.os.tag != .windows and builtin.os.tag != .linux) {
        if (telemetry_source) |source| source.release();
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
        if (telemetry_source) |source| source.release();
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
            if (telemetry_source) |source| source.release();
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
        if (telemetry_source) |source| source.release();
        return null;
    };
    telemetry.* = .{ .source = telemetry_source, .controller_graph = controller_graph };
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
    if (preset_browsers.len > 0) {
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
    const source = state.source orelse return 0.0;
    return source.load(source_id);
}

fn loadGraph(
    userdata: ?*anyopaque,
    source_id: types.uint32,
    output: [*]gui_graph.Point,
    capacity: types.uint32,
) callconv(.c) types.uint32 {
    const state: *TelemetryState = @ptrCast(@alignCast(userdata orelse return 0));
    if (source_id & controller_graph_source_flag != 0) {
        return state.controller_graph.load(
            state.controller_graph.userdata,
            source_id & ~controller_graph_source_flag,
            output,
            capacity,
        );
    }
    const source = state.source orelse return 0;
    return @intCast(source.loadGraph(source_id, output[0..capacity]));
}

fn requestEditorResize(userdata: ?*anyopaque, width: types.uint32, height: types.uint32) callconv(.c) types.int32 {
    const view: *View = @ptrCast(@alignCast(userdata orelse return -1));
    const result = view.requestResize(.{
        .left = 0,
        .top = 0,
        .right = @intCast(width),
        .bottom = @intCast(height),
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
