#include "zig_vstgui_editor.h"

#include "zig_vstgui_fonts.h"
#include "zig_vstgui_layout.h"
#include "zig_vstgui_platform.h"
#include "zig_vstgui_theme.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/vstguiinit.h"

#include <algorithm>
#include <atomic>
#include <cmath>
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

double graphAxisValue(double normalized, const ZigVstguiGraphAxis& axis) {
    const double value = std::clamp(normalized, 0.0, 1.0);
    if (axis.scale == ZIG_VSTGUI_GRAPH_LOGARITHMIC) {
        const double minimum = std::log10(axis.minimum);
        return std::pow(10.0, minimum + value * (std::log10(axis.maximum) - minimum));
    }
    return axis.minimum + value * (axis.maximum - axis.minimum);
}

}

ZigVstgui::RuntimeGuard::RuntimeGuard() {
    if (editor_count.fetch_add(1, std::memory_order_acq_rel) == 0) VSTGUI::init(nullptr);
}

ZigVstgui::RuntimeGuard::~RuntimeGuard() {
    if (editor_count.fetch_sub(1, std::memory_order_acq_rel) == 1) VSTGUI::exit();
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
    ZigVstguiGraphCallbacks value_graph_callbacks,
    const ZigVstguiXYPadDescription* xy_pads,
    uint32_t value_xy_pad_count,
    const ZigVstguiPresetBrowserDescription* preset_browsers,
    uint32_t value_preset_browser_count,
    const ZigVstguiActionMenuDescription* action_menus,
    uint32_t value_action_menu_count,
    const ZigVstguiPianoDescription* pianos,
    uint32_t value_piano_count,
    const ZigVstguiStepSequencerDescription* step_sequencers,
    uint32_t value_step_sequencer_count,
    const ZigVstguiFileDropDescription* file_drops,
    uint32_t value_file_drop_count,
    const ZigVstguiActionButtonDescription* action_buttons,
    uint32_t value_action_button_count,
    const ZigVstguiEditableLabelDescription* editable_labels,
    uint32_t value_editable_label_count,
    const ZigVstguiProgressIndicatorDescription* progress_indicators,
    uint32_t value_progress_indicator_count
)
: parameter_callbacks(callbacks),
  meter_count(value_meter_count),
  meter_callbacks(value_meter_callbacks),
  graph_count(value_graph_count),
  graph_callbacks(value_graph_callbacks),
  xy_pad_count(value_xy_pad_count),
  preset_browser_count(value_preset_browser_count),
  action_menu_count(value_action_menu_count),
  piano_count(value_piano_count), step_sequencer_count(value_step_sequencer_count),
  file_drop_count(value_file_drop_count),
  action_button_count(value_action_button_count),
  editable_label_count(value_editable_label_count),
  progress_indicator_count(value_progress_indicator_count),
  drawing_callbacks(skin.drawing),
  theme_resolver(selectedTheme(skin.theme)),
  theme_kind(skin.theme),
  layout_kind(skin.layout),
  parameter_thread(std::this_thread::get_id()) {
    profile_enabled = std::getenv("ZIG_VSTGUI_PROFILE") != nullptr;
    if (layout_kind == ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE ||
        layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        width = 720;
        height = 660;
        resize_control.setPresetSizes(480, 480, 960, 700, 840, 560);
    } else if (preset_browser_count > 0) {
        width = 720;
        height = 600;
    }
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
        if (graphs[index].editable_point_count > 0) {
            graph_editable_points[index].assign(
                graphs[index].editable_points,
                graphs[index].editable_points + graphs[index].editable_point_count
            );
            for (auto& point : graph_editable_points[index]) {
                if (point.parameter_mask != 3) continue;
                bool found_x = false;
                bool found_y = false;
                for (uint32_t parameter = 0; parameter < parameter_count; ++parameter) {
                    if (parameter_controls[parameter]->model().parameterId() == point.x_parameter_id) {
                        point.x_step_count = parameter_info[parameter].step_count;
                        point.x = graphAxisValue(
                            parameter_controls[parameter]->model().acceptedValue(),
                            graphs[index].x_axis
                        );
                        found_x = true;
                    }
                    if (parameter_controls[parameter]->model().parameterId() == point.y_parameter_id) {
                        point.y_step_count = parameter_info[parameter].step_count;
                        point.y = graphAxisValue(
                            parameter_controls[parameter]->model().acceptedValue(),
                            graphs[index].y_axis
                        );
                        found_y = true;
                    }
                }
                if (!found_x || !found_y) return;
            }
            std::stable_sort(
                graph_editable_points[index].begin(),
                graph_editable_points[index].end(),
                [](const ZigVstguiEnvelopePoint& left, const ZigVstguiEnvelopePoint& right) {
                    return left.x < right.x;
                }
            );
            graph_descriptions[index].editable_points = graph_editable_points[index].data();
        }
        graph_controls[index].reset(new (std::nothrow) ZigVstgui::GraphControl());
        if (!graph_controls[index]) return;
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        const auto& description = xy_pads[index];
        const auto* x_control = findControl(description.x_parameter_id);
        const auto* y_control = findControl(description.y_parameter_id);
        if (!description.title || !description.x_label || !description.y_label ||
            !x_control || !y_control || description.x_parameter_id == description.y_parameter_id) return;
        uint32_t x_index = 0;
        uint32_t y_index = 0;
        while (x_index < parameter_count && parameter_controls[x_index].get() != x_control) x_index += 1;
        while (y_index < parameter_count && parameter_controls[y_index].get() != y_control) y_index += 1;
        if (x_index == parameter_count || y_index == parameter_count) return;
        xy_pad_titles[index] = description.title;
        xy_pad_x_labels[index] = description.x_label;
        xy_pad_y_labels[index] = description.y_label;
        xy_pad_descriptions[index] = description;
        xy_pad_descriptions[index].title = xy_pad_titles[index].c_str();
        xy_pad_descriptions[index].x_label = xy_pad_x_labels[index].c_str();
        xy_pad_descriptions[index].y_label = xy_pad_y_labels[index].c_str();
        xy_pad_controls[index].reset(new (std::nothrow) ZigVstgui::XYPadControl(
            xy_pad_descriptions[index],
            parameter_info[x_index],
            x_control->model().acceptedValue(),
            parameter_info[y_index],
            y_control->model().acceptedValue(),
            callbacks
        ));
        if (!xy_pad_controls[index]) return;
    }
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        const auto& description = preset_browsers[index];
        preset_browser_titles[index] = description.title;
        preset_browser_searches[index] = description.initial_search;
        preset_browser_names[index].reserve(description.preset_count);
        preset_browser_presets[index].resize(description.preset_count);
        for (uint32_t preset = 0; preset < description.preset_count; ++preset) {
            preset_browser_names[index].emplace_back(description.presets[preset].name);
        }
        for (uint32_t preset = 0; preset < description.preset_count; ++preset) {
            preset_browser_presets[index][preset] = {
                description.presets[preset].preset_id,
                preset_browser_names[index][preset].c_str(),
            };
        }
        preset_browser_descriptions[index] = description;
        preset_browser_descriptions[index].title = preset_browser_titles[index].c_str();
        preset_browser_descriptions[index].initial_search = preset_browser_searches[index].c_str();
        preset_browser_descriptions[index].presets = preset_browser_presets[index].data();
        preset_browser_controls[index].reset(new (std::nothrow) ZigVstgui::PresetBrowserControl());
        if (!preset_browser_controls[index]) return;
    }
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        const auto& description = action_menus[index];
        action_menu_titles[index] = description.title;
        action_menu_items[index].resize(description.item_count);
        action_menu_labels[index].reserve(description.item_count);
        for (uint32_t item = 0; item < description.item_count; ++item) {
            if (description.items[item].label) action_menu_labels[index].emplace_back(description.items[item].label);
            else action_menu_labels[index].emplace_back();
        }
        for (uint32_t item = 0; item < description.item_count; ++item) {
            action_menu_items[index][item] = description.items[item];
            action_menu_items[index][item].label = action_menu_labels[index][item].empty()
                ? nullptr
                : action_menu_labels[index][item].c_str();
        }
        action_menu_descriptions[index] = description;
        action_menu_descriptions[index].title = action_menu_titles[index].c_str();
        action_menu_descriptions[index].items = action_menu_items[index].data();
        action_menu_controls[index].reset(new (std::nothrow) ZigVstgui::ActionMenuControl());
        if (!action_menu_controls[index]) return;
    }
    for (uint32_t index = 0; index < piano_count; ++index) {
        piano_titles[index] = pianos[index].title;
        piano_descriptions[index] = pianos[index];
        piano_descriptions[index].title = piano_titles[index].c_str();
        piano_controls[index].reset(new (std::nothrow) ZigVstgui::PianoControl(
            piano_descriptions[index], callbacks
        ));
        if (!piano_controls[index]) return;
    }
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        step_sequencer_titles[index] = step_sequencers[index].title;
        step_sequencer_descriptions[index] = step_sequencers[index];
        step_sequencer_descriptions[index].title = step_sequencer_titles[index].c_str();
        for (uint32_t step = 0; step < step_sequencers[index].step_count; ++step) {
            step_sequencer_parameter_ids[index][step] = step_sequencers[index].parameter_ids[step];
        }
        step_sequencer_descriptions[index].parameter_ids = step_sequencer_parameter_ids[index].data();
        step_sequencer_controls[index].reset(new (std::nothrow) ZigVstgui::StepSequencerControl(
            step_sequencer_descriptions[index], callbacks, {meter_callbacks.userdata, meter_callbacks.load}
        ));
        if (!step_sequencer_controls[index]) return;
    }
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        file_drop_titles[index] = file_drops[index].title;
        file_drop_prompts[index] = file_drops[index].prompt;
        file_drop_picker_labels[index] = file_drops[index].picker_label
            ? file_drops[index].picker_label : "Choose Audio File";
        file_drop_picker_titles[index] = file_drops[index].picker_title
            ? file_drops[index].picker_title : "Choose Audio File";
        file_drop_descriptions[index] = file_drops[index];
        file_drop_descriptions[index].title = file_drop_titles[index].c_str();
        file_drop_descriptions[index].prompt = file_drop_prompts[index].c_str();
        file_drop_descriptions[index].picker_label = file_drop_picker_labels[index].c_str();
        file_drop_descriptions[index].picker_title = file_drop_picker_titles[index].c_str();
        for (uint32_t extension = 0; extension < file_drops[index].extension_count; ++extension) {
            file_drop_extensions[index][extension] = file_drops[index].extensions[extension];
            file_drop_extension_pointers[index][extension] = file_drop_extensions[index][extension].c_str();
        }
        file_drop_descriptions[index].extensions = file_drop_extension_pointers[index].data();
        file_drop_controls[index].reset(new (std::nothrow) ZigVstgui::FileDropControl(
            file_drop_descriptions[index], callbacks
        ));
        if (!file_drop_controls[index]) return;
        file_drop_controls[index]->setImportStateHandler(this, importStateChanged);
    }
    for (uint32_t index = 0; index < action_button_count; ++index) {
        const auto& action = action_buttons[index];
        action_button_labels[index] = action.label ? action.label : "";
        action_button_accessible_labels[index] = action.accessible_label ? action.accessible_label : "";
        action_button_tooltips[index] = action.tooltip ? action.tooltip : "";
        action_button_confirmation_labels[index] = action.confirmation_label ? action.confirmation_label : "";
        action_button_failure_labels[index] = action.failure_label ? action.failure_label : "";
        action_button_descriptions[index] = action;
        action_button_descriptions[index].label = action_button_labels[index].empty()
            ? nullptr : action_button_labels[index].c_str();
        action_button_descriptions[index].accessible_label = action_button_accessible_labels[index].c_str();
        action_button_descriptions[index].tooltip = action_button_tooltips[index].empty()
            ? nullptr : action_button_tooltips[index].c_str();
        action_button_descriptions[index].confirmation_label = action_button_confirmation_labels[index].empty()
            ? nullptr : action_button_confirmation_labels[index].c_str();
        action_button_descriptions[index].failure_label = action_button_failure_labels[index].empty()
            ? nullptr : action_button_failure_labels[index].c_str();
        action_button_controls[index].reset(new (std::nothrow) ZigVstgui::ActionButtonControl());
        if (!action_button_controls[index]) return;
    }
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        const auto& editable = editable_labels[index];
        editable_label_labels[index] = editable.label;
        editable_label_accessible_labels[index] = editable.accessible_label;
        editable_label_placeholders[index] = editable.placeholder;
        editable_label_errors[index] = editable.error_text;
        editable_label_initial_text[index] = editable.initial_text;
        editable_label_descriptions[index] = editable;
        editable_label_descriptions[index].label = editable_label_labels[index].c_str();
        editable_label_descriptions[index].accessible_label = editable_label_accessible_labels[index].c_str();
        editable_label_descriptions[index].placeholder = editable_label_placeholders[index].c_str();
        editable_label_descriptions[index].error_text = editable_label_errors[index].c_str();
        editable_label_descriptions[index].initial_text = editable_label_initial_text[index].c_str();
        editable_label_controls[index].reset(new (std::nothrow) ZigVstgui::EditableLabelControl());
        if (!editable_label_controls[index]) return;
    }
    for (uint32_t index = 0; index < progress_indicator_count; ++index) {
        const auto& progress = progress_indicators[index];
        progress_labels[index] = progress.label;
        progress_accessible_labels[index] = progress.accessible_label;
        progress_idle_text[index] = progress.idle_text;
        progress_running_text[index] = progress.running_text;
        progress_complete_text[index] = progress.complete_text;
        progress_failure_text[index] = progress.failure_text;
        progress_descriptions[index] = progress;
        progress_descriptions[index].label = progress_labels[index].c_str();
        progress_descriptions[index].accessible_label = progress_accessible_labels[index].c_str();
        progress_descriptions[index].idle_text = progress_idle_text[index].c_str();
        progress_descriptions[index].running_text = progress_running_text[index].c_str();
        progress_descriptions[index].complete_text = progress_complete_text[index].c_str();
        progress_descriptions[index].failure_text = progress_failure_text[index].c_str();
        progress_controls[index].reset(new (std::nothrow) ZigVstgui::ProgressIndicatorControl());
        if (!progress_controls[index]) return;
    }
    uint32_t next_parameter = 0;
    uint32_t next_meter = 0;
    uint32_t next_graph = 0;
    uint32_t next_xy_pad = 0;
    for (uint32_t index = 0; index < skin.group_count; ++index) {
        const auto& group = skin.groups[index];
        if (!group.title || (group.parameter_count == 0 && group.meter_count == 0 &&
            group.graph_count == 0 && group.xy_pad_count == 0)) return;
        if (group.first_parameter != next_parameter || group.first_meter != next_meter ||
            group.first_graph != next_graph || group.first_xy_pad != next_xy_pad) return;
        if (group.parameter_count > parameter_count - next_parameter) return;
        if (group.meter_count > meter_count - next_meter) return;
        if (group.graph_count > graph_count - next_graph) return;
        if (group.xy_pad_count > xy_pad_count - next_xy_pad) return;
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
        next_xy_pad += group.xy_pad_count;
        group_count += 1;
    }
    if (group_count > 0 && (next_parameter != parameter_count || next_meter != meter_count ||
        next_graph != graph_count || next_xy_pad != xy_pad_count)) return;
    if (layout_kind == ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE ||
        layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        if (group_count < 2 || group_descriptions[0].graph_count != 1 ||
            group_descriptions[0].parameter_count > 3 || group_descriptions[0].meter_count != 0 ||
            group_descriptions[0].xy_pad_count != 0) return;
        for (uint32_t index = 1; index < group_count; ++index) {
            const auto& group = group_descriptions[index];
            if (group.parameter_count == 0 || group.parameter_count > 5 || group.graph_count != 0 ||
                group.meter_count != 0 || group.xy_pad_count != 0) return;
        }
        if (layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE &&
            (file_drop_count != 1 || progress_indicator_count != 1 || piano_count > 1)) return;
    }
    parameter_update_timer = new (std::nothrow) VSTGUI::CVSTGUITimer(
        [this](VSTGUI::CVSTGUITimer*) { flushParameterUpdates(); }, 16, false
    );
    if (!parameter_update_timer) return;
    buildFrame();
}

