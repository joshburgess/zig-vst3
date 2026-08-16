#include "zig_vstgui_viewport.h"

#include <algorithm>
#include <cmath>

namespace ZigVstgui {

bool ViewportModel::configure(const ZigVstguiViewportDescription& description) {
    config = description;
    valid = config.enabled == 0;
    current_zoom = 1.0;
    x_offset = 0.0;
    y_offset = 0.0;
    if (config.enabled == 0) return true;
    if (config.enabled != 1 || config.axes < ZIG_VSTGUI_VIEWPORT_HORIZONTAL ||
        config.axes > ZIG_VSTGUI_VIEWPORT_BOTH || !std::isfinite(config.minimum_zoom) ||
        !std::isfinite(config.maximum_zoom) || config.minimum_zoom < 1.0 ||
        config.maximum_zoom < config.minimum_zoom || config.maximum_zoom > 128.0 ||
        !std::isfinite(config.initial_zoom) || config.initial_zoom < config.minimum_zoom ||
        config.initial_zoom > config.maximum_zoom || !std::isfinite(config.zoom_step) ||
        config.zoom_step <= 1.0 || config.zoom_step > 4.0 || !std::isfinite(config.scroll_step) ||
        config.scroll_step <= 0.0 || config.scroll_step > 1.0) return false;
    current_zoom = config.initial_zoom;
    const double maximum = maximumOffset();
    const bool has_horizontal = config.axes != ZIG_VSTGUI_VIEWPORT_VERTICAL;
    const bool has_vertical = config.axes != ZIG_VSTGUI_VIEWPORT_HORIZONTAL;
    if (!std::isfinite(config.initial_x_offset) || !std::isfinite(config.initial_y_offset) ||
        config.initial_x_offset < 0.0 || config.initial_y_offset < 0.0 ||
        config.initial_x_offset > maximum || config.initial_y_offset > maximum ||
        (!has_horizontal && config.initial_x_offset != 0.0) ||
        (!has_vertical && config.initial_y_offset != 0.0)) return false;
    x_offset = config.initial_x_offset;
    y_offset = config.initial_y_offset;
    valid = true;
    return true;
}

bool ViewportModel::enabled() const { return valid && config.enabled != 0; }
bool ViewportModel::horizontal() const {
    return enabled() && config.axes != ZIG_VSTGUI_VIEWPORT_VERTICAL;
}
bool ViewportModel::vertical() const {
    return enabled() && config.axes != ZIG_VSTGUI_VIEWPORT_HORIZONTAL;
}
double ViewportModel::zoom() const { return current_zoom; }
double ViewportModel::xOffset() const { return x_offset; }
double ViewportModel::yOffset() const { return y_offset; }

double ViewportModel::visibleSpan(bool active) const {
    return active ? 1.0 / current_zoom : 1.0;
}

double ViewportModel::maximumOffset() const { return 1.0 - 1.0 / current_zoom; }

double ViewportModel::projectX(double normalized) const {
    return (normalized - x_offset) / visibleSpan(horizontal());
}

double ViewportModel::projectY(double normalized) const {
    return (normalized - y_offset) / visibleSpan(vertical());
}

double ViewportModel::unprojectX(double visible) const {
    return x_offset + visible * visibleSpan(horizontal());
}

double ViewportModel::unprojectY(double visible) const {
    return y_offset + visible * visibleSpan(vertical());
}

bool ViewportModel::zoomIn(double anchor_x, double anchor_y) {
    return setZoom(current_zoom * config.zoom_step, anchor_x, anchor_y);
}

bool ViewportModel::zoomOut(double anchor_x, double anchor_y) {
    return setZoom(current_zoom / config.zoom_step, anchor_x, anchor_y);
}

bool ViewportModel::setZoom(double value, double anchor_x, double anchor_y) {
    if (!enabled() || !std::isfinite(value) ||
        !std::isfinite(anchor_x) || !std::isfinite(anchor_y)) return false;
    const double next = std::clamp(value, config.minimum_zoom, config.maximum_zoom);
    if (next == current_zoom) return false;
    const double old_span = 1.0 / current_zoom;
    const double new_span = 1.0 / next;
    if (horizontal()) {
        const double anchor = std::clamp(anchor_x, 0.0, 1.0);
        const double content_anchor = x_offset + anchor * old_span;
        x_offset = std::clamp(content_anchor - anchor * new_span, 0.0, 1.0 - new_span);
    }
    if (vertical()) {
        const double anchor = std::clamp(anchor_y, 0.0, 1.0);
        const double content_anchor = y_offset + anchor * old_span;
        y_offset = std::clamp(content_anchor - anchor * new_span, 0.0, 1.0 - new_span);
    }
    current_zoom = next;
    return true;
}

bool ViewportModel::pan(double x_steps, double y_steps) {
    if (!enabled()) return false;
    bool changed = false;
    const double span = 1.0 / current_zoom;
    if (horizontal() && std::isfinite(x_steps)) {
        const double next = std::clamp(x_offset + x_steps * span * config.scroll_step, 0.0, 1.0 - span);
        changed = next != x_offset;
        x_offset = next;
    }
    if (vertical() && std::isfinite(y_steps)) {
        const double next = std::clamp(y_offset + y_steps * span * config.scroll_step, 0.0, 1.0 - span);
        changed = changed || next != y_offset;
        y_offset = next;
    }
    return changed;
}

bool ViewportModel::panToStart(bool horizontal_axis) {
    if ((horizontal_axis && !horizontal()) || (!horizontal_axis && !vertical())) return false;
    double& offset = horizontal_axis ? x_offset : y_offset;
    if (offset == 0.0) return false;
    offset = 0.0;
    return true;
}

bool ViewportModel::panToEnd(bool horizontal_axis) {
    if ((horizontal_axis && !horizontal()) || (!horizontal_axis && !vertical())) return false;
    double& offset = horizontal_axis ? x_offset : y_offset;
    const double next = maximumOffset();
    if (offset == next) return false;
    offset = next;
    return true;
}

bool ViewportModel::reset() {
    if (!enabled() || (current_zoom == config.initial_zoom && x_offset == config.initial_x_offset &&
        y_offset == config.initial_y_offset)) return false;
    current_zoom = config.initial_zoom;
    x_offset = config.initial_x_offset;
    y_offset = config.initial_y_offset;
    return true;
}

const ZigVstguiViewportDescription& ViewportModel::description() const { return config; }

}
