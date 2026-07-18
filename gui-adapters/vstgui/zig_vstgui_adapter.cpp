#include "zig_vstgui_adapter.h"
#include "zig_vstgui_editor.h"

#include <cmath>
#include <new>

extern "C" ZigVstguiEditor* zig_vstgui_editor_create(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks
) {
    return zig_vstgui_editor_create_with_meters(parameters, parameter_count, callbacks, nullptr, 0, {});
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_with_meters(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks
) {
    return zig_vstgui_editor_create_with_skin(
        parameters,
        parameter_count,
        callbacks,
        meters,
        meter_count,
        meter_callbacks,
        {}
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_with_skin(
    const ZigVstguiParameterDescription* parameters,
    uint32_t parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t meter_count,
    ZigVstguiMeterCallbacks meter_callbacks,
    ZigVstguiSkinDescription skin
) {
    return zig_vstgui_editor_create_configured(
        parameters, parameter_count, callbacks, meters, meter_count, meter_callbacks, nullptr, 0, {}, skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_configured(
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
) {
    constexpr uint32_t style_mask = ZIG_VSTGUI_STYLE_BACKGROUND |
        ZIG_VSTGUI_STYLE_FOREGROUND |
        ZIG_VSTGUI_STYLE_BORDER |
        ZIG_VSTGUI_STYLE_ACCENT;
    if (!parameters || parameter_count == 0 || parameter_count > ZIG_VSTGUI_MAX_PARAMETERS) return nullptr;
    if ((!meters && meter_count > 0) || meter_count > ZIG_VSTGUI_MAX_METERS) return nullptr;
    if ((!graphs && graph_count > 0) || graph_count > ZIG_VSTGUI_MAX_GRAPHS) return nullptr;
    for (uint32_t index = 0; index < graph_count; ++index) {
        const auto& graph = graphs[index];
        if (!graph.title || graph.point_count > ZIG_VSTGUI_MAX_GRAPH_POINTS ||
            (!graph.points && graph.point_count > 0) ||
            !std::isfinite(graph.x_axis.minimum) || !std::isfinite(graph.x_axis.maximum) ||
            !std::isfinite(graph.y_axis.minimum) || !std::isfinite(graph.y_axis.maximum) ||
            graph.x_axis.maximum <= graph.x_axis.minimum || graph.y_axis.maximum <= graph.y_axis.minimum ||
            (graph.x_axis.scale == ZIG_VSTGUI_GRAPH_LOGARITHMIC && graph.x_axis.minimum <= 0.0) ||
            (graph.y_axis.scale == ZIG_VSTGUI_GRAPH_LOGARITHMIC && graph.y_axis.minimum <= 0.0) ||
            graph.kind < ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION || graph.kind > ZIG_VSTGUI_GRAPH_SPECTRUM ||
            graph.style < ZIG_VSTGUI_GRAPH_PRIMARY || graph.style > ZIG_VSTGUI_GRAPH_WARNING ||
            graph.x_axis.scale < ZIG_VSTGUI_GRAPH_LINEAR || graph.x_axis.scale > ZIG_VSTGUI_GRAPH_DECIBELS ||
            graph.y_axis.scale < ZIG_VSTGUI_GRAPH_LINEAR || graph.y_axis.scale > ZIG_VSTGUI_GRAPH_DECIBELS ||
            (graph.dynamic && (!graph_callbacks.load || graph.maximum_refresh_hz == 0 || graph.maximum_refresh_hz > 60))) return nullptr;
        for (uint32_t point = 0; point < graph.point_count; ++point) {
            if (!std::isfinite(graph.points[point].x) || !std::isfinite(graph.points[point].y)) return nullptr;
        }
    }
    if ((!skin.assets && skin.asset_count > 0) || skin.asset_count > ZIG_VSTGUI_MAX_ASSETS) return nullptr;
    if ((!skin.groups && skin.group_count > 0) || skin.group_count > ZIG_VSTGUI_MAX_GROUPS) return nullptr;
    if (skin.editor_style.mask & ~style_mask) return nullptr;
    for (uint32_t index = 0; index < skin.group_count; ++index) {
        if (skin.groups[index].style.mask & ~style_mask) return nullptr;
    }
    if (skin.theme != ZIG_VSTGUI_THEME_DEFAULT && skin.theme != ZIG_VSTGUI_THEME_ALTERNATE) return nullptr;
    if (skin.layout != ZIG_VSTGUI_LAYOUT_ADAPTIVE && skin.layout != ZIG_VSTGUI_LAYOUT_COMPACT_STRIP) return nullptr;
    auto* editor = new (std::nothrow) ZigVstguiEditor(
        parameters,
        parameter_count,
        callbacks,
        meters,
        meter_count,
        meter_callbacks,
        skin,
        graphs,
        graph_count,
        graph_callbacks
    );
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

extern "C" int32_t zig_vstgui_editor_set_modulation(
    ZigVstguiEditor* editor,
    uint32_t parameter_id,
    double normalized
) {
    return editor && editor->setModulation(parameter_id, normalized) ? 0 : -1;
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
    return 6;
}
