#include "zig_vstgui_action_button.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cgradient.h"

#include <new>
#include <utility>

namespace ZigVstgui {

namespace {

constexpr uint32_t actionMask(AccessibilityAction action) {
    return static_cast<uint32_t>(action);
}

const char* iconText(ZigVstguiActionIcon icon) {
    switch (icon) {
        case ZIG_VSTGUI_ACTION_ICON_RESET: return "Reset";
        case ZIG_VSTGUI_ACTION_ICON_CLEAR: return "Clear";
        case ZIG_VSTGUI_ACTION_ICON_REVERSE: return "Reverse";
        case ZIG_VSTGUI_ACTION_ICON_ZOOM_IN: return "+";
        case ZIG_VSTGUI_ACTION_ICON_ZOOM_OUT: return "-";
        default: return "";
    }
}

}

bool ActionButtonControl::build(
    VSTGUI::CViewContainer* parent,
    const ZigVstguiActionButtonDescription& value_description,
    ZigVstguiCallbacks value_callbacks,
    const ThemeResolver& styles,
    std::function<void(uint32_t)> value_accepted_handler
) {
    if (!parent || button) return false;
    description = value_description;
    callbacks = value_callbacks;
    accepted_handler = std::move(value_accepted_handler);
    label = description.label ? description.label : "";
    accessible_label = description.accessible_label ? description.accessible_label : label;
    tooltip = description.tooltip ? description.tooltip : "";
    confirmation_label = description.confirmation_label ? description.confirmation_label : "";
    failure_label = description.failure_label ? description.failure_label : "Action failed. Try again";
    idle_text = label.empty() ? iconText(description.icon) : label;

    button = new (std::nothrow) VSTGUI::CTextButton(VSTGUI::CRect(), this, 0, idle_text.c_str());
    if (!button) return false;
    const auto style = styles.resolve(ComponentKind::resize_button);
    const auto pressed = styles.resolve(ComponentKind::resize_button, VisualState::pressed);
    const auto& colors = styles.theme().colors;
    button->setFont(styles.font(TypographyRole::body));
    button->setTextColor(description.role == ZIG_VSTGUI_ACTION_PRIMARY ? colors.surface : style.foreground);
    button->setTextColorHighlighted(description.role == ZIG_VSTGUI_ACTION_PRIMARY ? colors.surface : pressed.foreground);
    button->setFrameColor(description.role == ZIG_VSTGUI_ACTION_DESTRUCTIVE
        ? VSTGUI::CColor(196, 72, 72, 255)
        : description.role == ZIG_VSTGUI_ACTION_PRIMARY ? style.accent : style.border);
    button->setFrameColorHighlighted(pressed.border);
    button->setFrameWidth(style.frame_width);
    if (description.role == ZIG_VSTGUI_ACTION_PRIMARY) {
        button->setGradient(VSTGUI::owned(VSTGUI::CGradient::create(
            0, 1, colors.button_top, colors.button_bottom
        )));
        button->setGradientHighlighted(VSTGUI::owned(VSTGUI::CGradient::create(
            0, 1, colors.button_top_highlighted, colors.button_bottom_highlighted
        )));
    } else {
        button->setGradient(VSTGUI::owned(VSTGUI::CGradient::create(
            0, 1, colors.surface_raised, colors.surface_raised
        )));
        button->setGradientHighlighted(VSTGUI::owned(VSTGUI::CGradient::create(
            0, 1, colors.button_top_highlighted, colors.button_bottom_highlighted
        )));
    }
    button->setRoundRadius(style.radius);
    if (!tooltip.empty()) button->setTooltipText(tooltip.c_str());
    parent->addView(button);
    button->registerViewListener(this);

    component.bind(button);
    component.setEnabled(description.enabled != 0);
    component.setFocusable(true);
    component.accessibility().setRole(AccessibilityRole::button);
    component.accessibility().setName(accessible_label);
    component.accessibility().setDescription(tooltip);
    component.accessibility().setActionHandler(
        this,
        accessibilityAction,
        actionMask(AccessibilityAction::focus) | actionMask(AccessibilityAction::press)
    );
    syncState();
    return true;
}

void ActionButtonControl::clear() {
    if (button) button->unregisterViewListener(this);
    component.accessibility().clearActionHandler();
    component.clear();
    button = nullptr;
    accepted_handler = {};
}

void ActionButtonControl::setBounds(const VSTGUI::CRect& bounds) {
    component.setBounds(bounds);
}

void ActionButtonControl::setEnabled(bool enabled) {
    if (!enabled) {
        confirmation_pending = false;
        action_failed = false;
    }
    component.setEnabled(enabled);
    syncState();
}

bool ActionButtonControl::handleKey(uint16_t, int16_t key_code, int16_t) {
    if (key_code == Steinberg::KEY_ESCAPE) return cancelPending();
    if (key_code == Steinberg::KEY_RETURN || key_code == Steinberg::KEY_ENTER ||
        key_code == Steinberg::KEY_SPACE) return activate();
    return false;
}

bool ActionButtonControl::activate() {
    if (!component.state().enabled) return false;
    if (!confirmation_label.empty() && !confirmation_pending && !action_failed) {
        confirmation_pending = true;
        syncState();
        return true;
    }
    const bool accepted = callbacks.invoke_action &&
        callbacks.invoke_action(callbacks.userdata, description.group_id, description.action_id) == 0;
    confirmation_pending = false;
    action_failed = !accepted;
    syncState();
    if (accepted && accepted_handler) {
        accepted_handler(description.success_focus_importer_id);
    }
    return true;
}

bool ActionButtonControl::cancelPending() {
    if (!confirmation_pending && !action_failed) return false;
    confirmation_pending = false;
    action_failed = false;
    syncState();
    return true;
}

bool ActionButtonControl::confirming() const { return confirmation_pending; }
bool ActionButtonControl::failed() const { return action_failed; }
bool ActionButtonControl::enabled() const { return component.state().enabled; }
VSTGUI::CView* ActionButtonControl::focusView() const { return button; }

void ActionButtonControl::setFocusedView(VSTGUI::CView* view) {
    component.setFocused(view && view == button);
}

const AccessibilityNode& ActionButtonControl::accessibilityNode() const {
    return component.accessibility();
}

void ActionButtonControl::valueChanged(VSTGUI::CControl*) {
    activate();
}

void ActionButtonControl::viewLostFocus(VSTGUI::CView* view) {
    if (view == button) setFocusedView(nullptr);
}

void ActionButtonControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == button) setFocusedView(view);
}

bool ActionButtonControl::accessibilityAction(
    void* userdata,
    const AccessibilityNode&,
    const AccessibilityActionRequest& request
) {
    auto* self = static_cast<ActionButtonControl*>(userdata);
    return self && self->performAccessibilityAction(request);
}

bool ActionButtonControl::performAccessibilityAction(const AccessibilityActionRequest& request) {
    if (!component.state().enabled) return false;
    if (request.action == AccessibilityAction::focus) {
        if (!button || !button->getFrame()) return false;
        button->getFrame()->setFocusView(button);
        setFocusedView(button);
        return true;
    }
    if (request.action == AccessibilityAction::press) return activate();
    return false;
}

void ActionButtonControl::syncState() {
    if (!button) return;
    if (confirmation_pending) {
        button->setTitle(confirmation_label.c_str());
        component.accessibility().setValueText("Confirmation required");
    } else if (action_failed) {
        button->setTitle(failure_label.c_str());
        component.accessibility().setValueText(failure_label);
    } else {
        button->setTitle(idle_text.c_str());
        component.accessibility().setValueText("");
    }
    button->invalid();
}

}
