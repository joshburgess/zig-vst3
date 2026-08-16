#include "zig_vstgui_accessibility.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <string_view>
#include <utility>

namespace ZigVstgui {

namespace {

bool utf8CharacterCount(std::string_view text, uint32_t& result) {
    uint64_t count = 0;
    std::size_t index = 0;
    while (index < text.size()) {
        const auto first = static_cast<unsigned char>(text[index]);
        std::size_t width = 0;
        if (first <= 0x7f) width = 1;
        else if (first >= 0xc2 && first <= 0xdf) width = 2;
        else if (first >= 0xe0 && first <= 0xef) width = 3;
        else if (first >= 0xf0 && first <= 0xf4) width = 4;
        else return false;
        if (index + width > text.size()) return false;
        for (std::size_t offset = 1; offset < width; ++offset) {
            const auto continuation = static_cast<unsigned char>(text[index + offset]);
            if (continuation < 0x80 || continuation > 0xbf) return false;
        }
        if (width == 3) {
            const auto second = static_cast<unsigned char>(text[index + 1]);
            if ((first == 0xe0 && second < 0xa0) ||
                (first == 0xed && second > 0x9f)) return false;
        }
        if (width == 4) {
            const auto second = static_cast<unsigned char>(text[index + 1]);
            if ((first == 0xf0 && second < 0x90) ||
                (first == 0xf4 && second > 0x8f)) return false;
        }
        index += width;
        count += 1;
        if (count > std::numeric_limits<uint32_t>::max()) return false;
    }
    result = static_cast<uint32_t>(count);
    return true;
}

bool sameTextSelection(
    const AccessibilityTextSelection& left,
    const AccessibilityTextSelection& right
) {
    return left.present == right.present && left.anchor == right.anchor &&
        left.caret == right.caret;
}

bool allowedWhenReadOnly(AccessibilityAction action) {
    return action == AccessibilityAction::focus ||
        action == AccessibilityAction::set_caret ||
        action == AccessibilityAction::set_selection;
}

}

bool validUtf8(std::string_view text) {
    uint32_t count = 0;
    return utf8CharacterCount(text, count);
}

bool AccessibilityTextSelection::selected() const {
    return present && anchor != caret;
}

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
    const auto previous_selection = semantic_text_selection;
    semantic_value = std::move(value);
    uint32_t count = 0;
    if (!utf8CharacterCount(semantic_value, count)) {
        semantic_text_selection = {};
    } else if (semantic_text_selection.present) {
        semantic_text_selection.anchor = std::min(semantic_text_selection.anchor, count);
        semantic_text_selection.caret = std::min(semantic_text_selection.caret, count);
    }
    notify(AccessibilityChange::value);
    if (previous_selection.present != semantic_text_selection.present ||
        previous_selection.caret != semantic_text_selection.caret)
        notify(AccessibilityChange::text_caret);
    if (previous_selection.selected() != semantic_text_selection.selected() ||
        (semantic_text_selection.selected() &&
            !sameTextSelection(previous_selection, semantic_text_selection)))
        notify(AccessibilityChange::text_selection);
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

bool AccessibilityNode::setTextSelection(uint32_t anchor, uint32_t caret) {
    uint32_t count = 0;
    if (!utf8CharacterCount(semantic_value, count) || anchor > count || caret > count)
        return false;
    const AccessibilityTextSelection next {true, anchor, caret};
    if (sameTextSelection(semantic_text_selection, next)) return true;
    const auto previous = semantic_text_selection;
    semantic_text_selection = next;
    if (!previous.present || previous.caret != caret)
        notify(AccessibilityChange::text_caret);
    if (previous.selected() != next.selected() ||
        (next.selected() && !sameTextSelection(previous, next)))
        notify(AccessibilityChange::text_selection);
    return true;
}

void AccessibilityNode::clearTextSelection() {
    if (!semantic_text_selection.present) return;
    const bool was_selected = semantic_text_selection.selected();
    semantic_text_selection = {};
    notify(AccessibilityChange::text_caret);
    if (was_selected) notify(AccessibilityChange::text_selection);
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

const AccessibilityTextSelection& AccessibilityNode::textSelection() const {
    return semantic_text_selection;
}

uint64_t AccessibilityNode::generation() const {
    return change_generation;
}

bool AccessibilityNode::supports(AccessibilityAction action) const {
    return (supported_actions & static_cast<uint32_t>(action)) != 0;
}

bool AccessibilityNode::perform(AccessibilityAction action, double value, const char* text) const {
    if (!semantic_state.enabled ||
        (semantic_state.read_only && !allowedWhenReadOnly(action)) ||
        !supports(action) || !action_callback) return false;
    return action_callback(action_userdata, *this, {action, value, text});
}

bool AccessibilityNode::performTextSelection(
    AccessibilityAction action,
    uint32_t anchor,
    uint32_t caret
) const {
    if (action != AccessibilityAction::set_caret &&
        action != AccessibilityAction::set_selection) return false;
    if (action == AccessibilityAction::set_caret && anchor != caret) return false;
    uint32_t count = 0;
    if (!utf8CharacterCount(semantic_value, count) || anchor > count || caret > count)
        return false;
    if (!semantic_state.enabled ||
        (semantic_state.read_only && !allowedWhenReadOnly(action)) ||
        !supports(action) || !action_callback) return false;
    return action_callback(
        action_userdata,
        *this,
        {action, 0.0, nullptr, anchor, caret}
    );
}

void AccessibilityNode::notify(AccessibilityChange change) {
    change_generation += 1;
    if (observer_callback) observer_callback(observer_userdata, change);
}

}
