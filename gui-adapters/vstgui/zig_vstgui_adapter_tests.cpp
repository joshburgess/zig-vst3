#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_editor.h"
#include "zig_vstgui_layout.h"

#include "pluginterfaces/base/keycodes.h"

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
    uint32_t context_menu_count {0};
    int32_t context_x {0};
    int32_t context_y {0};
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

int32_t showContextMenu(void* userdata, uint32_t parameter_id, int32_t x, int32_t y) {
    auto* state = static_cast<CallbackState*>(userdata);
    state->context_menu_count += 1;
    state->last_parameter_id = parameter_id;
    state->context_x = x;
    state->context_y = y;
    return 0;
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
        {10, 0.25, {"Continuous", "x", 0, 0.5}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER},
        {20, 0.50, {"Integer", "voices", 7, 3.0 / 7.0}, ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM},
        {30, 0.00, {"Boolean", "", 1, 0.0}, ZIG_VSTGUI_CONTROL_TOGGLE},
        {40, 1.00, {"Enum", "", 2, 0.0}, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN},
    };

    ZigVstguiEditor first(descriptions, 4, callbacks);
    ZigVstguiEditor second(descriptions, 4, callbacks);
    if (!first.valid() || !second.valid()) return 1;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 0) return 12;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 1) return 13;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 2) return 14;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 1) || first.focusPosition() != 1) return 15;
    if (!first.setParameter(30, 1.0)) return 2;
    double value = 0.0;
    if (!first.parameterValue(30, value) || !closeEnough(value, 1.0)) return 3;
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
    }
    return 0;
}

}

int main() {
    if (const int result = testComponentState(); result != 0) return 10 + result;
    if (const int result = testGestureOwnership(); result != 0) return 30 + result;
    if (const int result = testActiveGestureCleanup(); result != 0) return 50 + result;
    if (const int result = testSteppedGestureQuantization(); result != 0) return 55 + result;
    if (const int result = testParameterContextMenu(); result != 0) return 60 + result;
    if (const int result = testThemeResolution(); result != 0) return 70 + result;
    if (const int result = testMultiParameterRouting(); result != 0) return 90 + result;
    if (const int result = testLayoutSolvers(); result != 0) return 110 + result;
    if (const int result = testGalleryLayoutExtents(); result != 0) return 130 + result;
    return 0;
}
