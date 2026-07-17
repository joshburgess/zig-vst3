#ifndef ZIG_VSTGUI_DRAWING_H
#define ZIG_VSTGUI_DRAWING_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_assets.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cview.h"
#include "vstgui/lib/controls/ccontrol.h"

namespace ZigVstgui {

class DrawingOverlay final : public VSTGUI::CView {
public:
    DrawingOverlay(
        uint32_t parameter_id,
        ZigVstguiDrawingComponent component,
        VSTGUI::CControl* source,
        const AssetStore* assets,
        ZigVstguiDrawingCallbacks callbacks
    );

    void draw(VSTGUI::CDrawContext* context) override;
    void setInteractionState(ZigVstguiDrawingState state);
    CLASS_METHODS_NOCOPY(DrawingOverlay, VSTGUI::CView)

private:
    ZigVstguiDrawingState drawingState() const;

    uint32_t parameter_id;
    ZigVstguiDrawingComponent component;
    VSTGUI::CControl* source;
    const AssetStore* assets;
    ZigVstguiDrawingCallbacks callbacks;
    ZigVstguiDrawingState interaction_state {ZIG_VSTGUI_DRAW_NORMAL};
};

}

#endif