ZigVstguiEditor::~ZigVstguiEditor() {
    close();
    if (parameter_update_timer) {
        parameter_update_timer->stop();
        parameter_update_timer->forget();
        parameter_update_timer = nullptr;
    }
    if (frame) frame->forget();
    reportMetrics();
    ZigVstgui::releasePlatformInterfaces(plug_frame, wayland_host);
}

bool ZigVstguiEditor::valid() const {
    return parameter_count > 0 && frame && parameter_update_timer;
}

bool ZigVstguiEditor::open(void* parent, ZigVstguiPlatform platform) {
    if (!frame) buildFrame();
    if (!ZigVstgui::openFrame(frame, parent, platform, plug_frame, wayland_host)) return false;
    flushParameterUpdates();
    parameter_update_timer->start();
    accessibility_bridge.open(frame, accessibilityEntries());
    metrics.open_count += 1;
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->start();
    for (uint32_t index = 0; index < graph_count; ++index) graph_controls[index]->start();
    for (uint32_t index = 0; index < step_sequencer_count; ++index) step_sequencer_controls[index]->start();
    for (uint32_t index = 0; index < editable_label_count; ++index) editable_label_controls[index]->start();
    for (uint32_t index = 0; index < progress_indicator_count; ++index) progress_controls[index]->start();
    return true;
}

