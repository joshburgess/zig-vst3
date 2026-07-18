#ifndef ZIG_VSTGUI_ACCESSIBILITY_H
#define ZIG_VSTGUI_ACCESSIBILITY_H

#include <cstdint>
#include <string>

namespace ZigVstgui {

enum class AccessibilityRole {
    slider,
    button,
    toggle,
    choice,
    text_field,
    meter,
    graph,
    group,
};

enum class AccessibilityChange {
    role,
    name,
    description,
    value,
    range,
    state,
    focus,
};

enum class AccessibilityAction : uint32_t {
    focus = 1u << 0,
    press = 1u << 1,
    increment = 1u << 2,
    decrement = 1u << 3,
    set_value = 1u << 4,
};

struct AccessibilityActionRequest {
    AccessibilityAction action {AccessibilityAction::focus};
    double value {0.0};
    const char* text {nullptr};
};

struct AccessibilityRange {
    bool present {false};
    double minimum {0.0};
    double maximum {0.0};
    double current {0.0};
};

struct AccessibilityState {
    bool enabled {true};
    bool focused {false};
    bool checked {false};
    bool selected {false};
    bool read_only {false};
};

using AccessibilityChangeCallback = void (*)(void*, AccessibilityChange);
class AccessibilityNode;
using AccessibilityActionCallback = bool (*)(void*, const AccessibilityNode&, const AccessibilityActionRequest&);

class AccessibilityNode {
public:
    void setObserver(void* userdata, AccessibilityChangeCallback callback) const;
    void setActionHandler(void* userdata, AccessibilityActionCallback callback, uint32_t actions);
    void clearActionHandler();
    void setRole(AccessibilityRole role);
    void setName(std::string name);
    void setDescription(std::string description);
    void setValueText(std::string value);
    void setRange(double minimum, double maximum, double current);
    void clearRange();
    void setEnabled(bool enabled);
    void setFocused(bool focused);
    void setChecked(bool checked);
    void setSelected(bool selected);
    void setReadOnly(bool read_only);

    AccessibilityRole role() const;
    const std::string& name() const;
    const std::string& description() const;
    const std::string& valueText() const;
    const AccessibilityRange& range() const;
    const AccessibilityState& state() const;
    uint64_t generation() const;
    bool supports(AccessibilityAction action) const;
    bool perform(AccessibilityAction action, double value = 0.0, const char* text = nullptr) const;

private:
    void notify(AccessibilityChange change);

    AccessibilityRole semantic_role {AccessibilityRole::group};
    std::string semantic_name;
    std::string semantic_description;
    std::string semantic_value;
    AccessibilityRange semantic_range;
    AccessibilityState semantic_state;
    mutable void* observer_userdata {nullptr};
    mutable AccessibilityChangeCallback observer_callback {nullptr};
    void* action_userdata {nullptr};
    AccessibilityActionCallback action_callback {nullptr};
    uint32_t supported_actions {0};
    uint64_t change_generation {0};
};

}

#endif
