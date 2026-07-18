#include "zig_vstgui_accessibility.h"

#include <algorithm>
#include <utility>

namespace ZigVstgui {

void AccessibilityNode::setObserver(void* userdata, AccessibilityChangeCallback callback) const {
    observer_userdata = userdata;
    observer_callback = callback;
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
    AccessibilityRange next {
        true,
        std::min(minimum, maximum),
        std::max(minimum, maximum),
        std::clamp(current, std::min(minimum, maximum), std::max(minimum, maximum)),
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

void AccessibilityNode::notify(AccessibilityChange change) {
    change_generation += 1;
    if (observer_callback) observer_callback(observer_userdata, change);
}

}
