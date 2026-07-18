#ifndef ZIG_VSTGUI_GRAPHS_H
#define ZIG_VSTGUI_GRAPHS_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"

#include "vstgui/lib/cvstguitimer.h"
#include "vstgui/lib/controls/ctextlabel.h"

#include <cstdint>
#include <vector>

namespace ZigVstgui {

class GraphView final : public VSTGUI::CView {
public:
    GraphView(
        const VSTGUI::CRect& size,
        const ZigVstguiGraphDescription& description,
        const ThemeResolver& styles,
        AccessibilityNode* accessibility
    );

    bool valid() const;
    bool setPoints(const ZigVstguiGraphPoint* points, uint32_t count);
    uint32_t pointCount() const;
    void draw(VSTGUI::CDrawContext* context) override;
    CLASS_METHODS_NOCOPY(GraphView, VSTGUI::CView)

private:
    double normalize(double value, const ZigVstguiGraphAxis& axis) const;

    ZigVstguiGraphDescription description;
    const ThemeResolver& styles;
    AccessibilityNode* accessibility;
    std::vector<ZigVstguiGraphPoint> points;
    bool valid_description {false};
};

class GraphControl {
public:
    ~GraphControl();
    bool build(
        VSTGUI::CViewContainer* parent,
        const ZigVstguiGraphDescription& description,
        ZigVstguiGraphCallbacks callbacks,
        const ThemeResolver& styles
    );
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& graph_bounds);
    void start();
    void stop();
    bool running() const;
    bool refresh();
    const GraphView* graphView() const;
    const AccessibilityNode& accessibilityNode() const;

private:
    VSTGUI::CTextLabel* label {nullptr};
    GraphView* graph {nullptr};
    VSTGUI::CVSTGUITimer* timer {nullptr};
    Component label_component;
    Component graph_component;
    ZigVstguiGraphDescription description {};
    ZigVstguiGraphCallbacks callbacks {};
    bool active {false};
};

}

#endif
