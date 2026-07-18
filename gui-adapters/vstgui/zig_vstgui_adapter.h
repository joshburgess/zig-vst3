#ifndef ZIG_VSTGUI_ADAPTER_H
#define ZIG_VSTGUI_ADAPTER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ZigVstguiFileImportEntryPoint {
    ZIG_VSTGUI_FILE_IMPORT_DROP = 0,
    ZIG_VSTGUI_FILE_IMPORT_PICKER = 1
} ZigVstguiFileImportEntryPoint;

typedef enum ZigVstguiFileImportStatus {
    ZIG_VSTGUI_FILE_IMPORT_IDLE = 0,
    ZIG_VSTGUI_FILE_IMPORT_VALIDATING = 1,
    ZIG_VSTGUI_FILE_IMPORT_IMPORTING = 2,
    ZIG_VSTGUI_FILE_IMPORT_READY = 3,
    ZIG_VSTGUI_FILE_IMPORT_EMPTY = 4,
    ZIG_VSTGUI_FILE_IMPORT_UNSUPPORTED_FILE = 5,
    ZIG_VSTGUI_FILE_IMPORT_CAPACITY_LIMIT = 6,
    ZIG_VSTGUI_FILE_IMPORT_INVALID_PATH = 7,
    ZIG_VSTGUI_FILE_IMPORT_CANCELLED = 8,
    ZIG_VSTGUI_FILE_IMPORT_FAILED = 9
} ZigVstguiFileImportStatus;

typedef enum ZigVstguiFileImportFailure {
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE = 0,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_OPEN = 1,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_TOO_LARGE = 2,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_MALFORMED = 3,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_TRUNCATED = 4,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_UNSUPPORTED_FORMAT = 5,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_CANCELLED = 6,
    ZIG_VSTGUI_FILE_IMPORT_FAILURE_WORKER_UNAVAILABLE = 7
} ZigVstguiFileImportFailure;

typedef enum ZigVstguiFileImportCommand {
    ZIG_VSTGUI_FILE_IMPORT_CANCEL = 0,
    ZIG_VSTGUI_FILE_IMPORT_RETRY = 1,
    ZIG_VSTGUI_FILE_IMPORT_RESET = 2
} ZigVstguiFileImportCommand;

typedef struct ZigVstguiFileImportSnapshot {
    ZigVstguiFileImportStatus status;
    ZigVstguiFileImportFailure failure;
    ZigVstguiFileImportEntryPoint entry_point;
    double progress;
    uint64_t generation;
    uint32_t sample_rate;
    uint32_t channels;
    uint64_t sample_frames;
    uint32_t preview_points;
} ZigVstguiFileImportSnapshot;

typedef struct ZigVstguiCallbacks {
    void* userdata;
    void (*begin_edit)(void* userdata, uint32_t parameter_id);
    int32_t (*perform_edit)(void* userdata, uint32_t parameter_id, double normalized);
    void (*end_edit)(void* userdata, uint32_t parameter_id);
    int32_t (*format_value)(void* userdata, uint32_t parameter_id, double normalized, char* output, uint32_t capacity);
    int32_t (*parse_value)(void* userdata, uint32_t parameter_id, const char* text, double* normalized);
    int32_t (*show_context_menu)(void* userdata, uint32_t parameter_id, int32_t x, int32_t y);
    int32_t (*store_editor_index)(void* userdata, uint32_t field_id, uint32_t value);
    int32_t (*store_editor_envelope)(void* userdata, uint32_t field_id, const struct ZigVstguiEnvelopePoint* points, uint32_t count);
    int32_t (*store_editor_text)(void* userdata, uint32_t field_id, const char* text);
    int32_t (*load_preset)(void* userdata, uint32_t preset_id);
    int32_t (*store_editor_bool)(void* userdata, uint32_t field_id, int32_t value);
    int32_t (*invoke_menu_action)(void* userdata, uint32_t menu_id, uint32_t item_id, int32_t checked);
    int32_t (*send_note)(void* userdata, int32_t channel, int32_t pitch, double velocity, int32_t pressed);
    int32_t (*drop_files)(void* userdata, uint32_t drop_id, const char* const* paths, uint32_t count);
    int32_t (*import_files)(void* userdata, uint32_t drop_id, ZigVstguiFileImportEntryPoint entry_point, const char* const* paths, uint32_t count);
    int32_t (*load_file_import)(void* userdata, uint32_t drop_id, ZigVstguiFileImportSnapshot* snapshot);
    int32_t (*command_file_import)(void* userdata, uint32_t drop_id, ZigVstguiFileImportCommand command);
} ZigVstguiCallbacks;

