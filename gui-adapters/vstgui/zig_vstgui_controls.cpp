#include "zig_vstgui_controls.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cgradient.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <utility>

namespace ZigVstgui {

namespace {

constexpr int32_t kParameterTag = 1;
constexpr int32_t kValueTag = 2;
constexpr int32_t kResizeTag = 3;

}

double clampNormalized(double value) {
    return std::clamp(value, 0.0, 1.0);
}

double quantizeNormalized(double value, int32_t step_count) {
    const double clamped = clampNormalized(value);
    if (step_count <= 0) return clamped;
    return std::round(clamped * step_count) / step_count;
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
    const double normalized = quantizeNormalized(requested, step_count);
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
    accepted_value = quantizeNormalized(value, step_count);
}

void ParameterControlModel::setStepCount(int32_t value_step_count) {
    step_count = std::max(0, value_step_count);
    accepted_value = quantizeNormalized(accepted_value, step_count);
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
    const ThemeResolver& value_styles
)
: CSlider(size, listener, tag, 0, 1, nullptr, nullptr), styles(value_styles) {}

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
    const auto style = styles.resolve(ComponentKind::slider, visualState());
    setAlphaValueNoInvalidate(style.alpha);
    setFrameWidth(style.frame_width);
    setFrameColor(style.border);
    setBackColor(style.background);
    setValueColor(style.accent);
    CSlider::draw(context);
    const auto bounds = getViewSize();
    const auto center_x = bounds.left + bounds.getWidth() * getValueNormalized();
    const auto center_y = bounds.top + bounds.getHeight() / 2.0;
    VSTGUI::CRect thumb(
        center_x - style.thumb_radius,
        center_y - style.thumb_radius,
        center_x + style.thumb_radius,
        center_y + style.thumb_radius
    );
    context->setDrawMode(VSTGUI::kAntiAliasing);
    context->setLineWidth(style.frame_width);
    context->setFrameColor(style.accent);
    context->setFillColor(style.foreground);
    context->drawEllipse(thumb, VSTGUI::kDrawFilledAndStroked);
}

void GainSlider::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    pressed = true;
    invalid();
    CSlider::onMouseDownEvent(event);
}

void GainSlider::onMouseUpEvent(VSTGUI::MouseUpEvent& event) {
    pressed = false;
    invalid();
    CSlider::onMouseUpEvent(event);
}

void GainSlider::onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) {
    pressed = false;
    invalid();
    CSlider::onMouseCancelEvent(event);
}

void GainSlider::onMouseEnterEvent(VSTGUI::MouseEnterEvent& event) {
    hovered = true;
    invalid();
    CSlider::onMouseEnterEvent(event);
}