void ZigVstguiEditor::close() {
    if (parameter_update_timer) parameter_update_timer->stop();
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->stop();
    for (uint32_t index = 0; index < graph_count; ++index) graph_controls[index]->stop();
    for (uint32_t index = 0; index < step_sequencer_count; ++index) step_sequencer_controls[index]->stop();
    for (uint32_t index = 0; index < editable_label_count; ++index) editable_label_controls[index]->stop();
    for (uint32_t index = 0; index < progress_indicator_count; ++index) progress_controls[index]->stop();
    accessibility_bridge.close();
    if (!frame || !frame->getPlatformFrame()) return;
    for (uint32_t index = 0; index < parameter_count; ++index) parameter_controls[index]->clear();
    resize_control.clear();
    for (uint32_t index = 0; index < meter_count; ++index) meter_controls[index]->clear();
    for (uint32_t index = 0; index < graph_count; ++index) graph_controls[index]->clear();
    for (uint32_t index = 0; index < xy_pad_count; ++index) xy_pad_controls[index]->clear();
    for (uint32_t index = 0; index < preset_browser_count; ++index) preset_browser_controls[index]->clear();
    for (uint32_t index = 0; index < action_menu_count; ++index) action_menu_controls[index]->clear();
    for (uint32_t index = 0; index < piano_count; ++index) piano_controls[index]->clear();
    for (uint32_t index = 0; index < step_sequencer_count; ++index) step_sequencer_controls[index]->clear();
    for (uint32_t index = 0; index < file_drop_count; ++index) file_drop_controls[index]->clear();
    for (uint32_t index = 0; index < action_button_count; ++index) action_button_controls[index]->clear();
    for (uint32_t index = 0; index < editable_label_count; ++index) editable_label_controls[index]->clear();
    for (uint32_t index = 0; index < progress_indicator_count; ++index) progress_controls[index]->clear();
    title_component.clear();
    help_component.clear();
    for (uint32_t index = 0; index < group_count; ++index) group_components[index].clear();
    metrics.close_count += 1;
    ZigVstgui::prepareFrameForClose(frame);
    frame->close();
    clearFrameReferences();
}

bool ZigVstguiEditor::resize(uint32_t new_width, uint32_t new_height) {
    if (!frame || new_width < 320 || new_height < 240) return false;
    const double scale = frame->getZoom();
    if (!std::isfinite(scale) || scale <= 0.0 ||
        !frame->setSize(new_width * scale, new_height * scale)) return false;
    width = new_width;
    height = new_height;
    metrics.resize_count += 1;
    resize_control.setSize(width, height);
    layout();
    accessibility_bridge.layoutChanged();
    return true;
}

bool ZigVstguiEditor::setScale(double scale) {
    if (!frame || !std::isfinite(scale) || scale <= 0.0 || !frame->setZoom(scale)) return false;
    metrics.scale_count += 1;
    accessibility_bridge.layoutChanged();
    return true;
}

bool ZigVstguiEditor::setParameter(uint32_t parameter_id, double normalized) {
    const uint32_t parameter_index = findParameterIndex(parameter_id);
    if (parameter_index == UINT32_MAX) return false;
    if (std::this_thread::get_id() != parameter_thread) {
        pending_parameter_values[parameter_index].store(normalized, std::memory_order_relaxed);
        pending_parameter_dirty[parameter_index].store(true, std::memory_order_release);
        return true;
    }
    pending_parameter_dirty[parameter_index].store(false, std::memory_order_release);
    return applyParameter(parameter_id, normalized);
}

void ZigVstguiEditor::flushParameterUpdates() {
    if (std::this_thread::get_id() != parameter_thread) return;
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (!pending_parameter_dirty[index].exchange(false, std::memory_order_acq_rel)) continue;
        applyParameter(
            parameter_controls[index]->model().parameterId(),
            pending_parameter_values[index].load(std::memory_order_acquire)
        );
    }
}

bool ZigVstguiEditor::applyParameter(uint32_t parameter_id, double normalized) {
    auto* control = findControl(parameter_id);
    bool found = control != nullptr;
    if (control) control->setValue(normalized);
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        found = xy_pad_controls[index]->setParameter(parameter_id, normalized) || found;
    }
    for (uint32_t index = 0; index < graph_count; ++index) {
        found = graph_controls[index]->setParameter(parameter_id, normalized) || found;
    }
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        found = step_sequencer_controls[index]->setParameter(parameter_id, normalized) || found;
    }
    if (!found) return false;
    metrics.parameter_update_count += 1;
    return true;
}

uint32_t ZigVstguiEditor::findParameterIndex(uint32_t parameter_id) const {
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (parameter_controls[index]->model().parameterId() == parameter_id) return index;
    }
    return UINT32_MAX;
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
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        editable_label_controls[index]->refresh();
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

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::xyPadAccessibility(
    uint32_t index,
    uint32_t axis
) const {
    return index < xy_pad_count && axis < 2
        ? &xy_pad_controls[index]->axisAccessibility(axis)
        : nullptr;
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::presetBrowserAccessibility(uint32_t index) const {
    return index < preset_browser_count ? &preset_browser_controls[index]->accessibilityNode() : nullptr;
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::actionMenuAccessibility(uint32_t index) const {
    return index < action_menu_count ? &action_menu_controls[index]->accessibilityNode() : nullptr;
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::pianoAccessibility(uint32_t index) const {
    return index < piano_count ? &piano_controls[index]->accessibilityNode() : nullptr;
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::stepSequencerAccessibility(uint32_t index) const {
    return index < step_sequencer_count ? &step_sequencer_controls[index]->accessibilityNode() : nullptr;
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::fileDropAccessibility(uint32_t index) const {
    return index < file_drop_count ? &file_drop_controls[index]->accessibilityNode() : nullptr;
}

void ZigVstguiEditor::focusFileImporter(uint32_t importer_id) {
    if (!frame) return;
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        if (file_drop_descriptions[index].drop_id != importer_id) continue;
        if (auto* view = file_drop_controls[index]->focusView()) {
            frame->setFocusView(view);
            for (uint32_t action_index = 0; action_index < action_button_count; ++action_index) {
                action_button_controls[action_index]->setFocusedView(nullptr);
            }
            for (uint32_t importer_index = 0; importer_index < file_drop_count; ++importer_index) {
                file_drop_controls[importer_index]->setFocusedView(
                    importer_index == index ? view : nullptr
                );
            }
        }
        return;
    }
}

void ZigVstguiEditor::actionAccepted(uint32_t importer_id) {
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        file_drop_controls[index]->refreshImportState();
    }
    if (importer_id != 0) focusFileImporter(importer_id);
}

void ZigVstguiEditor::importStateChanged(void* userdata, uint32_t, ZigVstguiFileImportStatus) {
    auto* editor = static_cast<ZigVstguiEditor*>(userdata);
    if (editor) editor->updateActionButtonStates();
}

void ZigVstguiEditor::updateActionButtonStates() {
    for (uint32_t action_index = 0; action_index < action_button_count; ++action_index) {
        const auto& description = action_button_descriptions[action_index];
        bool enabled = description.enabled != 0;
        if (enabled && description.ready_importer_id != 0) {
            enabled = false;
            for (uint32_t importer_index = 0; importer_index < file_drop_count; ++importer_index) {
                if (file_drop_descriptions[importer_index].drop_id == description.ready_importer_id) {
                    enabled = file_drop_controls[importer_index]->importReady();
                    break;
                }
            }
        }
        const bool loses_focus = !enabled && frame &&
            frame->getFocusView() == action_button_controls[action_index]->focusView();
        action_button_controls[action_index]->setEnabled(enabled);
        if (loses_focus) focusFileImporter(description.ready_importer_id);
    }
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::actionButtonAccessibility(uint32_t index) const {
    return index < action_button_count ? &action_button_controls[index]->accessibilityNode() : nullptr;
}

VSTGUI::CRect ZigVstguiEditor::actionButtonBounds(uint32_t index) const {
    return index < action_button_count ? action_button_controls[index]->bounds() : VSTGUI::CRect();
}

double ZigVstguiEditor::parameterControlValueGap(uint32_t parameter_id) const {
    const auto* control = findControl(parameter_id);
    return control ? control->primaryValueGap() : 0.0;
}

bool ZigVstguiEditor::parameterControlBounds(
    uint32_t parameter_id,
    VSTGUI::CRect& label_bounds,
    VSTGUI::CRect& primary_bounds,
    VSTGUI::CRect& value_bounds
) const {
    const auto* control = findControl(parameter_id);
    return control && control->bounds(label_bounds, primary_bounds, value_bounds);
}

VSTGUI::CRect ZigVstguiEditor::groupBounds(uint32_t index) const {
    auto* label = index < group_count ? group_labels[index] : nullptr;
    return label ? label->getViewSize() : VSTGUI::CRect();
}

VSTGUI::CRect ZigVstguiEditor::graphBounds(uint32_t index) const {
    auto* graph = index < graph_count ? graph_controls[index]->graphView() : nullptr;
    return graph ? graph->getViewSize() : VSTGUI::CRect();
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::editableLabelAccessibility(uint32_t index) const {
    return index < editable_label_count ? &editable_label_controls[index]->accessibilityNode() : nullptr;
}

const ZigVstgui::AccessibilityNode* ZigVstguiEditor::progressAccessibility(uint32_t index) const {
    return index < progress_indicator_count ? &progress_controls[index]->accessibilityNode() : nullptr;
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
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        auto& menu = *action_menu_controls[index];
        if (menu.menuView() && menu.menuView()->isOpen()) return menu.handleKey(key, key_code, modifiers);
    }
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
    for (uint32_t index = 0; index < graph_count; ++index) {
        auto& graph = *graph_controls[index];
        if (focused == graph.focusView() && graph.handleKey(key, key_code, modifiers)) return true;
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        auto& xy_pad = *xy_pad_controls[index];
        if (focused == xy_pad.focusView() && xy_pad.handleKey(key, key_code, modifiers)) return true;
    }
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        auto& editable = *editable_label_controls[index];
        if (focused == editable.focusView() && editable.handleKey(key, key_code)) return true;
    }
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        auto& browser = *preset_browser_controls[index];
        if (focused == browser.focusView() && browser.handleKey(key, key_code, modifiers)) return true;
    }
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        auto& menu = *action_menu_controls[index];
        if (focused == menu.focusView() && menu.handleKey(key, key_code, modifiers)) return true;
    }
    for (uint32_t index = 0; index < piano_count; ++index) {
        auto& piano = *piano_controls[index];
        if (focused == piano.focusView() && piano.handleKey(key, key_code, modifiers, true)) return true;
    }
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        auto& sequencer = *step_sequencer_controls[index];
        if (focused == sequencer.focusView() && sequencer.handleKey(key, key_code, modifiers)) return true;
    }
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        auto& file_drop = *file_drop_controls[index];
        if (focused == file_drop.focusView() && file_drop.handleKey(key, key_code, modifiers)) return true;
    }
    for (uint32_t index = 0; index < action_button_count; ++index) {
        auto& action = *action_button_controls[index];
        if (focused == action.focusView() && action.handleKey(key, key_code, modifiers)) return true;
    }
    if (parameter_count == 0 || !parameter_controls[0]->handleKey(key, key_code, modifiers)) return false;
    frame->setFocusView(parameter_controls[0]->focusView());
    return true;
}

