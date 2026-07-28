#include "zig_vstgui_accessibility.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace ZigVstgui {

void AccessibilityNode::setObserver(void* userdata, AccessibilityChangeCallback callback) const {
    observer_userdata = userdata;
    observer_callback = callback;
}

void AccessibilityNode::setActionHandler(
    void* userdata,
    AccessibilityActionCallback callback,
    uint32_t actions
) {
    action_userdata = userdata;
    action_callback = callback;
    supported_actions = callback ? actions : 0;
}

void AccessibilityNode::clearActionHandler() {
    action_userdata = nullptr;
    action_callback = nullptr;
    supported_actions = 0;
}

void AccessibilityNode::setRole(AccessibilityRole role) {
    if (semantic_role == role) return;
    semantic_role = role;
    notify(AccessibilityChange::role);
}

void AccessibilityNode::setName(std::string name) {
    if (semantic_name == name) return;
    semantic_name = std::move(name);
    notify(AccessibilityChange::name);
}

void AccessibilityNode::setDescription(std::string description) {
    if (semantic_description == description) return;
    semantic_description = std::move(description);
    notify(AccessibilityChange::description);
}

void AccessibilityNode::setValueText(std::string value) {
    if (semantic_value == value) return;
    semantic_value = std::move(value);
    notify(AccessibilityChange::value);
}

void AccessibilityNode::setRange(double minimum, double maximum, double current) {
    if (!std::isfinite(minimum) || !std::isfinite(maximum)) {
        clearRange();
        return;
    }
    const double lower = std::min(minimum, maximum);
    const double upper = std::max(minimum, maximum);
    AccessibilityRange next {
        true,
        lower,
        upper,
        std::isnan(current) ? lower : std::clamp(current, lower, upper),
    };
    if (semantic_range.present == next.present &&
        semantic_range.minimum == next.minimum &&
        semantic_range.maximum == next.maximum &&
        semantic_range.current == next.current) return;
    semantic_range = next;
    notify(AccessibilityChange::range);
}

void AccessibilityNode::clearRange() {
    if (!semantic_range.present) return;
    semantic_range = {};
    notify(AccessibilityChange::range);
}

void AccessibilityNode::setEnabled(bool enabled) {
    if (semantic_state.enabled == enabled) return;
    semantic_state.enabled = enabled;
    notify(AccessibilityChange::state);
}

void AccessibilityNode::setFocused(bool focused) {
    if (semantic_state.focused == focused) return;
    semantic_state.focused = focused;
    notify(AccessibilityChange::focus);
}

void AccessibilityNode::setChecked(bool checked) {
    if (semantic_state.checked == checked) return;
    semantic_state.checked = checked;
    notify(AccessibilityChange::state);
}

void AccessibilityNode::setSelected(bool selected) {
    if (semantic_state.selected == selected) return;
    semantic_state.selected = selected;
    notify(AccessibilityChange::state);
}

void AccessibilityNode::setReadOnly(bool read_only) {
    if (semantic_state.read_only == read_only) return;
    semantic_state.read_only = read_only;
    notify(AccessibilityChange::state);
}

AccessibilityRole AccessibilityNode::role() const {
    return semantic_role;
}

const std::string& AccessibilityNode::name() const {
    return semantic_name;
}

const std::string& AccessibilityNode::description() const {
    return semantic_description;
}

const std::string& AccessibilityNode::valueText() const {
    return semantic_value;
}

const AccessibilityRange& AccessibilityNode::range() const {
    return semantic_range;
}

const AccessibilityState& AccessibilityNode::state() const {
    return semantic_state;
}

uint64_t AccessibilityNode::generation() const {
    return change_generation;
}

bool AccessibilityNode::supports(AccessibilityAction action) const {
    return (supported_actions & static_cast<uint32_t>(action)) != 0;
}

bool AccessibilityNode::perform(AccessibilityAction action, double value, const char* text) const {
    if (!semantic_state.enabled || semantic_state.read_only || !supports(action) || !action_callback) return false;
    return action_callback(action_userdata, *this, {action, value, text});
}

void AccessibilityNode::notify(AccessibilityChange change) {
    change_generation += 1;
    if (observer_callback) observer_callback(observer_userdata, change);
}

}
