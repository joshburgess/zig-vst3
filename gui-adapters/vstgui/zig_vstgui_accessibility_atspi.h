#ifndef ZIG_VSTGUI_ACCESSIBILITY_ATSPI_H
#define ZIG_VSTGUI_ACCESSIBILITY_ATSPI_H

#include "zig_vstgui_accessibility.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace ZigVstgui {

enum class AtspiRole : uint32_t {
    combo_box = 11,
    panel = 39,
    progress_bar = 42,
    push_button = 43,
    slider = 51,
    toggle_button = 62,
    entry = 79,
    chart = 80,
};

enum class AtspiState : uint32_t {
    checked = 4,
    editable = 7,
    enabled = 8,
    focusable = 11,
    focused = 12,
    selectable = 22,
    selected = 23,
    sensitive = 24,
    showing = 25,
    single_line = 26,
    visible = 30,
    selectable_text = 38,
    checkable = 41,
    read_only = 43,
};

enum class AtspiInterface : uint32_t {
    accessible = 1u << 0,
    action = 1u << 1,
    component = 1u << 2,
    editable_text = 1u << 3,
    value = 1u << 4,
    text = 1u << 5,
};

enum class AtspiChange {
    role,
    name,
    description,
    value,
    range,
    state,
    focus,
    text_caret,
    text_selection,
};

struct AtspiAction {
    AccessibilityAction action {AccessibilityAction::focus};
    const char* name {nullptr};
    const char* description {nullptr};
};

struct AtspiSnapshot {
    AtspiRole role {AtspiRole::panel};
    std::string name;
    std::string description;
    std::string value_text;
    AccessibilityRange range;
    AccessibilityTextSelection text_selection;
    std::array<uint32_t, 2> states {};
    uint32_t interfaces {0};
    uint64_t generation {0};

    bool hasState(AtspiState state) const;
    bool hasInterface(AtspiInterface interface) const;
};

class AtspiNodeAdapter {
public:
    explicit AtspiNodeAdapter(const AccessibilityNode* node);

    bool valid() const;
    AtspiSnapshot snapshot(bool focusable, bool visible, bool showing) const;
    std::size_t actionCount() const;
    bool actionAt(std::size_t index, AtspiAction& result) const;
    bool performAction(std::size_t index) const;
    bool setCurrentValue(double value) const;
    bool setCurrentText(const char* text) const;
    bool grabFocus() const;

    static AtspiChange mapChange(AccessibilityChange change);

private:
    const AccessibilityNode* node {nullptr};
};

}

#endif