typedef struct ZigVstguiParameterInfo {
    const char* title;
    const char* units;
    int32_t step_count;
    double default_normalized;
    const char* tooltip;
    double modulation_normalized;
    int32_t has_modulation;
} ZigVstguiParameterInfo;

typedef enum ZigVstguiControlKind {
    ZIG_VSTGUI_CONTROL_LINEAR_SLIDER = 0,
    ZIG_VSTGUI_CONTROL_ROTARY_KNOB = 1,
    ZIG_VSTGUI_CONTROL_TOGGLE = 2,
    ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN = 3,
    ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM = 4,
    ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER = 5,
    ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER = 6
} ZigVstguiControlKind;

typedef struct ZigVstguiParameterDescription {
    uint32_t parameter_id;
    double initial_normalized;
    ZigVstguiParameterInfo info;
    ZigVstguiControlKind control_kind;
} ZigVstguiParameterDescription;

typedef struct ZigVstguiParameterValue {
    uint32_t parameter_id;
    double normalized;
} ZigVstguiParameterValue;

enum { ZIG_VSTGUI_MAX_PARAMETERS = 64 };

typedef struct ZigVstguiXYPadDescription {
    const char* title;
    uint32_t x_parameter_id;
    uint32_t y_parameter_id;
    const char* x_label;
    const char* y_label;
} ZigVstguiXYPadDescription;

enum { ZIG_VSTGUI_MAX_XY_PADS = 8 };

typedef struct ZigVstguiPreset {
    uint32_t preset_id;
    const char* name;
} ZigVstguiPreset;

typedef struct ZigVstguiPresetBrowserDescription {
    const char* title;
    const ZigVstguiPreset* presets;
    uint32_t preset_count;
    uint32_t search_state_id;
    uint32_t selection_state_id;
    const char* initial_search;
    uint32_t initial_selection;
} ZigVstguiPresetBrowserDescription;

enum { ZIG_VSTGUI_MAX_PRESET_BROWSERS = 2 };
enum { ZIG_VSTGUI_MAX_PRESETS = 64 };

typedef enum ZigVstguiMenuItemKind {
    ZIG_VSTGUI_MENU_ACTION = 0,
    ZIG_VSTGUI_MENU_TOGGLE = 1,
    ZIG_VSTGUI_MENU_SEPARATOR = 2
} ZigVstguiMenuItemKind;

typedef struct ZigVstguiMenuItemDescription {
    uint32_t item_id;
    const char* label;
    ZigVstguiMenuItemKind kind;
    int32_t enabled;
    int32_t destructive;
    uint32_t checked_state_id;
    int32_t initial_checked;
} ZigVstguiMenuItemDescription;

typedef struct ZigVstguiActionMenuDescription {
    uint32_t menu_id;
    const char* title;
    const ZigVstguiMenuItemDescription* items;
    uint32_t item_count;
} ZigVstguiActionMenuDescription;

enum { ZIG_VSTGUI_MAX_ACTION_MENUS = 4 };
enum { ZIG_VSTGUI_MAX_MENU_ITEMS = 16 };

typedef struct ZigVstguiPianoDescription {
    const char* title;
    uint32_t first_note;
    uint32_t note_count;
    int32_t channel;
    double velocity;
    uint32_t computer_base_pitch;
} ZigVstguiPianoDescription;

enum { ZIG_VSTGUI_MAX_PIANOS = 2 };

