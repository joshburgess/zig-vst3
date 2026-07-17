#ifndef ZIG_VSTGUI_LAYOUT_H
#define ZIG_VSTGUI_LAYOUT_H

#include "vstgui/lib/crect.h"

#include <cstdint>

namespace ZigVstgui {

enum class Axis {
    horizontal,
    vertical,
};

enum class Alignment {
    start,
    center,
    end,
    stretch,
};

enum class LayoutMode {
    compact,
    expanded,
};

struct Insets {
    double left {0.0};
    double top {0.0};
    double right {0.0};
    double bottom {0.0};
};

struct StackItem {
    double minimum_main {0.0};
    double minimum_cross {0.0};
    double flex {0.0};
};

struct GridTrack {
    double minimum {0.0};
    double flex {0.0};
};

struct GridItem {
    uint32_t column {0};
    uint32_t row {0};
    uint32_t column_span {1};
    uint32_t row_span {1};
};

VSTGUI::CRect insetRect(const VSTGUI::CRect& bounds, const Insets& insets);
bool layoutStack(
    const VSTGUI::CRect& bounds,
    Axis axis,
    Alignment alignment,
    const Insets& padding,
    double gap,
    const StackItem* items,
    uint32_t item_count,
    VSTGUI::CRect* output
);
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
);
LayoutMode layoutMode(uint32_t width, uint32_t height);

}

#endif
