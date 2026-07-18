#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_action_menu.h"
#include "zig_vstgui_assets.h"
#include "zig_vstgui_editor.h"
#include "zig_vstgui_fonts.h"
#include "zig_vstgui_graphs.h"
#include "zig_vstgui_layout.h"
#include "zig_vstgui_meters.h"
#include "zig_vstgui_piano.h"
#include "zig_vstgui_preset_browser.h"
#include "zig_vstgui_step_sequencer.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/events.h"
#include "vstgui/lib/vstguiinit.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace {

struct CallbackState {
    uint32_t begin_count {0};
    uint32_t perform_count {0};
    uint32_t end_count {0};
    uint32_t last_parameter_id {0};
    double last_value {0.0};
    bool reject {false};
    uint32_t context_menu_count {0};
    int32_t context_x {0};
    int32_t context_y {0};
    double meter_values[5] {0.0, 0.0, 0.0, 0.0, 0.0};
    ZigVstguiGraphPoint graph_points[4] {};
    uint32_t graph_count {0};
    uint32_t graph_load_count {0};
    char operation_kinds[32] {};
    uint32_t operation_ids[32] {};
    uint32_t operation_count {0};
    uint32_t reject_parameter_id {UINT32_MAX};
    uint32_t stored_state_field {0};
    uint32_t stored_state_index {0};
    uint32_t stored_envelope_count {0};
    std::string stored_state_text;
    uint32_t loaded_preset_id {0};
    uint32_t preset_load_count {0};
    bool reject_preset {false};
    uint32_t invoked_menu_id {0};
    uint32_t invoked_menu_item_id {0};
    uint32_t menu_action_count {0};
    uint32_t stored_bool_field {0};
    bool stored_bool_value {false};
    bool reject_menu_action {false};
    bool reject_bool_store {false};
    uint32_t note_count {0};
    int32_t last_note_pitch {-1};
    int32_t last_note_pressed {0};
};

int32_t sendNote(void* userdata, int32_t, int32_t pitch, double, int32_t pressed) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->note_count += 1;
    state->last_note_pitch = pitch;
    state->last_note_pressed = pressed;
    return 0;
}

void recordOperation(CallbackState* state, char kind, uint32_t parameter_id) {
    if (state->operation_count >= 32) return;
    state->operation_kinds[state->operation_count] = kind;
    state->operation_ids[state->operation_count] = parameter_id;
    state->operation_count += 1;
}

struct AccessibilityObserverState {
    uint32_t count {0};
    ZigVstgui::AccessibilityChange last {ZigVstgui::AccessibilityChange::role};
    uint32_t action_count {0};
    ZigVstgui::AccessibilityAction last_action {ZigVstgui::AccessibilityAction::focus};
    double last_action_value {0.0};
    std::string last_action_text;
};

void accessibilityChanged(void* userdata, ZigVstgui::AccessibilityChange change) {
    auto* state = static_cast<AccessibilityObserverState*>(userdata);
    state->count += 1;
    state->last = change;
}

bool accessibilityAction(
    void* userdata,
    const ZigVstgui::AccessibilityNode&,
    const ZigVstgui::AccessibilityActionRequest& request
) {
    auto* state = static_cast<AccessibilityObserverState*>(userdata);
    state->action_count += 1;
    state->last_action = request.action;
    state->last_action_value = request.value;
    state->last_action_text = request.text ? request.text : "";
    return true;
}

void beginEdit(void* userdata, uint32_t parameter_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->begin_count += 1;
    state->last_parameter_id = parameter_id;
    recordOperation(state, 'b', parameter_id);
}

int32_t performEdit(void* userdata, uint32_t parameter_id, double value) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->perform_count += 1;
    state->last_parameter_id = parameter_id;
    state->last_value = value;
    recordOperation(state, 'p', parameter_id);
    return state->reject || state->reject_parameter_id == parameter_id ? -1 : 0;
}

void endEdit(void* userdata, uint32_t parameter_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->end_count += 1;
    state->last_parameter_id = parameter_id;
    recordOperation(state, 'e', parameter_id);
}

int32_t showContextMenu(void* userdata, uint32_t parameter_id, int32_t x, int32_t y) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->context_menu_count += 1;
    state->last_parameter_id = parameter_id;
    state->context_x = x;
    state->context_y = y;
    return 0;
}

double loadMeter(void* userdata, uint32_t source_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    return source_id < 5 ? state->meter_values[source_id] : 0.0;
}

uint32_t loadGraph(void* userdata, uint32_t, ZigVstguiGraphPoint* output, uint32_t capacity) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->graph_load_count += 1;
    const uint32_t count = std::min(state->graph_count, capacity);
    for (uint32_t index = 0; index < count; ++index) output[index] = state->graph_points[index];
    return count;
}

int32_t storeEditorIndex(void* userdata, uint32_t field_id, uint32_t value) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->stored_state_field = field_id;
    state->stored_state_index = value;
    return 0;
}

int32_t storeEditorEnvelope(void* userdata, uint32_t field_id, const ZigVstguiEnvelopePoint*, uint32_t count) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->stored_state_field = field_id;
    state->stored_envelope_count = count;
    return 0;
}

int32_t storeEditorText(void* userdata, uint32_t field_id, const char* value) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->stored_state_field = field_id;
    state->stored_state_text = value ? value : "";
    return value ? 0 : -1;
}

int32_t loadPreset(void* userdata, uint32_t preset_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->loaded_preset_id = preset_id;
    state->preset_load_count += 1;
    return state->reject_preset ? -1 : 0;
}

int32_t storeEditorBool(void* userdata, uint32_t field_id, int32_t value) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->stored_bool_field = field_id;
    state->stored_bool_value = value != 0;
    return state->reject_bool_store ? -1 : 0;
}

int32_t invokeMenuAction(void* userdata, uint32_t menu_id, uint32_t item_id, int32_t) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->invoked_menu_id = menu_id;
    state->invoked_menu_item_id = item_id;
    state->menu_action_count += 1;
    return state->reject_menu_action ? -1 : 0;
}

bool closeEnough(double left, double right) {
    return std::abs(left - right) < 0.000001;
}

bool sameColor(const VSTGUI::CColor& left, const VSTGUI::CColor& right) {
    return left.red == right.red &&
        left.green == right.green &&
        left.blue == right.blue &&
        left.alpha == right.alpha;
}

int testComponentState() {
    ZigVstgui::ComponentState state;
    if (state.visualState() != ZigVstgui::VisualState::normal) return 1;
    state.focused = true;
    if (state.visualState() != ZigVstgui::VisualState::focused) return 2;
    state.hovered = true;
    if (state.visualState() != ZigVstgui::VisualState::hovered) return 3;
    state.pressed = true;
    if (state.visualState() != ZigVstgui::VisualState::pressed) return 4;
    state.editing = true;
    if (state.visualState() != ZigVstgui::VisualState::editing) return 5;
    state.enabled = false;
    if (state.visualState() != ZigVstgui::VisualState::disabled) return 6;
    return 0;
}

int testAccessibilityNode() {
    AccessibilityObserverState observer;
    ZigVstgui::AccessibilityNode node;
    node.setObserver(&observer, accessibilityChanged);
    node.setActionHandler(
        &observer,
        accessibilityAction,
        static_cast<uint32_t>(ZigVstgui::AccessibilityAction::press) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::set_value)
    );
    node.setRole(ZigVstgui::AccessibilityRole::meter);
    node.setName("Output level");
    node.setDescription("Stereo peak level");
    node.setValueText("-12 dB");
    node.setRange(-60.0, 6.0, -12.0);
    node.setEnabled(false);
    node.setFocused(true);
    node.setChecked(true);
    node.setSelected(true);
    node.setReadOnly(true);
    if (node.role() != ZigVstgui::AccessibilityRole::meter) return 1;
    if (node.name() != "Output level" || node.description() != "Stereo peak level") return 2;
    if (node.valueText() != "-12 dB") return 3;
    if (!node.range().present || !closeEnough(node.range().current, -12.0)) return 4;
    if (node.state().enabled || !node.state().focused || !node.state().checked ||
        !node.state().selected || !node.state().read_only) return 5;
    if (observer.count != node.generation() || observer.last != ZigVstgui::AccessibilityChange::state) return 6;
    const auto generation = node.generation();
    node.setValueText("-12 dB");
    if (node.generation() != generation) return 7;
    node.clearRange();
    if (node.range().present || observer.last != ZigVstgui::AccessibilityChange::range) return 8;
    if (node.perform(ZigVstgui::AccessibilityAction::press)) return 9;
    node.setEnabled(true);
    node.setReadOnly(false);
    if (!node.supports(ZigVstgui::AccessibilityAction::press) ||
        node.supports(ZigVstgui::AccessibilityAction::increment)) return 10;
    if (!node.perform(ZigVstgui::AccessibilityAction::set_value, 0.75, "75%")) return 11;
    if (observer.action_count != 1 || observer.last_action != ZigVstgui::AccessibilityAction::set_value ||
        !closeEnough(observer.last_action_value, 0.75) || observer.last_action_text != "75%") return 12;
    node.clearActionHandler();
    if (node.perform(ZigVstgui::AccessibilityAction::press)) return 13;
    return 0;
}

int testGestureOwnership() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;

    ZigVstgui::ParameterControlModel model(42, 0.25, callbacks);
    if (model.performEdit(0.5)) return 1;
    if (!model.beginGesture()) return 2;
    if (model.beginGesture()) return 3;
    if (state.begin_count != 1 || state.last_parameter_id != 42) return 4;
    if (!model.performEdit(1.5)) return 5;
    if (!closeEnough(model.acceptedValue(), 1.0) || !closeEnough(state.last_value, 1.0)) return 6;

    state.reject = true;
    if (model.performEdit(0.5)) return 7;
    if (!closeEnough(model.acceptedValue(), 1.0)) return 8;
    model.endGesture();
    model.endGesture();
    if (state.end_count != 1 || model.gestureActive()) return 9;

    model.hostChanged(-0.5);
    if (!closeEnough(model.acceptedValue(), 0.0)) return 10;
    return 0;
}

