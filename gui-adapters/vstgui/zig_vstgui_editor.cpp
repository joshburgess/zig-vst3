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

const ZigVstgui::Theme& selectedTheme(ZigVstguiThemeKind requested) {
    if (requested == ZIG_VSTGUI_THEME_ALTERNATE) return ZigVstgui::alternateTheme();
    const char* name = std::getenv("ZIG_VSTGUI_THEME");
    return name && std::strcmp(name, "alternate") == 0
        ? ZigVstgui::alternateTheme()
        : ZigVstgui::defaultTheme();
}

VSTGUI::CColor rgba(uint32_t value) {
    return VSTGUI::CColor(
        static_cast<uint8_t>(value >> 24),
        static_cast<uint8_t>(value >> 16),
        static_cast<uint8_t>(value >> 8),
        static_cast<uint8_t>(value)
    );
}

ZigVstgui::StyleOverride styleOverride(const ZigVstguiStyleOverride& value) {
    ZigVstgui::StyleOverride result;
    if (value.mask & ZIG_VSTGUI_STYLE_BACKGROUND) result.background = rgba(value.background_rgba);
    if (value.mask & ZIG_VSTGUI_STYLE_FOREGROUND) result.foreground = rgba(value.foreground_rgba);
    if (value.mask & ZIG_VSTGUI_STYLE_BORDER) result.border = rgba(value.border_rgba);
    if (value.mask & ZIG_VSTGUI_STYLE_ACCENT) result.accent = rgba(value.accent_rgba);
    return result;
}

}

