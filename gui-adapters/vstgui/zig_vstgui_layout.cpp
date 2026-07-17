#include "zig_vstgui_layout.h"

#include <algorithm>
#include <array>

namespace ZigVstgui {

namespace {

constexpr uint32_t kMaximumTracks = 64;

double extent(const VSTGUI::CRect& rect, Axis axis) {
    return axis == Axis::horizontal ? rect.getWidth() : rect.getHeight();
}

double start(const VSTGUI::CRect& rect, Axis axis) {
    return axis == Axis::horizontal ? rect.left : rect.top;
}

VSTGUI::CRect makeRect(Axis axis, double main_start, double cross_start, double main_end, double cross_end) {
    return axis == Axis::horizontal
        ? VSTGUI::CRect(main_start, cross_start, main_end, cross_end)
        : VSTGUI::CRect(cross_start, main_start, cross_end, main_end);
}

bool solveTracks(
    double available,
    double gap,
    const GridTrack* tracks,
    uint32_t count,
    std::array<double, kMaximumTracks>& starts,
    std::array<double, kMaximumTracks>& ends
) {
    if (!tracks || count == 0 || count > kMaximumTracks) return false;
    double minimum = gap * (count - 1);
    double total_flex = 0.0;
    for (uint32_t index = 0; index < count; ++index) {
        minimum += std::max(0.0, tracks[index].minimum);
        total_flex += std::max(0.0, tracks[index].flex);
    }
    const double extra = std::max(0.0, available - minimum);
    double cursor = 0.0;
    for (uint32_t index = 0; index < count; ++index) {
        starts[index] = cursor;
        const double share = total_flex > 0.0
            ? extra * std::max(0.0, tracks[index].flex) / total_flex
            : 0.0;
        cursor += std::max(0.0, tracks[index].minimum) + share;
        ends[index] = cursor;
        cursor += gap;
    }
    return true;
}

}

VSTGUI::CRect insetRect(const VSTGUI::CRect& bounds, const Insets& insets) {
    return VSTGUI::CRect(
        std::min(bounds.right, bounds.left + std::max(0.0, insets.left)),
        std::min(bounds.bottom, bounds.top + std::max(0.0, insets.top)),
        std::max(bounds.left, bounds.right - std::max(0.0, insets.right)),
        std::max(bounds.top, bounds.bottom - std::max(0.0, insets.bottom))
    );
}

bool layoutStack(
    const VSTGUI::CRect& bounds,
    Axis axis,
    Alignment alignment,
    const Insets& padding,
    double gap,
    const StackItem* items,
    uint32_t item_count,
    VSTGUI::CRect* output
) {
    if ((!items && item_count > 0) || (!output && item_count > 0)) return false;
    const auto content = insetRect(bounds, padding);
    const Axis cross_axis = axis == Axis::horizontal ? Axis::vertical : Axis::horizontal;
    double minimum = item_count > 0 ? std::max(0.0, gap) * (item_count - 1) : 0.0;
    double total_flex = 0.0;
    for (uint32_t index = 0; index < item_count; ++index) {
        minimum += std::max(0.0, items[index].minimum_main);
        total_flex += std::max(0.0, items[index].flex);
    }
    const double extra = std::max(0.0, extent(content, axis) - minimum);
    const double cross_extent = extent(content, cross_axis);
    double cursor = start(content, axis);
    for (uint32_t index = 0; index < item_count; ++index) {
        const double share = total_flex > 0.0
            ? extra * std::max(0.0, items[index].flex) / total_flex
            : 0.0;
        const double item_extent = std::max(0.0, items[index].minimum_main) + share;
        const double requested_cross = std::min(cross_extent, std::max(0.0, items[index].minimum_cross));
        const double item_cross = alignment == Alignment::stretch ? cross_extent : requested_cross;
        double cross_start = start(content, cross_axis);
        if (alignment == Alignment::center) cross_start += (cross_extent - item_cross) / 2.0;
        if (alignment == Alignment::end) cross_start += cross_extent - item_cross;
        output[index] = makeRect(axis, cursor, cross_start, cursor + item_extent, cross_start + item_cross);
        cursor += item_extent + std::max(0.0, gap);
    }
    return true;
}

bool layoutGrid(
    const VSTGUI::CRect& bounds,
    const Insets& padding,
    double column_gap,
    double row_gap,
    const GridTrack* columns,
    uint32_t column_count,
    const GridTrack* rows,
    uint32_t row_count,
    const GridItem* items,
    uint32_t item_count,
    VSTGUI::CRect* output
) {
    if ((!items && item_count > 0) || (!output && item_count > 0)) return false;
    const auto content = insetRect(bounds, padding);
    std::array<double, kMaximumTracks> column_starts {};
    std::array<double, kMaximumTracks> column_ends {};
    std::array<double, kMaximumTracks> row_starts {};
    std::array<double, kMaximumTracks> row_ends {};
    if (!solveTracks(content.getWidth(), std::max(0.0, column_gap), columns, column_count, column_starts, column_ends) ||
        !solveTracks(content.getHeight(), std::max(0.0, row_gap), rows, row_count, row_starts, row_ends)) return false;
    for (uint32_t index = 0; index < item_count; ++index) {
        const auto& item = items[index];
        if (item.column >= column_count || item.row >= row_count || item.column_span == 0 || item.row_span == 0) return false;
        const uint32_t last_column = item.column + item.column_span - 1;
        const uint32_t last_row = item.row + item.row_span - 1;
        if (last_column >= column_count || last_row >= row_count) return false;
        output[index] = VSTGUI::CRect(
            content.left + column_starts[item.column],
            content.top + row_starts[item.row],
            content.left + column_ends[last_column],
            content.top + row_ends[last_row]
        );
    }
    return true;
}

LayoutMode layoutMode(uint32_t width, uint32_t height) {
    return width >= 520 && height >= 360 ? LayoutMode::expanded : LayoutMode::compact;
}

}