void GainSlider::onMouseExitEvent(VSTGUI::MouseExitEvent& event) {
    hovered = false;
    invalid();
    CSlider::onMouseExitEvent(event);
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

VisualState GainSlider::visualState() const {
    if (!getMouseEnabled()) return VisualState::disabled;
    if (isEditing()) return VisualState::editing;
    if (pressed) return VisualState::pressed;
    if (hovered) return VisualState::hovered;
    const auto* frame = getFrame();
    if (frame && frame->getFocusView() == this) return VisualState::focused;
    return VisualState::normal;
}

ParameterControl::ParameterControl(uint32_t parameter_id, double initial, ZigVstguiCallbacks callbacks)
: control_model(parameter_id, initial, callbacks) {}

ParameterControl::~ParameterControl() {
    control_model.cancelGesture();
}

void ParameterControl::build(
    VSTGUI::CViewContainer* parent,
    ZigVstguiParameterInfo value_parameter_info,
    ZigVstguiControlKind value_control_kind,
    const ThemeResolver& styles
) {
    if (!parent || label || primary_control || value_edit) return;
    parameter_info = value_parameter_info;
    control_kind = value_control_kind;
    control_model.setStepCount(parameter_info.step_count);
    disabled_alpha = styles.resolve(ComponentKind::slider, VisualState::disabled).alpha;
    const auto label_style = styles.resolve(ComponentKind::title);
    const auto value_style = styles.resolve(ComponentKind::value_field);
    label_text = parameter_info.title ? parameter_info.title : "Parameter";
    if (parameter_info.units && parameter_info.units[0] != '\0') {
        label_text += " (";
        label_text += parameter_info.units;
        label_text += ")";
    }
    label = new VSTGUI::CTextLabel(VSTGUI::CRect(), label_text.c_str());
    label->setFont(styles.theme().typography.body);
    label->setFontColor(label_style.foreground);
    label->setBackColor(label_style.background);
    label->setFrameColor(label_style.border);
    label->setHoriAlign(VSTGUI::kLeftText);
    parent->addView(label);
    label_component.bind(label);

    buildPrimaryControl(parent, parameter_info, control_kind, styles);

    if (control_kind == ZIG_VSTGUI_CONTROL_TOGGLE ||
        control_kind == ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN) {
        syncViews();
        return;
    }
    value_edit = new VSTGUI::CTextEdit(VSTGUI::CRect(), this, kValueTag, "");
    value_edit->setMin(0.f);
    value_edit->setMax(1.f);
    value_edit->setDefaultValue(static_cast<float>(clampNormalized(parameter_info.default_normalized)));
    value_edit->setFont(styles.theme().typography.value);
    value_edit->setFontColor(value_style.foreground);
    value_edit->setBackColor(value_style.background);
    value_edit->setFrameColor(value_style.border);
    value_edit->setFrameWidth(value_style.frame_width);
    value_edit->setRoundRectRadius(value_style.radius);
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
    value_edit->registerViewEventListener(this);
    value_component.bind(value_edit);
    value_component.setFocusable(true);
    syncViews();
}

void ParameterControl::buildPrimaryControl(
    VSTGUI::CViewContainer* parent,
    ZigVstguiParameterInfo info,
    ZigVstguiControlKind kind,
    const ThemeResolver& styles
) {
    const float default_value = static_cast<float>(clampNormalized(info.default_normalized));
    const float wheel_increment = info.step_count > 0 ? 1.f / static_cast<float>(info.step_count) : 0.01f;
    ComponentKind component_kind = ComponentKind::slider;
    switch (kind) {
        case ZIG_VSTGUI_CONTROL_ROTARY_KNOB: {
            component_kind = ComponentKind::knob;
            knob = new VSTGUI::CKnob(
                VSTGUI::CRect(),
                this,
                kParameterTag,
                nullptr,
                nullptr,
                VSTGUI::CPoint(),
                VSTGUI::CKnob::kCoronaDrawing | VSTGUI::CKnob::kCoronaOutline
            );
            const auto style = styles.resolve(component_kind);
            knob->setCoronaColor(style.accent);
            knob->setColorHandle(style.foreground);
            knob->setColorShadowHandle(style.background);
            knob->setHandleLineWidth(style.frame_width);
            primary_control = knob;
            break;
        }
        case ZIG_VSTGUI_CONTROL_TOGGLE: {
            component_kind = ComponentKind::toggle;
            const auto style = styles.resolve(component_kind);
            const auto pressed = styles.resolve(component_kind, VisualState::pressed);
            toggle = new VSTGUI::CTextButton(VSTGUI::CRect(), this, kParameterTag, "Off");
            toggle->setFont(styles.theme().typography.body);
            toggle->setTextColor(style.foreground);
            toggle->setTextColorHighlighted(pressed.foreground);
            toggle->setFrameColor(style.border);
            toggle->setFrameColorHighlighted(pressed.border);
            toggle->setFrameWidth(style.frame_width);
            toggle->setRoundRadius(style.radius);
            primary_control = toggle;
            break;
        }
        case ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN: {
            component_kind = ComponentKind::dropdown;
            const auto style = styles.resolve(component_kind);
            dropdown = new VSTGUI::COptionMenu(VSTGUI::CRect(), this, kParameterTag);
            dropdown->setFont(styles.theme().typography.body);
            dropdown->setFontColor(style.foreground);
            dropdown->setBackColor(style.background);
            dropdown->setFrameColor(style.border);
            dropdown->setFrameWidth(style.frame_width);
            dropdown->setRoundRectRadius(style.radius);
            const int32_t option_count = std::max(1, info.step_count + 1);
            for (int32_t index = 0; index < option_count; ++index) {
                dropdown->addEntry(formattedValue(
                    option_count == 1 ? 0.0 : static_cast<double>(index) / (option_count - 1)
                ).c_str());
            }
            primary_control = dropdown;
            break;
        }
        case ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM: {
            component_kind = ComponentKind::segmented;
            const auto style = styles.resolve(component_kind);
            segmented = new VSTGUI::CSegmentButton(VSTGUI::CRect(), this, kParameterTag);
            segmented->setFont(styles.theme().typography.body);
            segmented->setTextColor(style.foreground);
            segmented->setTextColorHighlighted(style.foreground);
            segmented->setFrameColor(style.border);
            segmented->setFrameWidth(style.frame_width);
            segmented->setRoundRadius(style.radius);
            const int32_t option_count = std::max(1, info.step_count + 1);
            for (int32_t index = 0; index < option_count; ++index) {
                VSTGUI::CSegmentButton::Segment segment;
                segment.name = formattedValue(
                    option_count == 1 ? 0.0 : static_cast<double>(index) / (option_count - 1)
                ).c_str();
                segmented->addSegment(std::move(segment));
            }
            primary_control = segmented;
            break;
        }
        case ZIG_VSTGUI_CONTROL_LINEAR_SLIDER:
        default: {
            const auto style = styles.resolve(component_kind);
            slider = new GainSlider(VSTGUI::CRect(), this, kParameterTag, styles);
            slider->setDrawStyle(VSTGUI::CSlider::kDrawFrame | VSTGUI::CSlider::kDrawBack | VSTGUI::CSlider::kDrawValue);
            slider->setFrameWidth(style.frame_width);
            slider->setFrameColor(style.border);
            slider->setBackColor(style.background);
            slider->setValueColor(style.accent);
            primary_control = slider;
            break;
        }
    }
    if (!primary_control) return;
    primary_control->setMin(0.f);
    primary_control->setMax(1.f);
    primary_control->setDefaultValue(default_value);
    primary_control->setWheelInc(wheel_increment);
    parent->addView(primary_control);
    primary_control->registerViewEventListener(this);
    primary_component.bind(primary_control);
    primary_component.setFocusable(true);
}

std::string ParameterControl::formattedValue(double normalized) const {
    char text[256] {};
    const auto& callbacks = control_model.callbacks();
    if (callbacks.format_value && callbacks.format_value(
            callbacks.userdata,
            control_model.parameterId(),
            clampNormalized(normalized),
            text,
            sizeof(text)
        ) >= 0) return text;
    std::snprintf(text, sizeof(text), "%.3f", clampNormalized(normalized));
    return text;
}

void ParameterControl::clear() {
    control_model.cancelGesture();
    if (primary_control) primary_control->unregisterViewEventListener(this);
    if (value_edit) value_edit->unregisterViewEventListener(this);
    label_component.clear();
    primary_component.clear();
    value_component.clear();
    label = nullptr;
    slider = nullptr;
    knob = nullptr;
    toggle = nullptr;
    dropdown = nullptr;
    segmented = nullptr;
    primary_control = nullptr;
    value_edit = nullptr;
}

void ParameterControl::setValue(double value) {
    control_model.hostChanged(value);
    syncViews();
}

void ParameterControl::setEnabled(bool enabled) {
    primary_component.setEnabled(enabled);
    value_component.setEnabled(enabled);
    if (primary_control) primary_control->setAlphaValue(enabled ? 1.f : disabled_alpha);
    if (value_edit) value_edit->setAlphaValue(enabled ? 1.f : disabled_alpha);
}

void ParameterControl::setBounds(
    const VSTGUI::CRect& label_bounds,
    const VSTGUI::CRect& slider_bounds,
    const VSTGUI::CRect& value_bounds
) {
    label_component.setBounds(label_bounds);
    if (control_kind == ZIG_VSTGUI_CONTROL_ROTARY_KNOB) {
        const double side = std::min(slider_bounds.getWidth(), slider_bounds.getHeight());
        const double center_x = slider_bounds.left + slider_bounds.getWidth() / 2.0;
        primary_component.setBounds(VSTGUI::CRect(
            center_x - side / 2.0,
            slider_bounds.top,
            center_x + side / 2.0,
            slider_bounds.top + side
        ));
    } else {
        primary_component.setBounds(slider_bounds);
    }
    value_component.setBounds(value_bounds);
}

bool ParameterControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    if (slider) return slider->handleKey(key, key_code, modifiers);
    if (!primary_control) return false;
    if (key_code == Steinberg::KEY_HOME || key_code == Steinberg::KEY_END) {
        primary_control->beginEdit();
        primary_control->setValueNormalized(key_code == Steinberg::KEY_HOME ? 0.f : 1.f);
        primary_control->valueChanged();
        primary_control->endEdit();
        return true;
    }
    VSTGUI::KeyboardEvent event;
    event.type = VSTGUI::EventType::KeyDown;
    event.character = key;
    switch (key_code) {
        case Steinberg::KEY_LEFT: event.virt = VSTGUI::VirtualKey::Left; break;
        case Steinberg::KEY_UP: event.virt = VSTGUI::VirtualKey::Up; break;
        case Steinberg::KEY_RIGHT: event.virt = VSTGUI::VirtualKey::Right; break;
        case Steinberg::KEY_DOWN: event.virt = VSTGUI::VirtualKey::Down; break;
        default: event.virt = VSTGUI::VirtualKey::None; break;
    }
    if ((modifiers & 1) != 0) event.modifiers.add(VSTGUI::ModifierKey::Shift);
    if ((modifiers & 2) != 0) event.modifiers.add(VSTGUI::ModifierKey::Alt);
    if ((modifiers & 4) != 0) event.modifiers.add(VSTGUI::ModifierKey::Control);
    if ((modifiers & 8) != 0) event.modifiers.add(VSTGUI::ModifierKey::Super);
    primary_control->onKeyboardEvent(event);
    return event.consumed;
}