ZigVstguiEditor::ZigVstguiEditor(
    const ZigVstguiParameterDescription* parameters,
    uint32_t value_parameter_count,
    ZigVstguiCallbacks callbacks,
    const ZigVstguiMeterDescription* meters,
    uint32_t value_meter_count,
    ZigVstguiMeterCallbacks value_meter_callbacks,
    ZigVstguiSkinDescription skin,
    const ZigVstguiGraphDescription* graphs,
    uint32_t value_graph_count,
    ZigVstguiGraphCallbacks value_graph_callbacks
)
: meter_count(value_meter_count),
  meter_callbacks(value_meter_callbacks),
  graph_count(value_graph_count),
  graph_callbacks(value_graph_callbacks),
  drawing_callbacks(skin.drawing),
  theme_resolver(selectedTheme(skin.theme)),
  theme_kind(skin.theme),
  layout_kind(skin.layout) {
    if (editor_count.fetch_add(1, std::memory_order_acq_rel) == 0) VSTGUI::init(nullptr);
    initialized = true;
    profile_enabled = std::getenv("ZIG_VSTGUI_PROFILE") != nullptr;
    if (!asset_store.load(skin.assets, skin.asset_count)) return;
    editor_title = skin.editor_title ? skin.editor_title : "";
    theme_resolver.setEditorOverride(styleOverride(skin.editor_style));
    ZigVstgui::applyFontDescription(skin.fonts, theme_resolver);
    for (uint32_t index = 0; index < value_parameter_count; ++index) {
        if (!parameters[index].info.title || findControl(parameters[index].parameter_id)) return;
        if (parameters[index].control_kind < ZIG_VSTGUI_CONTROL_LINEAR_SLIDER ||
            parameters[index].control_kind > ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER) return;
        auto* control = new (std::nothrow) ZigVstgui::ParameterControl(
            parameters[index].parameter_id,
            parameters[index].initial_normalized,
            callbacks
        );
        if (!control) return;
        parameter_controls[index].reset(control);
        parameter_titles[index] = parameters[index].info.title;
        parameter_units[index] = parameters[index].info.units ? parameters[index].info.units : "";
        parameter_tooltips[index] = parameters[index].info.tooltip ? parameters[index].info.tooltip : "";
        parameter_info[index] = parameters[index].info;
        parameter_info[index].title = parameter_titles[index].c_str();
        parameter_info[index].units = parameter_units[index].c_str();
        parameter_info[index].tooltip = parameter_tooltips[index].empty()
            ? nullptr
            : parameter_tooltips[index].c_str();
        parameter_control_kinds[index] = parameters[index].control_kind;
        parameter_count += 1;
    }
    for (uint32_t index = 0; index < meter_count; ++index) {
        if (!meters[index].title) return;
        meter_descriptions[index] = meters[index];
        meter_controls[index].reset(new (std::nothrow) ZigVstgui::MeterControl());
        if (!meter_controls[index]) return;
    }
    for (uint32_t index = 0; index < graph_count; ++index) {
        if (!graphs[index].title) return;
        graph_titles[index] = graphs[index].title;
        graph_x_labels[index] = graphs[index].x_axis.label ? graphs[index].x_axis.label : "";
        graph_y_labels[index] = graphs[index].y_axis.label ? graphs[index].y_axis.label : "";
        graph_descriptions[index] = graphs[index];
        graph_descriptions[index].title = graph_titles[index].c_str();
        graph_descriptions[index].x_axis.label = graph_x_labels[index].c_str();
        graph_descriptions[index].y_axis.label = graph_y_labels[index].c_str();
        if (!graphs[index].dynamic && graphs[index].point_count > 0) {
            graph_static_points[index].assign(graphs[index].points, graphs[index].points + graphs[index].point_count);
            graph_descriptions[index].points = graph_static_points[index].data();
        }
        graph_controls[index].reset(new (std::nothrow) ZigVstgui::GraphControl());
        if (!graph_controls[index]) return;
    }
    uint32_t next_parameter = 0;
    uint32_t next_meter = 0;
    uint32_t next_graph = 0;
    for (uint32_t index = 0; index < skin.group_count; ++index) {
        const auto& group = skin.groups[index];
        if (!group.title || (group.parameter_count == 0 && group.meter_count == 0 && group.graph_count == 0)) return;
        if (group.first_parameter != next_parameter || group.first_meter != next_meter || group.first_graph != next_graph) return;
        if (group.parameter_count > parameter_count - next_parameter) return;
        if (group.meter_count > meter_count - next_meter) return;
        if (group.graph_count > graph_count - next_graph) return;
        group_titles[index] = group.title;
        group_descriptions[index] = group;
        group_descriptions[index].title = group_titles[index].c_str();
        auto* resolver = new (std::nothrow) ZigVstgui::ThemeResolver(selectedTheme(skin.theme));
        if (!resolver) return;
        group_styles[index].reset(resolver);
        resolver->setEditorOverride(styleOverride(skin.editor_style));
        resolver->setComponentOverride(
            ZigVstgui::ComponentKind::editor,
            styleOverride(group.style)
        );
        const auto group_override = styleOverride(group.style);
        for (std::size_t kind = 0; kind < static_cast<std::size_t>(ZigVstgui::ComponentKind::count); ++kind) {
            resolver->setComponentOverride(static_cast<ZigVstgui::ComponentKind>(kind), group_override);
        }
        ZigVstgui::applyFontDescription(skin.fonts, *resolver);
        next_parameter += group.parameter_count;
        next_meter += group.meter_count;
        next_graph += group.graph_count;
        group_count += 1;
    }
    if (group_count > 0 && (next_parameter != parameter_count || next_meter != meter_count || next_graph != graph_count)) return;
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
    accessibility_bridge.open(frame, accessibilityEntries());
    metrics.open_count += 1;
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->start();
    for (uint32_t index = 0; index < graph_count; ++index) graph_controls[index]->start();
    return true;
}

void ZigVstguiEditor::close() {
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->stop();
    for (uint32_t index = 0; index < graph_count; ++index) graph_controls[index]->stop();
    accessibility_bridge.close();
    if (!frame || !frame->getPlatformFrame()) return;
    for (uint32_t index = 0; index < parameter_count; ++index) parameter_controls[index]->clear();
    resize_control.clear();
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->clear();
    for (uint32_t index = 0; index < graph_count; ++index) graph_controls[index]->clear();
    title_component.clear();
    help_component.clear();
    for (uint32_t index = 0; index < group_count; ++index) group_components[index].clear();
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
    accessibility_bridge.layoutChanged();
    return true;
}

bool ZigVstguiEditor::setScale(double scale) {
    if (!frame || scale <= 0.0 || !frame->setZoom(scale)) return false;
    metrics.scale_count += 1;
    accessibility_bridge.layoutChanged();
    return true;
}

bool ZigVstguiEditor::setParameter(uint32_t parameter_id, double normalized) {
    auto* control = findControl(parameter_id);
    if (!control) return false;
    metrics.parameter_update_count += 1;
    control->setValue(normalized);
    return true;
}