int testActiveGestureCleanup() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;
    {
        ZigVstgui::ParameterControlModel model(7, 0.0, callbacks);
        if (!model.beginGesture()) return 1;
    }
    return state.begin_count == 1 && state.end_count == 1 ? 0 : 2;
}

int testSteppedGestureQuantization() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;
    ZigVstgui::ParameterControlModel model(8, 0.0, callbacks);
    model.setStepCount(3);
    if (!model.beginGesture() || !model.performEdit(0.49)) return 1;
    if (!closeEnough(model.acceptedValue(), 1.0 / 3.0)) return 2;
    if (!closeEnough(state.last_value, 1.0 / 3.0)) return 3;
    model.endGesture();
    model.hostChanged(0.84);
    if (!closeEnough(model.acceptedValue(), 1.0)) return 4;
    return 0;
}

int testParameterContextMenu() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.show_context_menu = showContextMenu;
    ZigVstgui::ParameterControl control(77, 0.0, callbacks);
    if (!control.showContextMenu(12, 34)) return 1;
    if (state.context_menu_count != 1 || state.last_parameter_id != 77) return 2;
    if (state.context_x != 12 || state.context_y != 34) return 3;
    return 0;
}

int testThemeResolution() {
    const auto& default_theme = ZigVstgui::defaultTheme();
    const auto& alternate_theme = ZigVstgui::alternateTheme();
    const ZigVstgui::ColorTokens expected_default {
        VSTGUI::CColor(22, 25, 31, 255),
        VSTGUI::CColor(37, 42, 51, 255),
        VSTGUI::CColor(73, 82, 97, 255),
        VSTGUI::CColor(17, 113, 91, 255),
        VSTGUI::CColor(124, 232, 197, 255),
        VSTGUI::CColor(238, 241, 246, 255),
        VSTGUI::CColor(157, 166, 181, 255),
        VSTGUI::CColor(89, 201, 165, 255),
        VSTGUI::CColor(29, 83, 70, 255),
        VSTGUI::CColor(22, 62, 53, 255),
        VSTGUI::CColor(39, 125, 101, 255),
        VSTGUI::CColor(29, 83, 70, 255),
    };
    if (!sameColor(default_theme.colors.surface, expected_default.surface) ||
        !sameColor(default_theme.colors.surface_raised, expected_default.surface_raised) ||
        !sameColor(default_theme.colors.control_track, expected_default.control_track) ||
        !sameColor(default_theme.colors.control_fill, expected_default.control_fill) ||
        !sameColor(default_theme.colors.control_fill_highlighted, expected_default.control_fill_highlighted) ||
        !sameColor(default_theme.colors.text_primary, expected_default.text_primary) ||
        !sameColor(default_theme.colors.text_secondary, expected_default.text_secondary) ||
        !sameColor(default_theme.colors.focus_ring, expected_default.focus_ring) ||
        !sameColor(default_theme.colors.button_top, expected_default.button_top) ||
        !sameColor(default_theme.colors.button_bottom, expected_default.button_bottom) ||
        !sameColor(default_theme.colors.button_top_highlighted, expected_default.button_top_highlighted) ||
        !sameColor(default_theme.colors.button_bottom_highlighted, expected_default.button_bottom_highlighted)) return 8;
    ZigVstgui::ThemeResolver styles(default_theme);

    const auto normal = styles.resolve(ZigVstgui::ComponentKind::slider);
    if (!sameColor(normal.background, default_theme.colors.surface_raised)) return 1;
    if (!closeEnough(normal.thumb_radius, default_theme.control_metrics.thumb_radius)) return 2;

    const auto hovered = styles.resolve(
        ZigVstgui::ComponentKind::slider,
        ZigVstgui::VisualState::hovered
    );
    if (!sameColor(hovered.accent, default_theme.colors.control_fill_highlighted)) return 3;

    ZigVstgui::StyleOverride editor_override;
    editor_override.background = VSTGUI::CColor(1, 2, 3, 255);
    styles.setEditorOverride(editor_override);
    ZigVstgui::StyleOverride slider_override;
    slider_override.background = VSTGUI::CColor(4, 5, 6, 255);
    slider_override.border = VSTGUI::CColor(7, 8, 9, 255);
    styles.setComponentOverride(ZigVstgui::ComponentKind::slider, slider_override);
    const auto focused = styles.resolve(
        ZigVstgui::ComponentKind::slider,
        ZigVstgui::VisualState::focused
    );
    if (!sameColor(focused.background, *slider_override.background)) return 4;
    if (!sameColor(focused.border, default_theme.colors.focus_ring)) return 5;

    ZigVstgui::ThemeResolver alternate_styles(alternate_theme);
    const auto alternate_slider = alternate_styles.resolve(ZigVstgui::ComponentKind::slider);
    if (sameColor(alternate_slider.background, normal.background)) return 6;
    if (!closeEnough(alternate_slider.thumb_radius, normal.thumb_radius)) return 7;
    return 0;
}

int testMultiParameterAttachmentAndXYPad() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;

    ZigVstgui::MultiParameterControlModel model(10, 0.25, 0, 20, 0.75, 0, callbacks);
    if (!model.beginGesture() || !model.performEdit(0.4, 0.6)) return 1;
    model.endGesture();
    const char expected_kinds[] = {'b', 'b', 'p', 'p', 'e', 'e'};
    const uint32_t expected_ids[] = {10, 20, 10, 20, 10, 20};
    if (state.operation_count != 6) return 2;
    for (uint32_t index = 0; index < 6; ++index) {
        if (state.operation_kinds[index] != expected_kinds[index] ||
            state.operation_ids[index] != expected_ids[index]) return 3;
    }
    if (!closeEnough(model.acceptedValue(0), 0.4) || !closeEnough(model.acceptedValue(1), 0.6)) return 4;
    if (!model.hostChanged(20, 0.3) || !closeEnough(model.acceptedValue(1), 0.3) ||
        state.operation_count != 6) return 5;

    state.operation_count = 0;
    state.reject_parameter_id = 20;
    if (!model.beginGesture() || model.performEdit(0.9, 0.1)) return 6;
    model.cancelGesture();
    if (model.gestureActive() || !closeEnough(model.acceptedValue(0), 0.4) ||
        !closeEnough(model.acceptedValue(1), 0.3) || state.end_count != 4) return 7;
    state.reject_parameter_id = UINT32_MAX;

    CallbackState isolated_state;
    auto isolated_callbacks = callbacks;
    isolated_callbacks.userdata = &isolated_state;
    ZigVstgui::MultiParameterControlModel isolated(10, 0.1, 0, 20, 0.9, 0, isolated_callbacks);
    if (!isolated.hostChanged(10, 0.8) || !closeEnough(isolated.acceptedValue(0), 0.8) ||
        !closeEnough(model.acceptedValue(0), 0.4) || state.operation_count == 0 ||
        isolated_state.operation_count != 0) return 8;

    VSTGUI::init(nullptr);
    bool direct_keyboard_ok = false;
    {
        ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
        auto xy_container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 200, 160)));
        const ZigVstguiXYPadDescription direct_description {"Direct", 10, 20, "X", "Y"};
        const ZigVstguiParameterInfo x_info {"X", "", 0, 0.5};
        const ZigVstguiParameterInfo y_info {"Y", "", 0, 0.5};
        ZigVstgui::XYPadControl direct_control(direct_description, x_info, 0.25, y_info, 0.75, callbacks);
        direct_control.build(xy_container, styles);
        const uint32_t direct_begin_before = state.begin_count;
        const uint32_t direct_perform_before = state.perform_count;
        const uint32_t direct_end_before = state.end_count;
        direct_keyboard_ok = direct_control.handleKey(0, Steinberg::KEY_UP, 0) &&
            state.begin_count == direct_begin_before + 2 &&
            state.perform_count == direct_perform_before + 2 &&
            state.end_count == direct_end_before + 2 &&
            direct_control.model().acceptedValue(1) > 0.75;
        direct_control.clear();
    }
    VSTGUI::exit();
    if (!direct_keyboard_ok) return 9;

    const ZigVstguiParameterDescription parameters[] = {
        {10, 0.25, {"Horizontal", "x", 0, 0.5}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER},
        {20, 0.75, {"Vertical", "y", 0, 0.5}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER},
    };
    const ZigVstguiXYPadDescription xy_pad {"Position", 10, 20, "Pan", "Depth"};
    auto* editor = zig_vstgui_editor_create_advanced(
        parameters,
        2,
        callbacks,
        nullptr,
        0,
        {},
        nullptr,
        0,
        {},
        &xy_pad,
        1,
        nullptr,
        0,
        nullptr,
        0,
        {}
    );
    if (!editor) return 10;
    if (!editor->resize(720, 480) || !editor->setScale(2.0)) return 11;
    const auto* x_accessibility = editor->xyPadAccessibility(0, 0);
    const auto* y_accessibility = editor->xyPadAccessibility(0, 1);
    if (!x_accessibility || !y_accessibility ||
        x_accessibility->role() != ZigVstgui::AccessibilityRole::slider ||
        y_accessibility->role() != ZigVstgui::AccessibilityRole::slider ||
        x_accessibility->name() != "Position Pan" || y_accessibility->name() != "Position Depth") return 12;
    for (uint32_t index = 0; index < 5; ++index) {
        if (!editor->keyDown(0, Steinberg::KEY_TAB, 0)) return 13;
    }
    if (editor->focusPosition() != 4) return 14;
    const uint32_t begin_before = state.begin_count;
    const uint32_t perform_before = state.perform_count;
    const uint32_t end_before = state.end_count;
    if (!y_accessibility->perform(ZigVstgui::AccessibilityAction::set_value, 0.2)) return 15;
    if (state.begin_count != begin_before + 2 || state.perform_count != perform_before + 2 ||
        state.end_count != end_before + 2 || !closeEnough(y_accessibility->range().current, 0.2)) return 16;
    if (editor->xyPadAccessibility(1, 0) || editor->xyPadAccessibility(0, 2)) return 17;
    zig_vstgui_editor_destroy(editor);

    auto invalid_xy_pad = xy_pad;
    invalid_xy_pad.y_parameter_id = 10;
    if (zig_vstgui_editor_create_advanced(
            parameters, 2, callbacks, nullptr, 0, {}, nullptr, 0, {}, &invalid_xy_pad, 1,
            nullptr, 0, nullptr, 0, {}
        )) return 18;
    return 0;
}