VSTGUI::CControl* ParameterControl::focusView() const {
    return primary_control;
}

bool ParameterControl::showContextMenu(int32_t x, int32_t y) {
    const auto& callbacks = control_model.callbacks();
    return callbacks.show_context_menu && callbacks.show_context_menu(
        callbacks.userdata,
        control_model.parameterId(),
        x,
        y
    ) == 0;
}

void ParameterControl::controlBeginEdit(VSTGUI::CControl*) {
    if (control_model.beginGesture()) {
        primary_component.setEditing(true);
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
    primary_component.setEditing(false);
    value_component.setEditing(false);
}

void ParameterControl::viewOnEvent(VSTGUI::CView*, VSTGUI::Event& event) {
    if (event.type != VSTGUI::EventType::MouseDown) return;
    auto& mouse_event = VSTGUI::castMouseDownEvent(event);
    if (!mouse_event.buttonState.isRight()) return;
    if (showContextMenu(
            static_cast<int32_t>(std::lround(mouse_event.mousePosition.x)),
            static_cast<int32_t>(std::lround(mouse_event.mousePosition.y))
        )) event.consumed = true;
}

const ParameterControlModel& ParameterControl::model() const {
    return control_model;
}

void ParameterControl::syncViews() {
    const float normalized = static_cast<float>(control_model.acceptedValue());
    if (primary_control) {
        primary_control->setValueNormalized(normalized);
        if (toggle) toggle->setTitle(formattedValue(normalized).c_str());
        primary_control->invalid();
    }
    if (value_edit) {
        value_edit->setValueNormalized(normalized);
        value_edit->invalid();
    }
}

ResizeHandle::ResizeHandle(
    const VSTGUI::CRect& size,
    ResizeControl* value_owner,
    const ThemeResolver& value_styles
)
: CControl(size, nullptr, kResizeTag), owner(value_owner), styles(value_styles) {}

void ResizeHandle::draw(VSTGUI::CDrawContext* context) {
    const auto style = styles.resolve(
        ComponentKind::resize_button,
        dragging ? VisualState::pressed : VisualState::normal
    );
    const auto bounds = getViewSize();
    context->setDrawMode(VSTGUI::kAntiAliasing);
    context->setFrameColor(style.accent);
    context->setLineWidth(style.frame_width);
    for (double inset = 5.0; inset <= 13.0; inset += 4.0) {
        context->drawLine(
            VSTGUI::CPoint(bounds.right - inset, bounds.bottom - 2.0),
            VSTGUI::CPoint(bounds.right - 2.0, bounds.bottom - inset)
        );
    }
    setDirty(false);
}

void ResizeHandle::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (!event.buttonState.isLeft()) return;
    dragging = true;
    drag_origin = event.mousePosition;
    start_width = current_width;
    start_height = current_height;
    invalid();
    event.consumed = true;
}

