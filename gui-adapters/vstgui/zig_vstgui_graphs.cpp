#include "zig_vstgui_graphs.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cgraphicspath.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <string>

namespace ZigVstgui {

namespace {

bool validAxis(const ZigVstguiGraphAxis& axis) {
    if (!std::isfinite(axis.minimum) || !std::isfinite(axis.maximum) || axis.maximum <= axis.minimum) return false;
    if (axis.scale < ZIG_VSTGUI_GRAPH_LINEAR || axis.scale > ZIG_VSTGUI_GRAPH_DECIBELS) return false;
    return axis.scale != ZIG_VSTGUI_GRAPH_LOGARITHMIC || axis.minimum > 0.0;
}

constexpr uint32_t actionMask(AccessibilityAction action) {
    return static_cast<uint32_t>(action);
}

}

GraphView::GraphView(
    const VSTGUI::CRect& size,
    const ZigVstguiGraphDescription& value_description,
    const ThemeResolver& value_styles,
    AccessibilityNode* value_accessibility,
    ZigVstguiCallbacks value_parameter_callbacks
)
: CView(size),
  description(value_description),
  styles(value_styles),
  accessibility(value_accessibility),
  parameter_callbacks(value_parameter_callbacks) {
    valid_description = description.title && validAxis(description.x_axis) && validAxis(description.y_axis) &&
        description.kind >= ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION && description.kind <= ZIG_VSTGUI_GRAPH_SPECTRUM &&
        description.style >= ZIG_VSTGUI_GRAPH_PRIMARY && description.style <= ZIG_VSTGUI_GRAPH_WARNING;
    if (valid_description && !viewport.configure(description.viewport)) valid_description = false;
    if (valid_description && !range_selection.configure(
            description.range_selection,
            description.x_axis.minimum,
            description.x_axis.maximum
        )) valid_description = false;
    if (!valid_description) return;

    if (editable()) {
        if (range_selection.enabled() || description.kind != ZIG_VSTGUI_GRAPH_ENVELOPE ||
            description.dynamic || description.point_count != 0 ||
            description.point_capacity == 0 || description.point_capacity > ZIG_VSTGUI_MAX_GRAPH_POINTS ||
            description.editable_point_count > description.point_capacity ||
            description.minimum_point_count > description.editable_point_count ||
            (description.editable_point_count > 0 && !description.editable_points) ||
            !std::isfinite(description.snap_x) || !std::isfinite(description.snap_y) ||
            description.snap_x < 0.0 || description.snap_y < 0.0) {
            valid_description = false;
            return;
        }
        uint32_t maximum_id = 0;
        for (uint32_t index = 0; index < description.editable_point_count; ++index) {
            const auto& source = description.editable_points[index];
            if (source.point_id == 0 || !std::isfinite(source.x) || !std::isfinite(source.y) ||
                (source.parameter_mask & ~3u) != 0 ||
                (source.parameter_mask != 0 && (source.parameter_mask != 3 ||
                    source.x_parameter_id == source.y_parameter_id)) ||
                source.x < description.x_axis.minimum || source.x > description.x_axis.maximum ||
                source.y < description.y_axis.minimum || source.y > description.y_axis.maximum ||
                (index > 0 && description.editable_points[index - 1].x > source.x)) {
                valid_description = false;
                return;
            }
            for (uint32_t previous = 0; previous < index; ++previous) {
                if (description.editable_points[previous].point_id == source.point_id) {
                    valid_description = false;
                    return;
                }
            }
            std::shared_ptr<MultiParameterControlModel> model;
            if (source.parameter_mask == 3) {
                model = std::make_shared<MultiParameterControlModel>(
                    source.x_parameter_id,
                    normalize(source.x, description.x_axis),
                    source.x_step_count,
                    source.y_parameter_id,
                    normalize(source.y, description.y_axis),
                    source.y_step_count,
                    parameter_callbacks
                );
            }
            points.push_back({
                source.point_id,
                {source.x, source.y},
                source.x_parameter_id,
                source.y_parameter_id,
                source.parameter_mask,
                model,
            });
            maximum_id = std::max(maximum_id, source.point_id);
        }
        next_point_id = maximum_id == std::numeric_limits<uint32_t>::max() ? 1 : maximum_id + 1;
        if (description.initial_selected_point_id != 0 && indexOf(description.initial_selected_point_id)) {
            selected_id = description.initial_selected_point_id;
        }
        setWantsFocus(true);
    } else if (!description.dynamic) {
        if (description.point_count > ZIG_VSTGUI_MAX_GRAPH_POINTS ||
            (description.point_count > 0 && !description.points)) {
            valid_description = false;
            return;
        }
        for (uint32_t index = 0; index < description.point_count; ++index) {
            if (!std::isfinite(description.points[index].x) || !std::isfinite(description.points[index].y)) {
                valid_description = false;
                return;
            }
            points.push_back({index + 1, description.points[index]});
        }
    }
    if (editable() || viewport.enabled() || range_selection.enabled()) setWantsFocus(true);
    syncAccessibility();
}

bool GraphView::valid() const {
    return valid_description;
}

bool GraphView::editable() const {
    return description.point_capacity > 0 || description.editable_point_count > 0;
}

bool GraphView::setPoints(const ZigVstguiGraphPoint* next, uint32_t count) {
    if (editable() || count > ZIG_VSTGUI_MAX_GRAPH_POINTS || (count > 0 && !next)) return false;
    for (uint32_t index = 0; index < count; ++index) {
        if (!std::isfinite(next[index].x) || !std::isfinite(next[index].y)) return false;
    }
    if (points.size() == count) {
        bool same = true;
        for (uint32_t index = 0; index < count; ++index) {
            same = same && points[index].position.x == next[index].x && points[index].position.y == next[index].y;
        }
        if (same) return false;
    }
    points.clear();
    points.reserve(count);
    for (uint32_t index = 0; index < count; ++index) points.push_back({index + 1, next[index]});
    syncAccessibility();
    invalid();
    return true;
}

uint32_t GraphView::pointCount() const {
    return static_cast<uint32_t>(points.size());
}

bool GraphView::transactionActive() const {
    return transaction_active;
}

bool GraphView::beginTransaction() {
    if (!editable() || transaction_active) return false;
    transaction_points = points;
    transaction_selected_id = selected_id;
    transaction_next_point_id = next_point_id;
    transaction_active = true;
    return true;
}

void GraphView::finishTransaction() {
    for (auto& point : points) {
        if (point.parameter_model && point.parameter_model->gestureActive()) point.parameter_model->endGesture();
    }
    transaction_active = false;
    transaction_points.clear();
    persistEnvelope();
    persistSelection();
}

void GraphView::cancelTransaction() {
    if (range_dragging) {
        range_selection = range_transaction;
        range_dragging = false;
        range_creating = false;
        syncAccessibility();
        invalid();
    }
    if (!transaction_active) return;
    const auto before = points;
    for (auto& point : points) {
        if (point.parameter_model && point.parameter_model->gestureActive()) point.parameter_model->cancelGesture();
    }
    points = transaction_points;
    selected_id = transaction_selected_id;
    next_point_id = transaction_next_point_id;
    transaction_active = false;
    transaction_points.clear();
    dragging = false;
    syncAccessibility();
    auto dirty = contentBounds(before);
    dirty.unite(contentBounds(points));
    invalidRect(dirty);
}

std::optional<std::size_t> GraphView::indexOf(uint32_t point_id) const {
    for (std::size_t index = 0; index < points.size(); ++index) {
        if (points[index].id == point_id) return index;
    }
    return std::nullopt;
}

bool GraphView::selectPoint(uint32_t point_id) {
    const auto index = indexOf(point_id);
    if (!index) return false;
    const auto previous = selected_id ? indexOf(*selected_id) : std::nullopt;
    if (selected_id == point_id) return true;
    selected_id = point_id;
    syncAccessibility();
    if (previous) invalidRect(affectedBounds(points, *previous));
    invalidRect(affectedBounds(points, *index));
    if (!transaction_active) persistSelection();
    return true;
}

void GraphView::persistSelection() {
    if (description.selection_state_id == 0 || !selected_id || !parameter_callbacks.store_editor_index) return;
    parameter_callbacks.store_editor_index(
        parameter_callbacks.userdata,
        description.selection_state_id,
        *selected_id
    );
}

void GraphView::persistEnvelope() {
    if (description.envelope_state_id == 0 || !parameter_callbacks.store_editor_envelope) return;
    std::vector<ZigVstguiEnvelopePoint> stored;
    stored.reserve(points.size());
    for (const auto& point : points) {
        stored.push_back({
            point.id,
            point.position.x,
            point.position.y,
            point.x_parameter_id,
            point.y_parameter_id,
            point.parameter_mask,
            0,
            0,
        });
    }
    parameter_callbacks.store_editor_envelope(
        parameter_callbacks.userdata,
        description.envelope_state_id,
        stored.data(),
        static_cast<uint32_t>(stored.size())
    );
}

bool GraphView::persistViewport(const ViewportModel& previous) {
    const auto& viewport_description = viewport.description();
    uint32_t field_ids[3] {};
    double values[3] {};
    uint32_t count = 0;
    if (viewport_description.zoom_state_id != 0) {
        field_ids[count] = viewport_description.zoom_state_id;
        values[count++] = viewport.zoom();
    }
    if (viewport_description.x_offset_state_id != 0) {
        field_ids[count] = viewport_description.x_offset_state_id;
        values[count++] = viewport.xOffset();
    }
    if (viewport_description.y_offset_state_id != 0) {
        field_ids[count] = viewport_description.y_offset_state_id;
        values[count++] = viewport.yOffset();
    }
    if (count > 0 && (!parameter_callbacks.store_editor_scalars ||
        parameter_callbacks.store_editor_scalars(parameter_callbacks.userdata, field_ids, values, count) != 0)) {
        viewport = previous;
        return false;
    }
    syncAccessibility();
    invalid();
    return true;
}

bool GraphView::persistRangeSelection(const RangeSelectionModel& previous) {
    const auto& range_description = range_selection.description();
    if (range_description.start_state_id != 0) {
        const uint32_t field_ids[] = {
            range_description.start_state_id,
            range_description.end_state_id,
        };
        const double values[] = {range_selection.start(), range_selection.end()};
        if (!parameter_callbacks.store_editor_scalars ||
            parameter_callbacks.store_editor_scalars(parameter_callbacks.userdata, field_ids, values, 2) != 0) {
            range_selection = previous;
            syncAccessibility();
            invalid();
            return false;
        }
    }
    syncAccessibility();
    invalid();
    return true;
}

bool GraphView::selectAdjacent(bool next) {
    if (!editable() || points.empty()) return false;
    std::size_t index = next ? 0 : points.size() - 1;
    if (selected_id) {
        const auto current = indexOf(*selected_id);
        if (current) index = next ? (*current + 1) % points.size() : (*current == 0 ? points.size() - 1 : *current - 1);
    }
    return selectPoint(points[index].id);
}

bool GraphView::selectedPoint(ZigVstguiEnvelopePoint& point) const {
    if (!selected_id) return false;
    const auto index = indexOf(*selected_id);
    if (!index) return false;
    const auto& selected = points[*index];
    point = {selected.id, selected.position.x, selected.position.y};
    return true;
}

uint32_t GraphView::allocatePointId() {
    uint32_t candidate = next_point_id;
    for (uint32_t attempt = 0; attempt <= description.point_capacity; ++attempt) {
        if (candidate != 0 && !indexOf(candidate)) {
            next_point_id = candidate == std::numeric_limits<uint32_t>::max() ? 1 : candidate + 1;
            return candidate;
        }
        candidate = candidate == std::numeric_limits<uint32_t>::max() ? 1 : candidate + 1;
    }
    return 0;
}

bool GraphView::addPoint(double x, double y) {
    if (!transaction_active || points.size() >= description.point_capacity || !std::isfinite(x) || !std::isfinite(y)) return false;
    const ZigVstguiGraphPoint position {
        snap(x, description.x_axis, description.snap_x),
        snap(y, description.y_axis, description.snap_y),
    };
    const uint32_t id = allocatePointId();
    if (id == 0) return false;
    std::size_t insertion = points.size();
    for (std::size_t index = 0; index < points.size(); ++index) {
        if (points[index].position.x > position.x) {
            insertion = index;
            break;
        }
    }
    const auto before = points;
    points.insert(points.begin() + static_cast<std::ptrdiff_t>(insertion), {id, position, 0, 0, 0, nullptr});
    selected_id = id;
    syncAccessibility();
    invalidateChange(before, std::min(insertion, before.empty() ? 0ul : before.size() - 1), insertion);
    return true;
}

bool GraphView::moveSelected(double x, double y) {
    if (!transaction_active || !selected_id || !std::isfinite(x) || !std::isfinite(y)) return false;
    const auto index = indexOf(*selected_id);
    if (!index) return false;
    const auto before = points;
    auto position = ZigVstguiGraphPoint {
        snap(x, description.x_axis, description.snap_x),
        snap(y, description.y_axis, description.snap_y),
    };
    if (*index > 0) position.x = std::max(position.x, points[*index - 1].position.x);
    if (*index + 1 < points.size()) position.x = std::min(position.x, points[*index + 1].position.x);
    auto& selected = points[*index];
    if (selected.parameter_model) {
        if (!selected.parameter_model->gestureActive() && !selected.parameter_model->beginGesture()) return false;
        if (!selected.parameter_model->performEdit(
                normalize(position.x, description.x_axis),
                normalize(position.y, description.y_axis)
            )) {
            selected.parameter_model->cancelGesture();
            cancelTransaction();
            return false;
        }
        position.x = denormalize(selected.parameter_model->acceptedValue(0), description.x_axis);
        position.y = denormalize(selected.parameter_model->acceptedValue(1), description.y_axis);
        if ((*index > 0 && position.x < points[*index - 1].position.x) ||
            (*index + 1 < points.size() && position.x > points[*index + 1].position.x)) {
            selected.parameter_model->cancelGesture();
            cancelTransaction();
            return false;
        }
    }
    if (position.x == points[*index].position.x && position.y == points[*index].position.y) return true;
    points[*index].position = position;
    syncAccessibility();
    invalidateChange(before, *index, *index);
    return true;
}

bool GraphView::adjustSelected(double x_delta, double y_delta) {
    ZigVstguiEnvelopePoint selected {};
    return selectedPoint(selected) && moveSelected(selected.x + x_delta, selected.y + y_delta);
}

bool GraphView::deleteSelected() {
    if (!transaction_active || !selected_id || points.size() <= description.minimum_point_count) return false;
    const auto index = indexOf(*selected_id);
    if (!index) return false;
    if (points[*index].parameter_model) return false;
    const auto before = points;
    points.erase(points.begin() + static_cast<std::ptrdiff_t>(*index));
    if (points.empty()) selected_id.reset();
    else selected_id = points[std::min(*index, points.size() - 1)].id;
    syncAccessibility();
    invalidateChange(before, *index, std::min(*index, points.empty() ? 0ul : points.size() - 1));
    return true;
}

bool GraphView::setParameter(uint32_t parameter_id, double normalized) {
    if (!editable()) return false;
    const auto before = points;
    bool found = false;
    for (auto& point : points) {
        if (!point.parameter_model ||
            (point.x_parameter_id != parameter_id && point.y_parameter_id != parameter_id)) continue;
        point.parameter_model->hostChanged(parameter_id, normalized);
        point.position.x = denormalize(point.parameter_model->acceptedValue(0), description.x_axis);
        point.position.y = denormalize(point.parameter_model->acceptedValue(1), description.y_axis);
        found = true;
    }
    if (!found) return false;
    std::stable_sort(points.begin(), points.end(), [](const PointState& left, const PointState& right) {
        return left.position.x < right.position.x;
    });
    syncAccessibility();
    auto dirty = contentBounds(before);
    dirty.unite(contentBounds(points));
    invalidRect(dirty);
    return true;
}

bool GraphView::viewportEnabled() const { return viewport.enabled(); }
double GraphView::viewportZoom() const { return viewport.zoom(); }
double GraphView::viewportXOffset() const { return viewport.xOffset(); }
double GraphView::viewportYOffset() const { return viewport.yOffset(); }

bool GraphView::zoomViewportIn(double anchor_x, double anchor_y) {
    const auto previous = viewport;
    return viewport.zoomIn(anchor_x, anchor_y) && persistViewport(previous);
}

bool GraphView::zoomViewportOut(double anchor_x, double anchor_y) {
    const auto previous = viewport;
    return viewport.zoomOut(anchor_x, anchor_y) && persistViewport(previous);
}

bool GraphView::setViewportZoom(double zoom, double anchor_x, double anchor_y) {
    const auto previous = viewport;
    return viewport.setZoom(zoom, anchor_x, anchor_y) && persistViewport(previous);
}

bool GraphView::panViewport(double x_steps, double y_steps) {
    const auto previous = viewport;
    return viewport.pan(x_steps, y_steps) && persistViewport(previous);
}

bool GraphView::resetViewport() {
    const auto previous = viewport;
    return viewport.reset() && persistViewport(previous);
}

bool GraphView::rangeSelectionEnabled() const { return range_selection.enabled(); }
double GraphView::rangeSelectionStart() const { return range_selection.start(); }
double GraphView::rangeSelectionEnd() const { return range_selection.end(); }
RangeSelectionHandle GraphView::activeRangeSelectionHandle() const { return range_selection.activeHandle(); }

bool GraphView::selectRangeSelectionHandle(RangeSelectionHandle handle) {
    if (!range_selection.enabled()) return false;
    const bool changed = range_selection.activeHandle() != handle;
    range_selection.selectHandle(handle);
    syncAccessibility();
    invalid();
    return changed;
}

bool GraphView::cycleRangeSelectionHandle() {
    if (!range_selection.enabled()) return false;
    range_selection.cycleHandle();
    syncAccessibility();
    invalid();
    return true;
}

bool GraphView::setRangeSelectionValue(double value) {
    const auto previous = range_selection;
    return range_selection.set(range_selection.activeHandle(), value) && persistRangeSelection(previous);
}

bool GraphView::adjustRangeSelection(double delta) {
    const auto previous = range_selection;
    return range_selection.adjust(delta) && persistRangeSelection(previous);
}

bool GraphView::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    VSTGUI::KeyboardEvent event;
    event.type = VSTGUI::EventType::KeyDown;
    event.character = key;
    switch (key_code) {
        case Steinberg::KEY_LEFT: event.virt = VSTGUI::VirtualKey::Left; break;
        case Steinberg::KEY_UP: event.virt = VSTGUI::VirtualKey::Up; break;
        case Steinberg::KEY_RIGHT: event.virt = VSTGUI::VirtualKey::Right; break;
        case Steinberg::KEY_DOWN: event.virt = VSTGUI::VirtualKey::Down; break;
        case Steinberg::KEY_HOME: event.virt = VSTGUI::VirtualKey::Home; break;
        case Steinberg::KEY_END: event.virt = VSTGUI::VirtualKey::End; break;
        case Steinberg::KEY_PAGEUP: event.virt = VSTGUI::VirtualKey::PageUp; break;
        case Steinberg::KEY_PAGEDOWN: event.virt = VSTGUI::VirtualKey::PageDown; break;
        case Steinberg::KEY_BACK: event.virt = VSTGUI::VirtualKey::Back; break;
        case Steinberg::KEY_DELETE: event.virt = VSTGUI::VirtualKey::Delete; break;
        case Steinberg::KEY_RETURN: event.virt = VSTGUI::VirtualKey::Return; break;
        default:
            if (key != '[' && key != ']' && key != '+' && key != '=' && key != '-' && key != '0') return false;
            break;
    }
    if ((modifiers & 1) != 0) event.modifiers.add(VSTGUI::ModifierKey::Shift);
    if ((modifiers & 2) != 0) event.modifiers.add(VSTGUI::ModifierKey::Alt);
    if ((modifiers & 4) != 0) event.modifiers.add(VSTGUI::ModifierKey::Control);
    if ((modifiers & 8) != 0) event.modifiers.add(VSTGUI::ModifierKey::Super);
    onKeyboardEvent(event);
    return event.consumed;
}

