#ifndef ZIG_VSTGUI_ADAPTER_H
#define ZIG_VSTGUI_ADAPTER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ZigVstguiCallbacks {
    void* userdata;
    void (*begin_edit)(void* userdata, uint32_t parameter_id);
    int32_t (*perform_edit)(void* userdata, uint32_t parameter_id, double normalized);
    void (*end_edit)(void* userdata, uint32_t parameter_id);
    int32_t (*format_value)(void* userdata, uint32_t parameter_id, double normalized, char* output, uint32_t capacity);
    int32_t (*parse_value)(void* userdata, uint32_t parameter_id, const char* text, double* normalized);
    int32_t (*show_context_menu)(void* userdata, uint32_t parameter_id, int32_t x, int32_t y);
} ZigVstguiCallbacks;

typedef struct ZigVstguiParameterInfo {
    const char* title;
    const char* units;
    int32_t step_count;
    double default_normalized;
} ZigVstguiParameterInfo;

typedef enum ZigVstguiControlKind {
    ZIG_VSTGUI_CONTROL_LINEAR_SLIDER = 0,
    ZIG_VSTGUI_CONTROL_ROTARY_KNOB = 1,
    ZIG_VSTGUI_CONTROL_TOGGLE = 2,
    ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN = 3,
    ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM = 4
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
int32_t zig_vstgui_editor_open(ZigVstguiEditor* editor, void* parent, ZigVstguiPlatform platform);
void zig_vstgui_editor_close(ZigVstguiEditor* editor);
void zig_vstgui_editor_destroy(ZigVstguiEditor* editor);
int32_t zig_vstgui_editor_resize(ZigVstguiEditor* editor, uint32_t width, uint32_t height);
int32_t zig_vstgui_editor_set_scale(ZigVstguiEditor* editor, double scale);
int32_t zig_vstgui_editor_set_parameter(ZigVstguiEditor* editor, uint32_t parameter_id, double normalized);
int32_t zig_vstgui_editor_refresh_parameters(
    ZigVstguiEditor* editor,
    const ZigVstguiParameterValue* parameters,
    uint32_t parameter_count
);
int32_t zig_vstgui_editor_key_down(ZigVstguiEditor* editor, uint16_t key, int16_t key_code, int16_t modifiers);
void zig_vstgui_editor_set_focus(ZigVstguiEditor* editor, int32_t focused);
void zig_vstgui_editor_set_frame(ZigVstguiEditor* editor, void* plug_frame);
void zig_vstgui_editor_set_wayland_host(ZigVstguiEditor* editor, void* wayland_host);
void zig_vstgui_editor_set_resize_callbacks(ZigVstguiEditor* editor, ZigVstguiResizeCallbacks callbacks);
uint32_t zig_vstgui_adapter_version(void);

#ifdef __cplusplus
}
#endif

#endif