int testMultiParameterRouting() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;
    const ZigVstguiParameterDescription descriptions[] = {
        {10, 0.25, {"Continuous", "x", 0, 0.5, "Bipolar control", 0.75, 1}, ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER},
        {20, 0.50, {"Integer", "voices", 7, 3.0 / 7.0}, ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM},
        {30, 0.00, {"Boolean", "", 1, 0.0}, ZIG_VSTGUI_CONTROL_TOGGLE},
        {40, 1.00, {"Enum", "", 2, 0.0}, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN},
    };
    const ZigVstguiMeterDescription meters[] = {
        {"Peak", ZIG_VSTGUI_METER_PEAK, 0, 0},
        {"Stereo", ZIG_VSTGUI_METER_STEREO, 1, 2},
        {"Reduction", ZIG_VSTGUI_METER_GAIN_REDUCTION, 3, 0},
    };
    const ZigVstguiGroupDescription groups[] = {
        {"Continuous", 0, 1, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x7ce8c5ff}},
        {"Discrete", 1, 3, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0xe8c77cff}},
        {"Telemetry", 4, 0, 0, 3, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x7caee8ff}},
    };
    ZigVstguiSkinDescription skin {};
    skin.editor_title = "Component Gallery";
    skin.groups = groups;
    skin.group_count = 3;
    ZigVstguiEditor first(descriptions, 4, callbacks, meters, 3, {&state, loadMeter}, skin);
    ZigVstguiEditor second(descriptions, 4, callbacks);
    if (!first.valid() || !second.valid()) return 1;
    if (first.groupCount() != 3 || second.groupCount() != 0) return 35;
    const auto* slider_accessibility = first.parameterAccessibility(10, false);
    const auto* exact_accessibility = first.parameterAccessibility(10, true);
    const auto* choice_accessibility = first.parameterAccessibility(20, false);
    const auto* toggle_accessibility = first.parameterAccessibility(30, false);
    if (!slider_accessibility || slider_accessibility->role() != ZigVstgui::AccessibilityRole::slider) return 16;
    if (slider_accessibility->name() != "Continuous (x)" ||
        slider_accessibility->description() != "Bipolar control" ||
        !slider_accessibility->range().present) return 17;
    if (!exact_accessibility || exact_accessibility->role() != ZigVstgui::AccessibilityRole::text_field) return 18;
    if (!choice_accessibility || choice_accessibility->role() != ZigVstgui::AccessibilityRole::choice) return 19;
    if (!toggle_accessibility || toggle_accessibility->role() != ZigVstgui::AccessibilityRole::toggle) return 20;
    if (first.parameterAccessibility(30, true) || first.parameterAccessibility(99, false)) return 21;
    if (first.resizeAccessibility().role() != ZigVstgui::AccessibilityRole::button) return 22;
    state.meter_values[0] = 0.8;
    state.meter_values[1] = 0.6;
    state.meter_values[2] = 0.4;
    state.meter_values[3] = 0.25;
    for (uint32_t index = 0; index < 3; ++index) {
        const auto* accessibility = first.meterAccessibility(index);
        if (!accessibility || accessibility->role() != ZigVstgui::AccessibilityRole::meter ||
            accessibility->state().read_only ||
            accessibility->description() != "Audio level. Activate to reset held peaks.") return 25;
        if (!first.tickMeter(index, 0.0)) return 26;
    }
    if (!closeEnough(first.meterLevel(0, 0), 0.8)) return 27;
    if (!closeEnough(first.meterLevel(1, 0), 0.6) || !closeEnough(first.meterLevel(1, 1), 0.4)) return 28;
    if (!closeEnough(first.meterLevel(2, 0), 0.25)) return 29;
    if (first.meterAccessibility(3) || first.tickMeter(3, 0.0)) return 30;
    state.meter_values[0] = 0.2;
    if (!first.tickMeter(0, 100.0) || !closeEnough(first.meterPeak(0, 0), 0.8)) return 40;
    if (!first.resetMeterPeaks(0) || !closeEnough(first.meterPeak(0, 0), first.meterLevel(0, 0))) return 41;
    if (first.resetMeterPeaks(3)) return 42;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 0) return 12;
    if (!slider_accessibility->state().focused) return 23;
    const auto begin_before_key = state.begin_count;
    const auto perform_before_key = state.perform_count;
    const auto end_before_key = state.end_count;
    if (!first.keyDown(0, Steinberg::KEY_RIGHT, 0)) return 31;
    if (state.begin_count != begin_before_key + 1 ||
        state.perform_count != perform_before_key + 1 ||
        state.end_count != end_before_key + 1) return 32;
    double keyboard_value = 0.0;
    if (!first.parameterValue(10, keyboard_value) || keyboard_value <= 0.25) return 33;
    if (!first.keyDown(0, Steinberg::KEY_LEFT, 0)) return 37;
    if (state.begin_count != begin_before_key + 2 ||
        state.perform_count != perform_before_key + 2 ||
        state.end_count != end_before_key + 2) return 38;
    if (!first.parameterValue(10, keyboard_value) || !closeEnough(keyboard_value, 0.25)) return 39;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 1) return 13;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 2) return 14;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 1) || first.focusPosition() != 1) return 15;
    if (!first.setParameter(30, 1.0)) return 2;
    if (!first.setModulation(10, 0.8) || first.setModulation(99, 0.5)) return 36;
    if (!toggle_accessibility->state().checked || toggle_accessibility->valueText().empty()) return 24;
    const auto begin_before_accessibility = state.begin_count;
    const auto perform_before_accessibility = state.perform_count;
    const auto end_before_accessibility = state.end_count;
    if (!slider_accessibility->perform(ZigVstgui::AccessibilityAction::increment)) return 43;
    if (!toggle_accessibility->perform(ZigVstgui::AccessibilityAction::press)) return 44;
    if (state.begin_count != begin_before_accessibility + 2 ||
        state.perform_count != perform_before_accessibility + 2 ||
        state.end_count != end_before_accessibility + 2) return 45;
    double value = 0.0;
    if (!first.parameterValue(30, value) || !closeEnough(value, 0.0)) return 3;
    if (!first.parameterValue(20, value) || !closeEnough(value, 4.0 / 7.0)) return 4;
    if (!second.parameterValue(30, value) || !closeEnough(value, 0.0)) return 5;
    if (first.setParameter(99, 0.5)) return 6;

    const ZigVstguiParameterValue restored[] = {
        {10, 0.75},
        {20, 1.00},
        {30, 0.00},
        {40, 0.50},
    };
    if (!first.refreshParameters(restored, 4)) return 7;
    for (const auto& restored_value : restored) {
        if (!first.parameterValue(restored_value.parameter_id, value) ||
            !closeEnough(value, restored_value.normalized)) return 8;
    }

    const ZigVstguiParameterValue rejected[] = {{10, 0.0}, {99, 1.0}};
    if (first.refreshParameters(rejected, 2)) return 9;
    if (!first.parameterValue(10, value) || !closeEnough(value, 0.75)) return 10;

    const ZigVstguiParameterDescription duplicates[] = {
        descriptions[0],
        descriptions[0],
    };
    ZigVstguiEditor duplicate_editor(duplicates, 2, callbacks);
    if (duplicate_editor.valid()) return 11;
    if (!first.resize(640, 360) || first.resize(319, 360) || first.resize(640, 239)) return 34;
    return 0;
}

int testLayoutSolvers() {
    const ZigVstgui::StackItem stack_items[] = {
        {50.0, 20.0, 1.0},
        {50.0, 20.0, 2.0},
        {50.0, 20.0, 0.0},
    };
    VSTGUI::CRect stack_output[3];
    if (!ZigVstgui::layoutStack(
            VSTGUI::CRect(0.0, 0.0, 300.0, 100.0),
            ZigVstgui::Axis::horizontal,
            ZigVstgui::Alignment::center,
            {},
            10.0,
            stack_items,
            3,
            stack_output
        )) return 1;
    if (!closeEnough(stack_output[0].getWidth(), 50.0 + 130.0 / 3.0)) return 2;
    if (!closeEnough(stack_output[1].getWidth(), 50.0 + 260.0 / 3.0)) return 3;
    if (!closeEnough(stack_output[2].getWidth(), 50.0)) return 4;
    if (!closeEnough(stack_output[0].top, 40.0) || !closeEnough(stack_output[0].bottom, 60.0)) return 5;

    const ZigVstgui::GridTrack columns[] = {{50.0, 1.0}, {50.0, 2.0}, {50.0, 1.0}};
    const ZigVstgui::GridTrack rows[] = {{30.0, 1.0}, {30.0, 1.0}};
    const ZigVstgui::GridItem grid_items[] = {{0, 0, 1, 2}, {1, 0, 2, 1}};
    VSTGUI::CRect grid_output[2];
    if (!ZigVstgui::layoutGrid(
            VSTGUI::CRect(0.0, 0.0, 300.0, 100.0),
            {},
            10.0,
            10.0,
            columns,
            3,
            rows,
            2,
            grid_items,
            2,
            grid_output
        )) return 6;
    if (!closeEnough(grid_output[0].getHeight(), 100.0)) return 7;
    if (!closeEnough(grid_output[1].right, 300.0)) return 8;
    const ZigVstgui::GridItem invalid_item[] = {{2, 0, 2, 1}};
    if (ZigVstgui::layoutGrid(
            VSTGUI::CRect(0.0, 0.0, 300.0, 100.0),
            {},
            10.0,
            10.0,
            columns,
            3,
            rows,
            2,
            invalid_item,
            1,
            grid_output
        )) return 9;
    if (ZigVstgui::layoutMode(519, 700) != ZigVstgui::LayoutMode::compact) return 10;
    if (ZigVstgui::layoutMode(520, 360) != ZigVstgui::LayoutMode::expanded) return 11;
    return 0;
}

