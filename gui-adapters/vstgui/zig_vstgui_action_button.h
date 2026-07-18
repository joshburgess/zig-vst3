#ifndef ZIG_VSTGUI_ACTION_BUTTON_H
#define ZIG_VSTGUI_ACTION_BUTTON_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/controls/cbuttons.h"
#include "vstgui/lib/controls/icontrollistener.h"
#include "vstgui/lib/iviewlistener.h"

#include <string>

namespace ZigVstgui {

class ActionButtonControl final : public VSTGUI::IControlListener, public VSTGUI::ViewListenerAdapter {
public:
    bool build(
        VSTGUI::CViewContainer* parent,
        const ZigVstguiActionButtonDescription& description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles
    );
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    bool activate();
    bool cancelPending();
    bool confirming() const;
    bool failed() const;
    VSTGUI::CView* focusView() const;
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
    void syncState();

    ZigVstguiActionButtonDescription description {};
    ZigVstguiCallbacks callbacks {};
    std::string label;
    std::string accessible_label;
    std::string tooltip;
    std::string confirmation_label;
    std::string failure_label;
    std::string idle_text;
    VSTGUI::CTextButton* button {nullptr};
    Component component;
    bool confirmation_pending {false};
    bool action_failed {false};
};

}

#endif
