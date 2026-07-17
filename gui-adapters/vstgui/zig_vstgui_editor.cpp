#include "zig_vstgui_editor.h"

#include "zig_vstgui_platform.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/vstguiinit.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

std::atomic<uint32_t> editor_count {0};

const ZigVstgui::Theme& selectedTheme() {
    const char* name = std::getenv("ZIG_VSTGUI_THEME");
    return name && std::strcmp(name, "alternate") == 0
        ? ZigVstgui::alternateTheme()
        : ZigVstgui::defaultTheme();
}

}

ZigVstguiEditor::ZigVstguiEditor(
    const ZigVstguiParameterDescription* parameters,
    uint32_t value_parameter_count,
    ZigVstguiCallbacks callbacks
)
: theme_resolver(selectedTheme()) {
    if (editor_count.fetch_add(1, std::memory_order_acq_rel) == 0) VSTGUI::init(nullptr);
    initialized = true;
    profile_enabled = std::getenv("ZIG_VSTGUI_PROFILE") != nullptr;
    for (uint32_t index = 0; index < value_parameter_count; ++index) {
        if (!parameters[index].info.title || findControl(parameters[index].parameter_id)) return;
        auto* control = new (std::nothrow) ZigVstgui::ParameterControl(
            parameters[index].parameter_id,
            parameters[index].initial_normalized,
            callbacks
        );
        if (!control) return;
        parameter_controls[index].reset(control);
        parameter_info[index] = parameters[index].info;
        parameter_control_kinds[index] = parameters[index].control_kind;
        parameter_count += 1;
    }
    buildFrame();
}

ZigVstguiEditor::~ZigVstguiEditor() {
    close();
    if (frame) frame->forget();
    reportMetrics();
    ZigVstgui::releasePlatformInterfaces(plug_frame, wayland_host);
    if (initialized && editor_count.fetch_sub(1, std::memory_order_acq_rel) == 1) VSTGUI::exit();
}

bool ZigVstguiEditor::valid() const {
    return parameter_count > 0 && frame;
}

bool ZigVstguiEditor::open(void* parent, ZigVstguiPlatform platform) {
    if (!frame) buildFrame();
    if (!ZigVstgui::openFrame(frame, parent, platform, plug_frame, wayland_host)) return false;
    metrics.open_count += 1;
    return true;
}

void ZigVstguiEditor::close() {
    if (!frame || !frame->getPlatformFrame()) return;
    for (uint32_t index = 0; index < parameter_count; ++index) parameter_controls[index]->clear();
    resize_control.clear();
    title_component.clear();
    help_component.clear();
    metrics.close_count += 1;
    frame->close();
    clearFrameReferences();
}

bool ZigVstguiEditor::resize(uint32_t new_width, uint32_t new_height) {
    if (!frame || new_width < 320 || new_height < 240) return false;
    if (!frame->setSize(new_width, new_height)) return false;
    width = new_width;
    height = new_height;
    metrics.resize_count += 1;
    resize_control.setSize(width, height);
    layout();
    return true;
}

bool ZigVstguiEditor::setScale(double scale) {
    if (!frame || scale <= 0.0 || !frame->setZoom(scale)) return false;
    metrics.scale_count += 1;
    return true;
}

bool ZigVstguiEditor::setParameter(uint32_t parameter_id, double normalized) {
    auto* control = findControl(parameter_id);
    if (!control) return false;
    metrics.parameter_update_count += 1;
    control->setValue(normalized);
    return true;
}

bool ZigVstguiEditor::refreshParameters(
    const ZigVstguiParameterValue* parameters,
    uint32_t value_parameter_count
) {
    if (value_parameter_count > 0 && !parameters) return false;
    for (uint32_t index = 0; index < value_parameter_count; ++index) {
        if (!findControl(parameters[index].parameter_id)) return false;
    }
    for (uint32_t index = 0; index < value_parameter_count; ++index) {
        setParameter(parameters[index].parameter_id, parameters[index].normalized);
    }
    return true;
}

