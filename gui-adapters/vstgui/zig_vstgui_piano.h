#ifndef ZIG_VSTGUI_PIANO_H
#define ZIG_VSTGUI_PIANO_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cview.h"
#include "vstgui/lib/iviewlistener.h"
#include "vstgui/lib/controls/ctextlabel.h"

#include <array>
#include <string>

namespace ZigVstgui {

class PianoControl;

class PianoView final : public VSTGUI::CView {
public:
    PianoView(const VSTGUI::CRect& size, PianoControl* owner, const ThemeResolver& styles);
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) override;
    void onMouseUpEvent(VSTGUI::MouseUpEvent& event) override;
    void onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) override;
    void onMouseEnterEvent(VSTGUI::MouseEnterEvent& event) override;
    void onMouseExitEvent(VSTGUI::MouseExitEvent& event) override;
    CLASS_METHODS_NOCOPY(PianoView, VSTGUI::CView)

private:
    PianoControl* owner;
    const ThemeResolver& styles;
    bool hovered {false};
};

class PianoControl final : public VSTGUI::ViewListenerAdapter {
public:
    PianoControl(ZigVstguiPianoDescription description, ZigVstguiCallbacks callbacks);
    ~PianoControl() override;

    void build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& keyboard_bounds);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers, bool pressed);
    void releaseAll();
    VSTGUI::CView* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& accessibilityNode() const;

    int hitTest(const VSTGUI::CPoint& position) const;
    bool notePressed(uint32_t pitch) const;
    uint32_t selectedNote() const;
    uint32_t firstNote() const;
    uint32_t noteCount() const;
    void pointerPress(uint32_t pitch, double velocity);
    void pointerRelease();

    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(void* userdata, const AccessibilityNode&, const AccessibilityActionRequest& request);
    bool performAccessibilityAction(const AccessibilityActionRequest& request);
    bool press(uint32_t pitch, double velocity);
    bool release(uint32_t pitch);
    void select(uint32_t pitch);
    void syncAccessibility();
    static int computerOffset(uint16_t key);

    ZigVstguiPianoDescription description {};
    ZigVstguiCallbacks callbacks {};
    std::string title;
    VSTGUI::CTextLabel* label {nullptr};
    PianoView* keyboard {nullptr};
    Component label_component;
    Component keyboard_component;
    std::array<bool, 128> active {};
    std::array<int16_t, 256> key_notes {};
    int pointer_note {-1};
    uint32_t selected_note {0};
};

}

#endif
