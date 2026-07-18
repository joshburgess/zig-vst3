#ifndef ZIG_VSTGUI_TEXT_PROGRESS_H
#define ZIG_VSTGUI_TEXT_PROGRESS_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"

#include "vstgui/lib/controls/ctextedit.h"
#include "vstgui/lib/controls/ctextlabel.h"
#include "vstgui/lib/controls/icontrollistener.h"
#include "vstgui/lib/cvstguitimer.h"
#include "vstgui/lib/iviewlistener.h"

#include <string>

namespace ZigVstgui {

class EditableLabelControl final : public VSTGUI::IControlListener, public VSTGUI::ViewListenerAdapter {
public:
    ~EditableLabelControl();
    bool build(VSTGUI::CViewContainer* parent, const ZigVstguiEditableLabelDescription& description,
        ZigVstguiCallbacks callbacks, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& edit_bounds,
        const VSTGUI::CRect& message_bounds);
    void start();
    void stop();
    bool refresh();
    bool handleKey(uint16_t key, int16_t key_code);
    VSTGUI::CView* focusView() const;
    VSTGUI::CView* accessibilityView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& accessibilityNode() const;

    void valueChanged(VSTGUI::CControl* control) override;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(void* userdata, const AccessibilityNode& node,
        const AccessibilityActionRequest& request);
    bool commit(const char* text);
    void showError(bool visible);

    ZigVstguiEditableLabelDescription description {};
    ZigVstguiCallbacks callbacks {};
    std::string accepted_text;
    std::string error_text;
    VSTGUI::CTextLabel* label {nullptr};
    VSTGUI::CTextEdit* edit {nullptr};
    VSTGUI::CTextLabel* message {nullptr};
    VSTGUI::CVSTGUITimer* timer {nullptr};
    Component label_component;
    Component edit_component;
    Component message_component;
};

class ProgressView final : public VSTGUI::CView {
public:
    ProgressView(const VSTGUI::CRect& size, const ZigVstguiProgressIndicatorDescription& description,
        ZigVstguiCallbacks callbacks, const ThemeResolver& styles, AccessibilityNode* accessibility);
    bool tick();
    void draw(VSTGUI::CDrawContext* context) override;
    const ZigVstguiProgressSnapshot& snapshot() const;
    CLASS_METHODS_NOCOPY(ProgressView, VSTGUI::CView)

private:
    void updateAccessibility();
    const char* stateText() const;

    ZigVstguiProgressIndicatorDescription description {};
    ZigVstguiCallbacks callbacks {};
    const ThemeResolver& styles;
    AccessibilityNode* accessibility;
    ZigVstguiProgressSnapshot current {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_IDLE, 0.0, 0};
    double phase {0.0};
    bool initialized {false};
};

class ProgressIndicatorControl {
public:
    ~ProgressIndicatorControl();
    bool build(VSTGUI::CViewContainer* parent, const ZigVstguiProgressIndicatorDescription& description,
        ZigVstguiCallbacks callbacks, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& progress_bounds);
    void start();
    void stop();
    bool running() const;
    bool tick();
    const AccessibilityNode& accessibilityNode() const;
    VSTGUI::CView* accessibilityView() const;
    const ProgressView* progressView() const;

private:
    VSTGUI::CTextLabel* label {nullptr};
    ProgressView* progress {nullptr};
    VSTGUI::CVSTGUITimer* timer {nullptr};
    Component label_component;
    Component progress_component;
    bool active {false};
};

}

#endif
