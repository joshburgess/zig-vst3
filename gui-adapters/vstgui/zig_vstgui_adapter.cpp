#include "zig_vstgui_adapter.h"
#include "zig_vstgui_editor.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <new>
#include <string>

namespace {

std::string normalizedExtension(const char* value) {
    std::string result(value);
    std::transform(result.begin(), result.end(), result.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return result;
}

}

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
    return zig_vstgui_editor_create_advanced(
        parameters,
        parameter_count,
        callbacks,
        meters,
        meter_count,
        meter_callbacks,
        graphs,
        graph_count,
        graph_callbacks,
        nullptr,
        0,
        nullptr,
        0,
        nullptr,
        0,
        skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_advanced(
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
) {
    return zig_vstgui_editor_create_full(
        parameters, parameter_count, callbacks, meters, meter_count, meter_callbacks,
        graphs, graph_count, graph_callbacks, xy_pads, xy_pad_count,
        preset_browsers, preset_browser_count, action_menus, action_menu_count,
        nullptr, 0, skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_full(
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
) {
    return zig_vstgui_editor_create_complete(
        parameters, parameter_count, callbacks, meters, meter_count, meter_callbacks,
        graphs, graph_count, graph_callbacks, xy_pads, xy_pad_count,
        preset_browsers, preset_browser_count, action_menus, action_menu_count,
        pianos, piano_count, nullptr, 0, skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_complete(
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
) {
    return zig_vstgui_editor_create_latest(
        parameters, parameter_count, callbacks, meters, meter_count, meter_callbacks,
        graphs, graph_count, graph_callbacks, xy_pads, xy_pad_count,
        preset_browsers, preset_browser_count, action_menus, action_menu_count,
        pianos, piano_count, step_sequencers, step_sequencer_count, nullptr, 0, skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_latest(
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
) {
    return zig_vstgui_editor_create_widgets(
        parameters, parameter_count, callbacks, meters, meter_count, meter_callbacks,
        graphs, graph_count, graph_callbacks, xy_pads, xy_pad_count,
        preset_browsers, preset_browser_count, action_menus, action_menu_count,
        pianos, piano_count, step_sequencers, step_sequencer_count,
        file_drops, file_drop_count, nullptr, 0, skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_widgets(
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
    const ZigVstguiActionButtonDescription* action_buttons,
    uint32_t action_button_count,
    ZigVstguiSkinDescription skin
) {
    return zig_vstgui_editor_create_components(
        parameters, parameter_count, callbacks, meters, meter_count, meter_callbacks,
        graphs, graph_count, graph_callbacks, xy_pads, xy_pad_count,
        preset_browsers, preset_browser_count, action_menus, action_menu_count,
        pianos, piano_count, step_sequencers, step_sequencer_count,
        file_drops, file_drop_count, action_buttons, action_button_count,
        nullptr, 0, nullptr, 0, skin
    );
}

extern "C" ZigVstguiEditor* zig_vstgui_editor_create_components(
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
    const ZigVstguiActionButtonDescription* action_buttons,
    uint32_t action_button_count,
    const ZigVstguiEditableLabelDescription* editable_labels,
    uint32_t editable_label_count,
    const ZigVstguiProgressIndicatorDescription* progress_indicators,
    uint32_t progress_indicator_count,
    ZigVstguiSkinDescription skin
) {
    constexpr uint32_t style_mask = ZIG_VSTGUI_STYLE_BACKGROUND |
        ZIG_VSTGUI_STYLE_FOREGROUND |
        ZIG_VSTGUI_STYLE_BORDER |
        ZIG_VSTGUI_STYLE_ACCENT;
    if (!parameters || parameter_count == 0 || parameter_count > ZIG_VSTGUI_MAX_PARAMETERS) return nullptr;
    if ((!meters && meter_count > 0) || meter_count > ZIG_VSTGUI_MAX_METERS) return nullptr;
    if ((!graphs && graph_count > 0) || graph_count > ZIG_VSTGUI_MAX_GRAPHS) return nullptr;
    if ((!xy_pads && xy_pad_count > 0) || xy_pad_count > ZIG_VSTGUI_MAX_XY_PADS) return nullptr;
    if ((!preset_browsers && preset_browser_count > 0) ||
        preset_browser_count > ZIG_VSTGUI_MAX_PRESET_BROWSERS) return nullptr;
    for (uint32_t index = 0; index < preset_browser_count; ++index) {
        const auto& browser = preset_browsers[index];
        if (!browser.title || !browser.presets || browser.preset_count == 0 ||
            browser.preset_count > ZIG_VSTGUI_MAX_PRESETS || !browser.initial_search ||
            browser.search_state_id == 0 || browser.selection_state_id == 0 ||
            browser.search_state_id == browser.selection_state_id) return nullptr;
        for (uint32_t preset = 0; preset < browser.preset_count; ++preset) {
            if (browser.presets[preset].preset_id == 0 || !browser.presets[preset].name ||
                browser.presets[preset].name[0] == 0) return nullptr;
            for (uint32_t previous = 0; previous < preset; ++previous) {
                if (browser.presets[previous].preset_id == browser.presets[preset].preset_id) return nullptr;
            }
        }
    }
    if ((!action_menus && action_menu_count > 0) || action_menu_count > ZIG_VSTGUI_MAX_ACTION_MENUS ||
        (action_menu_count > 0 && !callbacks.invoke_menu_action)) return nullptr;
    for (uint32_t index = 0; index < action_menu_count; ++index) {
        const auto& menu = action_menus[index];
        if (menu.menu_id == 0 || !menu.title || menu.title[0] == 0 || !menu.items || menu.item_count == 0 ||
            menu.item_count > ZIG_VSTGUI_MAX_MENU_ITEMS) return nullptr;
        for (uint32_t previous_menu = 0; previous_menu < index; ++previous_menu) {
            if (action_menus[previous_menu].menu_id == menu.menu_id) return nullptr;
        }
        for (uint32_t item_index = 0; item_index < menu.item_count; ++item_index) {
            const auto& item = menu.items[item_index];
            if (item.kind == ZIG_VSTGUI_MENU_SEPARATOR) {
                if (item.item_id != 0 || item.label || item.enabled || item.destructive ||
                    item.checked_state_id != 0 || item.initial_checked) return nullptr;
                continue;
            }
            if (item.kind < ZIG_VSTGUI_MENU_ACTION || item.kind > ZIG_VSTGUI_MENU_TOGGLE ||
                item.item_id == 0 || !item.label || item.label[0] == 0 ||
                (item.kind == ZIG_VSTGUI_MENU_ACTION && item.checked_state_id != 0) ||
                (item.kind == ZIG_VSTGUI_MENU_TOGGLE &&
                    (item.checked_state_id == 0 || item.destructive || !callbacks.store_editor_bool))) return nullptr;
            for (uint32_t previous = 0; previous < item_index; ++previous) {
                if (menu.items[previous].kind != ZIG_VSTGUI_MENU_SEPARATOR &&
                    menu.items[previous].item_id == item.item_id) return nullptr;
            }
        }
    }
    if ((!pianos && piano_count > 0) || piano_count > ZIG_VSTGUI_MAX_PIANOS ||
        (piano_count > 0 && !callbacks.send_note)) return nullptr;
    for (uint32_t index = 0; index < piano_count; ++index) {
        const auto& piano = pianos[index];
        if (!piano.title || piano.title[0] == 0 || piano.note_count == 0 || piano.note_count > 48 ||
            piano.first_note >= 128 || piano.first_note + piano.note_count > 128 ||
            piano.channel < 0 || piano.channel > 15 || !std::isfinite(piano.velocity) ||
            piano.velocity <= 0.0 || piano.velocity > 1.0 || piano.computer_base_pitch >= 128) return nullptr;
    }
    if ((!step_sequencers && step_sequencer_count > 0) ||
        step_sequencer_count > ZIG_VSTGUI_MAX_STEP_SEQUENCERS) return nullptr;
    for (uint32_t index = 0; index < step_sequencer_count; ++index) {
        const auto& sequencer = step_sequencers[index];
        if (!sequencer.title || sequencer.title[0] == 0 || !sequencer.parameter_ids ||
            sequencer.step_count == 0 || sequencer.step_count > ZIG_VSTGUI_MAX_STEPS ||
            sequencer.selection_state_id == 0 ||
            (sequencer.enabled != 0 && sequencer.enabled != 1) ||
            (sequencer.initial_selection_mask & ~(sequencer.step_count == 32
                ? 0xffffffffu : (1u << sequencer.step_count) - 1u)) != 0 ||
            (sequencer.initial_active_mask & ~(sequencer.step_count == 32
                ? 0xffffffffu : (1u << sequencer.step_count) - 1u)) != 0 ||
            (sequencer.playhead_source_id != 0 &&
                (!meter_callbacks.load || sequencer.maximum_refresh_hz == 0 ||
                    sequencer.maximum_refresh_hz > 60))) return nullptr;
        for (uint32_t step = 0; step < sequencer.step_count; ++step) {
            for (uint32_t previous = 0; previous < step; ++previous) {
                if (sequencer.parameter_ids[previous] == sequencer.parameter_ids[step]) return nullptr;
            }
        }
    }
    if ((!file_drops && file_drop_count > 0) || file_drop_count > ZIG_VSTGUI_MAX_FILE_DROPS ||
        (file_drop_count > 0 && !callbacks.import_files && !callbacks.drop_files)) return nullptr;
    for (uint32_t index = 0; index < file_drop_count; ++index) {
        const auto& drop = file_drops[index];
        if (drop.drop_id == 0 || !drop.title || drop.title[0] == 0 || !drop.prompt || drop.prompt[0] == 0 ||
            (drop.picker_label && drop.picker_label[0] == 0) || (drop.picker_title && drop.picker_title[0] == 0) ||
            !drop.extensions || drop.extension_count == 0 || drop.extension_count > ZIG_VSTGUI_MAX_DROP_EXTENSIONS ||
            drop.maximum_files == 0 || drop.maximum_files > ZIG_VSTGUI_MAX_DROP_FILES ||
            (drop.enabled != 0 && drop.enabled != 1)) return nullptr;
        for (uint32_t previous_drop = 0; previous_drop < index; ++previous_drop) {
            if (file_drops[previous_drop].drop_id == drop.drop_id) return nullptr;
        }
        for (uint32_t extension = 0; extension < drop.extension_count; ++extension) {
            const char* value = drop.extensions[extension];
            if (!value || value[0] != '.' || value[1] == 0 ||
                std::char_traits<char>::length(value) > ZIG_VSTGUI_MAX_DROP_EXTENSION_BYTES) return nullptr;
            const auto normalized = normalizedExtension(value);
            for (uint32_t previous = 0; previous < extension; ++previous) {
                if (normalizedExtension(drop.extensions[previous]) == normalized) return nullptr;
            }
        }
    }
    if ((!action_buttons && action_button_count > 0) || action_button_count > ZIG_VSTGUI_MAX_ACTION_BUTTONS ||
        (action_button_count > 0 && !callbacks.invoke_action)) return nullptr;
    uint32_t primary_count = 0;
    for (uint32_t index = 0; index < action_button_count; ++index) {
        const auto& action = action_buttons[index];
        if (action.group_id == 0 || action.action_id == 0 || !action.accessible_label ||
            action.accessible_label[0] == 0 || (action.enabled != 0 && action.enabled != 1) ||
            action.role < ZIG_VSTGUI_ACTION_PRIMARY || action.role > ZIG_VSTGUI_ACTION_DESTRUCTIVE ||
            action.icon < ZIG_VSTGUI_ACTION_ICON_NONE || action.icon > ZIG_VSTGUI_ACTION_ICON_ZOOM_OUT ||
            ((!action.label || action.label[0] == 0) && action.icon == ZIG_VSTGUI_ACTION_ICON_NONE) ||
            (action.label && action.label[0] == 0) || (action.tooltip && action.tooltip[0] == 0) ||
            (action.confirmation_label && action.confirmation_label[0] == 0) ||
            (action.failure_label && action.failure_label[0] == 0) ||
            (action.role == ZIG_VSTGUI_ACTION_DESTRUCTIVE && !action.confirmation_label)) return nullptr;
        if (action.role == ZIG_VSTGUI_ACTION_PRIMARY && ++primary_count > 1) return nullptr;
        for (uint32_t previous = 0; previous < index; ++previous) {
            if (action_buttons[previous].group_id == action.group_id &&
                action_buttons[previous].action_id == action.action_id) return nullptr;
            if ((action.role == ZIG_VSTGUI_ACTION_DESTRUCTIVE &&
                    action_buttons[previous].role == ZIG_VSTGUI_ACTION_PRIMARY) ||
                (action.role == ZIG_VSTGUI_ACTION_PRIMARY &&
                    action_buttons[previous].role == ZIG_VSTGUI_ACTION_DESTRUCTIVE)) {
                if (action_buttons[previous].group_id == action.group_id) return nullptr;
            }
        }
    }
    if ((!editable_labels && editable_label_count > 0) ||
        editable_label_count > ZIG_VSTGUI_MAX_EDITABLE_LABELS ||
        (editable_label_count > 0 && (!callbacks.store_editor_text || !callbacks.load_editor_text))) return nullptr;
    for (uint32_t index = 0; index < editable_label_count; ++index) {
        const auto& label = editable_labels[index];
        if (label.field_id == 0 || !label.label || label.label[0] == 0 ||
            !label.accessible_label || label.accessible_label[0] == 0 || !label.placeholder ||
            !label.error_text || label.error_text[0] == 0 || !label.initial_text ||
            label.maximum_bytes == 0 || label.maximum_bytes > 96 ||
            std::char_traits<char>::length(label.initial_text) > label.maximum_bytes ||
            (label.enabled != 0 && label.enabled != 1)) return nullptr;
        for (uint32_t previous = 0; previous < index; ++previous) {
            if (editable_labels[previous].field_id == label.field_id) return nullptr;
        }
    }
    if ((!progress_indicators && progress_indicator_count > 0) ||
        progress_indicator_count > ZIG_VSTGUI_MAX_PROGRESS_INDICATORS ||
        (progress_indicator_count > 0 && !callbacks.load_progress)) return nullptr;
    for (uint32_t index = 0; index < progress_indicator_count; ++index) {
        const auto& progress = progress_indicators[index];
        if (progress.source_id == 0 || !progress.label || progress.label[0] == 0 ||
            !progress.accessible_label || progress.accessible_label[0] == 0 ||
            !progress.idle_text || progress.idle_text[0] == 0 ||
            !progress.running_text || progress.running_text[0] == 0 ||
            !progress.complete_text || progress.complete_text[0] == 0 ||
            !progress.failure_text || progress.failure_text[0] == 0 ||
            progress.maximum_refresh_hz == 0 || progress.maximum_refresh_hz > 60) return nullptr;
        for (uint32_t previous = 0; previous < index; ++previous) {
            if (progress_indicators[previous].source_id == progress.source_id) return nullptr;
        }
    }
    for (uint32_t index = 0; index < graph_count; ++index) {
        const auto& graph = graphs[index];
        const bool editable = graph.point_capacity > 0;
        const auto& viewport = graph.viewport;
        const auto& range_selection = graph.range_selection;
        if (viewport.enabled != 0 && viewport.enabled != 1) return nullptr;
        if (viewport.enabled != 0) {
            if (viewport.axes < ZIG_VSTGUI_VIEWPORT_HORIZONTAL || viewport.axes > ZIG_VSTGUI_VIEWPORT_BOTH ||
                !std::isfinite(viewport.minimum_zoom) || !std::isfinite(viewport.maximum_zoom) ||
                viewport.minimum_zoom < 1.0 || viewport.maximum_zoom < viewport.minimum_zoom ||
                viewport.maximum_zoom > 128.0 || !std::isfinite(viewport.initial_zoom) ||
                viewport.initial_zoom < viewport.minimum_zoom || viewport.initial_zoom > viewport.maximum_zoom ||
                !std::isfinite(viewport.initial_x_offset) || !std::isfinite(viewport.initial_y_offset) ||
                !std::isfinite(viewport.zoom_step) || viewport.zoom_step <= 1.0 || viewport.zoom_step > 4.0 ||
                !std::isfinite(viewport.scroll_step) || viewport.scroll_step <= 0.0 || viewport.scroll_step > 1.0 ||
                viewport.initial_x_offset < 0.0 || viewport.initial_y_offset < 0.0 ||
                viewport.initial_x_offset > 1.0 - 1.0 / viewport.initial_zoom ||
                viewport.initial_y_offset > 1.0 - 1.0 / viewport.initial_zoom ||
                (viewport.axes == ZIG_VSTGUI_VIEWPORT_HORIZONTAL &&
                    (viewport.initial_y_offset != 0.0 || viewport.y_offset_state_id != 0)) ||
                (viewport.axes == ZIG_VSTGUI_VIEWPORT_VERTICAL &&
                    (viewport.initial_x_offset != 0.0 || viewport.x_offset_state_id != 0))) return nullptr;
            const uint32_t state_ids[] = {
                viewport.zoom_state_id,
                viewport.x_offset_state_id,
                viewport.y_offset_state_id,
            };
            bool has_state = false;
            for (uint32_t field = 0; field < 3; ++field) {
                if (state_ids[field] == 0) continue;
                has_state = true;
                for (uint32_t previous = 0; previous < field; ++previous) {
                    if (state_ids[previous] == state_ids[field]) return nullptr;
                }
            }
            if (has_state && !callbacks.store_editor_scalars) return nullptr;
        }
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
            (graph.dynamic && (!graph_callbacks.load || graph.maximum_refresh_hz == 0 || graph.maximum_refresh_hz > 60)) ||
            (!editable && (graph.editable_points || graph.editable_point_count > 0 ||
                graph.minimum_point_count > 0 || graph.snap_x != 0.0 || graph.snap_y != 0.0)) ||
            (editable && (graph.kind != ZIG_VSTGUI_GRAPH_ENVELOPE || graph.dynamic || graph.point_count > 0 ||
                graph.point_capacity > ZIG_VSTGUI_MAX_GRAPH_POINTS ||
                graph.editable_point_count > graph.point_capacity ||
                graph.minimum_point_count > graph.editable_point_count ||
                (!graph.editable_points && graph.editable_point_count > 0) ||
                !std::isfinite(graph.snap_x) || !std::isfinite(graph.snap_y) ||
                graph.snap_x < 0.0 || graph.snap_y < 0.0))) return nullptr;
        if (range_selection.enabled != 0 && range_selection.enabled != 1) return nullptr;
        if (range_selection.enabled == 0) {
            if (range_selection.start_state_id != 0 || range_selection.end_state_id != 0) return nullptr;
        } else {
            const double axis_span = graph.x_axis.maximum - graph.x_axis.minimum;
            if (editable || !std::isfinite(range_selection.initial_start) ||
                !std::isfinite(range_selection.initial_end) ||
                !std::isfinite(range_selection.minimum_span) || !std::isfinite(range_selection.step) ||
                range_selection.initial_start < graph.x_axis.minimum ||
                range_selection.initial_end > graph.x_axis.maximum ||
                range_selection.initial_end < range_selection.initial_start ||
                range_selection.minimum_span < 0.0 || range_selection.minimum_span > axis_span ||
                range_selection.initial_end - range_selection.initial_start < range_selection.minimum_span ||
                range_selection.step <= 0.0 || range_selection.step > axis_span ||
                ((range_selection.start_state_id == 0) != (range_selection.end_state_id == 0)) ||
                (range_selection.start_state_id != 0 &&
                    range_selection.start_state_id == range_selection.end_state_id)) return nullptr;
            if (range_selection.start_state_id != 0 && !callbacks.store_editor_scalars) return nullptr;
            const uint32_t state_ids[] = {
                viewport.zoom_state_id,
                viewport.x_offset_state_id,
                viewport.y_offset_state_id,
                range_selection.start_state_id,
                range_selection.end_state_id,
            };
            for (uint32_t field = 0; field < 5; ++field) {
                if (state_ids[field] == 0) continue;
                for (uint32_t previous = 0; previous < field; ++previous) {
                    if (state_ids[previous] == state_ids[field]) return nullptr;
                }
            }
        }
        for (uint32_t point = 0; point < graph.point_count; ++point) {
            if (!std::isfinite(graph.points[point].x) || !std::isfinite(graph.points[point].y)) return nullptr;
        }
        for (uint32_t point = 0; point < graph.editable_point_count; ++point) {
            const auto& editable_point = graph.editable_points[point];
            if (editable_point.point_id == 0 || !std::isfinite(editable_point.x) ||
                !std::isfinite(editable_point.y) ||
                (editable_point.parameter_mask & ~3u) != 0 ||
                editable_point.x_step_count < 0 || editable_point.y_step_count < 0 ||
                (editable_point.parameter_mask != 0 && (editable_point.parameter_mask != 3 ||
                    editable_point.x_parameter_id == editable_point.y_parameter_id)) ||
                editable_point.x < graph.x_axis.minimum || editable_point.x > graph.x_axis.maximum ||
                editable_point.y < graph.y_axis.minimum || editable_point.y > graph.y_axis.maximum ||
                (point > 0 && graph.editable_points[point - 1].x > editable_point.x)) return nullptr;
            for (uint32_t previous = 0; previous < point; ++previous) {
                if (graph.editable_points[previous].point_id == editable_point.point_id) return nullptr;
            }
            if (editable_point.parameter_mask == 3) {
                bool found_x = false;
                bool found_y = false;
                for (uint32_t parameter = 0; parameter < parameter_count; ++parameter) {
                    found_x = found_x || parameters[parameter].parameter_id == editable_point.x_parameter_id;
                    found_y = found_y || parameters[parameter].parameter_id == editable_point.y_parameter_id;
                }
                if (!found_x || !found_y) return nullptr;
            }
        }
    }
    for (uint32_t index = 0; index < xy_pad_count; ++index) {
        const auto& xy_pad = xy_pads[index];
        if (!xy_pad.title || !xy_pad.x_label || !xy_pad.y_label ||
            xy_pad.x_parameter_id == xy_pad.y_parameter_id) return nullptr;
        bool found_x = false;
        bool found_y = false;
        for (uint32_t parameter = 0; parameter < parameter_count; ++parameter) {
            found_x = found_x || parameters[parameter].parameter_id == xy_pad.x_parameter_id;
            found_y = found_y || parameters[parameter].parameter_id == xy_pad.y_parameter_id;
        }
        if (!found_x || !found_y) return nullptr;
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
        graph_callbacks,
        xy_pads,
        xy_pad_count,
        preset_browsers,
        preset_browser_count,
        action_menus,
        action_menu_count,
        pianos,
        piano_count,
        step_sequencers,
        step_sequencer_count,
        file_drops,
        file_drop_count,
        action_buttons,
        action_button_count,
        editable_labels,
        editable_label_count,
        progress_indicators,
        progress_indicator_count
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

extern "C" int32_t zig_vstgui_editor_key_up(
    ZigVstguiEditor* editor,
    uint16_t key,
    int16_t key_code,
    int16_t modifiers
) {
    return editor && editor->keyUp(key, key_code, modifiers) ? 0 : -1;
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
    return 18;
}
