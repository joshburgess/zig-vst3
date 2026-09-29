#ifndef ZIG_VSTGUI_RANGE_SELECTION_H
#define ZIG_VSTGUI_RANGE_SELECTION_H

#include "zig_vstgui_adapter.h"

namespace ZigVstgui {

enum class RangeSelectionHandle {
    start,
    end,
};

class RangeSelectionModel {
public:
    bool configure(const ZigVstguiRangeSelectionDescription& description, double minimum, double maximum);
    bool enabled() const;
    double start() const;
    double end() const;
    double value(RangeSelectionHandle handle) const;
    RangeSelectionHandle activeHandle() const;
    void selectHandle(RangeSelectionHandle handle);
    void cycleHandle();
    bool set(RangeSelectionHandle handle, double value);
    bool adjust(double delta);
    bool replace(double first, double second);
    const ZigVstguiRangeSelectionDescription& description() const;

private:
    ZigVstguiRangeSelectionDescription config {};
    double range_minimum {0.0};
    double range_maximum {0.0};
    double selection_start {0.0};
    double selection_end {0.0};
    RangeSelectionHandle active_handle {RangeSelectionHandle::start};
    bool valid {false};
};

}

#endif
