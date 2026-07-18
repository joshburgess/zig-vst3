#ifndef ZIG_VSTGUI_ACTION_MENU_H
#define ZIG_VSTGUI_ACTION_MENU_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/controls/cbuttons.h"
#include "vstgui/lib/controls/icontrollistener.h"
#include "vstgui/lib/iviewlistener.h"

#include <array>
#include <optional>
#include <string>

namespace ZigVstgui {

class ActionMenuControl;

class ActionMenuView final : public VSTGUI::CView {
public:
    ActionMenuView(
        const ZigVstguiActionMenuDescription& description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles,
        AccessibilityNode* accessibility,
        ActionMenuControl* owner
    );

    bool valid() const;
    void open();
    void close(bool restore_focus);
    bool isOpen() const;
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    void setLayout(const VSTGUI::CRect& editor_bounds, const VSTGUI::CRect& anchor_bounds);
    uint32_t selectedItem() const;
    bool itemChecked(uint32_t item_id) const;
    const std::string& statusText() const;
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onKeyboardEvent(VSTGUI::KeyboardEvent& event) override;
    CLASS_METHODS_NOCOPY(ActionMenuView, VSTGUI::CView)

private:
    struct Entry {
        uint32_t id {0};
        std::string label;
        std::string display_unchecked;
        std::string display_checked;
        ZigVstguiMenuItemKind kind {ZIG_VSTGUI_MENU_ACTION};
        bool enabled {false};
        bool destructive {false};
        uint32_t checked_state_id {0};
        bool checked {false};
    };

    bool selectRelative(bool next);
    bool selectBoundary(bool last);
    bool activateSelected();
    bool selectable(std::size_t index) const;
    std::optional<std::size_t> rowAt(double y) const;
    void syncAccessibility();
    void updateLayout();

    std::string title;
    std::array<Entry, ZIG_VSTGUI_MAX_MENU_ITEMS> entries;
    uint32_t entry_count {0};
    uint32_t menu_id {0};
    ZigVstguiCallbacks callbacks {};
    const ThemeResolver& styles;
    AccessibilityNode* accessibility {nullptr};
    ActionMenuControl* owner {nullptr};
    VSTGUI::CRect panel_bounds;
    VSTGUI::CRect editor_bounds;
    VSTGUI::CRect anchor_bounds;
    double rows_height {0.0};
    double visible_rows_height {0.0};
    double content_scroll {0.0};
    std::optional<std::size_t> selected;
    std::string status;
    bool valid_description {false};
    bool open_state {false};
};

class ActionMenuControl final : public VSTGUI::IControlListener, public VSTGUI::ViewListenerAdapter {
public:
    using WillOpenCallback = void (*)(void*, ActionMenuControl*);

    bool build(
        VSTGUI::CViewContainer* parent,
        const ZigVstguiActionMenuDescription& description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles
    );
    void clear();
    void setBounds(const VSTGUI::CRect& trigger_bounds, const VSTGUI::CRect& editor_bounds);
    void setOpenCoordinator(void* userdata, WillOpenCallback callback);
    void close(bool restore_focus);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    VSTGUI::CView* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& accessibilityNode() const;
    ActionMenuView* menuView();
    const ActionMenuView* menuView() const;
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
    void open();

    VSTGUI::CTextButton* trigger {nullptr};
    ActionMenuView* menu {nullptr};
    Component component;
    void* coordinator_userdata {nullptr};
    WillOpenCallback will_open {nullptr};
};

}

#endif
