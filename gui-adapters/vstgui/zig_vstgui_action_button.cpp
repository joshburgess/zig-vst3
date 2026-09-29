#include "zig_vstgui_action_button.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cgradient.h"

#include <algorithm>
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
    disabled_alpha = styles.resolve(ComponentKind::resize_button, VisualState::disabled).alpha;
    const auto& colors = styles.theme().colors;
    normal_top = description.role == ZIG_VSTGUI_ACTION_PRIMARY ? colors.button_top : colors.surface_raised;
    normal_bottom = description.role == ZIG_VSTGUI_ACTION_PRIMARY ? colors.button_bottom : colors.surface_raised;
    highlighted_top = colors.button_top_highlighted;
    highlighted_bottom = colors.button_bottom_highlighted;
    const auto normal_candidate = contrastingTextColor(
        normal_top,
        VSTGUI::kBlackCColor,
        VSTGUI::kWhiteCColor
    );
    const auto alternate_candidate = normal_candidate == VSTGUI::kBlackCColor
        ? VSTGUI::kWhiteCColor
        : VSTGUI::kBlackCColor;
    normal_text = std::min(
        contrastRatio(normal_candidate, normal_top),
        contrastRatio(normal_candidate, normal_bottom)
    ) >= std::min(
        contrastRatio(alternate_candidate, normal_top),
        contrastRatio(alternate_candidate, normal_bottom)
    ) ? normal_candidate : alternate_candidate;
    highlighted_text = contrastingTextColor(
        highlighted_top,
        VSTGUI::kBlackCColor,
        VSTGUI::kWhiteCColor
    );
    normal_frame = description.role == ZIG_VSTGUI_ACTION_DESTRUCTIVE
        ? VSTGUI::CColor(196, 72, 72, 255)
        : description.role == ZIG_VSTGUI_ACTION_PRIMARY ? style.accent : style.border;
    highlighted_frame = pressed.border;
    disabled_text = colors.text_secondary;
    disabled_frame = colors.control_track;
    disabled_background = colors.surface_raised;
    button->setFont(styles.font(TypographyRole::body));
    button->setFrameWidth(style.frame_width);
    button->setRoundRadius(style.radius);
    if (!tooltip.empty()) button->setTooltipText(tooltip.c_str());
    parent->addView(button);
    button->registerViewListener(this);

    component.bind(button);
    component.setEnabled(description.enabled != 0);
    applyStyle();
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
    applyStyle();
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

VSTGUI::CRect ActionButtonControl::bounds() const {
    return button ? button->getViewSize() : VSTGUI::CRect();
}

void ActionButtonControl::setFocusedView(VSTGUI::CView* view) {
    component.setFocused(view && view == button);
}

const AccessibilityNode& ActionButtonControl::accessibilityNode() const {
    return component.accessibility();
}

void ActionButtonControl::valueChanged(VSTGUI::CControl* control) {
    if (!control || control->getValue() != control->getMax()) return;
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

void ActionButtonControl::applyStyle() {
    if (!button) return;
    const bool is_enabled = component.state().enabled;
    button->setTextColor(is_enabled ? normal_text : disabled_text);
    button->setTextColorHighlighted(is_enabled ? highlighted_text : disabled_text);
    button->setFrameColor(is_enabled ? normal_frame : disabled_frame);
    button->setFrameColorHighlighted(is_enabled ? highlighted_frame : disabled_frame);
    button->setGradient(VSTGUI::owned(VSTGUI::CGradient::create(
        0, 1,
        is_enabled ? normal_top : disabled_background,
        is_enabled ? normal_bottom : disabled_background
    )));
    button->setGradientHighlighted(VSTGUI::owned(VSTGUI::CGradient::create(
        0, 1,
        is_enabled ? highlighted_top : disabled_background,
        is_enabled ? highlighted_bottom : disabled_background
    )));
    button->setAlphaValue(is_enabled ? 1.f : disabled_alpha);
    button->invalid();
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
