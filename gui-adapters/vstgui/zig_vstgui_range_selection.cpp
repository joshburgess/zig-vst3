#include "zig_vstgui_range_selection.h"

#include <algorithm>
#include <cmath>

namespace ZigVstgui {

bool RangeSelectionModel::configure(
    const ZigVstguiRangeSelectionDescription& description,
    double minimum,
    double maximum
) {
    config = description;
    range_minimum = minimum;
    range_maximum = maximum;
    selection_start = minimum;
    selection_end = maximum;
    active_handle = RangeSelectionHandle::start;
    valid = config.enabled == 0;
    if (config.enabled == 0) return true;
    const double span = maximum - minimum;
    if (config.enabled != 1 || !std::isfinite(minimum) || !std::isfinite(maximum) || span <= 0.0 ||
        !std::isfinite(config.initial_start) || !std::isfinite(config.initial_end) ||
        !std::isfinite(config.minimum_span) || !std::isfinite(config.step) ||
        config.initial_start < minimum || config.initial_end > maximum ||
        config.initial_end < config.initial_start || config.minimum_span < 0.0 ||
        config.minimum_span > span || config.initial_end - config.initial_start < config.minimum_span ||
        config.step <= 0.0 || config.step > span ||
        ((config.start_state_id == 0) != (config.end_state_id == 0)) ||
        (config.start_state_id != 0 && config.start_state_id == config.end_state_id) ||
        (config.parameter_bound != 0 && config.parameter_bound != 1) ||
        (config.parameter_bound != 0 && (config.start_parameter_id == config.end_parameter_id ||
            config.start_step_count < 0 || config.end_step_count < 0 || config.start_state_id != 0))) return false;
    selection_start = config.initial_start;
    selection_end = config.initial_end;
    valid = true;
    return true;
}

bool RangeSelectionModel::enabled() const { return valid && config.enabled != 0; }
double RangeSelectionModel::start() const { return selection_start; }
double RangeSelectionModel::end() const { return selection_end; }
double RangeSelectionModel::value(RangeSelectionHandle handle) const {
    return handle == RangeSelectionHandle::start ? selection_start : selection_end;
}
RangeSelectionHandle RangeSelectionModel::activeHandle() const { return active_handle; }
void RangeSelectionModel::selectHandle(RangeSelectionHandle handle) { active_handle = handle; }
void RangeSelectionModel::cycleHandle() {
    active_handle = active_handle == RangeSelectionHandle::start
        ? RangeSelectionHandle::end
        : RangeSelectionHandle::start;
}

bool RangeSelectionModel::set(RangeSelectionHandle handle, double target) {
    if (!enabled() || !std::isfinite(target)) return false;
    const double previous_start = selection_start;
    const double previous_end = selection_end;
    const auto previous_handle = active_handle;
    if (handle == RangeSelectionHandle::start) {
        selection_start = std::clamp(
            target,
            range_minimum,
            range_maximum - config.minimum_span
        );
        selection_end = std::clamp(
            std::max(selection_end, selection_start + config.minimum_span),
            range_minimum + config.minimum_span,
            range_maximum
        );
    } else {
        selection_end = std::clamp(
            target,
            range_minimum + config.minimum_span,
            range_maximum
        );
        selection_start = std::clamp(
            std::min(selection_start, selection_end - config.minimum_span),
            range_minimum,
            range_maximum - config.minimum_span
        );
    }
    active_handle = handle;
    return selection_start != previous_start || selection_end != previous_end || active_handle != previous_handle;
}

bool RangeSelectionModel::adjust(double delta) {
    return std::isfinite(delta) && set(active_handle, value(active_handle) + delta);
}

bool RangeSelectionModel::replace(double first, double second) {
    if (!enabled() || !std::isfinite(first) || !std::isfinite(second)) return false;
    const double low = std::clamp(std::min(first, second), range_minimum, range_maximum);
    const double high = std::clamp(std::max(first, second), range_minimum, range_maximum);
    const double previous_start = selection_start;
    const double previous_end = selection_end;
    const auto previous_handle = active_handle;
    if (high - low >= config.minimum_span) {
        selection_start = low;
        selection_end = high;
    } else if (second >= first) {
        selection_start = low;
        selection_end = std::min(range_maximum, low + config.minimum_span);
        if (selection_end - selection_start < config.minimum_span) {
            selection_start = selection_end - config.minimum_span;
        }
    } else {
        selection_end = high;
        selection_start = std::max(range_minimum, high - config.minimum_span);
        if (selection_end - selection_start < config.minimum_span) {
            selection_end = selection_start + config.minimum_span;
        }
    }
    active_handle = second >= first ? RangeSelectionHandle::end : RangeSelectionHandle::start;
    return selection_start != previous_start || selection_end != previous_end || active_handle != previous_handle;
}

const ZigVstguiRangeSelectionDescription& RangeSelectionModel::description() const { return config; }

}