double GraphView::normalize(double value, const ZigVstguiGraphAxis& axis) const {
    if (axis.scale == ZIG_VSTGUI_GRAPH_LOGARITHMIC) {
        if (value <= 0.0) return 0.0;
        const double low = std::log10(axis.minimum);
        return std::clamp((std::log10(value) - low) / (std::log10(axis.maximum) - low), 0.0, 1.0);
    }
    return std::clamp((value - axis.minimum) / (axis.maximum - axis.minimum), 0.0, 1.0);
}

double GraphView::denormalize(double value, const ZigVstguiGraphAxis& axis) const {
    const double normalized = std::clamp(value, 0.0, 1.0);
    if (axis.scale == ZIG_VSTGUI_GRAPH_LOGARITHMIC) {
        const double low = std::log10(axis.minimum);
        return std::pow(10.0, low + normalized * (std::log10(axis.maximum) - low));
    }
    return axis.minimum + normalized * (axis.maximum - axis.minimum);
}

double GraphView::snap(double value, const ZigVstguiGraphAxis& axis, double step) const {
    const double clamped = std::clamp(value, axis.minimum, axis.maximum);
    if (step <= 0.0) return clamped;
    return std::clamp(axis.minimum + std::round((clamped - axis.minimum) / step) * step, axis.minimum, axis.maximum);
}

