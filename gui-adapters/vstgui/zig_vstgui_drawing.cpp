#include "zig_vstgui_drawing.h"

#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"

#include <algorithm>

struct ZigVstguiCanvas {
    VSTGUI::CDrawContext* context;
    VSTGUI::CRect bounds;
    const ZigVstgui::AssetStore* assets;
};

namespace {

VSTGUI::CColor colorFromRgba(uint32_t rgba) {
    return VSTGUI::CColor(
        static_cast<uint8_t>((rgba >> 24) & 0xff),
        static_cast<uint8_t>((rgba >> 16) & 0xff),
        static_cast<uint8_t>((rgba >> 8) & 0xff),
        static_cast<uint8_t>(rgba & 0xff)
    );
}

VSTGUI::CRect localRect(
    const ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom
) {
    return VSTGUI::CRect(
        canvas->bounds.left + left,
        canvas->bounds.top + top,
        canvas->bounds.left + right,
        canvas->bounds.top + bottom
    );
}

}

extern "C" void zig_vstgui_canvas_fill_rect(
    ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom,
    uint32_t rgba
) {
    if (!canvas || !canvas->context) return;
    canvas->context->setFillColor(colorFromRgba(rgba));
    canvas->context->drawRect(localRect(canvas, left, top, right, bottom), VSTGUI::kDrawFilled);
}

extern "C" void zig_vstgui_canvas_stroke_rect(
    ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom,
    uint32_t rgba,
    double width
) {
    if (!canvas || !canvas->context || width <= 0.0) return;
    canvas->context->setFrameColor(colorFromRgba(rgba));
    canvas->context->setLineWidth(width);
    canvas->context->drawRect(localRect(canvas, left, top, right, bottom), VSTGUI::kDrawStroked);
}

extern "C" void zig_vstgui_canvas_fill_ellipse(
    ZigVstguiCanvas* canvas,
    double left,
    double top,
    double right,
    double bottom,
    uint32_t rgba
) {
    if (!canvas || !canvas->context) return;
    canvas->context->setFillColor(colorFromRgba(rgba));
    canvas->context->drawEllipse(localRect(canvas, left, top, right, bottom), VSTGUI::kDrawFilled);
}

extern "C" void zig_vstgui_canvas_line(
    ZigVstguiCanvas* canvas,
    double start_x,
    double start_y,
    double end_x,
    double end_y,
    uint32_t rgba,
    double width
) {
    if (!canvas || !canvas->context || width <= 0.0) return;
    canvas->context->setFrameColor(colorFromRgba(rgba));
    canvas->context->setLineWidth(width);
    canvas->context->drawLine(
        VSTGUI::CPoint(canvas->bounds.left + start_x, canvas->bounds.top + start_y),
        VSTGUI::CPoint(canvas->bounds.left + end_x, canvas->bounds.top + end_y)
    );
}

extern "C" int32_t zig_vstgui_canvas_draw_asset(
    ZigVstguiCanvas* canvas,
    uint32_t asset_id,
    double left,
    double top,
    double right,
    double bottom,
    float alpha
) {
    if (!canvas || !canvas->context || !canvas->assets) return -1;
    return canvas->assets->draw(
        asset_id,
        canvas->context,
        localRect(canvas, left, top, right, bottom),
        alpha
    ) ? 0 : -1;
}

namespace ZigVstgui {

DrawingOverlay::DrawingOverlay(
    uint32_t value_parameter_id,
    ZigVstguiDrawingComponent value_component,
    VSTGUI::CControl* value_source,
    const AssetStore* value_assets,
    ZigVstguiDrawingCallbacks value_callbacks
)
: CView(VSTGUI::CRect()),
  parameter_id(value_parameter_id),
  component(value_component),
  source(value_source),
  assets(value_assets),
  callbacks(value_callbacks) {
    setMouseEnabled(false);
    setTransparency(true);
}

void DrawingOverlay::draw(VSTGUI::CDrawContext* context) {
    if (!context || !source || !callbacks.draw_parameter) {
        setDirty(false);
        return;
    }
    const auto bounds = getViewSize();
    const ZigVstguiDrawRequest request {
        parameter_id,
        component,
        drawingState(),
        source->getValueNormalized(),
        bounds.getWidth(),
        bounds.getHeight(),
        context->getScaleFactor(),
    };
    ZigVstguiCanvas canvas {context, bounds, assets};
    context->saveGlobalState();
    context->setClipRect(bounds);
    context->setDrawMode(VSTGUI::kAntiAliasing);
    if (callbacks.draw_parameter(callbacks.userdata, &request, &canvas) != 0) {
        drawMissingAsset(context, bounds);
    }
    context->restoreGlobalState();
    setDirty(false);
}

void DrawingOverlay::setInteractionState(ZigVstguiDrawingState state) {
    if (interaction_state == state) return;
    interaction_state = state;
    invalid();
}

ZigVstguiDrawingState DrawingOverlay::drawingState() const {
    if (!source->getMouseEnabled()) return ZIG_VSTGUI_DRAW_DISABLED;
    if (interaction_state == ZIG_VSTGUI_DRAW_PRESSED) return interaction_state;
    if (source->isEditing()) return ZIG_VSTGUI_DRAW_EDITING;
    const auto* frame = source->getFrame();
    if (frame && frame->getFocusView() == source) return ZIG_VSTGUI_DRAW_FOCUSED;
    return interaction_state;
}

}
