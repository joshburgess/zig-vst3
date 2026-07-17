#include "zig_vstgui_controls.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cgradient.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <cstdio>

namespace ZigVstgui {

namespace {

constexpr int32_t kParameterTag = 1;
constexpr int32_t kValueTag = 2;
constexpr int32_t kResizeTag = 3;

}

double clampNormalized(double value) {
    return std::clamp(value, 0.0, 1.0);
}

ParameterControlModel::ParameterControlModel(
    uint32_t value_parameter_id,
    double initial,
    ZigVstguiCallbacks callbacks
)
: parameter_id(value_parameter_id),
  accepted_value(clampNormalized(initial)),
  callback_set(callbacks) {}

ParameterControlModel::~ParameterControlModel() {
    cancelGesture();
}

bool ParameterControlModel::beginGesture() {
    if (gesture_active) return false;
    if (callback_set.begin_edit) callback_set.begin_edit(callback_set.userdata, parameter_id);
    gesture_active = true;
    return true;
}

bool ParameterControlModel::performEdit(double requested) {
    if (!gesture_active) return false;
    const double normalized = clampNormalized(requested);
    if (!callback_set.perform_edit ||
        callback_set.perform_edit(callback_set.userdata, parameter_id, normalized) != 0) return false;
    accepted_value = normalized;
    return true;
}

void ParameterControlModel::endGesture() {
    if (!gesture_active) return;
    if (callback_set.end_edit) callback_set.end_edit(callback_set.userdata, parameter_id);
    gesture_active = false;
}

void ParameterControlModel::cancelGesture() {
    endGesture();
}

void ParameterControlModel::hostChanged(double value) {
    accepted_value = clampNormalized(value);
}

uint32_t ParameterControlModel::parameterId() const {
    return parameter_id;
}

double ParameterControlModel::acceptedValue() const {
    return accepted_value;
}

bool ParameterControlModel::gestureActive() const {
    return gesture_active;
}

const ZigVstguiCallbacks& ParameterControlModel::callbacks() const {
    return callback_set;
}

GainSlider::GainSlider(
    const VSTGUI::CRect& size,
    VSTGUI::IControlListener* listener,
    int32_t tag,
    const Theme& value_theme
)
: CSlider(size, listener, tag, 0, 1, nullptr, nullptr), theme(value_theme) {}

bool GainSlider::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    VSTGUI::VirtualKey virtual_key = VSTGUI::VirtualKey::None;
    switch (key_code) {
        case Steinberg::KEY_END: virtual_key = VSTGUI::VirtualKey::End; break;
        case Steinberg::KEY_HOME: virtual_key = VSTGUI::VirtualKey::Home; break;
        case Steinberg::KEY_LEFT: virtual_key = VSTGUI::VirtualKey::Left; break;
        case Steinberg::KEY_UP: virtual_key = VSTGUI::VirtualKey::Up; break;
        case Steinberg::KEY_RIGHT: virtual_key = VSTGUI::VirtualKey::Right; break;
        case Steinberg::KEY_DOWN: virtual_key = VSTGUI::VirtualKey::Down; break;
        default: return false;
    }
    VSTGUI::KeyboardEvent event;
    event.type = VSTGUI::EventType::KeyDown;
    event.character = key;
    event.virt = virtual_key;
    if ((modifiers & 1) != 0) event.modifiers.add(VSTGUI::ModifierKey::Shift);
    if ((modifiers & 2) != 0) event.modifiers.add(VSTGUI::ModifierKey::Alt);
    if ((modifiers & 4) != 0) event.modifiers.add(VSTGUI::ModifierKey::Control);
    if ((modifiers & 8) != 0) event.modifiers.add(VSTGUI::ModifierKey::Super);
    onKeyboardEvent(event);
    return event.consumed;
}