typedef struct ZigVstguiStepSequencerDescription {
    const char* title;
    const uint32_t* parameter_ids;
    uint32_t step_count;
    uint32_t selection_state_id;
    uint32_t initial_selection_mask;
    uint32_t initial_active_mask;
    int32_t enabled;
    uint32_t playhead_source_id;
    uint32_t maximum_refresh_hz;
} ZigVstguiStepSequencerDescription;

enum { ZIG_VSTGUI_MAX_STEP_SEQUENCERS = 2 };
enum { ZIG_VSTGUI_MAX_STEPS = 32 };

typedef struct ZigVstguiFileDropDescription {
    uint32_t drop_id;
    const char* title;
    const char* prompt;
    const char* const* extensions;
    uint32_t extension_count;
    uint32_t maximum_files;
    int32_t enabled;
    const char* picker_label;
    const char* picker_title;
} ZigVstguiFileDropDescription;

enum { ZIG_VSTGUI_MAX_FILE_DROPS = 2 };
enum { ZIG_VSTGUI_MAX_DROP_EXTENSIONS = 8 };
enum { ZIG_VSTGUI_MAX_DROP_EXTENSION_BYTES = 16 };
enum { ZIG_VSTGUI_MAX_DROP_FILES = 8 };
enum { ZIG_VSTGUI_MAX_DROP_PATH_BYTES = 1024 };

typedef enum ZigVstguiMeterKind {
    ZIG_VSTGUI_METER_PEAK = 0,
    ZIG_VSTGUI_METER_STEREO = 1,
    ZIG_VSTGUI_METER_GAIN_REDUCTION = 2
} ZigVstguiMeterKind;

typedef struct ZigVstguiMeterDescription {
    const char* title;
    ZigVstguiMeterKind kind;
    uint32_t first_source_id;
    uint32_t second_source_id;
} ZigVstguiMeterDescription;

typedef struct ZigVstguiMeterCallbacks {
    void* userdata;
    double (*load)(void* userdata, uint32_t source_id);
} ZigVstguiMeterCallbacks;

enum { ZIG_VSTGUI_MAX_METERS = 8 };

typedef struct ZigVstguiGraphPoint {
    double x;
    double y;
} ZigVstguiGraphPoint;

typedef enum ZigVstguiGraphScale {
    ZIG_VSTGUI_GRAPH_LINEAR = 0,
    ZIG_VSTGUI_GRAPH_LOGARITHMIC = 1,
    ZIG_VSTGUI_GRAPH_DECIBELS = 2
} ZigVstguiGraphScale;

typedef enum ZigVstguiGraphKind {
    ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION = 0,
    ZIG_VSTGUI_GRAPH_ENVELOPE = 1,
    ZIG_VSTGUI_GRAPH_WAVEFORM = 2,
    ZIG_VSTGUI_GRAPH_SPECTRUM = 3
} ZigVstguiGraphKind;

typedef enum ZigVstguiGraphStyleRole {
    ZIG_VSTGUI_GRAPH_PRIMARY = 0,
    ZIG_VSTGUI_GRAPH_SECONDARY = 1,
    ZIG_VSTGUI_GRAPH_MODULATION = 2,
    ZIG_VSTGUI_GRAPH_WARNING = 3
} ZigVstguiGraphStyleRole;

typedef struct ZigVstguiGraphAxis {
    double minimum;
    double maximum;
    ZigVstguiGraphScale scale;
    const char* label;
} ZigVstguiGraphAxis;

typedef struct ZigVstguiEnvelopePoint {
    uint32_t point_id;
    double x;
    double y;
    uint32_t x_parameter_id;
    uint32_t y_parameter_id;
    uint32_t parameter_mask;
    int32_t x_step_count;
    int32_t y_step_count;
} ZigVstguiEnvelopePoint;

typedef struct ZigVstguiGraphDescription {
    const char* title;
    ZigVstguiGraphKind kind;
    ZigVstguiGraphStyleRole style;
    ZigVstguiGraphAxis x_axis;
    ZigVstguiGraphAxis y_axis;
    const ZigVstguiGraphPoint* points;
    uint32_t point_count;
    uint32_t source_id;
    int32_t dynamic;
    uint32_t maximum_refresh_hz;
    const ZigVstguiEnvelopePoint* editable_points;
    uint32_t editable_point_count;
    uint32_t point_capacity;
    uint32_t minimum_point_count;
    double snap_x;
    double snap_y;
    uint32_t selection_state_id;
    uint32_t envelope_state_id;
    uint32_t initial_selected_point_id;
} ZigVstguiGraphDescription;