void ResizeHandle::onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) {
    if (!dragging || !owner) return;
    const double width = std::clamp(
        static_cast<double>(start_width) + event.mousePosition.x - drag_origin.x,
        320.0,
        1000.0
    );
    const double height = std::clamp(
        static_cast<double>(start_height) + event.mousePosition.y - drag_origin.y,
        240.0,
        700.0
    );
    owner->requestResize(static_cast<uint32_t>(std::lround(width)), static_cast<uint32_t>(std::lround(height)));
    event.consumed = true;
}

void ResizeHandle::onMouseUpEvent(VSTGUI::MouseUpEvent& event) {
    if (!dragging) return;
    dragging = false;
    invalid();
    event.consumed = true;
}

void ResizeHandle::onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) {
    if (!dragging) return;
    dragging = false;
    invalid();
    event.consumed = true;
}

void ResizeHandle::setCurrentSize(uint32_t width, uint32_t height) {
    current_width = width;
    current_height = height;
}

void ResizeControl::build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles) {
    if (!parent || button) return;
    const auto style = styles.resolve(ComponentKind::resize_button);
    const auto highlighted = styles.resolve(ComponentKind::resize_button, VisualState::pressed);
    const auto& colors = styles.theme().colors;
    button = new VSTGUI::CTextButton(VSTGUI::CRect(), this, kResizeTag, "Expand");
    button->setFont(styles.theme().typography.body);
    button->setTextColor(style.foreground);
    button->setTextColorHighlighted(highlighted.foreground);
    button->setFrameColor(style.border);
    button->setFrameColorHighlighted(highlighted.border);
    button->setFrameWidth(style.frame_width);
    button->setGradient(VSTGUI::owned(VSTGUI::CGradient::create(0, 1, colors.button_top, colors.button_bottom)));
    button->setGradientHighlighted(VSTGUI::owned(VSTGUI::CGradient::create(
        0,
        1,
        colors.button_top_highlighted,
        colors.button_bottom_highlighted
    )));
    button->setRoundRadius(style.radius);
    parent->addView(button);
    button_component.bind(button);
    button_component.setFocusable(true);
    handle = new ResizeHandle(VSTGUI::CRect(), this, styles);
    parent->addView(handle);
    handle_component.bind(handle);
    setSize(current_width, current_height);
}