VSTGUI::CPoint GraphView::viewPoint(const ZigVstguiGraphPoint& point) const {
    const auto bounds = getViewSize();
    const double x = normalize(point.x, description.x_axis);
    const double y = normalize(point.y, description.y_axis);
    if (!viewport.enabled()) {
        return {
            bounds.left + bounds.getWidth() * x,
            bounds.bottom - bounds.getHeight() * y,
        };
    }
    return {
        bounds.left + bounds.getWidth() * viewport.projectX(x),
        bounds.bottom - bounds.getHeight() * viewport.projectY(y),
    };
}

ZigVstguiGraphPoint GraphView::graphPoint(const VSTGUI::CPoint& point) const {
    const auto bounds = getViewSize();
    const double x = (point.x - bounds.left) / std::max(1.0, bounds.getWidth());
    const double y = (bounds.bottom - point.y) / std::max(1.0, bounds.getHeight());
    if (!viewport.enabled()) {
        return {
            denormalize(x, description.x_axis),
            denormalize(y, description.y_axis),
        };
    }
    return {
        denormalize(viewport.unprojectX(x), description.x_axis),
        denormalize(viewport.unprojectY(y), description.y_axis),
    };
}

std::optional<std::size_t> GraphView::hitTestPoint(const VSTGUI::CPoint& point) const {
    constexpr double hit_radius = 9.0;
    for (std::size_t offset = 0; offset < points.size(); ++offset) {
        const std::size_t index = points.size() - offset - 1;
        const auto candidate = viewPoint(points[index].position);
        const double x = candidate.x - point.x;
        const double y = candidate.y - point.y;
        if (x * x + y * y <= hit_radius * hit_radius) return index;
    }
    return std::nullopt;
}