typedef struct ZigVstguiGraphCallbacks {
    void* userdata;
    uint32_t (*load)(void* userdata, uint32_t source_id, ZigVstguiGraphPoint* output, uint32_t capacity);
} ZigVstguiGraphCallbacks;

enum { ZIG_VSTGUI_MAX_GRAPHS = 8 };
enum { ZIG_VSTGUI_MAX_GRAPH_POINTS = 256 };

typedef enum ZigVstguiAssetFormat {
    ZIG_VSTGUI_ASSET_PNG = 0,
    ZIG_VSTGUI_ASSET_SVG = 1
} ZigVstguiAssetFormat;

typedef enum ZigVstguiAssetScale {
    ZIG_VSTGUI_ASSET_PIXEL_EXACT = 0,
    ZIG_VSTGUI_ASSET_CONTAIN = 1,
    ZIG_VSTGUI_ASSET_COVER = 2,
    ZIG_VSTGUI_ASSET_STRETCH = 3
} ZigVstguiAssetScale;

typedef struct ZigVstguiAssetDescription {
    uint32_t asset_id;
    const uint8_t* data;
    uint32_t data_size;
    ZigVstguiAssetFormat format;
    ZigVstguiAssetScale scale;
} ZigVstguiAssetDescription;

enum { ZIG_VSTGUI_MAX_ASSETS = 16 };
enum { ZIG_VSTGUI_MAX_GROUPS = 8 };

typedef struct ZigVstguiFontDescription {
    const char* title_family;
    const char* body_family;
    const char* value_family;
    const char* fallback_family;
} ZigVstguiFontDescription;

typedef enum ZigVstguiDrawingComponent {
    ZIG_VSTGUI_DRAW_SLIDER = 0,
    ZIG_VSTGUI_DRAW_KNOB = 1,
    ZIG_VSTGUI_DRAW_TOGGLE = 2,
    ZIG_VSTGUI_DRAW_DROPDOWN = 3,
    ZIG_VSTGUI_DRAW_SEGMENTED = 4
} ZigVstguiDrawingComponent;

typedef enum ZigVstguiDrawingState {
    ZIG_VSTGUI_DRAW_NORMAL = 0,
    ZIG_VSTGUI_DRAW_HOVERED = 1,
    ZIG_VSTGUI_DRAW_PRESSED = 2,
    ZIG_VSTGUI_DRAW_FOCUSED = 3,
    ZIG_VSTGUI_DRAW_DISABLED = 4,
    ZIG_VSTGUI_DRAW_EDITING = 5
} ZigVstguiDrawingState;

typedef struct ZigVstguiDrawRequest {
    uint32_t parameter_id;
    ZigVstguiDrawingComponent component;
    ZigVstguiDrawingState state;
    double normalized;
    double width;
    double height;
    double scale_factor;
} ZigVstguiDrawRequest;

typedef struct ZigVstguiCanvas ZigVstguiCanvas;

typedef struct ZigVstguiDrawingCallbacks {
    void* userdata;
    int32_t (*draw_parameter)(
        void* userdata,
        const ZigVstguiDrawRequest* request,
        ZigVstguiCanvas* canvas
    );
} ZigVstguiDrawingCallbacks;

typedef enum ZigVstguiThemeKind {
    ZIG_VSTGUI_THEME_DEFAULT = 0,
    ZIG_VSTGUI_THEME_ALTERNATE = 1
} ZigVstguiThemeKind;

typedef enum ZigVstguiLayoutKind {
    ZIG_VSTGUI_LAYOUT_ADAPTIVE = 0,
    ZIG_VSTGUI_LAYOUT_COMPACT_STRIP = 1
} ZigVstguiLayoutKind;

