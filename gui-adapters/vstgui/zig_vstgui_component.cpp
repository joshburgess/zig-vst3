#include "zig_vstgui_component.h"

#include <algorithm>
#include <chrono>

namespace ZigVstgui {

VisualState ComponentState::visualState() const {
    if (!enabled) return VisualState::disabled;
    if (editing) return VisualState::editing;
    if (pressed) return VisualState::pressed;
    if (hovered) return VisualState::hovered;
    if (focused) return VisualState::focused;
    return VisualState::normal;
}

Component::Component(VSTGUI::CView* value_view) {
    bind(value_view);
}

void Component::bind(VSTGUI::CView* value_view) {
    bound_view = value_view;
    applyState();
}

void Component::clear() {
    bound_view = nullptr;
}

void Component::setBounds(const VSTGUI::CRect& bounds) {
    if (bound_view) bound_view->setViewSize(bounds, true);
}

void Component::setVisible(bool visible) {
    component_state.visible = visible;
    applyState();
}

void Component::setEnabled(bool enabled) {
    component_state.enabled = enabled;
    accessibility_node.setEnabled(enabled);
    applyState();
}

void Component::setFocusable(bool focusable) {
    component_state.focusable = focusable;
    applyState();
}

void Component::setFocused(bool focused) {
    component_state.focused = focused;
    accessibility_node.setFocused(focused);
    invalidate();
}

void Component::setHovered(bool hovered) {
    component_state.hovered = hovered;
    invalidate();
}

void Component::setPressed(bool pressed) {
    component_state.pressed = pressed;
    invalidate();
}

void Component::setEditing(bool editing) {
    component_state.editing = editing;
    invalidate();
}

AccessibilityNode& Component::accessibility() {
    return accessibility_node;
}

const AccessibilityNode& Component::accessibility() const {
    return accessibility_node;
}

void Component::invalidate() {
    if (bound_view) bound_view->invalid();
}

VSTGUI::CView* Component::view() const {
    return bound_view;
}

const ComponentState& Component::state() const {
    return component_state;
}

void Component::applyState() {
    if (!bound_view) return;
    bound_view->setVisible(component_state.visible);
    bound_view->setMouseEnabled(component_state.enabled);
    bound_view->setWantsFocus(component_state.focusable && component_state.enabled);
    bound_view->invalid();
}

ProfiledContainer::ProfiledContainer(const VSTGUI::CRect& size, RenderMetrics* value_metrics)
: CViewContainer(size), metrics(value_metrics) {}

void ProfiledContainer::drawRect(VSTGUI::CDrawContext* context, const VSTGUI::CRect& update_rect) {
    if (!metrics) {
        CViewContainer::drawRect(context, update_rect);
        return;
    }
    const auto start = std::chrono::steady_clock::now();
    CViewContainer::drawRect(context, update_rect);
    const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now() - start
    ).count();
    const auto elapsed_ns = static_cast<uint64_t>(std::max<int64_t>(elapsed, 0));
    metrics->draw_count += 1;
    metrics->draw_total_ns += elapsed_ns;
    metrics->draw_max_ns = std::max(metrics->draw_max_ns, elapsed_ns);
    metrics->invalidated_area += std::max(0.0, update_rect.getWidth()) * std::max(0.0, update_rect.getHeight());
}

}