int testGalleryLayoutExtents() {
    const auto& theme = ZigVstgui::defaultTheme();
    constexpr uint32_t parameter_count = 4;
    constexpr uint32_t meter_count = 3;
    const uint32_t sizes[][2] = {{320, 240}, {1000, 700}};
    for (const auto& size : sizes) {
        const double width = size[0];
        const double height = size[1];
        const auto mode = ZigVstgui::layoutMode(size[0], size[1]);
        const bool expanded = mode == ZigVstgui::LayoutMode::expanded;
        const double margin = theme.spacing.large;
        const double right = width - margin;
        const double controls_top = expanded ? 92.0 : theme.spacing.medium;
        const double controls_bottom = height - margin -
            theme.control_metrics.compact_control_height - theme.spacing.medium;
        const double row_gap = expanded ? theme.spacing.small : 0.0;
        ZigVstgui::StackItem row_items[parameter_count];
        VSTGUI::CRect row_bounds[parameter_count];
        for (auto& item : row_items) {
            item = {
                expanded ? theme.control_metrics.compact_control_height : 32.0,
                right - margin,
                0.0,
            };
        }
        if (!ZigVstgui::layoutStack(
                VSTGUI::CRect(margin, controls_top, right, controls_bottom),
                ZigVstgui::Axis::vertical,
                ZigVstgui::Alignment::stretch,
                {},
                row_gap,
                row_items,
                parameter_count,
                row_bounds
            )) return 1;

        const double label_width = expanded ? 112.0 : 88.0;
        const double value_width = expanded ? 104.0 : 80.0;
        const ZigVstgui::GridTrack columns[] = {
            {label_width, 0.0},
            {64.0, 1.0},
            {value_width, 0.0},
        };
        const ZigVstgui::GridTrack rows[] = {{24.0, 1.0}};
        const ZigVstgui::GridItem items[] = {
            {0, 0, 1, 1},
            {1, 0, 1, 1},
            {2, 0, 1, 1},
        };
        for (uint32_t index = 0; index < parameter_count; ++index) {
            const auto& row = row_bounds[index];
            if (row.left < margin || row.right > right || row.top < controls_top || row.bottom > controls_bottom) return 2;
            if (index > 0 && row.top < row_bounds[index - 1].bottom) return 3;
            VSTGUI::CRect cells[3];
            if (!ZigVstgui::layoutGrid(
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
                )) return 4;
            for (const auto& cell : cells) {
                if (cell.left < row.left || cell.right > row.right || cell.top < row.top || cell.bottom > row.bottom) return 5;
            }
            if (cells[0].right > cells[1].left || cells[1].right > cells[2].left) return 6;
        }
        const VSTGUI::CRect footer(
            right - theme.control_metrics.button_width,
            height - margin - theme.control_metrics.compact_control_height,
            right,
            height - margin
        );
        if (row_bounds[parameter_count - 1].bottom > footer.top) return 7;
        if (footer.left < margin || footer.right > right || footer.bottom > height) return 8;
        const double meter_top = row_bounds[parameter_count - 1].bottom + theme.spacing.small;
        const double meter_bottom = controls_bottom;
        const double meter_gap = theme.spacing.small;
        const double meter_width = (right - margin - meter_gap * (meter_count - 1)) / meter_count;
        if (meter_top >= meter_bottom || meter_width <= 0.0) return 9;
        double previous_right = margin;
        for (uint32_t index = 0; index < meter_count; ++index) {
            const double left = margin + index * (meter_width + meter_gap);
            const double meter_right = left + meter_width;
            if (left < margin || meter_right > right || left < previous_right) return 10;
            previous_right = meter_right;
        }
        if (meter_bottom > footer.top) return 11;
    }
    return 0;
}

int testMeterAbi() {
    if (zig_vstgui_adapter_version() != 15) return 1;
    const ZigVstguiParameterDescription parameter {
        1,
        0.5,
        {"Gain", "dB", 0, 0.5, "Equal dB steps", 0.65, 1},
        ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER,
    };
    if (zig_vstgui_editor_create_with_meters(&parameter, 1, {}, nullptr, 1, {})) return 2;
    ZigVstguiMeterDescription meters[ZIG_VSTGUI_MAX_METERS + 1] {};
    if (zig_vstgui_editor_create_with_meters(
            &parameter,
            1,
            {},
            meters,
            ZIG_VSTGUI_MAX_METERS + 1,
            {}
        )) return 3;
    if (zig_vstgui_editor_create_configured(&parameter, 1, {}, nullptr, 0, {}, nullptr, 1, {}, {})) return 4;
    const ZigVstguiGraphPoint points[] = {{-2.0, -2.0}, {0.0, 0.0}, {2.0, 2.0}};
    const ZigVstguiGraphDescription graph {
        "Transfer",
        ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION,
        ZIG_VSTGUI_GRAPH_PRIMARY,
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Input"},
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Output"},
        points,
        3,
        0,
        0,
        0,
    };
    const ZigVstguiGroupDescription group {"Graph", 0, 1, 0, 0, {}, 0, 1};
    ZigVstguiSkinDescription skin {};
    skin.groups = &group;
    skin.group_count = 1;
    auto* editor = zig_vstgui_editor_create_configured(&parameter, 1, {}, nullptr, 0, {}, &graph, 1, {}, skin);
    if (!editor || editor->graphPointCount(0) != 3) return 5;
    const auto* semantics = editor->graphAccessibility(0);
    if (!semantics || semantics->role() != ZigVstgui::AccessibilityRole::graph ||
        semantics->name() != "Transfer" || !semantics->state().read_only) return 6;
    if (!editor->resize(640, 480) || !editor->setScale(2.0)) return 7;
    zig_vstgui_editor_destroy(editor);
    auto invalid_graph = graph;
    invalid_graph.point_count = ZIG_VSTGUI_MAX_GRAPH_POINTS + 1;
    if (zig_vstgui_editor_create_configured(&parameter, 1, {}, nullptr, 0, {}, &invalid_graph, 1, {}, {})) return 8;
    const ZigVstguiEnvelopePoint envelope_points[] = {{1, 0.0, 0.0}, {2, 1.0, 1.0}};
    const ZigVstguiGraphDescription editable_graph {
        "Envelope",
        ZIG_VSTGUI_GRAPH_ENVELOPE,
        ZIG_VSTGUI_GRAPH_PRIMARY,
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"},
        nullptr, 0, 0, 0, 0,
        envelope_points, 2, 4, 1, 0.1, 0.1,
    };
    auto* editable_editor = zig_vstgui_editor_create_configured(
        &parameter, 1, {}, nullptr, 0, {}, &editable_graph, 1, {}, {}
    );
    if (!editable_editor) return 9;
    const auto* editable_semantics = editable_editor->graphAccessibility(0);
    if (!editable_semantics || editable_semantics->state().read_only ||
        !editable_editor->resize(720, 480) || !editable_editor->setScale(2.0)) return 10;
    if (!editable_editor->keyDown(0, Steinberg::KEY_TAB, 0) ||
        !editable_editor->keyDown(0, Steinberg::KEY_TAB, 0) ||
        !editable_editor->keyDown(0, Steinberg::KEY_TAB, 0) ||
        editable_editor->focusPosition() != 2 ||
        !editable_semantics->perform(ZigVstgui::AccessibilityAction::select_next) ||
        !editable_semantics->perform(ZigVstgui::AccessibilityAction::increment)) return 11;
    if (!editable_semantics->state().selected || !editable_semantics->range().present ||
        editable_semantics->range().current <= 0.0) return 12;
    zig_vstgui_editor_destroy(editable_editor);
    CallbackState preset_state;
    ZigVstguiCallbacks preset_callbacks {};
    preset_callbacks.userdata = &preset_state;
    preset_callbacks.store_editor_index = storeEditorIndex;
    preset_callbacks.store_editor_text = storeEditorText;
    preset_callbacks.load_preset = loadPreset;
    const ZigVstguiPreset presets[] = {{1, "Clean"}, {2, "Driven"}};
    const ZigVstguiPresetBrowserDescription browser {
        "Presets", presets, 2, 6, 7, "", 1,
    };
    auto* preset_editor = zig_vstgui_editor_create_advanced(
        &parameter, 1, preset_callbacks, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
        &browser, 1, nullptr, 0, {}
    );
    if (!preset_editor || !preset_editor->resize(640, 480)) return 13;
    const auto* preset_semantics = preset_editor->presetBrowserAccessibility(0);
    if (!preset_semantics || preset_semantics->role() != ZigVstgui::AccessibilityRole::choice ||
        !preset_semantics->perform(ZigVstgui::AccessibilityAction::set_value, 0.0, "drive") ||
        !preset_semantics->perform(ZigVstgui::AccessibilityAction::press) ||
        preset_state.loaded_preset_id != 2) return 14;
    zig_vstgui_editor_destroy(preset_editor);
    auto invalid_browser = browser;
    invalid_browser.search_state_id = invalid_browser.selection_state_id;
    if (zig_vstgui_editor_create_advanced(
            &parameter, 1, preset_callbacks, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
            &invalid_browser, 1, nullptr, 0, {}
        )) return 15;
    return 0;
}

