#ifndef ZIG_VSTGUI_VIEWPORT_H
#define ZIG_VSTGUI_VIEWPORT_H

#include "zig_vstgui_adapter.h"

namespace ZigVstgui {

class ViewportModel {
public:
    bool configure(const ZigVstguiViewportDescription& description);
    bool enabled() const;
    bool horizontal() const;
    bool vertical() const;
    double zoom() const;
    double xOffset() const;
    double yOffset() const;
    double projectX(double normalized) const;
    double projectY(double normalized) const;
    double unprojectX(double visible) const;
    double unprojectY(double visible) const;
    bool zoomIn(double anchor_x = 0.5, double anchor_y = 0.5);
    bool zoomOut(double anchor_x = 0.5, double anchor_y = 0.5);
    bool setZoom(double value, double anchor_x = 0.5, double anchor_y = 0.5);
    bool pan(double x_steps, double y_steps);
    bool panToStart(bool horizontal_axis);
    bool panToEnd(bool horizontal_axis);
    bool reset();
    const ZigVstguiViewportDescription& description() const;

private:
    double visibleSpan(bool active) const;
    double maximumOffset() const;

    ZigVstguiViewportDescription config {};
    double current_zoom {1.0};
    double x_offset {0.0};
    double y_offset {0.0};
    bool valid {false};
};

}

#endif
