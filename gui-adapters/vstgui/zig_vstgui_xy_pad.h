#ifndef ZIG_VSTGUI_XY_PAD_H
#define ZIG_VSTGUI_XY_PAD_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/controls/cxypad.h"
#include "vstgui/lib/iviewlistener.h"

#include <optional>
#include <string>

namespace ZigVstgui {

class MultiParameterControlModel {
public:
    MultiParameterControlModel(
        uint32_t x_parameter_id,
        double initial_x,
        int32_t x_step_count,
        uint32_t y_parameter_id,
        double initial_y,
        int32_t y_step_count,
        ZigVstguiCallbacks callbacks
    );
    ~MultiParameterControlModel();

    bool beginGesture();
    bool performEdit(double x, double y);
    void endGesture();
    void cancelGesture();
    bool hostChanged(uint32_t parameter_id, double value);
    uint32_t parameterId(uint32_t axis) const;
    double acceptedValue(uint32_t axis) const;
    bool gestureActive() const;
    const ZigVstguiCallbacks& callbacks() const;

private:
    ParameterControlModel x_model;
    ParameterControlModel y_model;
    double initial_x {0.0};
    double initial_y {0.0};
    bool gesture_active {false};
};

class XYPadControl;

class XYPadView final : public VSTGUI::CXYPad {
public:
    XYPadView(const VSTGUI::CRect& size, XYPadControl* owner, const ThemeResolver& styles);
    void setXY(double x, double y);
    void getXY(double& x, double& y) const;
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    void draw(VSTGUI::CDrawContext* context) override;
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    void onMouseUpEvent(VSTGUI::MouseUpEvent& event) override;
    void onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) override;
    void onMouseEnterEvent(VSTGUI::MouseEnterEvent& event) override;
    void onMouseExitEvent(VSTGUI::MouseExitEvent& event) override;
    void onKeyboardEvent(VSTGUI::KeyboardEvent& event) override;
    CLASS_METHODS_NOCOPY(XYPadView, VSTGUI::CXYPad)

private:
    VisualState visualState() const;

    XYPadControl* owner;
    const ThemeResolver& styles;
    bool hovered {false};
    bool pressed {false};
};

class XYPadControl final :
    public VSTGUI::IControlListener,
    public VSTGUI::ViewListenerAdapter {
public:
    XYPadControl(
        ZigVstguiXYPadDescription description,
        ZigVstguiParameterInfo x_info,
        double initial_x,
        ZigVstguiParameterInfo y_info,
        double initial_y,
        ZigVstguiCallbacks callbacks
    );
    ~XYPadControl() override;

    void build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& pad_bounds);
    bool setParameter(uint32_t parameter_id, double value);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    VSTGUI::CView* focusView() const;
    void setFocusedView(VSTGUI::CView* view);
    const AccessibilityNode& axisAccessibility(uint32_t axis) const;
    void selectAxis(uint32_t axis);

    void controlBeginEdit(VSTGUI::CControl* control) override;
    void valueChanged(VSTGUI::CControl* control) override;
    void controlEndEdit(VSTGUI::CControl* control) override;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

    const MultiParameterControlModel& model() const;

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
    std::string formattedValue(uint32_t axis, double normalized) const;
    void syncView();
    void syncAccessibility();

    ZigVstguiXYPadDescription description {};
    ZigVstguiParameterInfo parameter_info[2] {};
    std::string title;
    std::string axis_labels[2];
    MultiParameterControlModel control_model;
    VSTGUI::CTextLabel* label {nullptr};
    XYPadView* pad {nullptr};
    Component label_component;
    Component pad_component;
    AccessibilityNode axis_accessibility[2];
    uint32_t selected_axis {0};
};

}

#endif