int testAssetsAndFonts() {
    const auto contain = ZigVstgui::placeAsset(
        VSTGUI::CRect(0.0, 0.0, 200.0, 100.0),
        100.0,
        100.0,
        ZIG_VSTGUI_ASSET_CONTAIN
    );
    if (!closeEnough(contain.destination.left, 50.0) ||
        !closeEnough(contain.destination.getWidth(), 100.0)) return 1;
    const auto cover = ZigVstgui::placeAsset(
        VSTGUI::CRect(0.0, 0.0, 200.0, 100.0),
        100.0,
        100.0,
        ZIG_VSTGUI_ASSET_COVER
    );
    if (!closeEnough(cover.destination.top, -50.0) ||
        !closeEnough(cover.destination.getHeight(), 200.0)) return 2;
    const auto exact = ZigVstgui::placeAsset(
        VSTGUI::CRect(0.0, 0.0, 200.0, 100.0),
        20.0,
        10.0,
        ZIG_VSTGUI_ASSET_PIXEL_EXACT
    );
    if (!closeEnough(exact.destination.left, 90.0) ||
        !closeEnough(exact.destination.top, 45.0)) return 3;
    const auto stretch = ZigVstgui::placeAsset(
        VSTGUI::CRect(0.0, 0.0, 200.0, 100.0),
        20.0,
        20.0,
        ZIG_VSTGUI_ASSET_STRETCH
    );
    if (!closeEnough(stretch.scale_x, 10.0) || !closeEnough(stretch.scale_y, 5.0)) return 4;

    constexpr char svg[] =
        "<svg viewBox=\"0 0 24 24\">"
        "<path d=\"M2 12 L9 19 L22 4 Z\" fill=\"#59c9a5\"/>"
        "<path d=\"M4 4 C8 1 16 1 20 4\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"2\"/>"
        "</svg>";
    ZigVstgui::SvgDocument document;
    if (!document.parse(reinterpret_cast<const uint8_t*>(svg), sizeof(svg) - 1)) return 5;
    if (!document.valid() || document.pathCount() != 2 ||
        !closeEnough(document.width(), 24.0) || !closeEnough(document.height(), 24.0)) return 6;
    constexpr char unsupported[] =
        "<svg viewBox=\"0 0 10 10\"><path d=\"M1 1 A2 2 0 0 0 5 5\"/></svg>";
    if (document.parse(reinterpret_cast<const uint8_t*>(unsupported), sizeof(unsupported) - 1)) return 7;
    constexpr char incomplete[] =
        "<svg viewBox=\"0 0 10 10\"><path d=\"M1 1 L5\"/></svg>";
    if (document.parse(reinterpret_cast<const uint8_t*>(incomplete), sizeof(incomplete) - 1) || document.valid()) return 8;
    constexpr char transformed[] =
        "<svg viewBox=\"0 0 10 10\"><path transform=\"scale(2)\" d=\"M1 1 L5 5\"/></svg>";
    if (document.parse(reinterpret_cast<const uint8_t*>(transformed), sizeof(transformed) - 1)) return 9;

    const ZigVstguiAssetDescription svg_asset {
        7,
        reinterpret_cast<const uint8_t*>(svg),
        sizeof(svg) - 1,
        ZIG_VSTGUI_ASSET_SVG,
        ZIG_VSTGUI_ASSET_CONTAIN,
    };
    constexpr uint8_t png[] = {
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
        0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, 0x1f,
        0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d,
        0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
        0x44, 0xae, 0x42, 0x60, 0x82,
    };
    const ZigVstguiAssetDescription png_asset {
        8,
        png,
        sizeof(png),
        ZIG_VSTGUI_ASSET_PNG,
        ZIG_VSTGUI_ASSET_PIXEL_EXACT,
    };
    ZigVstgui::AssetStore assets;
    if (!assets.load(&svg_asset, 1) || assets.count() != 1 || !assets.find(7)) return 10;
    const ZigVstguiAssetDescription duplicate_assets[] = {svg_asset, svg_asset};
    if (assets.load(duplicate_assets, 2)) return 11;

    const std::vector<std::string> families {"Fallback Sans", "Preferred Sans"};
    if (ZigVstgui::chooseFontFamily("Preferred Sans", "Fallback Sans", families) != "Preferred Sans") return 12;
    if (ZigVstgui::chooseFontFamily("Missing", "Fallback Sans", families) != "Fallback Sans") return 13;
    if (!ZigVstgui::chooseFontFamily("Missing", "Also Missing", families).empty()) return 14;

    const ZigVstguiParameterDescription parameter {
        1,
        0.5,
        {"Gain", "dB", 0, 0.5},
        ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
    };
    const ZigVstguiAssetDescription valid_assets[] = {svg_asset, png_asset};
    ZigVstguiSkinDescription valid_skin {};
    valid_skin.assets = valid_assets;
    valid_skin.asset_count = 2;
    valid_skin.theme = ZIG_VSTGUI_THEME_ALTERNATE;
    valid_skin.layout = ZIG_VSTGUI_LAYOUT_COMPACT_STRIP;
    valid_skin.editor_title = "Grouped editor";
    const ZigVstguiGroupDescription valid_group {
        "Input",
        0,
        1,
        0,
        0,
        {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x3578baff},
    };
    valid_skin.groups = &valid_group;
    valid_skin.group_count = 1;
    auto* skinned_editor = zig_vstgui_editor_create_with_skin(
        &parameter,
        1,
        {},
        nullptr,
        0,
        {},
        valid_skin
    );
    if (!skinned_editor) return 15;
    if (skinned_editor->themeKind() != ZIG_VSTGUI_THEME_ALTERNATE) return 16;
    if (skinned_editor->layoutKind() != ZIG_VSTGUI_LAYOUT_COMPACT_STRIP) return 17;
    if (skinned_editor->groupCount() != 1) return 18;
    auto* default_editor = zig_vstgui_editor_create_with_skin(
        &parameter,
        1,
        {},
        nullptr,
        0,
        {},
        {}
    );
    if (!default_editor || default_editor == skinned_editor) return 19;
    if (default_editor->themeKind() != ZIG_VSTGUI_THEME_DEFAULT) return 20;
    if (default_editor->layoutKind() != ZIG_VSTGUI_LAYOUT_ADAPTIVE) return 21;
    zig_vstgui_editor_destroy(default_editor);
    zig_vstgui_editor_destroy(skinned_editor);
    ZigVstguiSkinDescription invalid_skin {};
    invalid_skin.asset_count = 1;
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 22;
    invalid_skin.asset_count = ZIG_VSTGUI_MAX_ASSETS + 1;
    invalid_skin.assets = &svg_asset;
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 23;
    invalid_skin = {};
    invalid_skin.theme = static_cast<ZigVstguiThemeKind>(99);
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 24;
    invalid_skin = {};
    invalid_skin.layout = static_cast<ZigVstguiLayoutKind>(99);
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 25;
    invalid_skin = {};
    const ZigVstguiGroupDescription incomplete_group {"Incomplete", 0, 0, 0, 0, {}};
    invalid_skin.groups = &incomplete_group;
    invalid_skin.group_count = 1;
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 26;
    invalid_skin = {};
    const ZigVstguiGroupDescription out_of_order_group {"Gap", 1, 1, 0, 0, {}};
    invalid_skin.groups = &out_of_order_group;
    invalid_skin.group_count = 1;
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 27;
    invalid_skin = {};
    invalid_skin.editor_style.mask = 1u << 31;
    if (zig_vstgui_editor_create_with_skin(&parameter, 1, {}, nullptr, 0, {}, invalid_skin)) return 28;
    auto invalid_parameter = parameter;
    invalid_parameter.control_kind = static_cast<ZigVstguiControlKind>(99);
    if (zig_vstgui_editor_create_with_skin(&invalid_parameter, 1, {}, nullptr, 0, {}, {})) return 29;
    return 0;
}

int testMeterBallistics() {
    ZigVstgui::MeterBallistics meter(500.0, 1.5);
    if (!meter.update(0.8, 0.0)) return 1;
    if (!closeEnough(meter.level(), 0.8) || !closeEnough(meter.peak(), 0.8)) return 2;
    if (!meter.update(0.2, 100.0)) return 3;
    if (!closeEnough(meter.level(), 0.65) || !closeEnough(meter.peak(), 0.8)) return 4;
    if (!meter.update(0.2, 400.0)) return 5;
    if (!closeEnough(meter.level(), 0.2) || !closeEnough(meter.peak(), 0.8)) return 6;
    meter.resetPeak();
    if (!closeEnough(meter.level(), 0.2) || !closeEnough(meter.peak(), 0.2)) return 12;
    if (meter.update(0.2, 100.0)) return 7;
    if (!closeEnough(meter.level(), 0.2) || !closeEnough(meter.peak(), 0.2)) return 8;
    if (!meter.update(2.0, 0.0) || !closeEnough(meter.level(), 1.0)) return 9;
    if (!meter.update(std::nan(""), 1000.0) || !closeEnough(meter.level(), 0.0)) return 10;
    meter.reset();
    if (!closeEnough(meter.level(), 0.0) || !closeEnough(meter.peak(), 0.0)) return 11;
    return 0;
}

