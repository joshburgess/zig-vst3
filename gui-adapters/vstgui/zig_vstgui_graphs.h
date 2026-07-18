#ifndef ZIG_VSTGUI_GRAPHS_H
#define ZIG_VSTGUI_GRAPHS_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_viewport.h"
#include "zig_vstgui_xy_pad.h"

#include "vstgui/lib/cvstguitimer.h"
#include "vstgui/lib/controls/ctextlabel.h"
#include "vstgui/lib/iviewlistener.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

namespace ZigVstgui {

class GraphView final : public VSTGUI::CView {
public:
    GraphView(
        const VSTGUI::CRect& size,
        const ZigVstguiGraphDescription& description,
        const ThemeResolver& styles,
        AccessibilityNode* accessibility,
        ZigVstguiCallbacks parameter_callbacks = {}
    );

    bool valid() const;
    bool setPoints(const ZigVstguiGraphPoint* points, uint32_t count);
    uint32_t pointCount() const;
    bool editable() const;
    bool transactionActive() const;
    bool beginTransaction();
    void finishTransaction();
    void cancelTransaction();
    bool selectPoint(uint32_t point_id);
    bool selectAdjacent(bool next);
    bool selectedPoint(ZigVstguiEnvelopePoint& point) const;
    bool addPoint(double x, double y);
    bool moveSelected(double x, double y);
    bool adjustSelected(double x_delta, double y_delta);
    bool deleteSelected();
    bool setParameter(uint32_t parameter_id, double normalized);
    bool viewportEnabled() const;
    double viewportZoom() const;
    double viewportXOffset() const;
    double viewportYOffset() const;
    bool zoomViewportIn(double anchor_x = 0.5, double anchor_y = 0.5);
    bool zoomViewportOut(double anchor_x = 0.5, double anchor_y = 0.5);
    bool setViewportZoom(double zoom, double anchor_x = 0.5, double anchor_y = 0.5);
    bool panViewport(double x_steps, double y_steps);
    bool resetViewport();
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) override;
    void onMouseUpEvent(VSTGUI::MouseUpEvent& event) override;
    void onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) override;
    void onMouseWheelEvent(VSTGUI::MouseWheelEvent& event) override;
    void onZoomGestureEvent(VSTGUI::ZoomGestureEvent& event) override;
    void onKeyboardEvent(VSTGUI::KeyboardEvent& event) override;
    CLASS_METHODS_NOCOPY(GraphView, VSTGUI::CView)

private:
    struct PointState {
        uint32_t id {0};
        ZigVstguiGraphPoint position {};
        uint32_t x_parameter_id {0};
        uint32_t y_parameter_id {0};
        uint32_t parameter_mask {0};
        std::shared_ptr<MultiParameterControlModel> parameter_model;
    };

    double normalize(double value, const ZigVstguiGraphAxis& axis) const;
    double denormalize(double value, const ZigVstguiGraphAxis& axis) const;
    double snap(double value, const ZigVstguiGraphAxis& axis, double step) const;
    VSTGUI::CPoint viewPoint(const ZigVstguiGraphPoint& point) const;
    ZigVstguiGraphPoint graphPoint(const VSTGUI::CPoint& point) const;
    std::optional<std::size_t> indexOf(uint32_t point_id) const;
    std::optional<std::size_t> hitTestPoint(const VSTGUI::CPoint& point) const;
    VSTGUI::CRect affectedBounds(const std::vector<PointState>& values, std::size_t index) const;
    VSTGUI::CRect contentBounds(const std::vector<PointState>& values) const;
    void invalidateChange(const std::vector<PointState>& before, std::size_t before_index, std::size_t after_index);
    void syncAccessibility();
    void persistSelection();
    void persistEnvelope();
    bool persistViewport(const ViewportModel& previous);
    void drawViewportOverlay(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds);
    uint32_t allocatePointId();

    ZigVstguiGraphDescription description;
    const ThemeResolver& styles;
    AccessibilityNode* accessibility;
    ZigVstguiCallbacks parameter_callbacks {};
    std::vector<PointState> points;
    std::vector<PointState> transaction_points;
    std::optional<uint32_t> selected_id;
    std::optional<uint32_t> transaction_selected_id;
    uint32_t next_point_id {1};
    uint32_t transaction_next_point_id {1};
    bool transaction_active {false};
    bool dragging {false};
    bool valid_description {false};
    ViewportModel viewport;
};

class GraphControl final : public VSTGUI::ViewListenerAdapter {
public:
    ~GraphControl();
    bool build(
        VSTGUI::CViewContainer* parent,
        const ZigVstguiGraphDescription& description,
        ZigVstguiGraphCallbacks callbacks,
        ZigVstguiCallbacks parameter_callbacks,
        const ThemeResolver& styles
    );
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& graph_bounds);
    void start();
    void stop();
    bool running() const;
    bool refresh();
    bool setParameter(uint32_t parameter_id, double normalized);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    VSTGUI::CView* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    GraphView* graphView();
    const GraphView* graphView() const;
    const AccessibilityNode& accessibilityNode() const;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(
        void* userdata,
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool performAccessibilityAction(const AccessibilityActionRequest& request);

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
