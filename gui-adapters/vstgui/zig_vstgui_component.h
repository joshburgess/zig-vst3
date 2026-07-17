#ifndef ZIG_VSTGUI_COMPONENT_H
#define ZIG_VSTGUI_COMPONENT_H

#include "vstgui/lib/cviewcontainer.h"

#include <cstdint>

namespace ZigVstgui {

enum class VisualState {
    normal,
    hovered,
    pressed,
    focused,
    disabled,
    editing,
};

struct ComponentState {
    bool visible {true};
    bool enabled {true};
    bool focusable {false};
    bool focused {false};
    bool hovered {false};
    bool pressed {false};
    bool editing {false};

    VisualState visualState() const;
};

class Component {
public:
    Component() = default;
    explicit Component(VSTGUI::CView* value_view);

    void bind(VSTGUI::CView* value_view);
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    void setVisible(bool visible);
    void setEnabled(bool enabled);
    void setFocusable(bool focusable);
    void setFocused(bool focused);
    void setHovered(bool hovered);
    void setPressed(bool pressed);
    void setEditing(bool editing);
    void invalidate();

    VSTGUI::CView* view() const;
    const ComponentState& state() const;

private:
    void applyState();

    VSTGUI::CView* bound_view {nullptr};
    ComponentState component_state {};
};

struct RenderMetrics {
    uint64_t draw_count {0};
    uint64_t draw_total_ns {0};
    uint64_t draw_max_ns {0};
    double invalidated_area {0.0};
    uint64_t open_count {0};
    uint64_t close_count {0};
    uint64_t resize_count {0};
    uint64_t scale_count {0};
    uint64_t parameter_update_count {0};
};

class ProfiledContainer final : public VSTGUI::CViewContainer {
public:
    ProfiledContainer(const VSTGUI::CRect& size, RenderMetrics* metrics);
    void drawRect(VSTGUI::CDrawContext* context, const VSTGUI::CRect& update_rect) override;

private:
    RenderMetrics* metrics;
};

}

#endif
