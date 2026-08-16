#ifndef ZIG_VSTGUI_STEP_SEQUENCER_H
#define ZIG_VSTGUI_STEP_SEQUENCER_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_meters.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cview.h"
#include "vstgui/lib/cvstguitimer.h"
#include "vstgui/lib/iviewlistener.h"
#include "vstgui/lib/controls/ctextlabel.h"

#include <array>
#include <string>

namespace ZigVstgui {

class StepSequencerControl;

class StepSequencerView final : public VSTGUI::CView {
public:
    StepSequencerView(const VSTGUI::CRect& size, StepSequencerControl* owner, const ThemeResolver& styles);
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) override;
    void onMouseUpEvent(VSTGUI::MouseUpEvent& event) override;
    void onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) override;
    CLASS_METHODS_NOCOPY(StepSequencerView, VSTGUI::CView)

private:
    StepSequencerControl* owner;
    const ThemeResolver& styles;
};

class StepSequencerControl final : public VSTGUI::ViewListenerAdapter {
public:
    StepSequencerControl(
        ZigVstguiStepSequencerDescription description,
        ZigVstguiCallbacks callbacks,
        MeterSource telemetry
    );
    ~StepSequencerControl() override;

    void build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& sequencer_bounds);
    void start();
    void stop();
    bool tick();
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    bool setParameter(uint32_t parameter_id, double normalized);
    VSTGUI::CView* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& accessibilityNode() const;

    uint32_t stepCount() const;
    uint32_t cursor() const;
    int32_t playhead() const;
    bool stepActive(uint32_t step) const;
    bool stepSelected(uint32_t step) const;
    bool enabled() const;
    bool editFailed() const;
    int hitTest(const VSTGUI::CPoint& position) const;
    void pointerBegin(uint32_t step, bool additive, bool range);
    void pointerPaint(uint32_t step);
    void pointerEnd();

    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(void* userdata, const AccessibilityNode&, const AccessibilityActionRequest& request);
    bool performAccessibilityAction(const AccessibilityActionRequest& request);
    void select(uint32_t step, bool additive, bool range);
    void move(bool previous, bool extend);
    void toggleSelected();
    void setStep(uint32_t step, bool active);
    void storeSelection();
    void syncAccessibility();
    uint32_t validMask() const;
    uint32_t rangeMask(uint32_t first, uint32_t last) const;

    ZigVstguiStepSequencerDescription description {};
    ZigVstguiCallbacks callbacks {};
    MeterSource telemetry {};
    std::string title;
    std::array<uint32_t, ZIG_VSTGUI_MAX_STEPS> parameter_ids {};
    VSTGUI::CTextLabel* label {nullptr};
    StepSequencerView* sequencer {nullptr};
    VSTGUI::CVSTGUITimer* timer {nullptr};
    Component label_component;
    Component sequencer_component;
    uint32_t active_mask {0};
    uint32_t selection_mask {0};
    uint32_t cursor_step {0};
    uint32_t anchor_step {0};
    int32_t playhead_step {-1};
    bool painting {false};
    bool paint_active {false};
    bool edit_failed {false};
};

}

#endif