int testGraphs() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    ZigVstgui::AccessibilityNode accessibility;
    const ZigVstguiGraphPoint clipped[] = {{-2.0, 2.0}, {0.0, 0.0}, {2.0, -2.0}};
    ZigVstguiGraphDescription static_graph {
        "Transfer",
        ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION,
        ZIG_VSTGUI_GRAPH_PRIMARY,
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Input"},
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Output"},
        clipped,
        3,
        0,
        0,
        0,
    };
    ZigVstgui::GraphView graph(VSTGUI::CRect(0, 0, 200, 100), static_graph, styles, &accessibility);
    if (!graph.valid() || graph.pointCount() != 3) return 1;

    auto invalid_axis = static_graph;
    invalid_axis.x_axis.maximum = invalid_axis.x_axis.minimum;
    ZigVstgui::GraphView invalid_range(VSTGUI::CRect(), invalid_axis, styles, &accessibility);
    if (invalid_range.valid()) return 2;
    auto invalid_points = static_graph;
    const ZigVstguiGraphPoint nan_point[] = {{0.0, std::nan("")}};
    invalid_points.points = nan_point;
    invalid_points.point_count = 1;
    ZigVstgui::GraphView invalid_data(VSTGUI::CRect(), invalid_points, styles, &accessibility);
    if (invalid_data.valid()) return 3;
    auto empty_graph = static_graph;
    empty_graph.points = nullptr;
    empty_graph.point_count = 0;
    ZigVstgui::GraphView empty(VSTGUI::CRect(), empty_graph, styles, &accessibility);
    if (!empty.valid() || empty.pointCount() != 0) return 4;

    CallbackState state;
    state.graph_points[0] = {-1.0, -0.5};
    state.graph_points[1] = {1.0, 0.5};
    state.graph_count = 2;
    auto dynamic_graph = empty_graph;
    dynamic_graph.title = "Waveform";
    dynamic_graph.kind = ZIG_VSTGUI_GRAPH_WAVEFORM;
    dynamic_graph.dynamic = 1;
    dynamic_graph.maximum_refresh_hz = 30;
    ZigVstgui::GraphControl control;
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 240, 140)));
    if (!control.build(container, dynamic_graph, {&state, loadGraph}, {}, styles)) return 5;
    if (control.graphView()->pointCount() != 2 || state.graph_load_count != 1) return 6;
    if (control.running()) return 7;
    control.start();
    if (!control.running()) return 8;
    control.stop();
    if (control.running()) return 9;
    state.graph_points[1] = {1.0, 0.75};
    if (!control.refresh() || control.graphView()->pointCount() != 2) return 10;
    state.graph_points[0].y = std::nan("");
    if (control.refresh() || control.graphView()->pointCount() != 2) return 11;
    control.clear();

    ZigVstgui::GraphControl static_control;
    auto static_container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 240, 140)));
    if (!static_control.build(static_container, static_graph, {}, {}, styles)) return 12;
    static_control.start();
    if (static_control.running()) return 13;
    static_control.clear();

    dynamic_graph.maximum_refresh_hz = 61;
    ZigVstgui::GraphControl invalid_rate;
    auto invalid_container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 240, 140)));
    if (invalid_rate.build(invalid_container, dynamic_graph, {&state, loadGraph}, {}, styles)) return 14;

    const ZigVstguiEnvelopePoint envelope_points[] = {
        {10, 0.0, 0.0},
        {20, 1.0, 1.0},
    };
    ZigVstguiGraphDescription editable_graph {
        "Envelope",
        ZIG_VSTGUI_GRAPH_ENVELOPE,
        ZIG_VSTGUI_GRAPH_PRIMARY,
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"},
        nullptr,
        0,
        0,
        0,
        0,
        envelope_points,
        2,
        4,
        1,
        0.25,
        0.25,
    };
    editable_graph.selection_state_id = 41;
    editable_graph.envelope_state_id = 42;
    editable_graph.initial_selected_point_id = 20;
    ZigVstguiCallbacks editor_state_callbacks {};
    editor_state_callbacks.userdata = &state;
    editor_state_callbacks.store_editor_index = storeEditorIndex;
    editor_state_callbacks.store_editor_envelope = storeEditorEnvelope;
    ZigVstgui::AccessibilityNode envelope_accessibility;
    ZigVstgui::GraphView envelope(
        VSTGUI::CRect(0, 0, 200, 100), editable_graph, styles, &envelope_accessibility, editor_state_callbacks
    );
    if (!envelope.valid() || !envelope.editable() || envelope.pointCount() != 2) return 15;
    ZigVstguiEnvelopePoint initially_selected {};
    if (!envelope.selectedPoint(initially_selected) || initially_selected.point_id != 20) return 37;
    if (!envelope.selectAdjacent(true)) return 16;
    ZigVstguiEnvelopePoint selected {};
    if (!envelope.selectedPoint(selected) || selected.point_id != 10) return 17;
    if (!envelope.beginTransaction() || !envelope.addPoint(0.61, 0.62)) return 18;
    if (!envelope.selectedPoint(selected) || selected.point_id != 21 ||
        !closeEnough(selected.x, 0.5) || !closeEnough(selected.y, 0.5)) return 19;
    envelope.finishTransaction();
    if (state.stored_envelope_count != 3 || state.stored_state_field != 41 || state.stored_state_index != 21) return 38;
    if (!envelope.beginTransaction() || !envelope.moveSelected(2.0, -2.0)) return 20;
    envelope.cancelTransaction();
    if (!envelope.selectedPoint(selected) || !closeEnough(selected.x, 0.5) || !closeEnough(selected.y, 0.5)) return 21;
    if (!envelope.handleKey(0, Steinberg::KEY_UP, 0) || !envelope.selectedPoint(selected) ||
        !closeEnough(selected.y, 0.75)) return 22;
    if (!envelope.handleKey('[', 0, 0) || !envelope.selectedPoint(selected) || selected.point_id != 10) return 23;

    ZigVstgui::AccessibilityNode mouse_accessibility;
    ZigVstgui::GraphView mouse_envelope(
        VSTGUI::CRect(0, 0, 200, 100), editable_graph, styles, &mouse_accessibility
    );
    VSTGUI::MouseDownEvent mouse_down(
        VSTGUI::CPoint(100, 50),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Left)
    );
    mouse_envelope.onMouseDownEvent(mouse_down);
    VSTGUI::MouseMoveEvent mouse_move(
        VSTGUI::CPoint(150, 25),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Left)
    );
    mouse_envelope.onMouseMoveEvent(mouse_move);
    VSTGUI::MouseUpEvent mouse_up(
        VSTGUI::CPoint(150, 25),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Left)
    );
    mouse_envelope.onMouseUpEvent(mouse_up);
    if (!mouse_down.consumed || !mouse_move.consumed || !mouse_up.consumed ||
        mouse_envelope.pointCount() != 3 || !mouse_envelope.selectedPoint(selected) ||
        !closeEnough(selected.x, 0.75) || !closeEnough(selected.y, 0.75)) return 24;
    VSTGUI::MouseDownEvent right_click(
        VSTGUI::CPoint(150, 25),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Right)
    );
    mouse_envelope.onMouseDownEvent(right_click);
    if (!right_click.consumed || mouse_envelope.pointCount() != 2) return 25;

    ZigVstgui::GraphControl editable_control;
    auto editable_container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 240, 140)));
    if (!editable_control.build(editable_container, editable_graph, {}, {}, styles)) return 26;
    editable_control.start();
    if (editable_control.running()) return 36;
    const auto& editable_semantics = editable_control.accessibilityNode();
    if (editable_semantics.state().read_only ||
        !editable_semantics.supports(ZigVstgui::AccessibilityAction::add_point) ||
        !editable_semantics.perform(ZigVstgui::AccessibilityAction::select_next) ||
        !editable_semantics.perform(ZigVstgui::AccessibilityAction::increment) ||
        !editable_semantics.perform(ZigVstgui::AccessibilityAction::add_point, 0.5) ||
        editable_control.graphView()->pointCount() != 3 ||
        !editable_semantics.perform(ZigVstgui::AccessibilityAction::delete_selected) ||
        editable_control.graphView()->pointCount() != 2) return 27;
    editable_control.clear();

    auto invalid_editable = editable_graph;
    invalid_editable.point_capacity = 1;
    ZigVstgui::GraphView invalid_capacity(VSTGUI::CRect(), invalid_editable, styles, &envelope_accessibility);
    if (invalid_capacity.valid()) return 28;

    CallbackState parameter_state;
    ZigVstguiCallbacks parameter_callbacks {};
    parameter_callbacks.userdata = &parameter_state;
    parameter_callbacks.begin_edit = beginEdit;
    parameter_callbacks.perform_edit = performEdit;
    parameter_callbacks.end_edit = endEdit;
    const ZigVstguiEnvelopePoint bound_point {31, 0.25, 0.75, 10, 20, 3, 0, 3};
    auto bound_graph = editable_graph;
    bound_graph.editable_points = &bound_point;
    bound_graph.editable_point_count = 1;
    bound_graph.point_capacity = 1;
    bound_graph.minimum_point_count = 1;
    ZigVstgui::AccessibilityNode bound_accessibility;
    ZigVstgui::GraphView bound_envelope(
        VSTGUI::CRect(0, 0, 200, 100),
        bound_graph,
        styles,
        &bound_accessibility,
        parameter_callbacks
    );
    if (!bound_envelope.valid() || !bound_envelope.selectPoint(31) ||
        !bound_envelope.beginTransaction() || !bound_envelope.moveSelected(0.5, 0.5)) return 29;
    bound_envelope.finishTransaction();
    if (parameter_state.begin_count != 2 || parameter_state.perform_count != 2 ||
        parameter_state.end_count != 2) return 30;
    parameter_state.reject_parameter_id = 20;
    if (!bound_envelope.beginTransaction() || bound_envelope.moveSelected(0.75, 0.25) ||
        bound_envelope.transactionActive()) return 31;
    if (!bound_envelope.selectedPoint(selected) || !closeEnough(selected.x, 0.5) ||
        !closeEnough(selected.y, 2.0 / 3.0)) return 32;
    parameter_state.reject_parameter_id = UINT32_MAX;
    if (!bound_envelope.setParameter(20, 0.25) || !bound_envelope.selectedPoint(selected) ||
        !closeEnough(selected.y, 1.0 / 3.0)) return 33;
    CallbackState teardown_state;
    auto teardown_callbacks = parameter_callbacks;
    teardown_callbacks.userdata = &teardown_state;
    {
        ZigVstgui::AccessibilityNode teardown_accessibility;
        ZigVstgui::GraphView teardown_envelope(
            VSTGUI::CRect(0, 0, 200, 100),
            bound_graph,
            styles,
            &teardown_accessibility,
            teardown_callbacks
        );
        if (!teardown_envelope.selectPoint(31) || !teardown_envelope.beginTransaction() ||
            !teardown_envelope.moveSelected(0.5, 0.5)) return 34;
    }
    if (teardown_state.end_count != 2 || teardown_state.perform_count != 4) return 35;
    return 0;
}