bool ZigVstguiEditor::setModulation(uint32_t parameter_id, double normalized) {
    auto* control = findControl(parameter_id);
    if (!control) return false;
    control->setModulation(normalized);
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

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::graphAccessibility(uint32_t index) const {
    return index < graph_count ? &graph_controls[index]->accessibilityNode() : nullptr;
}

bool ZigVstguiEditor::tickMeter(uint32_t index, double elapsed_ms) {
    return index < meter_count && meter_controls[index]->tick(elapsed_ms);
}

bool ZigVstguiEditor::refreshGraph(uint32_t index) {
    return index < graph_count && graph_controls[index]->refresh();
}

uint32_t ZigVstguiEditor::graphPointCount(uint32_t index) const {
    if (index >= graph_count || !graph_controls[index]->graphView()) return 0;
    return graph_controls[index]->graphView()->pointCount();
}

double ZigVstguiEditor::meterLevel(uint32_t index, uint32_t channel) const {
    if (index >= meter_count || !meter_controls[index]->meterView()) return 0.0;
    return meter_controls[index]->meterView()->level(channel);
}

double ZigVstguiEditor::meterPeak(uint32_t index, uint32_t channel) const {
    if (index >= meter_count || !meter_controls[index]->meterView()) return 0.0;
    return meter_controls[index]->meterView()->peak(channel);
}

bool ZigVstguiEditor::resetMeterPeaks(uint32_t index) {
    if (index >= meter_count) return false;
    meter_controls[index]->resetPeaks();
    return true;
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
    for (uint32_t index = 0; index < meter_count; ++index) {
        auto& meter = *meter_controls[index];
        if (focused == meter.focusView() && meter.handleKey(key, key_code)) return true;
    }
    if (parameter_count == 0 || !parameter_controls[0]->handleKey(key, key_code, modifiers)) return false;
    frame->setFocusView(parameter_controls[0]->focusView());
    return true;
}

bool ZigVstguiEditor::focusNext(bool reverse) {
    if (!frame) return false;
    std::array<VSTGUI::CView*, ZIG_VSTGUI_MAX_PARAMETERS * 2 + ZIG_VSTGUI_MAX_METERS + 1> focus_order {};
    uint32_t focus_count = 0;
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (auto* primary = parameter_controls[index]->focusView()) focus_order[focus_count++] = primary;
        if (auto* value = parameter_controls[index]->valueFocusView()) focus_order[focus_count++] = value;
    }
    for (uint32_t index = 0; index < meter_count; ++index) {
        if (auto* meter = meter_controls[index]->focusView()) focus_order[focus_count++] = meter;
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

ZigVstguiThemeKind ZigVstguiEditor::themeKind() const {
    return theme_kind;
}

ZigVstguiLayoutKind ZigVstguiEditor::layoutKind() const {
    return layout_kind;
}

uint32_t ZigVstguiEditor::groupCount() const {
    return group_count;
}

bool ZigVstguiEditor::nativeAccessibilityActive() const {
    return accessibility_bridge.active();
}

std::size_t ZigVstguiEditor::nativeAccessibilityElementCount() const {
    return accessibility_bridge.elementCount();
}

std::vector<ZigVstgui::AccessibilityEntry> ZigVstguiEditor::accessibilityEntries() const {
    std::vector<ZigVstgui::AccessibilityEntry> entries;
    entries.reserve(2 + group_count + parameter_count * 2 + meter_count + graph_count + 1);
    entries.push_back({&title_component.accessibility(), title_component.view()});
    entries.push_back({&help_component.accessibility(), help_component.view()});
    for (uint32_t index = 0; index < group_count; ++index) {
        entries.push_back({&group_components[index].accessibility(), group_components[index].view()});
    }
    for (uint32_t index = 0; index < parameter_count; ++index) {
        const auto& control = *parameter_controls[index];
        entries.push_back({&control.primaryAccessibility(), control.focusView()});
        if (const auto* value = control.valueAccessibility()) {
            entries.push_back({value, control.valueFocusView()});
        }
    }
    for (uint32_t index = 0; index < meter_count; ++index) {
        entries.push_back({&meter_controls[index]->accessibilityNode(), meter_controls[index]->focusView()});
    }
    for (uint32_t index = 0; index < graph_count; ++index) {
        entries.push_back({&graph_controls[index]->accessibilityNode(), graph_controls[index]->graphView()});
    }
    entries.push_back({&resize_control.buttonAccessibility(), resize_control.focusView()});
    return entries;
}

void ZigVstguiEditor::buildFrame() {
    if (frame) return;
    const auto editor_style = theme_resolver.resolve(ZigVstgui::ComponentKind::editor);
    const auto title_style = theme_resolver.resolve(ZigVstgui::ComponentKind::title);
    const auto help_style = theme_resolver.resolve(ZigVstgui::ComponentKind::help);
    const auto& theme = theme_resolver.theme();
    frame = new VSTGUI::CFrame(VSTGUI::CRect(0, 0, width, height), nullptr);
    frame->enableTooltips(true, 600);
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

    const char* visible_title = !editor_title.empty()
        ? editor_title.c_str()
        : parameter_count == 1 ? parameter_info[0].title : "zig-vst3 Parameters";
    title = new VSTGUI::CTextLabel(VSTGUI::CRect(), visible_title);
    title->setFont(theme_resolver.font(ZigVstgui::TypographyRole::title));
    title->setFontColor(title_style.foreground);
    title->setBackColor(title_style.background);
    title->setFrameColor(title_style.border);
    content->addView(title);
    title_component.bind(title);
    title_component.accessibility().setRole(ZigVstgui::AccessibilityRole::group);
    title_component.accessibility().setName(visible_title);
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

    for (uint32_t index = 0; index < group_count; ++index) {
        const auto& styles = *group_styles[index];
        const auto style = styles.resolve(ZigVstgui::ComponentKind::title);
        group_labels[index] = new VSTGUI::CTextLabel(VSTGUI::CRect(), group_titles[index].c_str());
        group_labels[index]->setFont(styles.font(ZigVstgui::TypographyRole::title));
        group_labels[index]->setFontColor(style.foreground);
        group_labels[index]->setBackColor(style.background);
        group_labels[index]->setFrameColor(style.border);
        group_labels[index]->setFrameWidth(style.frame_width);
        group_labels[index]->setRoundRectRadius(style.radius);
        content->addView(group_labels[index]);
        group_components[index].bind(group_labels[index]);
        group_components[index].accessibility().setRole(ZigVstgui::AccessibilityRole::group);
        group_components[index].accessibility().setName(group_titles[index]);
        group_components[index].accessibility().setReadOnly(true);
    }

    for (uint32_t index = 0; index < parameter_count; ++index) {
        parameter_controls[index]->build(
            content,
            parameter_info[index],
            parameter_control_kinds[index],
            stylesForParameter(index),
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
            stylesForMeter(index)
        );
    }
    for (uint32_t index = 0; index < graph_count; ++index) {
        if (!graph_controls[index]->build(
                content,
                graph_descriptions[index],
                graph_callbacks,
                stylesForGraph(index))) return;
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
    group_labels.fill(nullptr);
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
    if (group_count > 0) {
        const bool wide = width >= 620;
        title_component.setVisible(true);
        help_component.setVisible(wide);
        title_component.setBounds(VSTGUI::CRect(margin, 12, right, 46));
        help_component.setBounds(VSTGUI::CRect(margin, 46, right, 72));
        const double groups_top = wide ? 82.0 : 54.0;
        const double footer_top = static_cast<double>(height) - margin - theme.control_metrics.compact_control_height;
        const uint32_t columns = wide ? 2 : 1;
        const uint32_t rows = (group_count + columns - 1) / columns;
        const double column_gap = theme.spacing.medium;
        const double row_gap = theme.spacing.medium;
        const double cell_width = (right - margin - column_gap * (columns - 1)) / columns;
        const double cell_height = std::max(
            1.0,
            (footer_top - theme.spacing.medium - groups_top - row_gap * (rows - 1)) / rows
        );
        for (uint32_t group_index = 0; group_index < group_count; ++group_index) {
            const uint32_t column = group_index % columns;
            const uint32_t row = group_index / columns;
            const double left = margin + column * (cell_width + column_gap);
            const double top = groups_top + row * (cell_height + row_gap);
            const double bottom = top + cell_height;
            const double group_right = left + cell_width;
            group_components[group_index].setBounds(VSTGUI::CRect(left, top, group_right, top + 28.0));
            const auto& group = group_descriptions[group_index];
            const double content_top = top + 28.0 + theme.spacing.small;
            const bool has_visuals = group.meter_count > 0 || group.graph_count > 0;
            const double parameter_fraction = has_visuals && group.parameter_count > 0 ? 0.45 : 1.0;
            const double parameter_bottom = content_top + (bottom - content_top) * parameter_fraction;
            const double control_gap = theme.spacing.small;
            const double control_height = group.parameter_count > 0
                ? std::max(24.0, (parameter_bottom - content_top - control_gap * (group.parameter_count - 1)) / group.parameter_count)
                : 0.0;
            const double label_width = std::min(88.0, cell_width * 0.26);
            const double row_value_width = std::min(82.0, cell_width * 0.24);
            for (uint32_t offset = 0; offset < group.parameter_count; ++offset) {
                const uint32_t index = group.first_parameter + offset;
                const double control_top = content_top + offset * (control_height + control_gap);
                const VSTGUI::CRect row_bounds(left, control_top, group_right, control_top + control_height);
                const ZigVstgui::GridTrack tracks[] = {
                    {label_width, 0.0},
                    {48.0, 1.0},
                    {row_value_width, 0.0},
                };
                const ZigVstgui::GridTrack row_track[] = {{24.0, 1.0}};
                const ZigVstgui::GridItem items[] = {
                    {0, 0, 1, 1},
                    {1, 0, 1, 1},
                    {2, 0, 1, 1},
                };
                VSTGUI::CRect cells[3];
                ZigVstgui::layoutGrid(
                    row_bounds,
                    {},
                    theme.spacing.small,
                    0.0,
                    tracks,
                    3,
                    row_track,
                    1,
                    items,
                    3,
                    cells
                );
                parameter_controls[index]->setBounds(cells[0], cells[1], cells[2]);
            }
            double visuals_top = group.parameter_count > 0 ? parameter_bottom + theme.spacing.small : content_top;
            if (group.graph_count > 0) {
                const double graph_bottom = group.meter_count > 0
                    ? visuals_top + (bottom - visuals_top) * 0.58
                    : bottom;
                const double graph_gap = theme.spacing.small;
                const double graph_width = (cell_width - graph_gap * (group.graph_count - 1)) / group.graph_count;
                for (uint32_t offset = 0; offset < group.graph_count; ++offset) {
                    const uint32_t index = group.first_graph + offset;
                    const double graph_left = left + offset * (graph_width + graph_gap);
                    graph_controls[index]->setBounds(
                        VSTGUI::CRect(graph_left, visuals_top, graph_left + graph_width, visuals_top + 18.0),
                        VSTGUI::CRect(graph_left, visuals_top + 18.0, graph_left + graph_width, graph_bottom)
                    );
                }
                visuals_top = graph_bottom + theme.spacing.small;
            }
            if (group.meter_count > 0) {
                const double meters_top = visuals_top;
                const double meter_gap = theme.spacing.small;
                const double meter_width = (cell_width - meter_gap * (group.meter_count - 1)) / group.meter_count;
                for (uint32_t offset = 0; offset < group.meter_count; ++offset) {
                    const uint32_t index = group.first_meter + offset;
                    const double meter_left = left + offset * (meter_width + meter_gap);
                    meter_controls[index]->setLabelVisible(true);
                    meter_controls[index]->setBounds(
                        VSTGUI::CRect(meter_left, meters_top, meter_left + meter_width, meters_top + 18.0),
                        VSTGUI::CRect(meter_left, meters_top + 18.0, meter_left + meter_width, bottom)
                    );
                }
            }
        }
        resize_control.setBounds(VSTGUI::CRect(
            right - theme.control_metrics.button_width,
            footer_top,
            right,
            height - margin
        ));
        return;
    }
    if (layout_kind == ZIG_VSTGUI_LAYOUT_COMPACT_STRIP) {
        title_component.setVisible(true);
        help_component.setVisible(false);
        title_component.setBounds(VSTGUI::CRect(margin, 16, right, 52));
        const double footer_top = static_cast<double>(height) - margin - theme.control_metrics.compact_control_height;
        const double parameter_bottom = graph_count > 0
            ? std::max(84.0, footer_top * 0.48)
            : meter_count > 0
            ? std::max(84.0, footer_top * 0.62)
            : footer_top - theme.spacing.medium;
        const double row_height = std::max(32.0, std::min(52.0, (parameter_bottom - 68.0) / parameter_count));
        const double stack_height = row_height * parameter_count + theme.spacing.small * (parameter_count - 1);
        double row_top = 68.0 + std::max(0.0, (parameter_bottom - 68.0 - stack_height) * 0.5);
        const double label_width = std::min(96.0, (right - margin) * 0.25);
        const double row_value_width = std::min(92.0, value_width);
        for (uint32_t index = 0; index < parameter_count; ++index) {
            const VSTGUI::CRect row(margin, row_top, right, row_top + row_height);
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
            VSTGUI::CRect cells[3];
            ZigVstgui::layoutGrid(
                row,
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
            parameter_controls[index]->setBounds(cells[0], cells[1], cells[2]);
            row_top += row_height + theme.spacing.small;
        }
        double visuals_top = parameter_bottom + theme.spacing.small;
        if (graph_count > 0) {
            const double graph_bottom = meter_count > 0
                ? visuals_top + (footer_top - visuals_top) * 0.56
                : footer_top - theme.spacing.medium;
            const double gap = theme.spacing.small;
            const double graph_width = std::max(1.0, (right - margin - gap * (graph_count - 1)) / graph_count);
            for (uint32_t index = 0; index < graph_count; ++index) {
                const double left = margin + index * (graph_width + gap);
                graph_controls[index]->setBounds(
                    VSTGUI::CRect(left, visuals_top, left + graph_width, visuals_top + 18.0),
                    VSTGUI::CRect(left, visuals_top + 18.0, left + graph_width, graph_bottom)
                );
            }
            visuals_top = graph_bottom + theme.spacing.small;
        }
        if (meter_count > 0) {
            const double meters_top = visuals_top;
            const double meters_bottom = footer_top - theme.spacing.medium;
            const double gap = theme.spacing.small;
            const double meter_width = std::max(1.0, (right - margin - gap * (meter_count - 1)) / meter_count);
            for (uint32_t index = 0; index < meter_count; ++index) {
                const double left = margin + index * (meter_width + gap);
                meter_controls[index]->setLabelVisible(true);
                meter_controls[index]->setBounds(
                    VSTGUI::CRect(left, meters_top, left + meter_width, meters_top + 18.0),
                    VSTGUI::CRect(left, meters_top + 18.0, left + meter_width, meters_bottom)
                );
            }
        }
        resize_control.setBounds(VSTGUI::CRect(
            right - theme.control_metrics.button_width,
            footer_top,
            right,
            height - margin
        ));
        return;
    }
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
        const double available_bottom = static_cast<double>(height) - margin - theme.control_metrics.compact_control_height - theme.spacing.medium;
        const double controls_bottom = (graph_count > 0 || meter_count > 0)
            ? controls_top + (available_bottom - controls_top) * (graph_count > 0 ? 0.45 : 0.62)
            : available_bottom;
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
    const double visuals_bottom = static_cast<double>(height) - margin -
        theme.control_metrics.compact_control_height - theme.spacing.medium;
    if (graph_count > 0) {
        const double graph_bottom = meter_count > 0
            ? meters_top + (visuals_bottom - meters_top) * 0.58
            : visuals_bottom;
        const double gap = theme.spacing.small;
        const double graph_width = std::max(1.0, (right - margin - gap * (graph_count - 1)) / graph_count);
        for (uint32_t index = 0; index < graph_count; ++index) {
            const double left = margin + index * (graph_width + gap);
            graph_controls[index]->setBounds(
                VSTGUI::CRect(left, meters_top, left + graph_width, meters_top + 18.0),
                VSTGUI::CRect(left, meters_top + 18.0, left + graph_width, graph_bottom)
            );
        }
        meters_top = graph_bottom + theme.spacing.small;
    }
    if (meter_count > 0) {
        const bool expanded = ZigVstgui::layoutMode(width, height) == ZigVstgui::LayoutMode::expanded;
        const double meters_bottom = visuals_bottom;
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

const ZigVstgui::ThemeResolver& ZigVstguiEditor::stylesForParameter(uint32_t index) const {
    for (uint32_t group_index = 0; group_index < group_count; ++group_index) {
        const auto& group = group_descriptions[group_index];
        if (index >= group.first_parameter && index < group.first_parameter + group.parameter_count) {
            return *group_styles[group_index];
        }
    }
    return theme_resolver;
}

const ZigVstgui::ThemeResolver& ZigVstguiEditor::stylesForMeter(uint32_t index) const {
    for (uint32_t group_index = 0; group_index < group_count; ++group_index) {
        const auto& group = group_descriptions[group_index];
        if (index >= group.first_meter && index < group.first_meter + group.meter_count) {
            return *group_styles[group_index];
        }
    }
    return theme_resolver;
}


const ZigVstgui::ThemeResolver& ZigVstguiEditor::stylesForGraph(uint32_t index) const {
    for (uint32_t group_index = 0; group_index < group_count; ++group_index) {
        const auto& group = group_descriptions[group_index];
        if (index >= group.first_graph && index < group.first_graph + group.graph_count) {
            return *group_styles[group_index];
        }
    }
    return theme_resolver;
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
