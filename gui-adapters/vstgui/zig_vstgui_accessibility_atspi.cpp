#include "zig_vstgui_accessibility_atspi.h"

#include <cmath>

namespace ZigVstgui {

namespace {

constexpr uint32_t interfaceMask(AtspiInterface interface) {
    return static_cast<uint32_t>(interface);
}

AtspiRole mapRole(AccessibilityRole role) {
    switch (role) {
        case AccessibilityRole::slider: return AtspiRole::slider;
        case AccessibilityRole::button: return AtspiRole::push_button;
        case AccessibilityRole::toggle: return AtspiRole::toggle_button;
        case AccessibilityRole::choice: return AtspiRole::combo_box;
        case AccessibilityRole::text_field: return AtspiRole::entry;
        case AccessibilityRole::meter: return AtspiRole::progress_bar;
        case AccessibilityRole::graph: return AtspiRole::chart;
        case AccessibilityRole::group: return AtspiRole::panel;
    }
    return AtspiRole::panel;
}

void setState(std::array<uint32_t, 2>& states, AtspiState state) {
    const auto value = static_cast<uint32_t>(state);
    states[value / 32] |= uint32_t {1} << (value % 32);
}

constexpr AccessibilityAction ordered_actions[] {
    AccessibilityAction::press,
    AccessibilityAction::increment,
    AccessibilityAction::decrement,
    AccessibilityAction::select_previous,
    AccessibilityAction::select_next,
    AccessibilityAction::add_point,
    AccessibilityAction::delete_selected,
};

AtspiAction describeAction(AccessibilityAction action) {
    switch (action) {
        case AccessibilityAction::press:
            return {action, "activate", "Activate the control"};
        case AccessibilityAction::increment:
            return {action, "increment", "Increase the current value"};
        case AccessibilityAction::decrement:
            return {action, "decrement", "Decrease the current value"};
        case AccessibilityAction::select_previous:
            return {action, "select-previous", "Select the previous item"};
        case AccessibilityAction::select_next:
            return {action, "select-next", "Select the next item"};
        case AccessibilityAction::add_point:
            return {action, "add-point", "Add a point"};
        case AccessibilityAction::delete_selected:
            return {action, "delete-selected", "Delete the selected item"};
        case AccessibilityAction::focus:
        case AccessibilityAction::set_value:
            break;
    }
    return {};
}

}

bool AtspiSnapshot::hasState(AtspiState state) const {
    const auto value = static_cast<uint32_t>(state);
    return (states[value / 32] & (uint32_t {1} << (value % 32))) != 0;
}

bool AtspiSnapshot::hasInterface(AtspiInterface interface) const {
    return (interfaces & interfaceMask(interface)) != 0;
}

AtspiNodeAdapter::AtspiNodeAdapter(const AccessibilityNode* value) : node(value) {}

bool AtspiNodeAdapter::valid() const {
    return node != nullptr;
}

AtspiSnapshot AtspiNodeAdapter::snapshot(
    bool focusable,
    bool visible,
    bool showing
) const {
    AtspiSnapshot result;
    if (!node) return result;

    result.role = mapRole(node->role());
    result.name = node->name();
    result.description = node->description();
    result.value_text = node->valueText();
    result.range = node->range();
    result.generation = node->generation();
    result.interfaces =
        interfaceMask(AtspiInterface::accessible) |
        interfaceMask(AtspiInterface::component);

    const auto& state = node->state();
    if (state.enabled) {
        setState(result.states, AtspiState::enabled);
        setState(result.states, AtspiState::sensitive);
    }
    if (focusable) setState(result.states, AtspiState::focusable);
    if (state.focused) setState(result.states, AtspiState::focused);
    if (state.checked) setState(result.states, AtspiState::checked);
    if (state.selected) {
        setState(result.states, AtspiState::selectable);
        setState(result.states, AtspiState::selected);
    }
    if (visible) setState(result.states, AtspiState::visible);
    if (showing) setState(result.states, AtspiState::showing);
    if (node->role() == AccessibilityRole::toggle)
        setState(result.states, AtspiState::checkable);
    if (node->role() == AccessibilityRole::text_field)
        setState(result.states, AtspiState::single_line);

    const bool editable_text =
        node->role() == AccessibilityRole::text_field &&
        node->supports(AccessibilityAction::set_value) &&
        state.enabled &&
        !state.read_only;
    if (editable_text) {
        result.interfaces |= interfaceMask(AtspiInterface::editable_text);
        setState(result.states, AtspiState::editable);
    } else if (state.read_only) {
        setState(result.states, AtspiState::read_only);
    }

    if (node->range().present) result.interfaces |= interfaceMask(AtspiInterface::value);
    if (actionCount() != 0) result.interfaces |= interfaceMask(AtspiInterface::action);
    return result;
}

std::size_t AtspiNodeAdapter::actionCount() const {
    if (!node) return 0;
    std::size_t count = 0;
    for (const auto action : ordered_actions) {
        if (node->supports(action)) count += 1;
    }
    return count;
}

bool AtspiNodeAdapter::actionAt(std::size_t index, AtspiAction& result) const {
    if (!node) return false;
    std::size_t current = 0;
    for (const auto action : ordered_actions) {
        if (!node->supports(action)) continue;
        if (current == index) {
            result = describeAction(action);
            return result.name != nullptr;
        }
        current += 1;
    }
    return false;
}

bool AtspiNodeAdapter::performAction(std::size_t index) const {
    AtspiAction action;
    return actionAt(index, action) && node->perform(action.action);
}

bool AtspiNodeAdapter::setCurrentValue(double value) const {
    return node &&
        node->range().present &&
        std::isfinite(value) &&
        node->perform(AccessibilityAction::set_value, value);
}

bool AtspiNodeAdapter::setCurrentText(const char* text) const {
    return node &&
        node->role() == AccessibilityRole::text_field &&
        text &&
        node->perform(AccessibilityAction::set_value, 0.0, text);
}

bool AtspiNodeAdapter::grabFocus() const {
    return node && node->perform(AccessibilityAction::focus);
}

AtspiChange AtspiNodeAdapter::mapChange(AccessibilityChange change) {
    switch (change) {
        case AccessibilityChange::role: return AtspiChange::role;
        case AccessibilityChange::name: return AtspiChange::name;
        case AccessibilityChange::description: return AtspiChange::description;
        case AccessibilityChange::value: return AtspiChange::value;
        case AccessibilityChange::range: return AtspiChange::range;
        case AccessibilityChange::state: return AtspiChange::state;
        case AccessibilityChange::focus: return AtspiChange::focus;
    }
    return AtspiChange::state;
}

}