std::optional<RangeSelectionHandle> GraphView::hitTestRangeSelectionHandle(const VSTGUI::CPoint& point) const {
    if (!range_selection.enabled()) return std::nullopt;
    constexpr double hit_radius = 10.0;
    const auto start = viewPoint({range_selection.start(), description.y_axis.minimum});
    const auto end = viewPoint({range_selection.end(), description.y_axis.minimum});
    const double start_distance = std::abs(point.x - start.x);
    const double end_distance = std::abs(point.x - end.x);
    if (start_distance > hit_radius && end_distance > hit_radius) return std::nullopt;
    return start_distance <= end_distance ? RangeSelectionHandle::start : RangeSelectionHandle::end;
}

VSTGUI::CRect GraphView::affectedBounds(const std::vector<PointState>& values, std::size_t index) const {
    if (values.empty()) return getViewSize();
    const std::size_t first = index == 0 ? 0 : index - 1;
    const std::size_t last = std::min(index + 1, values.size() - 1);
    const auto initial = viewPoint(values[first].position);
    VSTGUI::CRect result(initial.x, initial.y, initial.x, initial.y);
    for (std::size_t current = first + 1; current <= last; ++current) {
        const auto point = viewPoint(values[current].position);
        result.unite(VSTGUI::CRect(point.x, point.y, point.x, point.y));
    }
    result.extend(12.0, 12.0);
    result.bound(getViewSize());
    return result;
}

VSTGUI::CRect GraphView::contentBounds(const std::vector<PointState>& values) const {
    if (values.empty()) return getViewSize();
    const auto initial = viewPoint(values.front().position);
    VSTGUI::CRect result(initial.x, initial.y, initial.x, initial.y);
    for (std::size_t index = 1; index < values.size(); ++index) {
        const auto point = viewPoint(values[index].position);
        result.unite(VSTGUI::CRect(point.x, point.y, point.x, point.y));
    }
    result.extend(12.0, 12.0);
    result.bound(getViewSize());
    return result;
}

void GraphView::invalidateChange(
    const std::vector<PointState>& before,
    std::size_t before_index,
    std::size_t after_index
) {
    auto dirty = affectedBounds(before, before_index);
    dirty.unite(affectedBounds(points, after_index));
    invalidRect(dirty);
}

void GraphView::syncAccessibility() {
    if (!accessibility) return;
    char text[160] {};
    ZigVstguiEnvelopePoint selected {};
    if (selectedPoint(selected)) {
        std::snprintf(
            text,
            sizeof(text),
            "%u points. Selected %u at %.3f, %.3f",
            static_cast<uint32_t>(points.size()),
            selected.point_id,
            selected.x,
            selected.y
        );
        accessibility->setRange(description.y_axis.minimum, description.y_axis.maximum, selected.y);
        accessibility->setSelected(true);
    } else if (description.kind == ZIG_VSTGUI_GRAPH_WAVEFORM) {
        double peak = 0.0;
        for (const auto& point : points) peak = std::max(peak, std::abs(point.position.y));
        if (points.empty()) std::snprintf(text, sizeof(text), "No waveform data");
        else std::snprintf(text, sizeof(text), "%u samples. Peak %.3f", static_cast<uint32_t>(points.size()), peak);
        accessibility->clearRange();
        accessibility->setSelected(false);
    } else if (description.kind == ZIG_VSTGUI_GRAPH_SPECTRUM) {
        if (points.empty()) {
            std::snprintf(text, sizeof(text), "No spectrum data");
        } else {
            const auto peak = std::max_element(points.begin(), points.end(), [](const PointState& left, const PointState& right) {
                return left.position.y < right.position.y;
            });
            std::snprintf(
                text,
                sizeof(text),
                "%u bins. Peak %.0f Hz at %.1f dB",
                static_cast<uint32_t>(points.size()),
                peak->position.x,
                peak->position.y
            );
        }
        accessibility->clearRange();
        accessibility->setSelected(false);
    } else {
        std::snprintf(text, sizeof(text), "%u points. No point selected", static_cast<uint32_t>(points.size()));
        accessibility->clearRange();
        accessibility->setSelected(false);
    }
    if (range_selection.enabled()) {
        const auto active = range_selection.activeHandle();
        const std::size_t length = std::char_traits<char>::length(text);
        std::snprintf(
            text + length,
            sizeof(text) - length,
            ". Selection %.3f to %.3f. %s handle active",
            range_selection.start(),
            range_selection.end(),
            active == RangeSelectionHandle::start ? "Start" : "End"
        );
        accessibility->setRange(
            description.x_axis.minimum,
            description.x_axis.maximum,
            range_selection.value(active)
        );
        accessibility->setSelected(true);
    }
    if (viewport.enabled()) {
        const double maximum_offset = std::max(0.0, 1.0 - 1.0 / viewport.zoom());
        const double x_position = maximum_offset > 0.0 ? viewport.xOffset() / maximum_offset * 100.0 : 0.0;
        const double y_position = maximum_offset > 0.0 ? viewport.yOffset() / maximum_offset * 100.0 : 0.0;
        const std::size_t length = std::char_traits<char>::length(text);
        if (viewport.horizontal() && viewport.vertical()) {
            std::snprintf(text + length, sizeof(text) - length, ". Zoom %.0f%%. Position %.0f%%, %.0f%%",
                viewport.zoom() * 100.0, x_position, y_position);
        } else {
            const double position = viewport.horizontal() ? x_position : y_position;
            std::snprintf(text + length, sizeof(text) - length, ". Zoom %.0f%%. Position %.0f%%",
                viewport.zoom() * 100.0, position);
        }
        if (!editable() && !range_selection.enabled()) {
            const auto& viewport_description = viewport.description();
            accessibility->setRange(
                viewport_description.minimum_zoom,
                viewport_description.maximum_zoom,
                viewport.zoom()
            );
        }
    }
    accessibility->setValueText(text);
}

