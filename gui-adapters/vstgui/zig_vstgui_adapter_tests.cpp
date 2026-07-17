#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_editor.h"

#include <cmath>
#include <cstdint>

namespace {

struct CallbackState {
    uint32_t begin_count {0};
    uint32_t perform_count {0};
    uint32_t end_count {0};
    uint32_t last_parameter_id {0};
    double last_value {0.0};
    bool reject {false};
};

void beginEdit(void* userdata, uint32_t parameter_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->begin_count += 1;
    state->last_parameter_id = parameter_id;
}

int32_t performEdit(void* userdata, uint32_t parameter_id, double value) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->perform_count += 1;
    state->last_parameter_id = parameter_id;
    state->last_value = value;
    return state->reject ? -1 : 0;
}

void endEdit(void* userdata, uint32_t parameter_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->end_count += 1;
    state->last_parameter_id = parameter_id;
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

int testThemeResolution() {
    const auto& default_theme = ZigVstgui::defaultTheme();
    const auto& alternate_theme = ZigVstgui::alternateTheme();
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

int testMultiParameterRouting() {
    CallbackState state;
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.begin_edit = beginEdit;
    callbacks.perform_edit = performEdit;
    callbacks.end_edit = endEdit;
    const ZigVstguiParameterDescription descriptions[] = {
        {10, 0.25, {"Continuous", 0, 0.5}},
        {20, 0.50, {"Integer", 7, 3.0 / 7.0}},
        {30, 0.00, {"Boolean", 1, 0.0}},
        {40, 1.00, {"Enum", 2, 0.0}},
    };

    ZigVstguiEditor first(descriptions, 4, callbacks);
    ZigVstguiEditor second(descriptions, 4, callbacks);
    if (!first.valid() || !second.valid()) return 1;
    if (!first.setParameter(30, 1.0)) return 2;
    double value = 0.0;
    if (!first.parameterValue(30, value) || !closeEnough(value, 1.0)) return 3;
    if (!first.parameterValue(20, value) || !closeEnough(value, 0.5)) return 4;
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
    return 0;
}

}

int main() {
    if (const int result = testComponentState(); result != 0) return 10 + result;
    if (const int result = testGestureOwnership(); result != 0) return 30 + result;
    if (const int result = testActiveGestureCleanup(); result != 0) return 50 + result;
    if (const int result = testThemeResolution(); result != 0) return 70 + result;
    if (const int result = testMultiParameterRouting(); result != 0) return 90 + result;
    return 0;
}
