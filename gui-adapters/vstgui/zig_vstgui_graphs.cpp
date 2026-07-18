#include "zig_vstgui_graphs.h"

#include "vstgui/lib/cdrawcontext.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

namespace ZigVstgui {

namespace {

bool validAxis(const ZigVstguiGraphAxis& axis) {
    if (!std::isfinite(axis.minimum) || !std::isfinite(axis.maximum) || axis.maximum <= axis.minimum) return false;
    if (axis.scale < ZIG_VSTGUI_GRAPH_LINEAR || axis.scale > ZIG_VSTGUI_GRAPH_DECIBELS) return false;
    return axis.scale != ZIG_VSTGUI_GRAPH_LOGARITHMIC || axis.minimum > 0.0;
}

bool samePoints(const std::vector<ZigVstguiGraphPoint>& current, const ZigVstguiGraphPoint* next, uint32_t count) {
    if (current.size() != count) return false;
    for (uint32_t index = 0; index < count; ++index) {
        if (current[index].x != next[index].x || current[index].y != next[index].y) return false;
    }
    return true;
}

}

GraphView::GraphView(
    const VSTGUI::CRect& size,
    const ZigVstguiGraphDescription& value_description,
    const ThemeResolver& value_styles,
    AccessibilityNode* value_accessibility
)
: CView(size),
  description(value_description),
  styles(value_styles),
  accessibility(value_accessibility) {
    valid_description = description.title && validAxis(description.x_axis) && validAxis(description.y_axis) &&
        description.kind >= ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION && description.kind <= ZIG_VSTGUI_GRAPH_SPECTRUM &&
        description.style >= ZIG_VSTGUI_GRAPH_PRIMARY && description.style <= ZIG_VSTGUI_GRAPH_WARNING;
    if (valid_description && !description.dynamic) {
        if (description.point_count > ZIG_VSTGUI_MAX_GRAPH_POINTS ||
            (description.point_count > 0 && !description.points)) {
            valid_description = false;
        } else {
            for (uint32_t index = 0; index < description.point_count; ++index) {
                if (!std::isfinite(description.points[index].x) || !std::isfinite(description.points[index].y)) {
                    valid_description = false;
                    break;
                }
            }
            if (valid_description && description.point_count > 0) {
                points.assign(description.points, description.points + description.point_count);
            }
        }
    }
    if (valid_description && accessibility) {
        char text[64] {};
        std::snprintf(text, sizeof(text), "%u points", static_cast<uint32_t>(points.size()));
        accessibility->setValueText(text);
    }
}

bool GraphView::valid() const {
    return valid_description;
}

bool GraphView::setPoints(const ZigVstguiGraphPoint* next, uint32_t count) {
    if (count > ZIG_VSTGUI_MAX_GRAPH_POINTS || (count > 0 && !next)) return false;
    for (uint32_t index = 0; index < count; ++index) {
        if (!std::isfinite(next[index].x) || !std::isfinite(next[index].y)) return false;
    }
    if (samePoints(points, next, count)) return false;
    points.assign(next, next + count);
    if (accessibility) {
        char text[64] {};
        std::snprintf(text, sizeof(text), "%u points", count);
        accessibility->setValueText(text);
    }
    invalid();
    return true;
}

uint32_t GraphView::pointCount() const {
    return static_cast<uint32_t>(points.size());
}

double GraphView::normalize(double value, const ZigVstguiGraphAxis& axis) const {
    if (axis.scale == ZIG_VSTGUI_GRAPH_LOGARITHMIC) {
        if (value <= 0.0) return 0.0;
        const double low = std::log10(axis.minimum);
        return std::clamp((std::log10(value) - low) / (std::log10(axis.maximum) - low), 0.0, 1.0);
    }
    return std::clamp((value - axis.minimum) / (axis.maximum - axis.minimum), 0.0, 1.0);
}

void GraphView::draw(VSTGUI::CDrawContext* context) {
    const auto bounds = getViewSize();
    const auto style = styles.resolve(ComponentKind::graph);
    context->setFillColor(style.background);
    context->setFrameColor(style.border);
    context->setLineWidth(style.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);

    context->setFrameColor(style.foreground);
    context->setLineWidth(1.0);
    for (uint32_t division = 1; division < 4; ++division) {
        const double x = bounds.left + bounds.getWidth() * division / 4.0;
        const double y = bounds.top + bounds.getHeight() * division / 4.0;
        context->drawLine(VSTGUI::CPoint(x, bounds.top), VSTGUI::CPoint(x, bounds.bottom));
        context->drawLine(VSTGUI::CPoint(bounds.left, y), VSTGUI::CPoint(bounds.right, y));
    }

    if (points.empty()) {
        context->setFont(styles.font(TypographyRole::body));
        context->setFontColor(style.foreground);
        context->drawString("No graph data", bounds, VSTGUI::kCenterText);
        setDirty(false);
        return;
    }

    auto curve_color = style.accent;
    if (description.style == ZIG_VSTGUI_GRAPH_SECONDARY) curve_color = style.border;
    if (description.style == ZIG_VSTGUI_GRAPH_MODULATION) curve_color = style.foreground;
    if (description.style == ZIG_VSTGUI_GRAPH_WARNING) {
        curve_color = styles.resolve(ComponentKind::graph, VisualState::pressed).accent;
    }
    context->setFrameColor(curve_color);
    context->setLineWidth(2.0);
    for (std::size_t index = 1; index < points.size(); ++index) {
        const auto& previous = points[index - 1];
        const auto& current = points[index];
        context->drawLine(
            VSTGUI::CPoint(
                bounds.left + bounds.getWidth() * normalize(previous.x, description.x_axis),
                bounds.bottom - bounds.getHeight() * normalize(previous.y, description.y_axis)
            ),
            VSTGUI::CPoint(
                bounds.left + bounds.getWidth() * normalize(current.x, description.x_axis),
                bounds.bottom - bounds.getHeight() * normalize(current.y, description.y_axis)
            )
        );
    }
    setDirty(false);
}

GraphControl::~GraphControl() {
    stop();
    if (timer) timer->forget();
}

bool GraphControl::build(
    VSTGUI::CViewContainer* parent,
    const ZigVstguiGraphDescription& value_description,
    ZigVstguiGraphCallbacks value_callbacks,
    const ThemeResolver& styles
) {
    if (!parent || label || graph) return false;
    description = value_description;
    callbacks = value_callbacks;
    if (description.dynamic &&
        (!callbacks.load || description.maximum_refresh_hz == 0 || description.maximum_refresh_hz > 60)) return false;
    const auto label_style = styles.resolve(ComponentKind::title);
    label = new VSTGUI::CTextLabel(VSTGUI::CRect(), description.title ? description.title : "Graph");
    label->setFont(styles.font(TypographyRole::body));
    label->setFontColor(label_style.foreground);
    label->setBackColor(label_style.background);
    parent->addView(label);
    label_component.bind(label);
    label_component.accessibility().setRole(AccessibilityRole::group);
    label_component.accessibility().setName(description.title ? description.title : "Graph");
    label_component.accessibility().setReadOnly(true);

    graph_component.accessibility().setRole(AccessibilityRole::graph);
    graph_component.accessibility().setName(description.title ? description.title : "Graph");
    std::string semantic_description = description.dynamic ? "Updating graph" : "Static graph";
    if (description.x_axis.label && description.x_axis.label[0]) semantic_description += ". X: " + std::string(description.x_axis.label);
    if (description.y_axis.label && description.y_axis.label[0]) semantic_description += ". Y: " + std::string(description.y_axis.label);
    graph_component.accessibility().setDescription(semantic_description);
    graph_component.accessibility().setReadOnly(true);
    graph = new GraphView(VSTGUI::CRect(), description, styles, &graph_component.accessibility());
    if (!graph->valid()) {
        graph->forget();
        graph = nullptr;
        label_component.clear();
        parent->removeView(label);
        label = nullptr;
        return false;
    }
    parent->addView(graph);
    graph_component.bind(graph);

    if (description.dynamic) {
        const uint32_t interval = std::max(16u, (1000u + description.maximum_refresh_hz - 1) / description.maximum_refresh_hz);
        timer = new VSTGUI::CVSTGUITimer([this](VSTGUI::CVSTGUITimer*) { refresh(); }, interval, false);
        refresh();
    }
    return true;
}

void GraphControl::clear() {
    stop();
    label_component.clear();
    graph_component.clear();
    label = nullptr;
    graph = nullptr;
}

void GraphControl::setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& graph_bounds) {
    label_component.setBounds(label_bounds);
    graph_component.setBounds(graph_bounds);
}

void GraphControl::start() {
    if (timer && timer->start()) active = true;
}

void GraphControl::stop() {
    if (timer) timer->stop();
    active = false;
}

bool GraphControl::running() const {
    return active;
}

bool GraphControl::refresh() {
    if (!graph || !description.dynamic || !callbacks.load) return false;
    ZigVstguiGraphPoint next[ZIG_VSTGUI_MAX_GRAPH_POINTS] {};
    const uint32_t count = callbacks.load(callbacks.userdata, description.source_id, next, ZIG_VSTGUI_MAX_GRAPH_POINTS);
    if (count > ZIG_VSTGUI_MAX_GRAPH_POINTS) return false;
    return graph->setPoints(next, count);
}

const GraphView* GraphControl::graphView() const {
    return graph;
}

const AccessibilityNode& GraphControl::accessibilityNode() const {
    return graph_component.accessibility();
}

}