void GraphView::drawViewportOverlay(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds) {
    if (!viewport.enabled()) return;
    const auto style = styles.resolve(ComponentKind::value_field);
    const double span = 1.0 / viewport.zoom();
    context->setFillColor(style.background);
    context->setFrameColor(style.border);
    context->setLineWidth(1.0);
    if (viewport.horizontal()) {
        VSTGUI::CRect track(bounds.left + 8.0, bounds.bottom - 9.0, bounds.right - 52.0, bounds.bottom - 4.0);
        context->drawRect(track, VSTGUI::kDrawFilledAndStroked);
        VSTGUI::CRect thumb = track;
        thumb.left += track.getWidth() * viewport.xOffset();
        thumb.right = thumb.left + track.getWidth() * span;
        context->setFillColor(style.accent);
        context->drawRect(thumb, VSTGUI::kDrawFilled);
    }
    if (viewport.vertical()) {
        VSTGUI::CRect track(bounds.right - 9.0, bounds.top + 24.0, bounds.right - 4.0, bounds.bottom - 14.0);
        context->setFillColor(style.background);
        context->drawRect(track, VSTGUI::kDrawFilledAndStroked);
        VSTGUI::CRect thumb = track;
        thumb.bottom -= track.getHeight() * viewport.yOffset();
        thumb.top = thumb.bottom - track.getHeight() * span;
        context->setFillColor(style.accent);
        context->drawRect(thumb, VSTGUI::kDrawFilled);
    }
    char zoom_text[24] {};
    std::snprintf(zoom_text, sizeof(zoom_text), "%.1fx", viewport.zoom());
    context->setFont(styles.font(TypographyRole::body));
    context->setFontColor(style.foreground);
    context->drawString(zoom_text, VSTGUI::CRect(bounds.right - 48.0, bounds.top + 4.0, bounds.right - 6.0, bounds.top + 20.0),
        VSTGUI::kRightText);
}

void GraphView::drawRangeSelection(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds) {
    if (!range_selection.enabled()) return;
    const double start_x = viewPoint({range_selection.start(), description.y_axis.minimum}).x;
    const double end_x = viewPoint({range_selection.end(), description.y_axis.minimum}).x;
    if (end_x < bounds.left || start_x > bounds.right) return;
    const double visible_start = std::clamp(start_x, bounds.left, bounds.right);
    const double visible_end = std::clamp(end_x, bounds.left, bounds.right);
    const auto style = styles.resolve(ComponentKind::graph);
    auto fill = style.accent;
    fill.alpha = 42;
    context->setFillColor(fill);
    context->drawRect(
        VSTGUI::CRect(visible_start, bounds.top, visible_end, bounds.bottom),
        VSTGUI::kDrawFilled
    );
    const bool focused = getFrame() && getFrame()->getFocusView() == this;
    const auto draw_handle = [&](double x, RangeSelectionHandle handle) {
        if (x < bounds.left || x > bounds.right) return;
        const bool active = range_selection.activeHandle() == handle;
        context->setFrameColor(active && focused ? style.accent : style.foreground);
        context->setFillColor(active ? style.accent : style.background);
        context->setLineWidth(active ? 2.5 : 1.5);
        context->drawLine(VSTGUI::CPoint(x, bounds.top), VSTGUI::CPoint(x, bounds.bottom));
        const double radius = active ? 6.0 : 4.5;
        context->drawEllipse(
            VSTGUI::CRect(x - radius, bounds.top + 3.0, x + radius, bounds.top + 3.0 + radius * 2.0),
            VSTGUI::kDrawFilledAndStroked
        );
    };
    draw_handle(start_x, RangeSelectionHandle::start);
    draw_handle(end_x, RangeSelectionHandle::end);
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
    if (auto grid = VSTGUI::owned(context->createGraphicsPath())) {
        for (uint32_t division = 1; division < 4; ++division) {
            const double x = bounds.left + bounds.getWidth() * division / 4.0;
            const double y = bounds.top + bounds.getHeight() * division / 4.0;
            grid->beginSubpath(VSTGUI::CPoint(x, bounds.top));
            grid->addLine(VSTGUI::CPoint(x, bounds.bottom));
            grid->beginSubpath(VSTGUI::CPoint(bounds.left, y));
            grid->addLine(VSTGUI::CPoint(bounds.right, y));
        }
        context->drawGraphicsPath(grid, VSTGUI::CDrawContext::kPathStroked);
    } else {
        for (uint32_t division = 1; division < 4; ++division) {
            const double x = bounds.left + bounds.getWidth() * division / 4.0;
            const double y = bounds.top + bounds.getHeight() * division / 4.0;
            context->drawLine(VSTGUI::CPoint(x, bounds.top), VSTGUI::CPoint(x, bounds.bottom));
            context->drawLine(VSTGUI::CPoint(bounds.left, y), VSTGUI::CPoint(bounds.right, y));
        }
    }

    if (description.kind == ZIG_VSTGUI_GRAPH_WAVEFORM &&
        description.y_axis.minimum <= 0.0 && description.y_axis.maximum >= 0.0) {
        const double zero = viewPoint({description.x_axis.minimum, 0.0}).y;
        context->setFrameColor(style.border);
        context->setLineWidth(1.5);
        context->drawLine(VSTGUI::CPoint(bounds.left, zero), VSTGUI::CPoint(bounds.right, zero));
    }

    if (points.empty()) {
        context->setFont(styles.font(TypographyRole::body));
        context->setFontColor(style.foreground);
        const char* message = editable() ? "Press Return or click to add a point" :
            description.kind == ZIG_VSTGUI_GRAPH_WAVEFORM ? "No waveform data" :
            description.kind == ZIG_VSTGUI_GRAPH_SPECTRUM ? "No spectrum data" : "No graph data";
        context->drawString(message, bounds, VSTGUI::kCenterText);
        drawViewportOverlay(context, bounds);
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
    if (description.kind == ZIG_VSTGUI_GRAPH_SPECTRUM) {
        context->setLineWidth(std::clamp(bounds.getWidth() / std::max(1.0, static_cast<double>(points.size())) * 0.7, 1.0, 5.0));
        if (auto path = VSTGUI::owned(context->createGraphicsPath())) {
            for (const auto& point : points) {
                const auto top = viewPoint(point.position);
                const auto bottom = viewPoint({point.position.x, description.y_axis.minimum});
                path->beginSubpath(bottom);
                path->addLine(top);
            }
            context->drawGraphicsPath(path, VSTGUI::CDrawContext::kPathStroked);
        } else {
            for (const auto& point : points) {
                context->drawLine(
                    viewPoint({point.position.x, description.y_axis.minimum}),
                    viewPoint(point.position)
                );
            }
        }
    } else {
        context->setLineWidth(2.0);
        if (auto path = VSTGUI::owned(context->createGraphicsPath())) {
            path->beginSubpath(viewPoint(points.front().position));
            for (std::size_t index = 1; index < points.size(); ++index) path->addLine(viewPoint(points[index].position));
            context->drawGraphicsPath(path, VSTGUI::CDrawContext::kPathStroked);
        } else {
            for (std::size_t index = 1; index < points.size(); ++index) {
                context->drawLine(viewPoint(points[index - 1].position), viewPoint(points[index].position));
            }
        }
    }
    if (editable()) {
        const bool focused = getFrame() && getFrame()->getFocusView() == this;
        for (const auto& point : points) {
            const auto center = viewPoint(point.position);
            const bool selected = selected_id == point.id;
            const double radius = selected ? 6.0 : 4.0;
            const auto point_style = styles.resolve(
                ComponentKind::graph,
                selected && focused ? VisualState::focused : selected ? VisualState::pressed : VisualState::normal
            );
            context->setFillColor(selected ? point_style.accent : point_style.foreground);
            context->setFrameColor(selected && focused ? point_style.border : curve_color);
            context->setLineWidth(selected ? 2.0 : 1.0);
            context->drawEllipse(
                VSTGUI::CRect(center.x - radius, center.y - radius, center.x + radius, center.y + radius),
                VSTGUI::kDrawFilledAndStroked
            );
        }
    }
    drawRangeSelection(context, bounds);
    drawViewportOverlay(context, bounds);
    setDirty(false);
}

void GraphView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (range_selection.enabled()) {
        if (!event.buttonState.isLeft() || range_dragging) return;
        if (getFrame()) getFrame()->setFocusView(this);
        range_transaction = range_selection;
        const auto position = graphPoint(event.mousePosition);
        const auto hit = hitTestRangeSelectionHandle(event.mousePosition);
        if (hit) {
            range_selection.selectHandle(*hit);
            range_creating = false;
        } else {
            range_anchor = position.x;
            range_selection.replace(range_anchor, range_anchor);
            range_creating = true;
        }
        range_dragging = true;
        syncAccessibility();
        invalid();
        event.consumed = true;
        return;
    }
    if (!editable()) return;
    const auto hit = hitTestPoint(event.mousePosition);
    if (event.buttonState.isRight()) {
        if (hit && beginTransaction()) {
            selectPoint(points[*hit].id);
            if (deleteSelected()) finishTransaction();
            else cancelTransaction();
            event.consumed = true;
        }
        return;
    }
    if (!event.buttonState.isLeft() || !beginTransaction()) return;
    if (getFrame()) getFrame()->setFocusView(this);
    if (hit) {
        selectPoint(points[*hit].id);
    } else {
        const auto position = graphPoint(event.mousePosition);
        if (!addPoint(position.x, position.y)) {
            cancelTransaction();
            return;
        }
    }
    dragging = true;
    event.consumed = true;
}