typedef enum ZigVstguiStyleMask {
    ZIG_VSTGUI_STYLE_BACKGROUND = 1 << 0,
    ZIG_VSTGUI_STYLE_FOREGROUND = 1 << 1,
    ZIG_VSTGUI_STYLE_BORDER = 1 << 2,
    ZIG_VSTGUI_STYLE_ACCENT = 1 << 3
} ZigVstguiStyleMask;

typedef struct ZigVstguiStyleOverride {
    uint32_t mask;
    uint32_t background_rgba;
    uint32_t foreground_rgba;
    uint32_t border_rgba;
    uint32_t accent_rgba;
} ZigVstguiStyleOverride;

typedef struct ZigVstguiGroupDescription {
    const char* title;
    uint32_t first_parameter;
    uint32_t parameter_count;
    uint32_t first_meter;
    uint32_t meter_count;
    ZigVstguiStyleOverride style;
    uint32_t first_graph;
    uint32_t graph_count;
    uint32_t first_xy_pad;
    uint32_t xy_pad_count;
} ZigVstguiGroupDescription;

typedef struct ZigVstguiSkinDescription {
    const ZigVstguiAssetDescription* assets;
    uint32_t asset_count;
    ZigVstguiFontDescription fonts;
    ZigVstguiDrawingCallbacks drawing;
    ZigVstguiThemeKind theme;
    ZigVstguiLayoutKind layout;
    const char* editor_title;
    const ZigVstguiGroupDescription* groups;
    uint32_t group_count;
    ZigVstguiStyleOverride editor_style;
} ZigVstguiSkinDescription;

typedef struct ZigVstguiResizeCallbacks {
    void* userdata;
    int32_t (*request_resize)(void* userdata, uint32_t width, uint32_t height);
} ZigVstguiResizeCallbacks;

typedef struct ZigVstguiEditor ZigVstguiEditor;

typedef enum ZigVstguiPlatform {
    ZIG_VSTGUI_PLATFORM_MACOS = 0,
    ZIG_VSTGUI_PLATFORM_WINDOWS = 1,
    ZIG_VSTGUI_PLATFORM_X11 = 2,
    ZIG_VSTGUI_PLATFORM_WAYLAND = 3
} ZigVstguiPlatform;