bool ZigVstguiEditor::parameterValue(uint32_t parameter_id, double& value) const {
    const auto* control = findControl(parameter_id);
    if (!control) return false;
    value = control->model().acceptedValue();
    return true;
}

bool ZigVstguiEditor::keyDown(uint16_t key, int16_t key_code, int16_t modifiers) {
    if (!frame) return false;
    const auto* focused = frame->getFocusView();
    for (uint32_t index = 0; index < parameter_count; ++index) {
        auto& control = *parameter_controls[index];
        if (focused == control.focusView() && control.handleKey(key, key_code, modifiers)) return true;
    }
    if (parameter_count == 0 || !parameter_controls[0]->handleKey(key, key_code, modifiers)) return false;
    frame->setFocusView(parameter_controls[0]->focusView());
    return true;
}

void ZigVstguiEditor::setFocus(bool focused) {
    if (frame) frame->onActivate(focused);
}

void ZigVstguiEditor::setPlugFrame(void* value_frame) {
    ZigVstgui::replacePlugFrame(plug_frame, value_frame);
}

void ZigVstguiEditor::setWaylandHost(void* host) {
    ZigVstgui::replaceWaylandHost(wayland_host, host);
}

void ZigVstguiEditor::setResizeCallbacks(ZigVstguiResizeCallbacks callbacks) {
    resize_control.setCallbacks(callbacks);
}

void ZigVstguiEditor::buildFrame() {
    if (frame) return;
    const auto editor_style = theme_resolver.resolve(ZigVstgui::ComponentKind::editor);
    const auto title_style = theme_resolver.resolve(ZigVstgui::ComponentKind::title);
    const auto help_style = theme_resolver.resolve(ZigVstgui::ComponentKind::help);
    const auto& theme = theme_resolver.theme();
    frame = new VSTGUI::CFrame(VSTGUI::CRect(0, 0, width, height), nullptr);
    frame->setBackgroundColor(editor_style.background);
    frame->setFocusDrawingEnabled(true);
    frame->setFocusColor(editor_style.accent);
    frame->setFocusWidth(theme.control_metrics.focus_width);
    content = new ZigVstgui::ProfiledContainer(
        VSTGUI::CRect(0, 0, width, height),
        profile_enabled ? &metrics : nullptr
    );
    content->setBackgroundColor(editor_style.background);
    frame->addView(content);

    const char* editor_title = parameter_count == 1 ? parameter_info[0].title : "zig-vst3 Parameters";
    title = new VSTGUI::CTextLabel(VSTGUI::CRect(), editor_title);
    title->setFont(theme.typography.title);
    title->setFontColor(title_style.foreground);
    title->setBackColor(title_style.background);
    title->setFrameColor(title_style.border);
    content->addView(title);
    title_component.bind(title);

#if defined(__APPLE__)
    help = new VSTGUI::CTextLabel(
        VSTGUI::CRect(),
        "Drag | Arrows | Fn+Left/Right limits | Command-click resets"
    );
#else
    help = new VSTGUI::CTextLabel(
        VSTGUI::CRect(),
        "Drag | Arrows | Home/End | Control-click resets"
    );
#endif
    help->setFont(theme.typography.body);
    help->setFontColor(help_style.foreground);
    help->setBackColor(help_style.background);
    help->setFrameColor(help_style.border);
    content->addView(help);
    help_component.bind(help);

    for (uint32_t index = 0; index < parameter_count; ++index) {
        parameter_controls[index]->build(
            content,
            parameter_info[index],
            parameter_control_kinds[index],
            theme_resolver
        );
    }
    resize_control.build(content, theme_resolver);
    resize_control.setSize(width, height);
    layout();
}

void ZigVstguiEditor::clearFrameReferences() {
    frame = nullptr;
    content = nullptr;
    title = nullptr;
    help = nullptr;
}