void ResizeControl::clear() {
    button_component.clear();
    handle_component.clear();
    button = nullptr;
    handle = nullptr;
}

void ResizeControl::setBounds(const VSTGUI::CRect& bounds) {
    const double handle_side = std::min(24.0, bounds.getHeight());
    button_component.setBounds(VSTGUI::CRect(
        bounds.left,
        bounds.top,
        std::max(bounds.left, bounds.right - handle_side - 4.0),
        bounds.bottom
    ));
    handle_component.setBounds(VSTGUI::CRect(
        bounds.right - handle_side,
        bounds.bottom - handle_side,
        bounds.right,
        bounds.bottom
    ));
}

void ResizeControl::setSize(uint32_t width, uint32_t height) {
    current_width = width;
    current_height = height;
    if (handle) handle->setCurrentSize(width, height);
    if (!button) return;
    const bool expanded = width >= 520 || height >= 360;
    button->setTitle(expanded ? "Compact" : "Expand");
}

void ResizeControl::setCallbacks(ZigVstguiResizeCallbacks value_callbacks) {
    callbacks = value_callbacks;
}

bool ResizeControl::requestResize(uint32_t width, uint32_t height) {
    return callbacks.request_resize && callbacks.request_resize(callbacks.userdata, width, height) == 0;
}

void ResizeControl::valueChanged(VSTGUI::CControl* control) {
    if (!control || control->getValue() != control->getMax()) return;
    const bool expanded = current_width >= 520 || current_height >= 360;
    const uint32_t requested_width = expanded ? 400 : 640;
    const uint32_t requested_height = expanded ? 300 : 420;
    if (!requestResize(requested_width, requested_height)) {
        if (button) button->setTitle("Resize unavailable");
    }
}

}