bool ZigVstguiEditor::keyUp(uint16_t key, int16_t key_code, int16_t modifiers) {
    bool handled = false;
    for (uint32_t index = 0; index < piano_count; ++index) {
        handled = piano_controls[index]->handleKey(key, key_code, modifiers, false) || handled;
    }
    return handled;
}

bool ZigVstguiEditor::focusNext(bool reverse) {
    if (!frame) return false;
    std::array<
        VSTGUI::CView*,
        ZIG_VSTGUI_MAX_PARAMETERS * 2 + ZIG_VSTGUI_MAX_METERS + ZIG_VSTGUI_MAX_GRAPHS +
            ZIG_VSTGUI_MAX_XY_PADS + 1
            + ZIG_VSTGUI_MAX_PRESET_BROWSERS
            + ZIG_VSTGUI_MAX_ACTION_MENUS
            + ZIG_VSTGUI_MAX_PIANOS
            + ZIG_VSTGUI_MAX_STEP_SEQUENCERS
            + ZIG_VSTGUI_MAX_FILE_DROPS
            + ZIG_VSTGUI_MAX_ACTION_BUTTONS
            + ZIG_VSTGUI_MAX_EDITABLE_LABELS
    > focus_order {};
    uint32_t focus_count = 0;
    if (layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        for (uint32_t index = 0; index < file_drop_count; ++index) {
            if (auto* importer = file_drop_controls[index]->focusView()) focus_order[focus_count++] = importer;
        }
        for (uint32_t index = 0; index < graph_count; ++index) {
            if (auto* graph = graph_controls[index]->focusView()) focus_order[focus_count++] = graph;
        }
    }
    for (uint32_t index = 0; index < parameter_count; ++index) {
        if (auto* primary = parameter_controls[index]->focusView()) focus_order[focus_count++] = primary;
        if (auto* value = parameter_controls[index]->valueFocusView()) focus_order[focus_count++] = value;
    }
    for (uint32_t index = 0; index < meter_count; ++index) {
        if (auto* meter = meter_controls[index]->focusView()) focus_order[focus_count++] = meter;
    }
    if (layout_kind != ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        for (uint32_t index = 0; index < graph_count; ++index) {
            if (auto* graph = graph_controls[index]->focusView()) focus_order[focus_count++] = graph;
        }
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        if (auto* xy_pad = xy_pad_controls[index]->focusView()) focus_order[focus_count++] = xy_pad;
    }
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        if (auto* editable = editable_label_controls[index]->focusView()) focus_order[focus_count++] = editable;
    }
    if (layout_kind != ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        for (uint32_t index = 0; index < file_drop_count; ++index) {
            if (auto* importer = file_drop_controls[index]->focusView()) focus_order[focus_count++] = importer;
        }
    }
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        if (auto* sequencer = step_sequencer_controls[index]->focusView()) focus_order[focus_count++] = sequencer;
    }
    for (uint32_t index = 0; index < piano_count; ++index) {
        if (auto* piano = piano_controls[index]->focusView()) focus_order[focus_count++] = piano;
    }
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        if (auto* browser = preset_browser_controls[index]->focusView()) focus_order[focus_count++] = browser;
    }
    for (uint32_t index = 0; index < action_button_count; ++index) {
        if (action_button_controls[index]->enabled()) {
            if (auto* action = action_button_controls[index]->focusView()) focus_order[focus_count++] = action;
        }
    }
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        if (auto* menu = action_menu_controls[index]->focusView()) focus_order[focus_count++] = menu;
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
    for (uint32_t index = 0; index < graph_count; ++index) {
        graph_controls[index]->setFocusedView(next_view);
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        xy_pad_controls[index]->setFocusedView(next_view);
    }
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        editable_label_controls[index]->setFocusedView(next_view);
    }
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        preset_browser_controls[index]->setFocusedView(next_view);
    }
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        action_menu_controls[index]->setFocusedView(next_view);
    }
    for (uint32_t index = 0; index < piano_count; ++index) piano_controls[index]->setFocusedView(next_view);
    for (uint32_t index = 0; index < step_sequencer_count; ++index) step_sequencer_controls[index]->setFocusedView(next_view);
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        file_drop_controls[index]->setFocusedView(next_view);
    }
    for (uint32_t index = 0; index < action_button_count; ++index) {
        action_button_controls[index]->setFocusedView(next_view);
    }
    resize_control.setFocusedView(next_view);
    focus_position = static_cast<int32_t>(next);
    return true;
}

