#include "zig_vstgui_accessibility_atspi.h"

#include <cmath>
#include <cstring>

namespace {

struct ActionState {
    std::size_t count {0};
    ZigVstgui::AccessibilityAction last {ZigVstgui::AccessibilityAction::focus};
    double value {0.0};
    const char* text {nullptr};
    uint32_t text_start {0};
    uint32_t text_end {0};
};

bool perform(
    void* userdata,
    const ZigVstgui::AccessibilityNode&,
    const ZigVstgui::AccessibilityActionRequest& request
) {
    auto* state = static_cast<ActionState*>(userdata);
    state->count += 1;
    state->last = request.action;
    state->value = request.value;
    state->text = request.text;
    state->text_start = request.text_start;
    state->text_end = request.text_end;
    return true;
}

int testRoleMapping() {
    using namespace ZigVstgui;
    struct Case {
        AccessibilityRole source;
        AtspiRole expected;
    };
    constexpr Case cases[] {
        {AccessibilityRole::slider, AtspiRole::slider},
        {AccessibilityRole::button, AtspiRole::push_button},
        {AccessibilityRole::toggle, AtspiRole::toggle_button},
        {AccessibilityRole::choice, AtspiRole::combo_box},
        {AccessibilityRole::text_field, AtspiRole::entry},
        {AccessibilityRole::meter, AtspiRole::progress_bar},
        {AccessibilityRole::graph, AtspiRole::chart},
        {AccessibilityRole::group, AtspiRole::panel},
    };
    for (const auto& item : cases) {
        AccessibilityNode node;
        node.setRole(item.source);
        if (AtspiNodeAdapter(&node).snapshot(true, true, true).role != item.expected) return 1;
    }
    return 0;
}

int testSnapshot() {
    using namespace ZigVstgui;
    AccessibilityNode node;
    node.setRole(AccessibilityRole::toggle);
    node.setName("Bypass");
    node.setDescription("Bypass processing");
    node.setValueText("On");
    node.setRange(0.0, 1.0, 1.0);
    node.setFocused(true);
    node.setChecked(true);
    node.setSelected(true);
    ActionState actions;
    node.setActionHandler(
        &actions,
        perform,
        static_cast<uint32_t>(AccessibilityAction::focus) |
            static_cast<uint32_t>(AccessibilityAction::press) |
            static_cast<uint32_t>(AccessibilityAction::set_value)
    );
    const auto snapshot = AtspiNodeAdapter(&node).snapshot(true, true, true);
    if (snapshot.name != "Bypass" ||
        snapshot.description != "Bypass processing" ||
        snapshot.value_text != "On" ||
        snapshot.role != AtspiRole::toggle_button ||
        !snapshot.range.present ||
        std::abs(snapshot.range.current - 1.0) > 1e-12) return 1;
    constexpr AtspiState required[] {
        AtspiState::checked,
        AtspiState::enabled,
        AtspiState::focusable,
        AtspiState::focused,
        AtspiState::selectable,
        AtspiState::selected,
        AtspiState::sensitive,
        AtspiState::showing,
        AtspiState::visible,
        AtspiState::checkable,
    };
    for (const auto state : required) {
        if (!snapshot.hasState(state)) return 2;
    }
    if (!snapshot.hasInterface(AtspiInterface::accessible) ||
        !snapshot.hasInterface(AtspiInterface::component) ||
        !snapshot.hasInterface(AtspiInterface::action) ||
        !snapshot.hasInterface(AtspiInterface::value) ||
        snapshot.hasInterface(AtspiInterface::editable_text)) return 3;
    return 0;
}

int testTextAndReadOnlyState() {
    using namespace ZigVstgui;
    AccessibilityNode node;
    node.setRole(AccessibilityRole::text_field);
    ActionState actions;
    node.setActionHandler(
        &actions,
        perform,
        static_cast<uint32_t>(AccessibilityAction::focus) |
            static_cast<uint32_t>(AccessibilityAction::set_value) |
            static_cast<uint32_t>(AccessibilityAction::set_caret) |
            static_cast<uint32_t>(AccessibilityAction::set_selection)
    );
    auto snapshot = AtspiNodeAdapter(&node).snapshot(true, true, true);
    if (!snapshot.hasState(AtspiState::editable) ||
        !snapshot.hasState(AtspiState::single_line) ||
        !snapshot.hasState(AtspiState::selectable_text) ||
        !snapshot.hasInterface(AtspiInterface::text) ||
        !snapshot.hasInterface(AtspiInterface::editable_text)) return 1;
    node.setReadOnly(true);
    snapshot = AtspiNodeAdapter(&node).snapshot(true, true, true);
    if (snapshot.hasState(AtspiState::editable) ||
        !snapshot.hasState(AtspiState::read_only) ||
        !snapshot.hasState(AtspiState::selectable_text) ||
        !snapshot.hasInterface(AtspiInterface::text) ||
        snapshot.hasInterface(AtspiInterface::editable_text)) return 2;
    node.setValueText("AéB");
    if (!node.setTextSelection(1, 2)) return 3;
    snapshot = AtspiNodeAdapter(&node).snapshot(true, true, true);
    if (!snapshot.text_selection.present ||
        snapshot.text_selection.anchor != 1 || snapshot.text_selection.caret != 2 ||
        !node.performTextSelection(AccessibilityAction::set_caret, 2, 2) ||
        actions.last != AccessibilityAction::set_caret ||
        actions.text_start != 2 || actions.text_end != 2 ||
        node.perform(AccessibilityAction::set_value, 0.0, "AB")) return 4;
    return 0;
}

int testActions() {
    using namespace ZigVstgui;
    AccessibilityNode node;
    ActionState actions;
    node.setActionHandler(
        &actions,
        perform,
        static_cast<uint32_t>(AccessibilityAction::focus) |
            static_cast<uint32_t>(AccessibilityAction::press) |
            static_cast<uint32_t>(AccessibilityAction::increment) |
            static_cast<uint32_t>(AccessibilityAction::decrement) |
            static_cast<uint32_t>(AccessibilityAction::set_value) |
            static_cast<uint32_t>(AccessibilityAction::select_next)
    );
    node.setRange(-1.0, 1.0, 0.0);
    AtspiNodeAdapter adapter(&node);
    if (adapter.actionCount() != 4) return 1;
    AtspiAction action;
    if (!adapter.actionAt(0, action) || std::strcmp(action.name, "activate") != 0 ||
        !adapter.actionAt(1, action) || std::strcmp(action.name, "increment") != 0 ||
        !adapter.actionAt(2, action) || std::strcmp(action.name, "decrement") != 0 ||
        !adapter.actionAt(3, action) || std::strcmp(action.name, "select-next") != 0 ||
        adapter.actionAt(4, action)) return 2;
    if (!adapter.performAction(1) ||
        actions.last != AccessibilityAction::increment ||
        !adapter.setCurrentValue(0.75) ||
        actions.last != AccessibilityAction::set_value ||
        std::abs(actions.value - 0.75) > 1e-12 ||
        adapter.setCurrentValue(std::nan("")) ||
        !adapter.grabFocus() ||
        actions.last != AccessibilityAction::focus) return 3;
    node.setEnabled(false);
    if (adapter.performAction(0) || adapter.setCurrentValue(0.5) || adapter.grabFocus()) return 4;
    return 0;
}

int testTextAction() {
    using namespace ZigVstgui;
    AccessibilityNode node;
    node.setRole(AccessibilityRole::text_field);
    ActionState actions;
    node.setActionHandler(
        &actions,
        perform,
        static_cast<uint32_t>(AccessibilityAction::set_value)
    );
    AtspiNodeAdapter adapter(&node);
    if (!adapter.setCurrentText("0.42") ||
        actions.last != AccessibilityAction::set_value ||
        !actions.text ||
        std::strcmp(actions.text, "0.42") != 0 ||
        adapter.setCurrentText(nullptr)) return 1;
    node.setRole(AccessibilityRole::slider);
    if (adapter.setCurrentText("0.5")) return 2;
    return 0;
}

int testChangesAndInvalidAdapter() {
    using namespace ZigVstgui;
    constexpr AccessibilityChange source[] {
        AccessibilityChange::role,
        AccessibilityChange::name,
        AccessibilityChange::description,
        AccessibilityChange::value,
        AccessibilityChange::range,
        AccessibilityChange::state,
        AccessibilityChange::focus,
        AccessibilityChange::text_caret,
        AccessibilityChange::text_selection,
    };
    constexpr AtspiChange expected[] {
        AtspiChange::role,
        AtspiChange::name,
        AtspiChange::description,
        AtspiChange::value,
        AtspiChange::range,
        AtspiChange::state,
        AtspiChange::focus,
        AtspiChange::text_caret,
        AtspiChange::text_selection,
    };
    for (std::size_t index = 0; index < std::size(source); ++index) {
        if (AtspiNodeAdapter::mapChange(source[index]) != expected[index]) return 1;
    }
    AtspiNodeAdapter invalid(nullptr);
    AtspiAction action;
    if (invalid.valid() ||
        invalid.actionCount() != 0 ||
        invalid.actionAt(0, action) ||
        invalid.performAction(0) ||
        invalid.setCurrentValue(0.0) ||
        invalid.setCurrentText("") ||
        invalid.grabFocus()) return 2;
    return 0;
}

}

int main() {
    if (const int result = testRoleMapping()) return 10 + result;
    if (const int result = testSnapshot()) return 20 + result;
    if (const int result = testTextAndReadOnlyState()) return 30 + result;
    if (const int result = testActions()) return 40 + result;
    if (const int result = testTextAction()) return 50 + result;
    if (const int result = testChangesAndInvalidAdapter()) return 60 + result;
    return 0;
}
