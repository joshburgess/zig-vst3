#include "zig_vstgui_editor.h"

#include "zig_vstgui_platform.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/vstguiinit.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>

namespace {

std::atomic<uint32_t> editor_count {0};

}

ZigVstguiEditor::ZigVstguiEditor(
    uint32_t parameter_id,
    double initial,
    ZigVstguiParameterInfo value_parameter_info,
    ZigVstguiCallbacks callbacks
)
: parameter_control(parameter_id, initial, callbacks),
  parameter_info(value_parameter_info) {
    if (editor_count.fetch_add(1, std::memory_order_acq_rel) == 0) VSTGUI::init(nullptr);
    profile_enabled = std::getenv("ZIG_VSTGUI_PROFILE") != nullptr;
    buildFrame();
}

ZigVstguiEditor::~ZigVstguiEditor() {
    close();
    if (frame) frame->forget();
    reportMetrics();
    ZigVstgui::releasePlatformInterfaces(plug_frame, wayland_host);
    if (editor_count.fetch_sub(1, std::memory_order_acq_rel) == 1) VSTGUI::exit();
}

bool ZigVstguiEditor::open(void* parent, ZigVstguiPlatform platform) {
    if (!frame) buildFrame();
    if (!ZigVstgui::openFrame(frame, parent, platform, plug_frame, wayland_host)) return false;
    metrics.open_count += 1;
    return true;
}

void ZigVstguiEditor::close() {
    if (!frame || !frame->getPlatformFrame()) return;
    parameter_control.clear();
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

void ZigVstguiEditor::setParameter(double normalized) {
    metrics.parameter_update_count += 1;
    parameter_control.setValue(normalized);
}

bool ZigVstguiEditor::keyDown(uint16_t key, int16_t key_code, int16_t modifiers) {
    if (!frame || !parameter_control.handleKey(key, key_code, modifiers)) return false;
    frame->setFocusView(parameter_control.focusView());
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
    const auto& theme = ZigVstgui::defaultTheme();
    frame = new VSTGUI::CFrame(VSTGUI::CRect(0, 0, width, height), nullptr);
    frame->setBackgroundColor(theme.surface);
    frame->setFocusDrawingEnabled(true);
    frame->setFocusColor(theme.focus_ring);
    frame->setFocusWidth(2.0);
    content = new ZigVstgui::ProfiledContainer(
        VSTGUI::CRect(0, 0, width, height),
        profile_enabled ? &metrics : nullptr
    );
    content->setBackgroundColor(theme.surface);
    frame->addView(content);

    title = new VSTGUI::CTextLabel(
        VSTGUI::CRect(),
        parameter_info.title ? parameter_info.title : "Parameter"
    );
    title->setFont(VSTGUI::kNormalFontVeryBig);
    title->setFontColor(theme.text_primary);
    title->setBackColor(theme.surface);
    title->setFrameColor(theme.surface);
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
    help->setFontColor(theme.text_secondary);
    help->setBackColor(theme.surface);
    help->setFrameColor(theme.surface);
    content->addView(help);
    help_component.bind(help);

    parameter_control.build(content, parameter_info, theme);
    resize_control.build(content, theme);
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
    const double margin = 24.0;
    const double right = std::max(margin + 1.0, static_cast<double>(width) - margin);
    const double track_top = std::clamp(
        static_cast<double>(height) * 0.42,
        92.0,
        static_cast<double>(height) - 116.0
    );
    const double value_width = std::min(148.0, static_cast<double>(width) - margin * 2.0);
    title_component.setBounds(VSTGUI::CRect(margin, 16, right, 52));
    help_component.setBounds(VSTGUI::CRect(margin, 54, right, 82));
    parameter_control.setBounds(
        VSTGUI::CRect(margin, track_top, right, track_top + 52),
        VSTGUI::CRect(margin, height - 64.0, margin + value_width, height - 24.0)
    );
    resize_control.setBounds(VSTGUI::CRect(right - 112.0, height - 64.0, right, height - 24.0));
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