void ZigVstguiEditor::setFocus(bool focused) {
    if (!frame) return;
    frame->onActivate(focused);
    if (focused) {
        for (uint32_t index = 0; index < file_drop_count; ++index) {
            file_drop_controls[index]->refreshImportState();
        }
        for (uint32_t index = 0; index < editable_label_count; ++index) {
            editable_label_controls[index]->refresh();
        }
    }
    if (!focused) {
        for (uint32_t index = 0; index < parameter_count; ++index) {
            parameter_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < graph_count; ++index) {
            graph_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < xy_pad_count; ++index) {
            xy_pad_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < editable_label_count; ++index) {
            editable_label_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < preset_browser_count; ++index) {
            preset_browser_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < action_menu_count; ++index) {
            action_menu_controls[index]->close(false);
            action_menu_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < piano_count; ++index) {
            piano_controls[index]->releaseAll();
            piano_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < step_sequencer_count; ++index) {
            step_sequencer_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < file_drop_count; ++index) {
            file_drop_controls[index]->setFocusedView(nullptr);
        }
        for (uint32_t index = 0; index < action_button_count; ++index) {
            action_button_controls[index]->cancelPending();
            action_button_controls[index]->setFocusedView(nullptr);
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

bool ZigVstguiEditor::contentScrollingActive() const {
    return content_height > static_cast<double>(height);
}

double ZigVstguiEditor::contentHeight() const { return content_height; }

bool ZigVstguiEditor::setVerticalScrollOffset(double offset) {
    if (!scroll_view) return false;
    scroll_view->setScrollOffset(VSTGUI::CPoint(0.0, offset));
    return true;
}

double ZigVstguiEditor::verticalScrollOffset() const {
    return scroll_view ? scroll_view->getScrollOffset().y : 0.0;
}

double ZigVstguiEditor::visibleContentTop() const {
    return content ? content->getViewSize().top : 0.0;
}

VSTGUI::CFrame* ZigVstguiEditor::frameView() const { return frame; }

std::size_t ZigVstguiEditor::nativeAccessibilityElementCount() const {
    return accessibility_bridge.elementCount();
}

std::vector<ZigVstgui::AccessibilityEntry> ZigVstguiEditor::accessibilityEntries() const {
    std::vector<ZigVstgui::AccessibilityEntry> entries;
    entries.reserve(2 + group_count + parameter_count * 2 + meter_count + graph_count +
        xy_pad_count * 2 + preset_browser_count + action_menu_count + piano_count + step_sequencer_count +
        file_drop_count + action_button_count + editable_label_count + progress_indicator_count + 1);
    entries.push_back({&title_component.accessibility(), title_component.view()});
    entries.push_back({&help_component.accessibility(), help_component.view()});
    if (layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        for (uint32_t index = 0; index < file_drop_count; ++index) {
            entries.push_back({&file_drop_controls[index]->accessibilityNode(), file_drop_controls[index]->dropView()});
        }
        for (uint32_t index = 0; index < progress_indicator_count; ++index) {
            entries.push_back({
                &progress_controls[index]->accessibilityNode(),
                progress_controls[index]->accessibilityView(),
            });
        }
        for (uint32_t index = 0; index < graph_count; ++index) {
            entries.push_back({&graph_controls[index]->accessibilityNode(), graph_controls[index]->graphView()});
        }
    }
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
    if (layout_kind != ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        for (uint32_t index = 0; index < graph_count; ++index) {
            entries.push_back({&graph_controls[index]->accessibilityNode(), graph_controls[index]->graphView()});
        }
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        const auto& xy_pad = *xy_pad_controls[index];
        entries.push_back({&xy_pad.axisAccessibility(0), xy_pad.focusView()});
        entries.push_back({&xy_pad.axisAccessibility(1), xy_pad.focusView()});
    }
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        entries.push_back({
            &editable_label_controls[index]->accessibilityNode(),
            editable_label_controls[index]->accessibilityView(),
        });
    }
    if (layout_kind != ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        for (uint32_t index = 0; index < progress_indicator_count; ++index) {
            entries.push_back({
                &progress_controls[index]->accessibilityNode(),
                progress_controls[index]->accessibilityView(),
            });
        }
        for (uint32_t index = 0; index < file_drop_count; ++index) {
            entries.push_back({&file_drop_controls[index]->accessibilityNode(), file_drop_controls[index]->dropView()});
        }
    }
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        entries.push_back({
            &step_sequencer_controls[index]->accessibilityNode(),
            step_sequencer_controls[index]->focusView(),
        });
    }
    for (uint32_t index = 0; index < piano_count; ++index) {
        entries.push_back({&piano_controls[index]->accessibilityNode(), piano_controls[index]->focusView()});
    }
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        entries.push_back({
            &preset_browser_controls[index]->accessibilityNode(),
            preset_browser_controls[index]->focusView(),
        });
    }
    for (uint32_t index = 0; index < action_button_count; ++index) {
        entries.push_back({
            &action_button_controls[index]->accessibilityNode(),
            action_button_controls[index]->focusView(),
        });
    }
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        entries.push_back({
            &action_menu_controls[index]->accessibilityNode(),
            action_menu_controls[index]->focusView(),
        });
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
    content_height = minimumContentHeight();
    scroll_view = new VSTGUI::CScrollView(
        VSTGUI::CRect(0, 0, width, height),
        VSTGUI::CRect(0, 0, width, content_height),
        VSTGUI::CScrollView::kVerticalScrollbar |
            VSTGUI::CScrollView::kOverlayScrollbars |
            VSTGUI::CScrollView::kAutoHideScrollbars |
            VSTGUI::CScrollView::kFollowFocusView |
            VSTGUI::CScrollView::kDontDrawFrame,
        12.0
    );
    scroll_view->setBackgroundColor(editor_style.background);
    frame->addView(scroll_view);
    content = new ZigVstgui::ProfiledContainer(
        VSTGUI::CRect(0, 0, width, content_height),
        profile_enabled ? &metrics : nullptr
    );
    content->setBackgroundColor(editor_style.background);
    scroll_view->addView(content);

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
                parameter_callbacks,
                stylesForGraph(index),
                this,
                graphSelectionChanged)) return;
    }
    resize_control.build(content, theme_resolver);
    resize_control.setSize(width, height);
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        if (!preset_browser_controls[index]->build(
            content,
            preset_browser_descriptions[index],
            parameter_callbacks,
            theme_resolver
        )) return;
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        xy_pad_controls[index]->build(content, stylesForXYPad(index));
    }
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        if (!action_menu_controls[index]->build(
            content,
            action_menu_descriptions[index],
            parameter_callbacks,
            theme_resolver
        )) return;
        action_menu_controls[index]->setOpenCoordinator(this, actionMenuWillOpen);
    }
    for (uint32_t index = 0; index < piano_count; ++index) {
        piano_controls[index]->build(content, theme_resolver);
    }
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        step_sequencer_controls[index]->build(content, theme_resolver);
    }
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        file_drop_controls[index]->build(content, theme_resolver);
    }
    for (uint32_t index = 0; index < action_button_count; ++index) {
        if (!action_button_controls[index]->build(
            content,
            action_button_descriptions[index],
            parameter_callbacks,
            theme_resolver,
            [this](uint32_t importer_id) { actionAccepted(importer_id); }
        )) return;
    }
    updateActionButtonStates();
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        if (!editable_label_controls[index]->build(
            content, editable_label_descriptions[index], parameter_callbacks, theme_resolver)) return;
    }
    for (uint32_t index = 0; index < progress_indicator_count; ++index) {
        if (!progress_controls[index]->build(
            content, progress_descriptions[index], parameter_callbacks, theme_resolver)) return;
    }
    layout();
}

void ZigVstguiEditor::clearFrameReferences() {
    frame = nullptr;
    scroll_view = nullptr;
    content = nullptr;
    title = nullptr;
    help = nullptr;
    group_labels.fill(nullptr);
}

