#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_assets.h"
#include "zig_vstgui_editor.h"
#include "zig_vstgui_fonts.h"
#include "zig_vstgui_layout.h"
#include "zig_vstgui_meters.h"

#include "pluginterfaces/base/keycodes.h"

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
    double meter_values[4] {0.0, 0.0, 0.0, 0.0};
};

struct AccessibilityObserverState {
    uint32_t count {0};
    ZigVstgui::AccessibilityChange last {ZigVstgui::AccessibilityChange::role};
};

void accessibilityChanged(void* userdata, ZigVstgui::AccessibilityChange change) {
    auto* state = static_cast<AccessibilityObserverState*>(userdata);
    state->count += 1;
    state->last = change;
}

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

double loadMeter(void* userdata, uint32_t source_id) {
    auto* state = static_cast<CallbackState*>(userdata);
    return source_id < 4 ? state->meter_values[source_id] : 0.0;
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
    if (slider_accessibility->name() != "Continuous (x)" || !slider_accessibility->range().present) return 17;
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
            !accessibility->state().read_only) return 25;
        if (!first.tickMeter(index, 0.0)) return 26;
    }
    if (!closeEnough(first.meterLevel(0, 0), 0.8)) return 27;
    if (!closeEnough(first.meterLevel(1, 0), 0.6) || !closeEnough(first.meterLevel(1, 1), 0.4)) return 28;
    if (!closeEnough(first.meterLevel(2, 0), 0.25)) return 29;
    if (first.meterAccessibility(3) || first.tickMeter(3, 0.0)) return 30;
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
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 1) return 13;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 0) || first.focusPosition() != 2) return 14;
    if (!first.keyDown(0, Steinberg::KEY_TAB, 1) || first.focusPosition() != 1) return 15;
    if (!first.setParameter(30, 1.0)) return 2;
    if (!toggle_accessibility->state().checked || toggle_accessibility->valueText().empty()) return 24;
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
    if (zig_vstgui_adapter_version() != 5) return 1;
    const ZigVstguiParameterDescription parameter {
        1,
        0.5,
        {"Gain", "dB", 0, 0.5},
        ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
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
    if (!meter.update(0.2, 100.0)) return 7;
    if (!closeEnough(meter.level(), 0.2) || !closeEnough(meter.peak(), 0.65)) return 8;
    if (!meter.update(2.0, 0.0) || !closeEnough(meter.level(), 1.0)) return 9;
    if (!meter.update(std::nan(""), 1000.0) || !closeEnough(meter.level(), 0.0)) return 10;
    meter.reset();
    if (!closeEnough(meter.level(), 0.0) || !closeEnough(meter.peak(), 0.0)) return 11;
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
    if (const int result = testMultiParameterRouting(); result != 0) return 90 + result;
    if (const int result = testLayoutSolvers(); result != 0) return 110 + result;
    if (const int result = testGalleryLayoutExtents(); result != 0) return 130 + result;
    if (const int result = testMeterBallistics(); result != 0) return 150 + result;
    if (const int result = testMeterAbi(); result != 0) return 170 + result;
    if (const int result = testAssetsAndFonts(); result != 0) return 190 + result;
    return 0;
}
