#ifndef ZIG_VSTGUI_PRESET_BROWSER_H
#define ZIG_VSTGUI_PRESET_BROWSER_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cview.h"
#include "vstgui/lib/iviewlistener.h"

#include <optional>
#include <array>
#include <string>
#include <vector>

namespace ZigVstgui {

class PresetBrowserView final : public VSTGUI::CView {
public:
    PresetBrowserView(
        const VSTGUI::CRect& size,
        const ZigVstguiPresetBrowserDescription& description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles,
        AccessibilityNode* accessibility
    );

    bool valid() const;
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    uint32_t selectedPreset() const;
    const std::string& searchText() const;
    const std::string& statusText() const;
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onKeyboardEvent(VSTGUI::KeyboardEvent& event) override;
    CLASS_METHODS_NOCOPY(PresetBrowserView, VSTGUI::CView)

private:
    struct PresetEntry {
        uint32_t id;
        std::string name;
    };

    struct MatchList {
        std::array<std::size_t, ZIG_VSTGUI_MAX_PRESETS> indices {};
        std::size_t count {0};
    };

    MatchList matches() const;
    bool selectRelative(bool next);
    bool selectBoundary(bool last);
    bool activate();
    void replaceSearch(std::string value);
    void ensureVisibleSelection();
    void ensureSelectionInViewport(const MatchList& visible);
    void persistSearch();
    void persistSelection();
    void syncAccessibility();
    void syncHeader();
    static bool accessibilityAction(
        void* userdata,
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool performAccessibilityAction(const AccessibilityActionRequest& request);

    std::string title;
    std::vector<PresetEntry> presets;
    std::string search;
    std::string header;
    std::optional<std::size_t> selected;
    std::size_t first_visible {0};
    std::string status;
    ZigVstguiCallbacks callbacks {};
    const ThemeResolver& styles;
    AccessibilityNode* accessibility {nullptr};
    uint32_t search_state_id {0};
    uint32_t selection_state_id {0};
    bool valid_description {false};
};

class PresetBrowserControl final : public VSTGUI::ViewListenerAdapter {
public:
    bool build(
        VSTGUI::CViewContainer* parent,
        const ZigVstguiPresetBrowserDescription& description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles
    );
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    VSTGUI::CView* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& accessibilityNode() const;
    PresetBrowserView* browserView();
    const PresetBrowserView* browserView() const;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    PresetBrowserView* browser {nullptr};
    Component component;
};

}

#endif