void GraphView::onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) {
    if (range_dragging) {
        const auto position = graphPoint(event.mousePosition);
        if (range_creating) range_selection.replace(range_anchor, position.x);
        else range_selection.set(range_selection.activeHandle(), position.x);
        syncAccessibility();
        invalid();
        event.consumed = true;
        return;
    }
    if (!dragging || !transaction_active) return;
    const auto position = graphPoint(event.mousePosition);
    moveSelected(position.x, position.y);
    event.consumed = true;
}

void GraphView::onMouseUpEvent(VSTGUI::MouseUpEvent& event) {
    if (range_dragging) {
        range_dragging = false;
        range_creating = false;
        persistRangeSelection(range_transaction);
        event.consumed = true;
        return;
    }
    if (!dragging) return;
    dragging = false;
    finishTransaction();
    event.consumed = true;
}

void GraphView::onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) {
    if (!dragging && !transaction_active && !range_dragging) return;
    dragging = false;
    cancelTransaction();
    event.consumed = true;
}

void GraphView::onMouseWheelEvent(VSTGUI::MouseWheelEvent& event) {
    if (!viewport.enabled()) return;
    const auto bounds = getViewSize();
    const double anchor_x = (event.mousePosition.x - bounds.left) / std::max(1.0, bounds.getWidth());
    const double anchor_y = (bounds.bottom - event.mousePosition.y) / std::max(1.0, bounds.getHeight());
    const bool zoom_modifier = event.modifiers.has(VSTGUI::ModifierKey::Control) ||
        event.modifiers.has(VSTGUI::ModifierKey::Super);
    bool changed = false;
    if (zoom_modifier) {
        changed = event.deltaY >= 0.0
            ? zoomViewportIn(anchor_x, anchor_y)
            : zoomViewportOut(anchor_x, anchor_y);
    } else {
        const double x_steps = std::abs(event.deltaX) > 0.0001
            ? -event.deltaX
            : viewport.horizontal() && !viewport.vertical() ? -event.deltaY : 0.0;
        const double y_steps = viewport.vertical() ? event.deltaY : 0.0;
        changed = panViewport(x_steps, y_steps);
    }
    if (changed) event.consumed = true;
}

void GraphView::onZoomGestureEvent(VSTGUI::ZoomGestureEvent& event) {
    if (!viewport.enabled() || event.phase == VSTGUI::ZoomGestureEvent::Phase::End) return;
    const auto bounds = getViewSize();
    const double anchor_x = (event.mousePosition.x - bounds.left) / std::max(1.0, bounds.getWidth());
    const double anchor_y = (bounds.bottom - event.mousePosition.y) / std::max(1.0, bounds.getHeight());
    if (setViewportZoom(viewport.zoom() * std::max(0.01, 1.0 + event.zoom), anchor_x, anchor_y)) {
        event.consumed = true;
    }
}

