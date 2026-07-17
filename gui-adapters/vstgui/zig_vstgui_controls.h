#ifndef ZIG_VSTGUI_CONTROLS_H
#define ZIG_VSTGUI_CONTROLS_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/controls/cbuttons.h"
#include "vstgui/lib/controls/cslider.h"
#include "vstgui/lib/controls/ctextedit.h"
#include "vstgui/lib/controls/icontrollistener.h"

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

    uint32_t parameterId() const;
    double acceptedValue() const;
    bool gestureActive() const;
    const ZigVstguiCallbacks& callbacks() const;

private:
    uint32_t parameter_id;
    double accepted_value;
    ZigVstguiCallbacks callback_set;
    bool gesture_active {false};
};

class GainSlider final : public VSTGUI::CSlider {
public:
    GainSlider(
        const VSTGUI::CRect& size,
        VSTGUI::IControlListener* listener,
        int32_t tag,
        const ThemeResolver& styles
    );

    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
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
    bool hovered {false};
    bool pressed {false};
};

class ParameterControl final : public VSTGUI::IControlListener {
public:
    ParameterControl(uint32_t parameter_id, double initial, ZigVstguiCallbacks callbacks);
    ~ParameterControl() override;

    void build(
        VSTGUI::CViewContainer* parent,
        ZigVstguiParameterInfo parameter_info,
        const ThemeResolver& styles
    );
    void clear();
    void setValue(double value);
    void setBounds(const VSTGUI::CRect& slider_bounds, const VSTGUI::CRect& value_bounds);
    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers);
    VSTGUI::CSlider* focusView() const;

    void controlBeginEdit(VSTGUI::CControl* control) override;
    void valueChanged(VSTGUI::CControl* control) override;
    void controlEndEdit(VSTGUI::CControl* control) override;

    const ParameterControlModel& model() const;

private:
    void syncViews();

    ParameterControlModel control_model;
    GainSlider* slider {nullptr};
    VSTGUI::CTextEdit* value_edit {nullptr};
    Component slider_component;
    Component value_component;
};

class ResizeControl final : public VSTGUI::IControlListener {
public:
    void build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    void setSize(uint32_t width, uint32_t height);
    void setCallbacks(ZigVstguiResizeCallbacks callbacks);

    void valueChanged(VSTGUI::CControl* control) override;

private:
    VSTGUI::CTextButton* button {nullptr};
    Component component;
    ZigVstguiResizeCallbacks callbacks {};
    uint32_t current_width {400};
    uint32_t current_height {300};
};

}

#endif