void ZigVstguiEditor::layout() {
    if (!frame) return;
    content_height = minimumContentHeight();
    VSTGUI::CPoint retained_scroll_offset {};
    if (scroll_view) {
        retained_scroll_offset = scroll_view->getScrollOffset();
        scroll_view->resetScrollOffset();
        scroll_view->setViewSize(VSTGUI::CRect(0, 0, width, height), true);
        scroll_view->setContainerSize(VSTGUI::CRect(0, 0, width, content_height), false);
    }
    if (content) content->setViewSize(VSTGUI::CRect(0, 0, width, content_height), true);
    if (scroll_view) {
        retained_scroll_offset.x = 0.0;
        retained_scroll_offset.y = std::clamp(
            retained_scroll_offset.y,
            0.0,
            std::max(0.0, content_height - static_cast<double>(height))
        );
        scroll_view->setScrollOffset(retained_scroll_offset);
    }
    const auto& theme = theme_resolver.theme();
    const bool instrument_workspace = layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE;
    const double margin = theme.spacing.large;
    const double right = std::max(margin + 1.0, static_cast<double>(width) - margin);
    const double value_width = std::min(
        theme.control_metrics.value_width,
        static_cast<double>(width) - margin * 2.0
    );
    const double footer_bottom = content_height - margin;
    const double footer_control_top = footer_bottom - theme.control_metrics.compact_control_height;
    const double footer_top = footer_bottom - footerHeight();
    const double browser_height = preset_browser_count > 0
        ? std::clamp(content_height * 0.22, 104.0, 156.0)
        : 0.0;
    const double browser_bottom = footer_top - theme.spacing.small;
    const double browser_top = browser_bottom - browser_height;
    const double lower_content_bottom = preset_browser_count > 0
        ? browser_top - theme.spacing.medium
        : footer_top - theme.spacing.medium;
    const double piano_height = piano_count > 0
        ? std::clamp(content_height * 0.2, 96.0, 140.0)
        : 0.0;
    const double piano_bottom = lower_content_bottom;
    const double piano_top = piano_bottom - piano_height;
    const double sequencer_height = step_sequencer_count > 0
        ? std::clamp(content_height * 0.12, 68.0, 94.0)
        : 0.0;
    const double sequencer_bottom = piano_count > 0 ? piano_top - theme.spacing.medium : lower_content_bottom;
    const double sequencer_top = sequencer_bottom - sequencer_height;
    const double file_drop_height = file_drop_count > 0 && !instrument_workspace ? 112.0 : 0.0;
    const double file_drop_bottom = step_sequencer_count > 0
        ? sequencer_top - theme.spacing.medium
        : (piano_count > 0 ? piano_top - theme.spacing.medium : lower_content_bottom);
    const double file_drop_top = file_drop_bottom - file_drop_height;
    const uint32_t utility_count = editable_label_count +
        (instrument_workspace ? 0 : progress_indicator_count);
    const double utility_bottom = file_drop_count > 0 ? file_drop_top - theme.spacing.medium : file_drop_bottom;
    const double utility_height = utility_count > 0
        ? editable_label_count * 58.0 + (instrument_workspace ? 0.0 : progress_indicator_count * 48.0) +
            theme.spacing.small * (utility_count - 1)
        : 0.0;
    const double utility_top = utility_bottom - utility_height;
    const double content_bottom = utility_count > 0 ? utility_top - theme.spacing.medium : utility_bottom;
    if (preset_browser_count > 0) {
        layoutPresetBrowsers(margin, browser_top, right, browser_bottom);
    }
    if (piano_count > 0) layoutPianos(margin, piano_top, right, piano_bottom);
    if (step_sequencer_count > 0) layoutStepSequencers(margin, sequencer_top, right, sequencer_bottom);
    if (file_drop_count > 0 && !instrument_workspace) {
        layoutFileDrops(margin, file_drop_top, right, file_drop_bottom);
    }
    double utility_cursor = utility_top;
    if (editable_label_count > 0) {
        const double editable_bottom = utility_cursor + editable_label_count * 58.0 +
            theme.spacing.small * (editable_label_count - 1);
        layoutEditableLabels(margin, utility_cursor, right, editable_bottom);
        utility_cursor = editable_bottom + (progress_indicator_count > 0 ? theme.spacing.small : 0.0);
    }
    if (progress_indicator_count > 0 && !instrument_workspace) {
        layoutProgressIndicators(margin, utility_cursor, right, utility_bottom);
    }
    if (instrument_workspace) {
        const double importer_top = 54.0;
        layoutFileDrops(margin, importer_top, right, importer_top + 112.0);
        layoutProgressIndicators(
            margin,
            importer_top + 112.0 + theme.spacing.small,
            right,
            importer_top + 160.0 + theme.spacing.small
        );
    }
    const double footer_right = right - theme.control_metrics.button_width - theme.spacing.small;
    if (action_button_count > 0 && action_menu_count > 0) {
        const double split = margin + (footer_right - margin) * 0.68;
        layoutActionButtons(margin, footer_top, split - theme.spacing.small, content_height - margin);
        layoutActionMenus(split, footer_control_top, footer_right, footer_bottom);
    } else if (action_button_count > 0) {
        layoutActionButtons(margin, footer_top, footer_right, footer_bottom);
    } else {
        layoutActionMenus(margin, footer_control_top, footer_right, footer_bottom);
    }
    if (layout_kind == ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE ||
        layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        layoutParameterWorkspace(margin, right, content_bottom, footer_control_top, footer_bottom);
        return;
    }
    if (group_count > 0) {
        const bool wide = width >= 620;
        title_component.setVisible(true);
        help_component.setVisible(wide);
        title_component.setBounds(VSTGUI::CRect(margin, 12, right, 46));
        help_component.setBounds(VSTGUI::CRect(margin, 46, right, 72));
        const double groups_top = wide ? 82.0 : 54.0;
        const uint32_t columns = wide ? 2 : 1;
        const uint32_t rows = (group_count + columns - 1) / columns;
        const double column_gap = theme.spacing.medium;
        const double row_gap = theme.spacing.medium;
        const double cell_width = (right - margin - column_gap * (columns - 1)) / columns;
        const double cell_height = std::max(
            1.0,
            (content_bottom - groups_top - row_gap * (rows - 1)) / rows
        );
        for (uint32_t group_index = 0; group_index < group_count; ++group_index) {
            const uint32_t column = group_index % columns;
            const uint32_t row = group_index / columns;
            const bool spans_row = columns == 2 && group_count % 2 == 1 && group_index + 1 == group_count;
            const double left = spans_row ? margin : margin + column * (cell_width + column_gap);
            const double top = groups_top + row * (cell_height + row_gap);
            const double bottom = top + cell_height;
            const double group_right = spans_row ? right : left + cell_width;
            const double group_width = group_right - left;
            group_components[group_index].setBounds(VSTGUI::CRect(left, top, group_right, top + 28.0));
            const auto& group = group_descriptions[group_index];
            const double content_top = top + 28.0 + theme.spacing.small;
            const bool has_visuals = group.meter_count > 0 || group.graph_count > 0 || group.xy_pad_count > 0;
            const double parameter_fraction = has_visuals && group.parameter_count > 0 ? 0.45 : 1.0;
            const double parameter_bottom = content_top + (bottom - content_top) * parameter_fraction;
            const double control_gap = theme.spacing.small;
            const double control_height = group.parameter_count > 0
                ? std::max(24.0, (parameter_bottom - content_top - control_gap * (group.parameter_count - 1)) / group.parameter_count)
                : 0.0;
            const double label_width = std::min(88.0, group_width * 0.26);
            const double row_value_width = std::min(82.0, group_width * 0.24);
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
            if (group.xy_pad_count > 0) {
                const bool has_following = group.graph_count > 0 || group.meter_count > 0;
                const double xy_bottom = has_following
                    ? visuals_top + (bottom - visuals_top) * 0.45
                    : bottom;
                const double xy_gap = theme.spacing.small;
                const double xy_width = (group_width - xy_gap * (group.xy_pad_count - 1)) / group.xy_pad_count;
                for (uint32_t offset = 0; offset < group.xy_pad_count; ++offset) {
                    const uint32_t index = group.first_xy_pad + offset;
                    const double xy_left = left + offset * (xy_width + xy_gap);
                    xy_pad_controls[index]->setBounds(
                        VSTGUI::CRect(xy_left, visuals_top, xy_left + xy_width, visuals_top + 18.0),
                        VSTGUI::CRect(xy_left, visuals_top + 18.0, xy_left + xy_width, xy_bottom)
                    );
                }
                visuals_top = xy_bottom + theme.spacing.small;
            }
            if (group.graph_count > 0) {
                const double graph_bottom = group.meter_count > 0
                    ? visuals_top + (bottom - visuals_top) * 0.58
                    : bottom;
                const double graph_gap = theme.spacing.small;
                const uint32_t graph_columns = ZigVstgui::responsiveColumnCount(
                    group_width,
                    graph_gap,
                    120.0,
                    group.graph_count
                );
                const uint32_t graph_rows = (group.graph_count + graph_columns - 1) / graph_columns;
                const double graph_width =
                    (group_width - graph_gap * (graph_columns - 1)) / graph_columns;
                const double graph_height = std::max(
                    1.0,
                    (graph_bottom - visuals_top - graph_gap * (graph_rows - 1)) / graph_rows
                );
                for (uint32_t offset = 0; offset < group.graph_count; ++offset) {
                    const uint32_t index = group.first_graph + offset;
                    const uint32_t graph_column = offset % graph_columns;
                    const uint32_t graph_row = offset / graph_columns;
                    const double graph_left = left + graph_column * (graph_width + graph_gap);
                    const double graph_top = visuals_top + graph_row * (graph_height + graph_gap);
                    graph_controls[index]->setBounds(
                        VSTGUI::CRect(graph_left, graph_top, graph_left + graph_width, graph_top + 18.0),
                        VSTGUI::CRect(
                            graph_left,
                            graph_top + 18.0,
                            graph_left + graph_width,
                            graph_top + graph_height
                        )
                    );
                }
                visuals_top = graph_bottom + theme.spacing.small;
            }
            if (group.meter_count > 0) {
                const double meters_top = visuals_top;
                const double meter_gap = theme.spacing.small;
                const double meter_width = (group_width - meter_gap * (group.meter_count - 1)) / group.meter_count;
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
            footer_control_top,
            right,
            footer_bottom
        ));
        return;
    }
    if (layout_kind == ZIG_VSTGUI_LAYOUT_COMPACT_STRIP) {
        title_component.setVisible(true);
        help_component.setVisible(false);
        title_component.setBounds(VSTGUI::CRect(margin, 16, right, 52));
        const double parameter_bottom = (graph_count > 0 || xy_pad_count > 0)
            ? std::max(84.0, content_bottom * 0.48)
            : meter_count > 0
            ? std::max(84.0, content_bottom * 0.62)
            : content_bottom;
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
        if (xy_pad_count > 0) {
            const bool has_following = graph_count > 0 || meter_count > 0;
            const double xy_bottom = has_following
                ? visuals_top + (content_bottom - visuals_top) * 0.42
                : content_bottom;
            const double gap = theme.spacing.small;
            const double xy_width = std::max(
                1.0,
                (right - margin - gap * (xy_pad_count - 1)) / xy_pad_count
            );
            for (uint32_t index = 0; index < xy_pad_count; ++index) {
                const double left = margin + index * (xy_width + gap);
                xy_pad_controls[index]->setBounds(
                    VSTGUI::CRect(left, visuals_top, left + xy_width, visuals_top + 18.0),
                    VSTGUI::CRect(left, visuals_top + 18.0, left + xy_width, xy_bottom)
                );
            }
            visuals_top = xy_bottom + theme.spacing.small;
        }
        if (graph_count > 0) {
            const double graph_bottom = meter_count > 0
                ? visuals_top + (content_bottom - visuals_top) * 0.56
                : content_bottom;
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
            const double meters_bottom = content_bottom;
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
            footer_control_top,
            right,
            footer_bottom
        ));
        return;
    }
    title_component.setBounds(VSTGUI::CRect(margin, 16, right, 52));
    help_component.setBounds(VSTGUI::CRect(margin, 54, right, 82));
    double meters_top = 92.0;
    if (parameter_count == 1) {
        title_component.setVisible(true);
        help_component.setVisible(true);
        const double initial_track_top = std::clamp(
            content_height * 0.42,
            92.0,
            content_height - 116.0
        );
        const double value_top = content_bottom - theme.control_metrics.compact_control_height;
        const double initial_gap = value_top -
            (initial_track_top + theme.control_metrics.control_height);
        const double track_top = std::max(
            92.0,
            initial_track_top - std::max(0.0, theme.spacing.medium - initial_gap)
        );
        parameter_controls[0]->setBounds(
            VSTGUI::CRect(),
            VSTGUI::CRect(margin, track_top, right, track_top + theme.control_metrics.control_height),
            VSTGUI::CRect(
                margin,
                value_top,
                margin + value_width,
                content_bottom
            )
        );
        meters_top = track_top + theme.control_metrics.control_height + theme.spacing.small;
    } else {
        const auto mode = ZigVstgui::layoutMode(width, height);
        const bool expanded = mode == ZigVstgui::LayoutMode::expanded;
        title_component.setVisible(expanded);
        help_component.setVisible(expanded);
        const double controls_top = expanded ? 92.0 : theme.spacing.medium;
        const double available_bottom = content_bottom;
        const double controls_bottom = (graph_count > 0 || meter_count > 0 || xy_pad_count > 0)
            ? controls_top + (available_bottom - controls_top) *
                ((graph_count > 0 || xy_pad_count > 0) ? 0.45 : 0.62)
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
    const double visuals_bottom = content_bottom;
    if (xy_pad_count > 0) {
        const bool has_following = graph_count > 0 || meter_count > 0;
        const double xy_bottom = has_following
            ? meters_top + (visuals_bottom - meters_top) * 0.42
            : visuals_bottom;
        const double gap = theme.spacing.small;
        const double xy_width = std::max(
            1.0,
            (right - margin - gap * (xy_pad_count - 1)) / xy_pad_count
        );
        for (uint32_t index = 0; index < xy_pad_count; ++index) {
            const double left = margin + index * (xy_width + gap);
            xy_pad_controls[index]->setBounds(
                VSTGUI::CRect(left, meters_top, left + xy_width, meters_top + 18.0),
                VSTGUI::CRect(left, meters_top + 18.0, left + xy_width, xy_bottom)
            );
        }
        meters_top = xy_bottom + theme.spacing.small;
    }
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
        footer_control_top,
        right,
        footer_bottom
    ));
}