void GraphView::onKeyboardEvent(VSTGUI::KeyboardEvent& event) {
    if (event.type != VSTGUI::EventType::KeyDown) return;
    if (range_selection.enabled()) {
        if (event.character == '[' || event.character == ']') {
            selectRangeSelectionHandle(event.character == '['
                ? RangeSelectionHandle::start
                : RangeSelectionHandle::end);
            event.consumed = true;
            return;
        }
        if (event.virt == VSTGUI::VirtualKey::Return) {
            if (cycleRangeSelectionHandle()) event.consumed = true;
            return;
        }
        const bool command = event.modifiers.has(VSTGUI::ModifierKey::Control) ||
            event.modifiers.has(VSTGUI::ModifierKey::Super);
        if (!command && (event.virt == VSTGUI::VirtualKey::Left ||
            event.virt == VSTGUI::VirtualKey::Right || event.virt == VSTGUI::VirtualKey::Home ||
            event.virt == VSTGUI::VirtualKey::End)) {
            bool changed = false;
            if (event.virt == VSTGUI::VirtualKey::Home) {
                changed = setRangeSelectionValue(description.x_axis.minimum);
            } else if (event.virt == VSTGUI::VirtualKey::End) {
                changed = setRangeSelectionValue(description.x_axis.maximum);
            } else {
                const double direction = event.virt == VSTGUI::VirtualKey::Left ? -1.0 : 1.0;
                const double scale = event.modifiers.has(VSTGUI::ModifierKey::Shift) ? 10.0 : 1.0;
                changed = adjustRangeSelection(direction * description.range_selection.step * scale);
            }
            if (changed) event.consumed = true;
            return;
        }
    }
    if (viewport.enabled()) {
        if (event.character == '+' || event.character == '=') {
            if (zoomViewportIn()) event.consumed = true;
            return;
        }
        if (event.character == '-') {
            if (zoomViewportOut()) event.consumed = true;
            return;
        }
        if (event.character == '0') {
            if (resetViewport()) event.consumed = true;
            return;
        }
        const bool command = event.modifiers.has(VSTGUI::ModifierKey::Control) ||
            event.modifiers.has(VSTGUI::ModifierKey::Super);
        if (!editable() || command) {
            const double distance = event.modifiers.has(VSTGUI::ModifierKey::Shift) ? 5.0 : 1.0;
            bool changed = false;
            if (event.virt == VSTGUI::VirtualKey::Left) changed = panViewport(-distance, 0.0);
            else if (event.virt == VSTGUI::VirtualKey::Right) changed = panViewport(distance, 0.0);
            else if (event.virt == VSTGUI::VirtualKey::Up) changed = panViewport(0.0, -distance);
            else if (event.virt == VSTGUI::VirtualKey::Down) changed = panViewport(0.0, distance);
            else if (event.virt == VSTGUI::VirtualKey::PageUp || event.virt == VSTGUI::VirtualKey::PageDown) {
                const double page = 1.0 / viewport.description().scroll_step;
                const double direction = event.virt == VSTGUI::VirtualKey::PageUp ? -page : page;
                changed = viewport.horizontal() ? panViewport(direction, 0.0) : panViewport(0.0, direction);
            } else if (event.virt == VSTGUI::VirtualKey::Home || event.virt == VSTGUI::VirtualKey::End) {
                const auto previous = viewport;
                const bool horizontal_axis = viewport.horizontal();
                changed = event.virt == VSTGUI::VirtualKey::Home
                    ? viewport.panToStart(horizontal_axis)
                    : viewport.panToEnd(horizontal_axis);
                if (changed) changed = persistViewport(previous);
            }
            if (changed) event.consumed = true;
            if (event.consumed || event.virt == VSTGUI::VirtualKey::Left ||
                event.virt == VSTGUI::VirtualKey::Right || event.virt == VSTGUI::VirtualKey::Up ||
                event.virt == VSTGUI::VirtualKey::Down || event.virt == VSTGUI::VirtualKey::PageUp ||
                event.virt == VSTGUI::VirtualKey::PageDown || event.virt == VSTGUI::VirtualKey::Home ||
                event.virt == VSTGUI::VirtualKey::End) return;
        }
    }
    if (!editable()) return;
    if (event.character == '[' || event.character == ']') {
        if (selectAdjacent(event.character == ']')) event.consumed = true;
        return;
    }
    if (event.virt == VSTGUI::VirtualKey::Home || event.virt == VSTGUI::VirtualKey::End) {
        if (!points.empty() && selectPoint(event.virt == VSTGUI::VirtualKey::Home ? points.front().id : points.back().id)) {
            event.consumed = true;
        }
        return;
    }
    if (event.virt == VSTGUI::VirtualKey::Return) {
        if (!beginTransaction()) return;
        double x = (description.x_axis.minimum + description.x_axis.maximum) * 0.5;
        double y = (description.y_axis.minimum + description.y_axis.maximum) * 0.5;
        ZigVstguiEnvelopePoint selected {};
        if (selectedPoint(selected)) {
            x = selected.x;
            y = selected.y;
        }
        if (addPoint(x, y)) finishTransaction();
        else cancelTransaction();
        event.consumed = true;
        return;
    }
    if (event.virt == VSTGUI::VirtualKey::Delete || event.virt == VSTGUI::VirtualKey::Back) {
        if (!beginTransaction()) return;
        if (deleteSelected()) finishTransaction();
        else cancelTransaction();
        event.consumed = true;
        return;
    }
    if (event.virt != VSTGUI::VirtualKey::Left && event.virt != VSTGUI::VirtualKey::Right &&
        event.virt != VSTGUI::VirtualKey::Up && event.virt != VSTGUI::VirtualKey::Down) return;
    if (!selected_id && !selectAdjacent(true)) return;
    const double fine = event.modifiers.has(VSTGUI::ModifierKey::Shift) ? 0.1 : 1.0;
    const double x_step = (description.snap_x > 0.0 ? description.snap_x :
        (description.x_axis.maximum - description.x_axis.minimum) * 0.01) * fine;
    const double y_step = (description.snap_y > 0.0 ? description.snap_y :
        (description.y_axis.maximum - description.y_axis.minimum) * 0.01) * fine;
    double x_delta = 0.0;
    double y_delta = 0.0;
    if (event.virt == VSTGUI::VirtualKey::Left) x_delta = -x_step;
    if (event.virt == VSTGUI::VirtualKey::Right) x_delta = x_step;
    if (event.virt == VSTGUI::VirtualKey::Down) y_delta = -y_step;
    if (event.virt == VSTGUI::VirtualKey::Up) y_delta = y_step;
    if (!beginTransaction()) return;
    if (adjustSelected(x_delta, y_delta)) finishTransaction();
    else cancelTransaction();
    event.consumed = true;
}

GraphControl::~GraphControl() {
    stop();
    if (timer) timer->forget();
}