int testPresetBrowser() {
    VSTGUI::init(nullptr);
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.store_editor_index = storeEditorIndex;
    callbacks.store_editor_text = storeEditorText;
    callbacks.load_preset = loadPreset;
    const ZigVstguiPreset presets[] = {
        {1, "Clean Start"},
        {2, "Console Push"},
        {3, "Peak Limit"},
    };
    const ZigVstguiPresetBrowserDescription description {
        "Channel Presets", presets, 3, 6, 7, "", 1,
    };
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 360, 180)));
    ZigVstgui::PresetBrowserControl browser;
    if (!browser.build(container, description, callbacks, styles)) {
        VSTGUI::exit();
        return 1;
    }
    browser.setBounds(VSTGUI::CRect(0, 0, 360, 180));
    const auto& accessibility = browser.accessibilityNode();
    if (accessibility.role() != ZigVstgui::AccessibilityRole::choice ||
        accessibility.name() != "Channel Presets" || browser.browserView()->selectedPreset() != 1) {
        browser.clear();
        VSTGUI::exit();
        return 2;
    }
    VSTGUI::MouseDownEvent double_click(
        VSTGUI::CPoint(40, 66),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Left)
    );
    double_click.clickCount = 2;
    browser.browserView()->onMouseDownEvent(double_click);
    if (!double_click.consumed || state.loaded_preset_id != 2) {
        browser.clear();
        VSTGUI::exit();
        return 3;
    }
    if (!browser.handleKey('p', 0, 0) || state.stored_state_field != 7 ||
        state.stored_state_index != 2 || state.stored_state_text != "p") {
        browser.clear();
        VSTGUI::exit();
        return 4;
    }
    if (!browser.handleKey(0, Steinberg::KEY_DOWN, 0) || browser.browserView()->selectedPreset() != 3 ||
        !browser.handleKey(0, Steinberg::KEY_RETURN, 0) || state.loaded_preset_id != 3) {
        browser.clear();
        VSTGUI::exit();
        return 5;
    }
    if (!accessibility.perform(ZigVstgui::AccessibilityAction::set_value, 0.0, "missing") ||
        browser.browserView()->selectedPreset() != 0 ||
        browser.browserView()->statusText().find("No matches") == std::string::npos ||
        !accessibility.perform(ZigVstgui::AccessibilityAction::set_value, 0.0, "clean") ||
        !accessibility.perform(ZigVstgui::AccessibilityAction::press) || state.loaded_preset_id != 1) {
        browser.clear();
        VSTGUI::exit();
        return 6;
    }
    state.reject_preset = true;
    if (!accessibility.perform(ZigVstgui::AccessibilityAction::press) ||
        browser.browserView()->statusText().find("retry") == std::string::npos) {
        browser.clear();
        VSTGUI::exit();
        return 7;
    }
    browser.clear();
    VSTGUI::exit();
    return 0;
}

int testActionMenus() {
    VSTGUI::init(nullptr);
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.store_editor_bool = storeEditorBool;
    callbacks.invoke_menu_action = invokeMenuAction;
    char reset_label[] = "Reset";
    ZigVstguiMenuItemDescription items[] = {
        {1, reset_label, ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
        {2, "Export", ZIG_VSTGUI_MENU_ACTION, 0, 0, 0, 0},
        {0, nullptr, ZIG_VSTGUI_MENU_SEPARATOR, 0, 0, 0, 0},
        {3, "Show analyzer", ZIG_VSTGUI_MENU_TOGGLE, 1, 0, 9, 1},
        {4, "Clear envelope", ZIG_VSTGUI_MENU_ACTION, 1, 1, 0, 0},
    };
    const ZigVstguiActionMenuDescription description {11, "Options", items, 5};
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 360, 240)));
    ZigVstgui::ActionMenuControl control;
    if (!control.build(container, description, callbacks, styles)) {
        VSTGUI::exit();
        return 1;
    }
    control.setBounds(VSTGUI::CRect(20, 200, 180, 228), VSTGUI::CRect(0, 0, 360, 240));
    const auto& accessibility = control.accessibilityNode();
    reset_label[0] = 'X';
    if (accessibility.role() != ZigVstgui::AccessibilityRole::choice ||
        accessibility.name() != "Options" || !accessibility.perform(ZigVstgui::AccessibilityAction::press) ||
        accessibility.valueText().find("Reset") == std::string::npos ||
        !control.menuView()->isOpen() || control.menuView()->selectedItem() != 1) {
        control.clear();
        VSTGUI::exit();
        return 2;
    }
    reset_label[0] = 'R';
    if (!accessibility.perform(ZigVstgui::AccessibilityAction::increment) ||
        control.menuView()->selectedItem() != 3 ||
        !accessibility.perform(ZigVstgui::AccessibilityAction::press) ||
        state.invoked_menu_id != 11 || state.invoked_menu_item_id != 3 ||
        state.stored_bool_field != 9 || state.stored_bool_value || control.menuView()->itemChecked(3)) {
        control.clear();
        VSTGUI::exit();
        return 3;
    }
    accessibility.perform(ZigVstgui::AccessibilityAction::press);
    accessibility.perform(ZigVstgui::AccessibilityAction::increment);
    state.reject_menu_action = true;
    if (!accessibility.perform(ZigVstgui::AccessibilityAction::press) ||
        control.menuView()->statusText().find("retry") == std::string::npos ||
        control.menuView()->itemChecked(3)) {
        control.clear();
        VSTGUI::exit();
        return 4;
    }
    state.reject_menu_action = false;
    state.reject_bool_store = true;
    if (!accessibility.perform(ZigVstgui::AccessibilityAction::press) ||
        control.menuView()->statusText().find("save") == std::string::npos ||
        control.menuView()->itemChecked(3)) {
        control.clear();
        VSTGUI::exit();
        return 5;
    }
    state.reject_bool_store = false;
    if (!accessibility.perform(ZigVstgui::AccessibilityAction::press) ||
        !control.menuView()->itemChecked(3) || control.menuView()->isOpen()) {
        control.clear();
        VSTGUI::exit();
        return 6;
    }
    accessibility.perform(ZigVstgui::AccessibilityAction::press);
    if (!control.handleKey(0, Steinberg::KEY_END, 0) || control.menuView()->selectedItem() != 4 ||
        !control.handleKey(0, Steinberg::KEY_HOME, 0) || control.menuView()->selectedItem() != 1 ||
        !control.handleKey(0, Steinberg::KEY_TAB, 0)) {
        control.clear();
        VSTGUI::exit();
        return 7;
    }
    VSTGUI::MouseDownEvent outside(
        VSTGUI::CPoint(350, 230),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Left)
    );
    control.menuView()->onMouseDownEvent(outside);
    if (!outside.consumed || control.menuView()->isOpen()) {
        control.clear();
        VSTGUI::exit();
        return 8;
    }
    accessibility.perform(ZigVstgui::AccessibilityAction::press);
    const uint32_t actions_before_pointer = state.menu_action_count;
    VSTGUI::MouseDownEvent item_click(
        VSTGUI::CPoint(30, 75),
        VSTGUI::MouseEventButtonState(VSTGUI::MouseButton::Left)
    );
    control.menuView()->onMouseDownEvent(item_click);
    if (!item_click.consumed || control.menuView()->isOpen() ||
        state.menu_action_count != actions_before_pointer + 1 || state.invoked_menu_item_id != 1) {
        control.clear();
        VSTGUI::exit();
        return 9;
    }
    control.clear();
    std::array<ZigVstguiMenuItemDescription, ZIG_VSTGUI_MAX_MENU_ITEMS> many_items {};
    for (std::size_t index = 0; index < many_items.size(); ++index) {
        many_items[index] = {
            static_cast<uint32_t>(index + 1), "Command", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0,
        };
    }
    const ZigVstguiActionMenuDescription many_description {
        15, "Many Actions", many_items.data(), static_cast<uint32_t>(many_items.size()),
    };
    ZigVstgui::AccessibilityNode many_accessibility;
    ZigVstgui::ActionMenuView many_menu(many_description, callbacks, styles, &many_accessibility, nullptr);
    many_menu.setLayout(VSTGUI::CRect(0, 0, 320, 240), VSTGUI::CRect(12, 200, 180, 228));
    many_menu.open();
    if (!many_menu.valid() || !many_menu.handleKey(0, Steinberg::KEY_END, 0) ||
        many_menu.selectedItem() != ZIG_VSTGUI_MAX_MENU_ITEMS ||
        !many_menu.handleKey(0, Steinberg::KEY_HOME, 0) || many_menu.selectedItem() != 1) {
        VSTGUI::exit();
        return 10;
    }
    VSTGUI::exit();

    const ZigVstguiParameterDescription parameter {
        10, 0.5, {"Gain", "dB", 0, 0.5}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
    };
    const ZigVstguiActionMenuDescription menus[] = {
        description,
        {12, "More", items, 5},
    };
    auto* editor = zig_vstgui_editor_create_advanced(
        &parameter, 1, callbacks, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
        nullptr, 0, menus, 2, {}
    );
    if (!editor) return 11;
    const auto* first = editor->actionMenuAccessibility(0);
    const auto* second = editor->actionMenuAccessibility(1);
    if (!first || !second || !first->perform(ZigVstgui::AccessibilityAction::press) ||
        !first->state().selected || !first->state().focused ||
        !second->perform(ZigVstgui::AccessibilityAction::press) ||
        first->state().selected || first->state().focused ||
        !second->state().selected || !second->state().focused ||
        !editor->keyDown(0, Steinberg::KEY_ESCAPE, 0) || second->state().selected) {
        zig_vstgui_editor_destroy(editor);
        return 12;
    }
    zig_vstgui_editor_destroy(editor);

    auto invalid_item = items[0];
    invalid_item.item_id = 0;
    const ZigVstguiActionMenuDescription invalid_menu {13, "Invalid", &invalid_item, 1};
    if (zig_vstgui_editor_create_advanced(
            &parameter, 1, callbacks, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
            nullptr, 0, &invalid_menu, 1, {}
        )) return 13;
    const ZigVstguiActionMenuDescription action_only {14, "Action", items, 1};
    if (zig_vstgui_editor_create_advanced(
            &parameter, 1, {}, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
            nullptr, 0, &action_only, 1, {}
        )) return 14;
    ZigVstguiCallbacks missing_store = callbacks;
    missing_store.store_editor_bool = nullptr;
    if (zig_vstgui_editor_create_advanced(
            &parameter, 1, missing_store, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
            nullptr, 0, &description, 1, {}
        )) return 15;
    return 0;
}