void ZigVstguiEditor::layoutParameterWorkspace(
    double margin,
    double right,
    double content_bottom,
    double footer_control_top,
    double footer_bottom
) {
    const auto& theme = theme_resolver.theme();
    const bool compact = width < 620;
    const bool expanded = width >= 840 && height >= 560;
    const bool instrument_workspace = layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE;
    title_component.setVisible(true);
    help_component.setVisible(!compact && !instrument_workspace);
    title_component.setBounds(VSTGUI::CRect(margin, 12.0, right, 46.0));
    help_component.setBounds(VSTGUI::CRect(margin, 46.0, right, 72.0));

    const double workspace_top = workspaceTop();
    const double hero_bottom = workspace_top + workspaceHeroHeight();
    const auto& hero = group_descriptions[0];
    group_components[0].setBounds(VSTGUI::CRect(margin, workspace_top, right, workspace_top + 28.0));
    const double hero_content_top = workspace_top + 28.0 + theme.spacing.small;
    const double gap = theme.spacing.small;

    const auto layout_parameter_row = [&](uint32_t parameter_index, const VSTGUI::CRect& bounds) {
        const auto kind = parameter_control_kinds[parameter_index];
        const double available = std::max(1.0, bounds.getWidth() - gap * 2.0);
        const double label_width = kind == ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM
            ? std::clamp(available * 0.26, 72.0, 80.0)
            : std::clamp(available * 0.32, 88.0, 96.0);
        const double value_width = std::clamp(available * 0.28, 60.0, 84.0);
        const ZigVstgui::GridTrack columns[] = {
            {label_width, 0.0},
            {48.0, 1.0},
            {value_width, 0.0},
        };
        const ZigVstgui::GridTrack rows[] = {{24.0, 1.0}};
        const ZigVstgui::GridItem items[] = {
            {0, 0, 1, 1},
            {1, 0, 1, 1},
            {2, 0, 1, 1},
        };
        VSTGUI::CRect cells[3];
        ZigVstgui::layoutGrid(
            bounds,
            {},
            gap,
            0.0,
            columns,
            3,
            rows,
            1,
            items,
            3,
            cells
        );
        const bool has_inline_value = kind == ZIG_VSTGUI_CONTROL_TOGGLE ||
            kind == ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN ||
            kind == ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM;
        const VSTGUI::CRect primary_bounds = has_inline_value
            ? VSTGUI::CRect(cells[1].left, cells[1].top, cells[2].right, cells[1].bottom)
            : cells[1];
        parameter_controls[parameter_index]->setBounds(cells[0], primary_bounds, cells[2]);
    };

    if (compact) {
        const double parameter_height = hero.parameter_count > 0
            ? std::min(48.0, (hero_bottom - hero_content_top) * 0.24)
            : 0.0;
        const double parameter_block_height = hero.parameter_count * parameter_height +
            (hero.parameter_count > 0 ? gap * (hero.parameter_count - 1) : 0.0);
        const double graph_bottom = hero_bottom - parameter_block_height -
            (hero.parameter_count > 0 ? gap : 0.0);
        graph_controls[hero.first_graph]->setBounds(
            VSTGUI::CRect(margin, hero_content_top, right, hero_content_top + 18.0),
            VSTGUI::CRect(margin, hero_content_top + 18.0, right, graph_bottom)
        );
        double row_top = graph_bottom + gap;
        for (uint32_t offset = 0; offset < hero.parameter_count; ++offset) {
            layout_parameter_row(
                hero.first_parameter + offset,
                VSTGUI::CRect(margin, row_top, right, row_top + parameter_height)
            );
            row_top += parameter_height + gap;
        }
    } else {
        const double parameter_width = std::clamp((right - margin) * (expanded ? 0.28 : 0.32), 220.0, 292.0);
        const double graph_right = right - parameter_width - theme.spacing.medium;
        graph_controls[hero.first_graph]->setBounds(
            VSTGUI::CRect(margin, hero_content_top, graph_right, hero_content_top + 18.0),
            VSTGUI::CRect(margin, hero_content_top + 18.0, graph_right, hero_bottom)
        );
        const double parameter_left = graph_right + theme.spacing.medium;
        const double parameter_height = hero.parameter_count > 0
            ? (hero_bottom - hero_content_top - gap * (hero.parameter_count - 1)) / hero.parameter_count
            : 0.0;
        for (uint32_t offset = 0; offset < hero.parameter_count; ++offset) {
            const double row_top = hero_content_top + offset * (parameter_height + gap);
            layout_parameter_row(
                hero.first_parameter + offset,
                VSTGUI::CRect(parameter_left, row_top, right, row_top + parameter_height)
            );
        }
    }

    const uint32_t panel_count = group_count - 1;
    const uint32_t columns = workspacePanelColumns(right - margin);
    const uint32_t rows = (panel_count + columns - 1) / columns;
    const double panel_gap = theme.spacing.medium;
    const double panel_width = (right - margin - panel_gap * (columns - 1)) / columns;
    const double panel_height = workspacePanelHeight();
    const double panels_top = hero_bottom + panel_gap;
    for (uint32_t panel = 0; panel < panel_count; ++panel) {
        const uint32_t group_index = panel + 1;
        const uint32_t column = panel % columns;
        const uint32_t row = panel / columns;
        const bool spans_row = columns > 1 && row + 1 == rows &&
            panel_count % columns == 1 && panel + 1 == panel_count;
        const double panel_left = spans_row
            ? margin
            : margin + column * (panel_width + panel_gap);
        const double panel_right = spans_row ? right : panel_left + panel_width;
        const double panel_top = panels_top + row * (panel_height + panel_gap);
        const auto& group = group_descriptions[group_index];
        group_components[group_index].setBounds(
            VSTGUI::CRect(panel_left, panel_top, panel_right, panel_top + 28.0)
        );
        const double rows_top = panel_top + 28.0 + gap;
        const double row_height = (panel_height - 28.0 - gap * group.parameter_count) /
            group.parameter_count;
        for (uint32_t offset = 0; offset < group.parameter_count; ++offset) {
            const double row_top = rows_top + offset * (row_height + gap);
            layout_parameter_row(
                group.first_parameter + offset,
                VSTGUI::CRect(panel_left, row_top, panel_right, row_top + row_height)
            );
        }
    }
    const double resize_gutter = theme.spacing.small;
    resize_control.setBounds(VSTGUI::CRect(
        right - theme.control_metrics.button_width,
        footer_control_top + resize_gutter,
        right,
        footer_bottom + resize_gutter
    ));
    (void)content_bottom;
}

uint32_t ZigVstguiEditor::workspacePanelColumns(double available) const {
    if (width < 620) return 1;
    return ZigVstgui::responsiveColumnCount(
        available,
        theme_resolver.theme().spacing.medium,
        208.0,
        group_count > 0 ? group_count - 1 : 0
    );
}

double ZigVstguiEditor::workspaceHeroHeight() const {
    if (width < 620) return 330.0;
    return width >= 840 && height >= 560 ? 280.0 : 240.0;
}

double ZigVstguiEditor::workspacePanelHeight() const {
    return 250.0;
}

double ZigVstguiEditor::workspaceTop() const {
    const double top = layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE
        ? 54.0
        : (width < 620 ? 54.0 : 82.0);
    if (layout_kind != ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) return top;
    return top + 160.0 + theme_resolver.theme().spacing.small + theme_resolver.theme().spacing.medium;
}

double ZigVstguiEditor::minimumContentHeight() const {
    const auto& spacing = theme_resolver.theme().spacing;
    double tail = spacing.large + footerHeight() + spacing.small;
    if (preset_browser_count > 0) tail += 156.0 + spacing.medium;
    if (piano_count > 0) tail += 140.0 + spacing.medium;
    if (step_sequencer_count > 0) tail += 94.0 + spacing.medium;
    if (file_drop_count > 0 && layout_kind != ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) {
        tail += 112.0 + spacing.medium;
    }
    const uint32_t utility_count = editable_label_count +
        (layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE ? 0 : progress_indicator_count);
    if (utility_count > 0) {
        tail += editable_label_count * 58.0 +
            (layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE ? 0.0 : progress_indicator_count * 48.0) +
            spacing.small * (utility_count - 1) + spacing.medium;
    }
    if ((layout_kind == ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE ||
            layout_kind == ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE) && group_count > 1) {
        const double available = std::max(1.0, static_cast<double>(width) - spacing.large * 2.0);
        const uint32_t columns = workspacePanelColumns(available);
        const uint32_t rows = (group_count - 1 + columns - 1) / columns;
        const double upper = workspaceTop() + workspaceHeroHeight() + spacing.medium +
            rows * workspacePanelHeight() + (rows - 1) * spacing.medium;
        return std::max(static_cast<double>(height), upper + tail);
    }
    double upper = 92.0 + parameter_count * 52.0;
    if (xy_pad_count > 0 || graph_count > 0 || meter_count > 0) upper += 240.0;
    if (group_count > 0) {
        const uint32_t columns = width >= 620 ? 2 : 1;
        const uint32_t rows = (group_count + columns - 1) / columns;
        upper = 82.0 + rows * 300.0 + (rows - 1) * spacing.medium;
    }
    return std::max(static_cast<double>(height), upper + tail);
}