bool GraphControl::build(
    VSTGUI::CViewContainer* parent,
    const ZigVstguiGraphDescription& value_description,
    ZigVstguiGraphCallbacks value_callbacks,
    ZigVstguiCallbacks value_parameter_callbacks,
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
    label->setFrameColor(label_style.border);
    parent->addView(label);
    label_component.bind(label);
    label_component.accessibility().setRole(AccessibilityRole::group);
    label_component.accessibility().setName(description.title ? description.title : "Graph");
    label_component.accessibility().setReadOnly(true);

    graph_component.accessibility().setRole(AccessibilityRole::graph);
    graph_component.accessibility().setName(description.title ? description.title : "Graph");
    std::string semantic_description = description.dynamic ? "Updating graph" : "Static graph";
    if (description.kind == ZIG_VSTGUI_GRAPH_WAVEFORM) {
        semantic_description = description.dynamic ? "Updating waveform" : "Static waveform";
    } else if (description.kind == ZIG_VSTGUI_GRAPH_SPECTRUM) {
        semantic_description = description.dynamic ? "Updating frequency spectrum" : "Static frequency spectrum";
    }
    if (description.point_capacity > 0) semantic_description = "Editable envelope. Brackets select points. Arrows adjust. Return adds. Delete removes.";
    if (description.viewport.enabled != 0) {
        semantic_description += description.point_capacity > 0 || description.range_selection.enabled != 0
            ? " Plus and minus zoom. Command with arrows pans. Zero resets the view."
            : " Plus and minus zoom. Arrows pan. Zero resets the view.";
    }
    if (description.range_selection.enabled != 0) {
        semantic_description += " Brackets choose the start or end handle. Arrows adjust it. Shift moves farther. Return switches handles.";
    }
    if (description.x_axis.label && description.x_axis.label[0]) semantic_description += ". X: " + std::string(description.x_axis.label);
    if (description.y_axis.label && description.y_axis.label[0]) semantic_description += ". Y: " + std::string(description.y_axis.label);
    graph_component.accessibility().setDescription(semantic_description);
    graph_component.accessibility().setReadOnly(
        description.point_capacity == 0 && description.viewport.enabled == 0 &&
        description.range_selection.enabled == 0
    );
    graph = new GraphView(
        VSTGUI::CRect(),
        description,
        styles,
        &graph_component.accessibility(),
        value_parameter_callbacks
    );
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
    if (graph->editable() || graph->viewportEnabled() || graph->rangeSelectionEnabled()) {
        graph->registerViewListener(this);
        graph_component.setFocusable(true);
        uint32_t actions = actionMask(AccessibilityAction::focus);
        if (graph->viewportEnabled()) {
            actions |= actionMask(AccessibilityAction::press) |
                actionMask(AccessibilityAction::increment) |
                actionMask(AccessibilityAction::decrement) |
                actionMask(AccessibilityAction::set_value);
        }
        if (graph->editable()) {
            actions |= actionMask(AccessibilityAction::press) |
                actionMask(AccessibilityAction::increment) |
                actionMask(AccessibilityAction::decrement) |
                actionMask(AccessibilityAction::set_value) |
                actionMask(AccessibilityAction::select_previous) |
                actionMask(AccessibilityAction::select_next) |
                actionMask(AccessibilityAction::add_point) |
                actionMask(AccessibilityAction::delete_selected);
        }
        if (graph->rangeSelectionEnabled()) {
            actions |= actionMask(AccessibilityAction::press) |
                actionMask(AccessibilityAction::increment) |
                actionMask(AccessibilityAction::decrement) |
                actionMask(AccessibilityAction::set_value) |
                actionMask(AccessibilityAction::select_previous) |
                actionMask(AccessibilityAction::select_next);
        }
        graph_component.accessibility().setActionHandler(
            this,
            accessibilityAction,
            actions
        );
    }

    if (description.dynamic) {
        const uint32_t interval = std::max(16u, (1000u + description.maximum_refresh_hz - 1) / description.maximum_refresh_hz);
        timer = new VSTGUI::CVSTGUITimer([this](VSTGUI::CVSTGUITimer*) { refresh(); }, interval, false);
        refresh();
    }
    return true;
}

void GraphControl::clear() {
    stop();
    if (graph) graph->unregisterViewListener(this);
    label_component.clear();
    graph_component.clear();
    graph_component.accessibility().clearActionHandler();
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
    if (graph) graph->cancelTransaction();
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

bool GraphControl::setParameter(uint32_t parameter_id, double normalized) {
    return graph && graph->setParameter(parameter_id, normalized);
}

bool GraphControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    return graph && graph->handleKey(key, key_code, modifiers);
}

VSTGUI::CView* GraphControl::focusView() const {
    return graph && (graph->editable() || graph->viewportEnabled() || graph->rangeSelectionEnabled())
        ? graph
        : nullptr;
}

void GraphControl::setFocusedView(VSTGUI::CView* view) {
    graph_component.setFocused(graph && view == graph);
}

GraphView* GraphControl::graphView() { return graph; }
const GraphView* GraphControl::graphView() const {
    return graph;
}

const AccessibilityNode& GraphControl::accessibilityNode() const {
    return graph_component.accessibility();
}

void GraphControl::viewLostFocus(VSTGUI::CView* view) {
    if (view == graph) graph_component.setFocused(false);
}

void GraphControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == graph) graph_component.setFocused(true);
}

bool GraphControl::accessibilityAction(
    void* userdata,
    const AccessibilityNode&,
    const AccessibilityActionRequest& request
) {
    auto* control = static_cast<GraphControl*>(userdata);
    return control && control->performAccessibilityAction(request);
}

bool GraphControl::performAccessibilityAction(const AccessibilityActionRequest& request) {
    if (!graph) return false;
    if (request.action == AccessibilityAction::focus) {
        if (!graph->getFrame()) return false;
        graph->getFrame()->setFocusView(graph);
        setFocusedView(graph);
        return true;
    }
    if (graph->rangeSelectionEnabled()) {
        if (request.action == AccessibilityAction::press) return graph->cycleRangeSelectionHandle();
        if (request.action == AccessibilityAction::select_previous) {
            graph->selectRangeSelectionHandle(RangeSelectionHandle::start);
            return true;
        }
        if (request.action == AccessibilityAction::select_next) {
            graph->selectRangeSelectionHandle(RangeSelectionHandle::end);
            return true;
        }
        if (request.action == AccessibilityAction::increment) {
            return graph->adjustRangeSelection(description.range_selection.step);
        }
        if (request.action == AccessibilityAction::decrement) {
            return graph->adjustRangeSelection(-description.range_selection.step);
        }
        if (request.action == AccessibilityAction::set_value) {
            return graph->setRangeSelectionValue(request.value);
        }
        return false;
    }
    if (graph->viewportEnabled() && !graph->editable()) {
        if (request.action == AccessibilityAction::increment) return graph->zoomViewportIn();
        if (request.action == AccessibilityAction::decrement) return graph->zoomViewportOut();
        if (request.action == AccessibilityAction::press) return graph->resetViewport();
        if (request.action == AccessibilityAction::set_value) return graph->setViewportZoom(request.value);
        return false;
    }
    if (!graph->editable()) return false;
    if (request.action == AccessibilityAction::press || request.action == AccessibilityAction::select_next) {
        return graph->selectAdjacent(true);
    }
    if (request.action == AccessibilityAction::select_previous) return graph->selectAdjacent(false);
    if (request.action == AccessibilityAction::add_point) {
        if (!graph->beginTransaction()) return false;
        const bool accepted = graph->addPoint(
            (description.x_axis.minimum + description.x_axis.maximum) * 0.5,
            request.value
        );
        if (accepted) graph->finishTransaction();
        else graph->cancelTransaction();
        return accepted;
    }
    if (request.action == AccessibilityAction::delete_selected) {
        if (!graph->beginTransaction()) return false;
        const bool accepted = graph->deleteSelected();
        if (accepted) graph->finishTransaction();
        else graph->cancelTransaction();
        return accepted;
    }
    ZigVstguiEnvelopePoint selected {};
    if (!graph->selectedPoint(selected) && !graph->selectAdjacent(true)) return false;
    if (!graph->selectedPoint(selected) || !graph->beginTransaction()) return false;
    bool accepted = false;
    const double y_step = description.snap_y > 0.0
        ? description.snap_y
        : (description.y_axis.maximum - description.y_axis.minimum) * 0.01;
    if (request.action == AccessibilityAction::increment) accepted = graph->adjustSelected(0.0, y_step);
    else if (request.action == AccessibilityAction::decrement) accepted = graph->adjustSelected(0.0, -y_step);
    else if (request.action == AccessibilityAction::set_value) accepted = graph->moveSelected(selected.x, request.value);
    if (accepted) graph->finishTransaction();
    else graph->cancelTransaction();
    return accepted;
}

}