int testPianoKeyboard() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.send_note = sendNote;
    const ZigVstguiPianoDescription description {"Keyboard", 48, 24, 0, 0.8, 60};
    VSTGUI::init(nullptr);
    {
        ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
        auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 160)));
        ZigVstgui::PianoControl piano(description, callbacks);
        piano.build(container, styles);
        piano.setBounds(VSTGUI::CRect(8, 8, 472, 28), VSTGUI::CRect(8, 28, 472, 152));
        if (!piano.handleKey('a', 0, 0, true) || state.last_note_pitch != 60 ||
            state.last_note_pressed != 1 || !piano.notePressed(60)) {
            VSTGUI::exit();
            return 1;
        }
        if (!piano.handleKey('a', 0, 0, false) || state.last_note_pressed != 0 || piano.notePressed(60)) {
            VSTGUI::exit();
            return 2;
        }
        if (!piano.handleKey(0, Steinberg::KEY_RIGHT, 0, true) || piano.selectedNote() != 61 ||
            !piano.accessibilityNode().perform(ZigVstgui::AccessibilityAction::press) ||
            !piano.notePressed(61)) {
            VSTGUI::exit();
            return 3;
        }
        piano.releaseAll();
        if (piano.notePressed(61) || state.last_note_pressed != 0) {
            VSTGUI::exit();
            return 4;
        }
        if (!piano.handleKey(' ', 0, 0, true) || !piano.handleKey(0, Steinberg::KEY_RIGHT, 0, true) ||
            !piano.handleKey(' ', 0, 0, false) || state.last_note_pitch != 61 ||
            piano.notePressed(61)) {
            VSTGUI::exit();
            return 5;
        }
        const int black = piano.hitTest(VSTGUI::CPoint(39.0, 40.0));
        if (black < 48 || black >= 72) {
            VSTGUI::exit();
            return 6;
        }
        piano.clear();
    }
    VSTGUI::exit();

    const ZigVstguiParameterDescription parameter {
        10, 0.5, {"Level", "", 0, 0.5}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
    };
    auto* editor = zig_vstgui_editor_create_full(
        &parameter, 1, callbacks, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
        nullptr, 0, nullptr, 0, &description, 1, {}
    );
    if (!editor) return 7;
    const auto* semantics = editor->pianoAccessibility(0);
    if (!semantics || semantics->role() != ZigVstgui::AccessibilityRole::choice) {
        zig_vstgui_editor_destroy(editor);
        return 8;
    }
    zig_vstgui_editor_destroy(editor);
    auto invalid = description;
    invalid.note_count = 49;
    if (zig_vstgui_editor_create_full(
            &parameter, 1, callbacks, nullptr, 0, {}, nullptr, 0, {}, nullptr, 0,
            nullptr, 0, nullptr, 0, &invalid, 1, {}
        )) return 9;
    return 0;
}

int testStepSequencer() {
    CallbackState state;
    state.meter_values[4] = 3.0;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;
    callbacks.store_editor_index = storeEditorIndex;
    const uint32_t ids[] = {100, 101, 102, 103, 104, 105, 106, 107};
    const ZigVstguiStepSequencerDescription description {
        "Pattern", ids, 8, 9, 1, 0x55, 1, 4, 30,
    };
    VSTGUI::init(nullptr);
    {
        ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
        auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 100)));
        ZigVstgui::StepSequencerControl control(description, callbacks, {&state, loadMeter});
        auto second_description = description;
        second_description.initial_active_mask = 0;
        ZigVstgui::StepSequencerControl second(second_description, callbacks, {&state, loadMeter});
        control.build(container, styles);
        second.build(container, styles);
        control.setBounds(VSTGUI::CRect(8, 8, 472, 28), VSTGUI::CRect(8, 28, 472, 92));
        if (!control.stepActive(0) || !control.stepActive(2) || control.stepActive(1) ||
            control.playhead() != 3) {
            VSTGUI::exit();
            return 1;
        }
        control.pointerBegin(2, true, false);
        control.pointerEnd();
        if (state.perform_count != 0 || state.stored_state_index != 5) {
            VSTGUI::exit();
            return 2;
        }
        control.pointerBegin(1, false, false);
        control.pointerEnd();
        if (!control.stepActive(1) || state.last_parameter_id != 101 || state.last_value != 1.0 ||
            state.stored_state_field != 9 || state.stored_state_index != 2) {
            VSTGUI::exit();
            return 3;
        }
        if (!control.handleKey(0, Steinberg::KEY_RIGHT, 1) ||
            !control.handleKey(' ', Steinberg::KEY_SPACE, 0) ||
            control.stepActive(1) || control.stepActive(2) || state.perform_count != 3) {
            VSTGUI::exit();
            return 4;
        }
        if (!control.accessibilityNode().perform(ZigVstgui::AccessibilityAction::increment) ||
            control.cursor() != 3 || control.accessibilityNode().valueText().empty()) {
            VSTGUI::exit();
            return 5;
        }
        if (!control.setParameter(107, 1.0) || !control.stepActive(7) || second.stepActive(7) ||
            control.setParameter(999, 1.0)) {
            VSTGUI::exit();
            return 6;
        }
        state.reject_parameter_id = 104;
        control.pointerBegin(4, false, false);
        control.pointerEnd();
        if (!control.stepActive(4) || !control.editFailed() ||
            control.accessibilityNode().valueText().find("rejected") == std::string::npos) {
            VSTGUI::exit();
            return 7;
        }
        second.clear();
        control.clear();
    }
    VSTGUI::exit();

    const ZigVstguiParameterDescription parameter {
        10, 0.5, {"Level", "", 0, 0.5}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
    };
    auto* editor = zig_vstgui_editor_create_complete(
        &parameter, 1, callbacks, nullptr, 0, {&state, loadMeter}, nullptr, 0, {}, nullptr, 0,
        nullptr, 0, nullptr, 0, nullptr, 0, &description, 1, {}
    );
    if (!editor || !editor->stepSequencerAccessibility(0)) {
        zig_vstgui_editor_destroy(editor);
        return 8;
    }
    zig_vstgui_editor_destroy(editor);
    auto invalid = description;
    invalid.step_count = 33;
    if (zig_vstgui_editor_create_complete(
        &parameter, 1, callbacks, nullptr, 0, {&state, loadMeter}, nullptr, 0, {}, nullptr, 0,
        nullptr, 0, nullptr, 0, nullptr, 0, &invalid, 1, {}
    )) return 9;
    auto disabled = description;
    disabled.enabled = 0;
    VSTGUI::init(nullptr);
    {
        ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
        auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 320, 80)));
        ZigVstgui::StepSequencerControl control(disabled, callbacks, {});
        control.build(container, styles);
        if (control.handleKey(' ', Steinberg::KEY_SPACE, 0) ||
            control.accessibilityNode().perform(ZigVstgui::AccessibilityAction::press)) {
            VSTGUI::exit();
            return 10;
        }
        control.clear();
    }
    VSTGUI::exit();
    return 0;
}

}

int main() {
    if (const int result = testComponentState(); result != 0) return 10 + result;
    if (const int result = testAccessibilityNode(); result != 0) return 20 + result;
    if (const int result = testGestureOwnership(); result != 0) return 30 + result;
    if (const int result = testActiveGestureCleanup(); result != 0) return 50 + result;
    if (const int result = testSteppedGestureQuantization(); result != 0) return 55 + result;
    if (const int result = testParameterContextMenu(); result != 0) return 60 + result;
    if (const int result = testThemeResolution(); result != 0) return 70 + result;
    if (const int result = testMultiParameterAttachmentAndXYPad(); result != 0) return 80 + result;
    if (const int result = testMultiParameterRouting(); result != 0) return 90 + result;
    if (const int result = testLayoutSolvers(); result != 0) return 110 + result;
    if (const int result = testGalleryLayoutExtents(); result != 0) return 130 + result;
    if (const int result = testMeterBallistics(); result != 0) return 150 + result;
    VSTGUI::init(nullptr);
    const int graph_result = testGraphs();
    VSTGUI::exit();
    if (graph_result != 0) return 160 + graph_result;
    if (const int result = testMeterAbi(); result != 0) return 170 + result;
    if (const int result = testAssetsAndFonts(); result != 0) return 190 + result;
    if (const int result = testPresetBrowser(); result != 0) return 210 + result;
    if (const int result = testActionMenus(); result != 0) return 220 + result;
    if (const int result = testPianoKeyboard(); result != 0) return 240 + result;
    if (const int result = testStepSequencer(); result != 0) return 250 + result;
    return 0;
}
