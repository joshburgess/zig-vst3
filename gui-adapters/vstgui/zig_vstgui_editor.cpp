#include "zig_vstgui_editor.h"

#include "zig_vstgui_fonts.h"
#include "zig_vstgui_layout.h"
#include "zig_vstgui_platform.h"
#include "zig_vstgui_theme.h"

#include "pluginterfaces/base/keycodes.h"
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
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t value_meter_count,
    ZigVstguiMeterCallbacks value_meter_callbacks,
    ZigVstguiSkinDescription skin
)
: meter_count(value_meter_count),
  meter_callbacks(value_meter_callbacks),
  drawing_callbacks(skin.drawing),
  theme_resolver(selectedTheme()) {
    if (editor_count.fetch_add(1, std::memory_order_acq_rel) == 0) VSTGUI::init(nullptr);
    initialized = true;
    profile_enabled = std::getenv("ZIG_VSTGUI_PROFILE") != nullptr;
    if (!asset_store.load(skin.assets, skin.asset_count)) return;
    ZigVstgui::applyFontDescription(skin.fonts, theme_resolver);
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
    for (uint32_t index = 0; index < meter_count; ++index) {
        if (!meters[index].title) return;
        meter_descriptions[index] = meters[index];
        meter_controls[index].reset(new (std::nothrow) ZigVstgui::MeterControl());
        if (!meter_controls[index]) return;
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
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->start();
    return true;
}

void ZigVstguiEditor::close() {
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->stop();
    if (!frame || !frame->getPlatformFrame()) return;
    for (uint32_t index = 0; index < parameter_count; ++index) parameter_controls[index]->clear();
    resize_control.clear();
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->clear();
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

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::parameterAccessibility(
    uint32_t parameter_id,
    bool exact_value
) const {
    const auto* control = findControl(parameter_id);
    if (!control) return nullptr;
    return exact_value ? control->valueAccessibility() : &control->primaryAccessibility();
}

const ZigVstgui::AccessibilityNode& ZigVstguiEditor::resizeAccessibility() const {
    return resize_control.buttonAccessibility();
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::meterAccessibility(uint32_t index) const {
    return index < meter_count ? &meter_controls[index]->accessibilityNode() : nullptr;
}

bool ZigVstguiEditor::tickMeter(uint32_t index, double elapsed_ms) {
    return index < meter_count && meter_controls[index]->tick(elapsed_ms);
}

double ZigVstguiEditor::meterLevel(uint32_t index, uint32_t channel) const {
    if (index >= meter_count || !meter_controls[index]->meterView()) return 0.0;
    return meter_controls[index]->meterView()->level(channel);
}

int32_t ZigVstguiEditor::focusPosition() const {
    return focus_position;
}

bool ZigVstguiEditor::keyDown(uint16_t key, int16_t key_code, int16_t modifiers) {
    if (!frame) return false;
    if (key_code == Steinberg::KEY_TAB) return focusNext((modifiers & 1) != 0);
    const auto* focused = frame->getFocusView();
    for (uint32_t index = 0; index < parameter_count; ++index) {
        auto& control = *parameter_controls[index];
        if (focused == control.focusView() && control.handleKey(key, key_code, modifiers)) return true;
    }
    if (parameter_count == 0 || !parameter_controls[0]->handleKey(key, key_code, modifiers)) return false;
    frame->setFocusView(parameter_controls[0]->focusView());
    return true;
}

bool ZigVstguiEditor::focusNext(bool reverse) {
    if (!frame) return false;
    std::array<VSTGUI::CView*, ZIG_VSTGUI_MAX_PARAMETERS * 2 + 1> focus_order {};
    uint32_t focus_count = 0;
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (auto* primary = parameter_controls[index]->focusView()) focus_order[focus_count++] = primary;
        if (auto* value = parameter_controls[index]->valueFocusView()) focus_order[focus_count++] = value;
    }
    if (auto* resize = resize_control.focusView()) focus_order[focus_count++] = resize;
    if (focus_count == 0) return false;
    const auto* focused = frame->getFocusView();
    uint32_t current = focus_count;
    for (uint32_t index = 0; index < focus_count; ++index) {
        if (focus_order[index] == focused) {
            current = index;
            break;
        }
    }
    if (current == focus_count && focus_position >= 0 &&
        static_cast<uint32_t>(focus_position) < focus_count) current = static_cast<uint32_t>(focus_position);
    const uint32_t next = current == focus_count
        ? (reverse ? focus_count - 1 : 0)
        : (reverse ? (current + focus_count - 1) % focus_count : (current + 1) % focus_count);
    auto* next_view = focus_order[next];
    frame->setFocusView(next_view);
    for (uint32_t index = 0; index < parameter_count; ++index) {
        parameter_controls[index]->setFocusedView(next_view);
    }
    resize_control.setFocusedView(next_view);
    focus_position = static_cast<int32_t>(next);
    return true;
}

void ZigVstguiEditor::setFocus(bool focused) {
    if (!frame) return;
    frame->onActivate(focused);
    if (!focused) {
        for (uint32_t index = 0; index < parameter_count; ++index) {
            parameter_controls[index]->setFocusedView(nullptr);
        }
        resize_control.setFocusedView(nullptr);
    }
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
    title->setFont(theme_resolver.font(ZigVstgui::TypographyRole::title));
    title->setFontColor(title_style.foreground);
    title->setBackColor(title_style.background);
    title->setFrameColor(title_style.border);
    content->addView(title);
    title_component.bind(title);
    title_component.accessibility().setRole(ZigVstgui::AccessibilityRole::group);
    title_component.accessibility().setName(editor_title);
    title_component.accessibility().setReadOnly(true);

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
    help->setFont(theme_resolver.font(ZigVstgui::TypographyRole::body));
    help->setFontColor(help_style.foreground);
    help->setBackColor(help_style.background);
    help->setFrameColor(help_style.border);
    content->addView(help);
    help_component.bind(help);
    help_component.accessibility().setRole(ZigVstgui::AccessibilityRole::group);
    help_component.accessibility().setName("Editor keyboard instructions");
    help_component.accessibility().setReadOnly(true);

    for (uint32_t index = 0; index < parameter_count; ++index) {
        parameter_controls[index]->build(
            content,
            parameter_info[index],
            parameter_control_kinds[index],
            theme_resolver,
            &asset_store,
            drawing_callbacks
        );
    }
    for (uint32_t index = 0; index < meter_count; ++index) {
        const auto& description = meter_descriptions[index];
        ZigVstgui::MeterVariant variant = ZigVstgui::MeterVariant::peak;
        if (description.kind == ZIG_VSTGUI_METER_STEREO) variant = ZigVstgui::MeterVariant::stereo;
        if (description.kind == ZIG_VSTGUI_METER_GAIN_REDUCTION) variant = ZigVstgui::MeterVariant::gain_reduction;
        meter_controls[index]->build(
            content,
            description.title,
            variant,
            description.first_source_id,
            description.second_source_id,
            {meter_callbacks.userdata, meter_callbacks.load},
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
    double meters_top = 92.0;
    if (parameter_count == 1) {
        title_component.setVisible(true);
        help_component.setVisible(true);
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
        meters_top = track_top + theme.control_metrics.control_height + theme.spacing.small;
    } else {
        const auto mode = ZigVstgui::layoutMode(width, height);
        const bool expanded = mode == ZigVstgui::LayoutMode::expanded;
        title_component.setVisible(expanded);
        help_component.setVisible(expanded);
        const double controls_top = expanded ? 92.0 : theme.spacing.medium;
        const double controls_bottom = static_cast<double>(height) - margin - theme.control_metrics.compact_control_height - theme.spacing.medium;
        const double row_gap = mode == ZigVstgui::LayoutMode::expanded ? theme.spacing.small : 0.0;
        std::array<ZigVstgui::StackItem, ZIG_VSTGUI_MAX_PARAMETERS> row_items {};
        std::array<VSTGUI::CRect, ZIG_VSTGUI_MAX_PARAMETERS> row_bounds {};
        for (uint32_t index = 0; index < parameter_count; ++index) {
            row_items[index] = {
                expanded ? theme.control_metrics.compact_control_height : 32.0,
                right - margin,
                0.0,
            };
        }
        ZigVstgui::layoutStack(
            VSTGUI::CRect(margin, controls_top, right, controls_bottom),
            ZigVstgui::Axis::vertical,
            ZigVstgui::Alignment::stretch,
            {},
            row_gap,
            row_items.data(),
            parameter_count,
            row_bounds.data()
        );
        const double label_width = mode == ZigVstgui::LayoutMode::expanded ? 112.0 : 88.0;
        const double row_value_width = mode == ZigVstgui::LayoutMode::expanded ? 104.0 : 80.0;
        const ZigVstgui::GridTrack columns[] = {
            {label_width, 0.0},
            {64.0, 1.0},
            {row_value_width, 0.0},
        };
        const ZigVstgui::GridTrack rows[] = {{24.0, 1.0}};
        const ZigVstgui::GridItem items[] = {
            {0, 0, 1, 1},
            {1, 0, 1, 1},
            {2, 0, 1, 1},
        };
        for (uint32_t index = 0; index < parameter_count; ++index) {
            VSTGUI::CRect cells[3];
            ZigVstgui::layoutGrid(
                row_bounds[index],
                {},
                theme.spacing.small,
                0.0,
                columns,
                3,
                rows,
                1,
                items,
                3,
                cells
            );
            parameter_controls[index]->setBounds(
                cells[0],
                cells[1],
                cells[2]
            );
        }
        meters_top = row_bounds[parameter_count - 1].bottom + theme.spacing.small;
    }
    if (meter_count > 0) {
        const bool expanded = ZigVstgui::layoutMode(width, height) == ZigVstgui::LayoutMode::expanded;
        const double meters_bottom = static_cast<double>(height) - margin -
            theme.control_metrics.compact_control_height - theme.spacing.medium;
        const double available_height = std::max(1.0, meters_bottom - meters_top);
        const double meter_gap = theme.spacing.small;
        const double available_width = right - margin - meter_gap * (meter_count - 1);
        const double meter_width = std::max(1.0, available_width / meter_count);
        const double label_height = std::min(expanded ? 24.0 : 12.0, available_height * 0.4);
        for (uint32_t index = 0; index < meter_count; ++index) {
            const double left = margin + index * (meter_width + meter_gap);
            const double meter_right = left + meter_width;
            meter_controls[index]->setLabelVisible(true);
            meter_controls[index]->setBounds(
                VSTGUI::CRect(left, meters_top, meter_right, meters_top + label_height),
                VSTGUI::CRect(left, meters_top + label_height, meter_right, meters_bottom)
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