void GainSlider::draw(VSTGUI::CDrawContext* context) {
    CSlider::draw(context);
    const auto bounds = getViewSize();
    const auto center_x = bounds.left + bounds.getWidth() * getValueNormalized();
    const auto center_y = bounds.top + bounds.getHeight() / 2.0;
    VSTGUI::CRect thumb(center_x - 8.0, center_y - 8.0, center_x + 8.0, center_y + 8.0);
    context->setDrawMode(VSTGUI::kAntiAliasing);
    context->setLineWidth(2.0);
    context->setFrameColor(theme.control_fill);
    context->setFillColor(theme.text_primary);
    context->drawEllipse(thumb, VSTGUI::kDrawFilledAndStroked);
}

void GainSlider::onKeyboardEvent(VSTGUI::KeyboardEvent& event) {
    if (event.type == VSTGUI::EventType::KeyDown &&
        (event.virt == VSTGUI::VirtualKey::Home || event.virt == VSTGUI::VirtualKey::End)) {
        beginEdit();
        setValueNormalized(event.virt == VSTGUI::VirtualKey::Home ? 0.f : 1.f);
        valueChanged();
        endEdit();
        invalid();
        event.consumed = true;
        return;
    }
    CSlider::onKeyboardEvent(event);
}

ParameterControl::ParameterControl(uint32_t parameter_id, double initial, ZigVstguiCallbacks callbacks)
: control_model(parameter_id, initial, callbacks) {}

ParameterControl::~ParameterControl() {
    control_model.cancelGesture();
}

void ParameterControl::build(
    VSTGUI::CViewContainer* parent,
    ZigVstguiParameterInfo parameter_info,
    const Theme& theme
) {
    if (!parent || slider || value_edit) return;
    slider = new GainSlider(VSTGUI::CRect(), this, kParameterTag, theme);
    slider->setMin(0.f);
    slider->setMax(1.f);
    slider->setDefaultValue(static_cast<float>(clampNormalized(parameter_info.default_normalized)));
    slider->setWheelInc(parameter_info.step_count > 0 ? 1.f / static_cast<float>(parameter_info.step_count) : 0.01f);
    slider->setDrawStyle(VSTGUI::CSlider::kDrawFrame | VSTGUI::CSlider::kDrawBack | VSTGUI::CSlider::kDrawValue);
    slider->setFrameWidth(2.0);
    slider->setFrameColor(theme.control_track);
    slider->setBackColor(theme.surface_raised);
    slider->setValueColor(theme.control_fill);
    parent->addView(slider);
    slider_component.bind(slider);
    slider_component.setFocusable(true);

    value_edit = new VSTGUI::CTextEdit(VSTGUI::CRect(), this, kValueTag, "");
    value_edit->setMin(0.f);
    value_edit->setMax(1.f);
    value_edit->setDefaultValue(static_cast<float>(clampNormalized(parameter_info.default_normalized)));
    value_edit->setFontColor(theme.text_primary);
    value_edit->setBackColor(theme.surface_raised);
    value_edit->setFrameColor(theme.focus_ring);
    value_edit->setRoundRectRadius(8);
    value_edit->setValueToStringFunction([](float value, char text[256], VSTGUI::CParamDisplay* display) {
        auto* control = static_cast<ParameterControl*>(display->getListener());
        if (control && control->control_model.callbacks().format_value) {
            const auto& callbacks = control->control_model.callbacks();
            return callbacks.format_value(
                callbacks.userdata,
                control->control_model.parameterId(),
                static_cast<double>(value),
                text,
                256
            ) >= 0;
        }
        std::snprintf(text, 256, "%.3f", static_cast<double>(value));
        return true;
    });
    value_edit->setStringToValueFunction([](VSTGUI::UTF8StringPtr text, float& value, VSTGUI::CTextEdit* edit) {
        if (!text) return false;
        auto* control = static_cast<ParameterControl*>(edit->getListener());
        if (!control || !control->control_model.callbacks().parse_value) return false;
        const auto& callbacks = control->control_model.callbacks();
        double parsed = 0.0;
        if (callbacks.parse_value(
                callbacks.userdata,
                control->control_model.parameterId(),
                text,
                &parsed
            ) != 0) return false;
        value = static_cast<float>(clampNormalized(parsed));
        return true;
    });
    parent->addView(value_edit);
    value_component.bind(value_edit);
    value_component.setFocusable(true);
    syncViews();
}