ZigVstguiEditor* zig_vstgui_editor_create(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks
);
ZigVstguiEditor* zig_vstgui_editor_create_with_meters(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks
);
ZigVstguiEditor* zig_vstgui_editor_create_with_skin(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    ZigVstguiSkinDescription skin
);
ZigVstguiEditor* zig_vstgui_editor_create_configured(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    const ZigVstguiGraphDescription* graphs,
    uint32_t graph_count,
    ZigVstguiGraphCallbacks graph_callbacks,
    ZigVstguiSkinDescription skin
);
ZigVstguiEditor* zig_vstgui_editor_create_advanced(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    const ZigVstguiGraphDescription* graphs,
    uint32_t graph_count,
    ZigVstguiGraphCallbacks graph_callbacks,
    const ZigVstguiXYPadDescription* xy_pads,
    uint32_t xy_pad_count,
    const ZigVstguiPresetBrowserDescription* preset_browsers,
    uint32_t preset_browser_count,
    const ZigVstguiActionMenuDescription* action_menus,
    uint32_t action_menu_count,
    ZigVstguiSkinDescription skin
);
ZigVstguiEditor* zig_vstgui_editor_create_full(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    const ZigVstguiGraphDescription* graphs,
    uint32_t graph_count,
    ZigVstguiGraphCallbacks graph_callbacks,
    const ZigVstguiXYPadDescription* xy_pads,
    uint32_t xy_pad_count,
    const ZigVstguiPresetBrowserDescription* preset_browsers,
    uint32_t preset_browser_count,
    const ZigVstguiActionMenuDescription* action_menus,
    uint32_t action_menu_count,
    const ZigVstguiPianoDescription* pianos,
    uint32_t piano_count,
    ZigVstguiSkinDescription skin
);
ZigVstguiEditor* zig_vstgui_editor_create_complete(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    const ZigVstguiGraphDescription* graphs,
    uint32_t graph_count,
    ZigVstguiGraphCallbacks graph_callbacks,
    const ZigVstguiXYPadDescription* xy_pads,
    uint32_t xy_pad_count,
    const ZigVstguiPresetBrowserDescription* preset_browsers,
    uint32_t preset_browser_count,
    const ZigVstguiActionMenuDescription* action_menus,
    uint32_t action_menu_count,
    const ZigVstguiPianoDescription* pianos,
    uint32_t piano_count,
    const ZigVstguiStepSequencerDescription* step_sequencers,
    uint32_t step_sequencer_count,
    ZigVstguiSkinDescription skin
);
ZigVstguiEditor* zig_vstgui_editor_create_latest(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    const ZigVstguiGraphDescription* graphs,
    uint32_t graph_count,
    ZigVstguiGraphCallbacks graph_callbacks,
    const ZigVstguiXYPadDescription* xy_pads,
    uint32_t xy_pad_count,
    const ZigVstguiPresetBrowserDescription* preset_browsers,
    uint32_t preset_browser_count,
    const ZigVstguiActionMenuDescription* action_menus,
    uint32_t action_menu_count,
    const ZigVstguiPianoDescription* pianos,
    uint32_t piano_count,
    const ZigVstguiStepSequencerDescription* step_sequencers,
    uint32_t step_sequencer_count,
    const ZigVstguiFileDropDescription* file_drops,
    uint32_t file_drop_count,
    ZigVstguiSkinDescription skin
);
void zig_vstgui_canvas_fill_rect(
    ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom,
    uint32_t rgba
);
void zig_vstgui_canvas_stroke_rect(
    ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom,
    uint32_t rgba,
    double width
);
void zig_vstgui_canvas_fill_ellipse(
    ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom,
    uint32_t rgba
);
void zig_vstgui_canvas_line(
    ZigVstguiCanvas* canvas,
    double start_x,
    double start_y,
    double end_x,
    double end_y,
    uint32_t rgba,
    double width
);
int32_t zig_vstgui_canvas_draw_asset(
    ZigVstguiCanvas* canvas,
    uint32_t asset_id,
    double left,
    double top,
    double right,
    double bottom,
    float alpha
);
int32_t zig_vstgui_editor_open(ZigVstguiEditor* editor, void* parent, ZigVstguiPlatform platform);
void zig_vstgui_editor_close(ZigVstguiEditor* editor);
void zig_vstgui_editor_destroy(ZigVstguiEditor* editor);
int32_t zig_vstgui_editor_resize(ZigVstguiEditor* editor, uint32_t width, uint32_t height);
int32_t zig_vstgui_editor_set_scale(ZigVstguiEditor* editor, double scale);
int32_t zig_vstgui_editor_set_parameter(ZigVstguiEditor* editor, uint32_t parameter_id, double normalized);
int32_t zig_vstgui_editor_set_modulation(ZigVstguiEditor* editor, uint32_t parameter_id, double normalized);
int32_t zig_vstgui_editor_refresh_parameters(
    ZigVstguiEditor* editor,
    const ZigVstguiParameterValue* parameters,
    uint32_t parameter_count
);
int32_t zig_vstgui_editor_key_down(ZigVstguiEditor* editor, uint16_t key, int16_t key_code, int16_t modifiers);
int32_t zig_vstgui_editor_key_up(ZigVstguiEditor* editor, uint16_t key, int16_t key_code, int16_t modifiers);
void zig_vstgui_editor_set_focus(ZigVstguiEditor* editor, int32_t focused);
void zig_vstgui_editor_set_frame(ZigVstguiEditor* editor, void* plug_frame);
void zig_vstgui_editor_set_wayland_host(ZigVstguiEditor* editor, void* wayland_host);
void zig_vstgui_editor_set_resize_callbacks(ZigVstguiEditor* editor, ZigVstguiResizeCallbacks callbacks);
uint32_t zig_vstgui_adapter_version(void);

#ifdef __cplusplus
}
#endif

#endif
