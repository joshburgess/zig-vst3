#include "zig_vstgui_adapter.h"
#include "zig_vstgui_editor.h"

#include <new>

extern "C" ZigVstguiEditor* zig_vstgui_editor_create(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks
) {
    if (!parameters || parameter_count == 0 || parameter_count > ZIG_VSTGUI_MAX_PARAMETERS) return nullptr;
    auto* editor = new (std::nothrow) ZigVstguiEditor(parameters, parameter_count, callbacks);
    if (editor && !editor->valid()) {
        delete editor;
        return nullptr;
    }
    return editor;
}

extern "C" int32_t zig_vstgui_editor_open(
    ZigVstguiEditor* editor,
    void* parent,
    ZigVstguiPlatform platform
) {
    return editor && editor->open(parent, platform) ? 0 : -1;
}

extern "C" void zig_vstgui_editor_close(ZigVstguiEditor* editor) {
    if (editor) editor->close();
}

extern "C" void zig_vstgui_editor_destroy(ZigVstguiEditor* editor) {
    delete editor;
}

extern "C" int32_t zig_vstgui_editor_resize(
    ZigVstguiEditor* editor,
    uint32_t width,
    uint32_t height
) {
    return editor && editor->resize(width, height) ? 0 : -1;
}

extern "C" int32_t zig_vstgui_editor_set_scale(ZigVstguiEditor* editor, double scale) {
    return editor && editor->setScale(scale) ? 0 : -1;
}

extern "C" int32_t zig_vstgui_editor_set_parameter(
    ZigVstguiEditor* editor,
    uint32_t parameter_id,
    double normalized
) {
    return editor && editor->setParameter(parameter_id, normalized) ? 0 : -1;
}

extern "C" int32_t zig_vstgui_editor_refresh_parameters(
    ZigVstguiEditor* editor,
    const ZigVstguiParameterValue* parameters,
    uint32_t parameter_count
) {
    return editor && editor->refreshParameters(parameters, parameter_count) ? 0 : -1;
}

extern "C" int32_t zig_vstgui_editor_key_down(
    ZigVstguiEditor* editor,
    uint16_t key,
    int16_t key_code,
    int16_t modifiers
) {
    return editor && editor->keyDown(key, key_code, modifiers) ? 0 : -1;
}

extern "C" void zig_vstgui_editor_set_focus(ZigVstguiEditor* editor, int32_t focused) {
    if (editor) editor->setFocus(focused != 0);
}

extern "C" void zig_vstgui_editor_set_frame(ZigVstguiEditor* editor, void* plug_frame) {
    if (editor) editor->setPlugFrame(plug_frame);
}

extern "C" void zig_vstgui_editor_set_wayland_host(ZigVstguiEditor* editor, void* wayland_host) {
    if (editor) editor->setWaylandHost(wayland_host);
}

extern "C" void zig_vstgui_editor_set_resize_callbacks(
    ZigVstguiEditor* editor,
    ZigVstguiResizeCallbacks callbacks
) {
    if (editor) editor->setResizeCallbacks(callbacks);
}

extern "C" uint32_t zig_vstgui_adapter_version() {
    return 2;
}
