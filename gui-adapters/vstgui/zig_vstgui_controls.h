#ifndef ZIG_VSTGUI_CONTROLS_H
#define ZIG_VSTGUI_CONTROLS_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_drawing.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/controls/cbuttons.h"
#include "vstgui/lib/controls/cknob.h"
#include "vstgui/lib/controls/coptionmenu.h"
#include "vstgui/lib/controls/csegmentbutton.h"
#include "vstgui/lib/controls/cslider.h"
#include "vstgui/lib/controls/ctextedit.h"
#include "vstgui/lib/controls/ctextlabel.h"
#include "vstgui/lib/controls/icontrollistener.h"
#include "vstgui/lib/iviewlistener.h"

#include <string>
#include <optional>

namespace ZigVstgui {

double clampNormalized(double value);

class ParameterControlModel {
public:
    ParameterControlModel(uint32_t parameter_id, double initial, ZigVstguiCallbacks callbacks);
    ~ParameterControlModel();

    bool beginGesture();
    bool performEdit(double requested);
    void endGesture();
    void cancelGesture();
    void hostChanged(double value);
    void setStepCount(int32_t step_count);

    uint32_t parameterId() const;
    double acceptedValue() const;
    bool gestureActive() const;
    const ZigVstguiCallbacks& callbacks() const;

private:
    uint32_t parameter_id;
    double accepted_value;
    ZigVstguiCallbacks callback_set;
    bool gesture_active {false};
    int32_t step_count {0};
};

class GainSlider final : public VSTGUI::CSlider {
public:
    GainSlider(
        const VSTGUI::CRect& size,
        VSTGUI::IControlListener* listener,
        int32_t tag,
        const ThemeResolver& styles,
        ZigVstguiControlKind control_kind = ZIG_VSTGUI_CONTROL_LINEAR_SLIDER
    );

    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    void setModulation(double normalized);
    void forceVisualStateForTesting(std::optional<VisualState> state);
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onMouseUpEvent(VSTGUI::MouseUpEvent& event) override;
    void onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) override;
    void onMouseEnterEvent(VSTGUI::MouseEnterEvent& event) override;
    void onMouseExitEvent(VSTGUI::MouseExitEvent& event) override;
    void onKeyboardEvent(VSTGUI::KeyboardEvent& event) override;

private:
    VisualState visualState() const;

    const ThemeResolver& styles;
    bool centered {false};
    bool hovered {false};
    bool pressed {false};
    std::optional<double> modulation;
    std::optional<VisualState> forced_state;
};

class ParameterControl final :
    public VSTGUI::IControlListener,
    public VSTGUI::IViewEventListener,
    public VSTGUI::ViewListenerAdapter {
public:
    ParameterControl(uint32_t parameter_id, double initial, ZigVstguiCallbacks callbacks);
    ~ParameterControl() override;

    void build(
        VSTGUI::CViewContainer* parent,
        ZigVstguiParameterInfo parameter_info,
        ZigVstguiControlKind control_kind,
        const ThemeResolver& styles,
        const AssetStore* assets = nullptr,
        ZigVstguiDrawingCallbacks drawing = {}
    );
    void clear();
    void setValue(double value);
    void setModulation(double normalized);
    void setEnabled(bool enabled);
    void setBounds(
        const VSTGUI::CRect& label_bounds,
        const VSTGUI::CRect& slider_bounds,
        const VSTGUI::CRect& value_bounds
    );
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    VSTGUI::CControl* focusView() const;
    VSTGUI::CControl* valueFocusView() const;
    void setFocusedView(VSTGUI::CView* view);
    bool showContextMenu(int32_t x, int32_t y);
    const AccessibilityNode& primaryAccessibility() const;
    const AccessibilityNode* valueAccessibility() const;
    VSTGUI::CPoint labelTextInset() const;
    double primaryValueGap() const;

    void controlBeginEdit(VSTGUI::CControl* control) override;
    void valueChanged(VSTGUI::CControl* control) override;
    void controlEndEdit(VSTGUI::CControl* control) override;
    void viewOnEvent(VSTGUI::CView* view, VSTGUI::Event& event) override;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

    const ParameterControlModel& model() const;

private:
    static bool accessibilityAction(
        void* userdata,
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool performAccessibilityAction(
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool applyAccessibleValue(double normalized);
    void buildPrimaryControl(
        VSTGUI::CViewContainer* parent,
        ZigVstguiParameterInfo parameter_info,
        ZigVstguiControlKind control_kind,
        const ThemeResolver& styles,
        const AssetStore* assets,
        ZigVstguiDrawingCallbacks drawing
    );
    std::string formattedValue(double normalized) const;
    void syncViews();

    ParameterControlModel control_model;
    ZigVstguiParameterInfo parameter_info {};
    ZigVstguiControlKind control_kind {ZIG_VSTGUI_CONTROL_LINEAR_SLIDER};
    std::string label_text;
    float disabled_alpha {0.45f};
    VSTGUI::CTextLabel* label {nullptr};
    GainSlider* slider {nullptr};
    VSTGUI::CKnob* knob {nullptr};
    VSTGUI::CTextButton* toggle {nullptr};
    VSTGUI::COptionMenu* dropdown {nullptr};
    VSTGUI::CSegmentButton* segmented {nullptr};
    VSTGUI::CControl* primary_control {nullptr};
    VSTGUI::CTextEdit* value_edit {nullptr};
    DrawingOverlay* drawing_overlay {nullptr};
    bool primary_hovered {false};
    bool primary_pressed {false};
    Component label_component;
    Component primary_component;
    Component value_component;
};

class ResizeControl;

class ResizeHandle final : public VSTGUI::CControl {
public:
    ResizeHandle(const VSTGUI::CRect& size, ResizeControl* owner, const ThemeResolver& styles);
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) override;
    void onMouseUpEvent(VSTGUI::MouseUpEvent& event) override;
    void onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) override;
    void setCurrentSize(uint32_t width, uint32_t height);
    CLASS_METHODS_NOCOPY(ResizeHandle, VSTGUI::CControl)

private:
    ResizeControl* owner;
    const ThemeResolver& styles;
    VSTGUI::CPoint drag_origin;
    uint32_t start_width {400};
    uint32_t start_height {300};
    uint32_t current_width {400};
    uint32_t current_height {300};
    bool dragging {false};
};

class ResizeControl final : public VSTGUI::IControlListener, public VSTGUI::ViewListenerAdapter {
public:
    void build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    void setSize(uint32_t width, uint32_t height);
    void setCallbacks(ZigVstguiResizeCallbacks callbacks);
    bool requestResize(uint32_t width, uint32_t height);
    VSTGUI::CControl* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& buttonAccessibility() const;
    const AccessibilityNode& handleAccessibility() const;

    void valueChanged(VSTGUI::CControl* control) override;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(
        void* userdata,
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool performAccessibilityAction(const AccessibilityActionRequest& request);
    VSTGUI::CTextButton* button {nullptr};
    ResizeHandle* handle {nullptr};
    Component button_component;
    Component handle_component;
    ZigVstguiResizeCallbacks callbacks {};
    uint32_t current_width {400};
    uint32_t current_height {300};
};

}

#endif