void ParameterControl::clear() {
    control_model.cancelGesture();
    slider_component.clear();
    value_component.clear();
    slider = nullptr;
    value_edit = nullptr;
}

void ParameterControl::setValue(double value) {
    control_model.hostChanged(value);
    syncViews();
}

void ParameterControl::setBounds(
    const VSTGUI::CRect& slider_bounds,
    const VSTGUI::CRect& value_bounds
) {
    slider_component.setBounds(slider_bounds);
    value_component.setBounds(value_bounds);
}

bool ParameterControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    return slider && slider->handleKey(key, key_code, modifiers);
}

VSTGUI::CSlider* ParameterControl::focusView() const {
    return slider;
}

void ParameterControl::controlBeginEdit(VSTGUI::CControl*) {
    if (control_model.beginGesture()) {
        slider_component.setEditing(true);
        value_component.setEditing(true);
    }
}

void ParameterControl::valueChanged(VSTGUI::CControl* control) {
    if (!control) return;
    const double requested = clampNormalized(control->getValueNormalized());
    control_model.performEdit(requested);
    syncViews();
}

void ParameterControl::controlEndEdit(VSTGUI::CControl*) {
    control_model.endGesture();
    slider_component.setEditing(false);
    value_component.setEditing(false);
}

const ParameterControlModel& ParameterControl::model() const {
    return control_model;
}

void ParameterControl::syncViews() {
    const float normalized = static_cast<float>(control_model.acceptedValue());
    if (slider) {
        slider->setValueNormalized(normalized);
        slider->invalid();
    }
    if (value_edit) {
        value_edit->setValueNormalized(normalized);
        value_edit->invalid();
    }
}

void ResizeControl::build(VSTGUI::CViewContainer* parent, const Theme& theme) {
    if (!parent || button) return;
    button = new VSTGUI::CTextButton(VSTGUI::CRect(), this, kResizeTag, "Expand");
    button->setTextColor(theme.text_primary);
    button->setTextColorHighlighted(theme.text_primary);
    button->setFrameColor(theme.focus_ring);
    button->setFrameColorHighlighted(theme.control_fill_highlighted);
    button->setGradient(VSTGUI::owned(VSTGUI::CGradient::create(0, 1, theme.button_top, theme.button_bottom)));
    button->setGradientHighlighted(VSTGUI::owned(VSTGUI::CGradient::create(
        0,
        1,
        theme.button_top_highlighted,
        theme.button_bottom_highlighted
    )));
    button->setRoundRadius(8);
    parent->addView(button);
    component.bind(button);
    component.setFocusable(true);
    setSize(current_width, current_height);
}

void ResizeControl::clear() {
    component.clear();
    button = nullptr;
}

void ResizeControl::setBounds(const VSTGUI::CRect& bounds) {
    component.setBounds(bounds);
}

void ResizeControl::setSize(uint32_t width, uint32_t height) {
    current_width = width;
    current_height = height;
    if (!button) return;
    const bool expanded = width >= 520 || height >= 360;
    button->setTitle(expanded ? "Compact" : "Expand");
}

void ResizeControl::setCallbacks(ZigVstguiResizeCallbacks value_callbacks) {
    callbacks = value_callbacks;
}

void ResizeControl::valueChanged(VSTGUI::CControl* control) {
    if (!control || control->getValue() != control->getMax()) return;
    const bool expanded = current_width >= 520 || current_height >= 360;
    const uint32_t requested_width = expanded ? 400 : 640;
    const uint32_t requested_height = expanded ? 300 : 420;
    if (!callbacks.request_resize ||
        callbacks.request_resize(callbacks.userdata, requested_width, requested_height) != 0) {
        if (button) button->setTitle("Resize unavailable");
    }
}

}
