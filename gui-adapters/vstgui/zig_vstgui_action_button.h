#ifndef ZIG_VSTGUI_ACTION_BUTTON_H
#define ZIG_VSTGUI_ACTION_BUTTON_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/controls/cbuttons.h"
#include "vstgui/lib/controls/icontrollistener.h"
#include "vstgui/lib/iviewlistener.h"

#include <string>
#include <functional>

namespace ZigVstgui {

class ActionButtonControl final : public VSTGUI::IControlListener, public VSTGUI::ViewListenerAdapter {
public:
    bool build(
        VSTGUI::CViewContainer* parent,
        const ZigVstguiActionButtonDescription& description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles,
        std::function<void(uint32_t)> accepted_handler = {}
    );
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    void setEnabled(bool enabled);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    bool activate();
    bool cancelPending();
    bool confirming() const;
    bool failed() const;
    bool enabled() const;
    VSTGUI::CView* focusView() const;
    VSTGUI::CRect bounds() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& accessibilityNode() const;

    void valueChanged(VSTGUI::CControl* control) override;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(
        void* userdata,
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool performAccessibilityAction(const AccessibilityActionRequest& request);
    void applyStyle();
    void syncState();

    ZigVstguiActionButtonDescription description {};
    ZigVstguiCallbacks callbacks {};
    std::string label;
    std::string accessible_label;
    std::string tooltip;
    std::string confirmation_label;
    std::string failure_label;
    std::string idle_text;
    std::function<void(uint32_t)> accepted_handler;
    VSTGUI::CTextButton* button {nullptr};
    Component component;
    VSTGUI::CColor normal_text;
    VSTGUI::CColor highlighted_text;
    VSTGUI::CColor normal_frame;
    VSTGUI::CColor highlighted_frame;
    VSTGUI::CColor normal_top;
    VSTGUI::CColor normal_bottom;
    VSTGUI::CColor highlighted_top;
    VSTGUI::CColor highlighted_bottom;
    VSTGUI::CColor disabled_text;
    VSTGUI::CColor disabled_frame;
    VSTGUI::CColor disabled_background;
    float disabled_alpha {1.f};
    bool confirmation_pending {false};
    bool action_failed {false};
};

}

#endif