void ZigVstguiEditor::layout() {
    if (!frame) return;
    if (content) content->setViewSize(VSTGUI::CRect(0, 0, width, height), true);
    const auto& theme = theme_resolver.theme();
    const double margin = theme.spacing.large;
    const double right = std::max(margin + 1.0, static_cast<double>(width) - margin);
    const double value_width = std::min(
        theme.control_metrics.value_width,
        static_cast<double>(width) - margin * 2.0
    );
    title_component.setBounds(VSTGUI::CRect(margin, 16, right, 52));
    help_component.setBounds(VSTGUI::CRect(margin, 54, right, 82));
    if (parameter_count == 1) {
        const double track_top = std::clamp(
            static_cast<double>(height) * 0.42,
            92.0,
            static_cast<double>(height) - 116.0
        );
        parameter_controls[0]->setBounds(
            VSTGUI::CRect(),
            VSTGUI::CRect(margin, track_top, right, track_top + theme.control_metrics.control_height),
            VSTGUI::CRect(
                margin,
                height - margin - theme.control_metrics.compact_control_height,
                margin + value_width,
                height - margin
            )
        );
    } else {
        const double controls_top = 92.0;
        const double controls_bottom = static_cast<double>(height) - margin - theme.control_metrics.compact_control_height - theme.spacing.medium;
        const double row_height = std::max(1.0, (controls_bottom - controls_top) / parameter_count);
        const double label_width = std::min(96.0, (right - margin) * 0.25);
        const double row_value_width = std::min(value_width, 90.0);
        for (uint32_t index = 0; index < parameter_count; ++index) {
            const double row_top = controls_top + row_height * index;
            const double control_top = row_top + theme.spacing.small;
            const double control_bottom = std::min(
                row_top + row_height - theme.spacing.small,
                control_top + theme.control_metrics.compact_control_height
            );
            parameter_controls[index]->setBounds(
                VSTGUI::CRect(margin, control_top, margin + label_width, control_bottom),
                VSTGUI::CRect(
                    margin + label_width + theme.spacing.medium,
                    control_top,
                    right - row_value_width - theme.spacing.medium,
                    control_bottom
                ),
                VSTGUI::CRect(right - row_value_width, control_top, right, control_bottom)
            );
        }
    }
    resize_control.setBounds(VSTGUI::CRect(
        right - theme.control_metrics.button_width,
        height - margin - theme.control_metrics.compact_control_height,
        right,
        height - margin
    ));
}

ZigVstgui::ParameterControl* ZigVstguiEditor::findControl(uint32_t parameter_id) {
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (parameter_controls[index]->model().parameterId() == parameter_id) return parameter_controls[index].get();
    }
    return nullptr;
}

const ZigVstgui::ParameterControl* ZigVstguiEditor::findControl(uint32_t parameter_id) const {
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (parameter_controls[index]->model().parameterId() == parameter_id) return parameter_controls[index].get();
    }
    return nullptr;
}

void ZigVstguiEditor::reportMetrics() const {
    if (!profile_enabled || (metrics.draw_count == 0 && metrics.open_count == 0)) return;
    const double average_us = metrics.draw_count == 0
        ? 0.0
        : static_cast<double>(metrics.draw_total_ns) / static_cast<double>(metrics.draw_count) / 1000.0;
    std::fprintf(
        stderr,
        "zig-vstgui profile: draws=%llu average_us=%.3f max_us=%.3f invalidated_pixels=%.0f opens=%llu closes=%llu resizes=%llu scales=%llu parameter_updates=%llu\n",
        static_cast<unsigned long long>(metrics.draw_count),
        average_us,
        static_cast<double>(metrics.draw_max_ns) / 1000.0,
        metrics.invalidated_area,
        static_cast<unsigned long long>(metrics.open_count),
        static_cast<unsigned long long>(metrics.close_count),
        static_cast<unsigned long long>(metrics.resize_count),
        static_cast<unsigned long long>(metrics.scale_count),
        static_cast<unsigned long long>(metrics.parameter_update_count)
    );
}