double ZigVstguiEditor::actionButtonAreaWidth() const {
    if (action_button_count == 0) return 0.0;
    const auto& theme = theme_resolver.theme();
    const double margin = theme.spacing.large;
    const double right = std::max(margin + 1.0, static_cast<double>(width) - margin);
    const double footer_right = right - theme.control_metrics.button_width - theme.spacing.small;
    if (action_menu_count == 0) return std::max(1.0, footer_right - margin);
    const double split = margin + (footer_right - margin) * 0.68;
    return std::max(1.0, split - theme.spacing.small - margin);
}

uint32_t ZigVstguiEditor::actionButtonColumnCount(double available) const {
    return ZigVstgui::responsiveColumnCount(
        available,
        theme_resolver.theme().spacing.small,
        theme_resolver.theme().control_metrics.button_width,
        action_button_count
    );
}

double ZigVstguiEditor::footerHeight() const {
    const auto& theme = theme_resolver.theme();
    if (action_button_count == 0) return theme.control_metrics.compact_control_height;
    const uint32_t columns = actionButtonColumnCount(actionButtonAreaWidth());
    const uint32_t rows = (action_button_count + columns - 1) / columns;
    return rows * theme.control_metrics.compact_control_height +
        (rows - 1) * theme.spacing.small;
}

void ZigVstguiEditor::layoutPresetBrowsers(double left, double top, double right, double bottom) {
    if (preset_browser_count == 0) return;
    const double gap = theme_resolver.theme().spacing.small;
    const double available = std::max(1.0, right - left - gap * (preset_browser_count - 1));
    const double browser_width = available / preset_browser_count;
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        const double browser_left = left + index * (browser_width + gap);
        preset_browser_controls[index]->setBounds(
            VSTGUI::CRect(browser_left, top, browser_left + browser_width, bottom)
        );
    }
}

void ZigVstguiEditor::layoutActionMenus(double left, double top, double right, double bottom) {
    if (action_menu_count == 0) return;
    const double gap = theme_resolver.theme().spacing.small;
    const double available = std::max(1.0, right - left - gap * (action_menu_count - 1));
    const double menu_width = available / action_menu_count;
    const VSTGUI::CRect editor_bounds(0, 0, width, content_height);
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        const double menu_left = left + index * (menu_width + gap);
        action_menu_controls[index]->setBounds(
            VSTGUI::CRect(menu_left, top, menu_left + menu_width, bottom),
            editor_bounds
        );
    }
}

void ZigVstguiEditor::layoutActionButtons(double left, double top, double right, double bottom) {
    if (action_button_count == 0) return;
    const auto& spacing = theme_resolver.theme().spacing;
    const double available = std::max(1.0, right - left);
    const uint32_t columns = actionButtonColumnCount(available);
    const uint32_t rows = (action_button_count + columns - 1) / columns;
    const double row_height = std::max(
        1.0,
        (bottom - top - spacing.small * (rows - 1)) / rows
    );
    for (uint32_t row = 0; row < rows; ++row) {
        const uint32_t first = row * columns;
        const uint32_t count = std::min(columns, action_button_count - first);
        double total_gap = spacing.small * (count - 1);
        for (uint32_t column = 1; column < count; ++column) {
            if (action_button_descriptions[first + column - 1].group_id !=
                action_button_descriptions[first + column].group_id) {
                total_gap += spacing.medium - spacing.small;
            }
        }
        const double button_width = std::max(1.0, (available - total_gap) / count);
        double button_left = left;
        const double button_top = top + row * (row_height + spacing.small);
        for (uint32_t column = 0; column < count; ++column) {
            const uint32_t index = first + column;
            action_button_controls[index]->setBounds(VSTGUI::CRect(
                button_left,
                button_top,
                button_left + button_width,
                button_top + row_height
            ));
            button_left += button_width;
            if (column + 1 < count) {
                button_left += action_button_descriptions[index].group_id ==
                    action_button_descriptions[index + 1].group_id
                    ? spacing.small : spacing.medium;
            }
        }
    }
}

void ZigVstguiEditor::layoutEditableLabels(double left, double top, double right, double) {
    if (editable_label_count == 0) return;
    const double gap = theme_resolver.theme().spacing.small;
    const double label_width = std::min(120.0, (right - left) * 0.24);
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        const double row_top = top + index * (58.0 + gap);
        editable_label_controls[index]->setBounds(
            VSTGUI::CRect(left, row_top, left + label_width, row_top + 32.0),
            VSTGUI::CRect(left + label_width + gap, row_top, right, row_top + 32.0),
            VSTGUI::CRect(left + label_width + gap, row_top + 32.0, right, row_top + 56.0)
        );
    }
}

void ZigVstguiEditor::layoutProgressIndicators(double left, double top, double right, double) {
    if (progress_indicator_count == 0) return;
    const double gap = theme_resolver.theme().spacing.small;
    const double label_width = std::min(120.0, (right - left) * 0.24);
    for (uint32_t index = 0; index < progress_indicator_count; ++index) {
        const double row_top = top + index * (48.0 + gap);
        progress_controls[index]->setBounds(
            VSTGUI::CRect(left, row_top, left + label_width, row_top + 40.0),
            VSTGUI::CRect(left + label_width + gap, row_top + 4.0, right, row_top + 36.0)
        );
    }
}

void ZigVstguiEditor::layoutPianos(double left, double top, double right, double bottom) {
    if (piano_count == 0) return;
    const double gap = theme_resolver.theme().spacing.small;
    const double available = std::max(1.0, right - left - gap * (piano_count - 1));
    const double piano_width = available / piano_count;
    for (uint32_t index = 0; index < piano_count; ++index) {
        const double piano_left = left + index * (piano_width + gap);
        piano_controls[index]->setBounds(
            VSTGUI::CRect(piano_left, top, piano_left + piano_width, top + 18.0),
            VSTGUI::CRect(piano_left, top + 18.0, piano_left + piano_width, bottom)
        );
    }
}

void ZigVstguiEditor::layoutStepSequencers(double left, double top, double right, double bottom) {
    if (step_sequencer_count == 0) return;
    const double gap = theme_resolver.theme().spacing.medium;
    const double available = std::max(1.0, right - left - gap * (step_sequencer_count - 1));
    const double sequencer_width = available / step_sequencer_count;
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        const double sequencer_left = left + index * (sequencer_width + gap);
        step_sequencer_controls[index]->setBounds(
            VSTGUI::CRect(sequencer_left, top, sequencer_left + sequencer_width, top + 18.0),
            VSTGUI::CRect(sequencer_left, top + 18.0, sequencer_left + sequencer_width, bottom)
        );
    }
}

void ZigVstguiEditor::layoutFileDrops(double left, double top, double right, double bottom) {
    if (file_drop_count == 0) return;
    const double gap = theme_resolver.theme().spacing.medium;
    const double available = std::max(1.0, right - left - gap * (file_drop_count - 1));
    const double drop_width = available / file_drop_count;
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        const double drop_left = left + index * (drop_width + gap);
        file_drop_controls[index]->setBounds(VSTGUI::CRect(drop_left, top, drop_left + drop_width, bottom));
    }
}

void ZigVstguiEditor::actionMenuWillOpen(void* userdata, ZigVstgui::ActionMenuControl* opening) {
    auto* editor = static_cast<ZigVstguiEditor*>(userdata);
    if (editor) editor->closeOtherActionMenus(opening);
}

void ZigVstguiEditor::closeOtherActionMenus(ZigVstgui::ActionMenuControl* opening) {
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        auto* menu = action_menu_controls[index].get();
        if (menu != opening) menu->close(false);
    }
}

void ZigVstguiEditor::graphSelectionChanged(void* userdata, uint32_t group_index) {
    auto* editor = static_cast<ZigVstguiEditor*>(userdata);
    if (editor) editor->updateSelectedGroup(group_index);
}

void ZigVstguiEditor::updateSelectedGroup(uint32_t group_index) {
    if (group_index >= group_count || selected_group_index == group_index) return;
    selected_group_index = group_index;
    for (uint32_t index = 0; index < group_count; ++index) {
        auto* label = group_labels[index];
        if (!label) continue;
        const auto state = index == selected_group_index
            ? ZigVstgui::VisualState::focused
            : ZigVstgui::VisualState::normal;
        const auto style = group_styles[index]->resolve(ZigVstgui::ComponentKind::title, state);
        label->setFontColor(style.foreground);
        label->setBackColor(style.background);
        label->setFrameColor(style.border);
        label->setFrameWidth(index == selected_group_index ? std::max(2.0, style.frame_width) : style.frame_width);
        label->invalid();
        group_components[index].accessibility().setSelected(index == selected_group_index);
    }
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

const ZigVstgui::ThemeResolver& ZigVstguiEditor::stylesForXYPad(uint32_t index) const {
    for (uint32_t group_index = 0; group_index < group_count; ++group_index) {
        const auto& group = group_descriptions[group_index];
        if (index >= group.first_xy_pad && index < group.first_xy_pad + group.xy_pad_count) {
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
