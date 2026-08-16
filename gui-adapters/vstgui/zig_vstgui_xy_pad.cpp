#include "zig_vstgui_xy_pad.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <cstdio>

namespace ZigVstgui {

namespace {

constexpr uint32_t actionMask(AccessibilityAction action) {
    return static_cast<uint32_t>(action);
}

}

MultiParameterControlModel::MultiParameterControlModel(
    uint32_t x_parameter_id,
    double value_initial_x,
    int32_t x_step_count,
    uint32_t y_parameter_id,
    double value_initial_y,
    int32_t y_step_count,
    ZigVstguiCallbacks callbacks
)
: x_model(x_parameter_id, value_initial_x, callbacks),
  y_model(y_parameter_id, value_initial_y, callbacks) {
    x_model.setStepCount(x_step_count);
    y_model.setStepCount(y_step_count);
}

MultiParameterControlModel::~MultiParameterControlModel() {
    cancelGesture();
}

bool MultiParameterControlModel::beginGesture() {
    if (gesture_active || !x_model.beginGesture()) return false;
    if (!y_model.beginGesture()) {
        x_model.endGesture();
        return false;
    }
    initial_x = x_model.acceptedValue();
    initial_y = y_model.acceptedValue();
    gesture_active = true;
    return true;
}

bool MultiParameterControlModel::performEdit(double x, double y) {
    if (!gesture_active) return false;
    if (!x_model.performEdit(x)) return false;
    return y_model.performEdit(y);
}

void MultiParameterControlModel::endGesture() {
    if (!gesture_active) return;
    x_model.endGesture();
    y_model.endGesture();
    gesture_active = false;
}

void MultiParameterControlModel::cancelGesture() {
    if (!gesture_active) return;
    x_model.performEdit(initial_x);
    y_model.performEdit(initial_y);
    endGesture();
}

bool MultiParameterControlModel::hostChanged(uint32_t parameter_id, double value) {
    if (x_model.parameterId() == parameter_id) {
        x_model.hostChanged(value);
        return true;
    }
    if (y_model.parameterId() == parameter_id) {
        y_model.hostChanged(value);
        return true;
    }
    return false;
}

uint32_t MultiParameterControlModel::parameterId(uint32_t axis) const {
    return axis == 0 ? x_model.parameterId() : y_model.parameterId();
}

double MultiParameterControlModel::acceptedValue(uint32_t axis) const {
    return axis == 0 ? x_model.acceptedValue() : y_model.acceptedValue();
}

bool MultiParameterControlModel::gestureActive() const {
    return gesture_active;
}

const ZigVstguiCallbacks& MultiParameterControlModel::callbacks() const {
    return x_model.callbacks();
}

XYPadView::XYPadView(
    const VSTGUI::CRect& size,
    XYPadControl* value_owner,
    const ThemeResolver& value_styles
)
: CXYPad(size), owner(value_owner), styles(value_styles) {
    setListener(owner);
    setWantsFocus(true);
    setWheelInc(0.01f);
}

void XYPadView::setXY(double x, double y) {
    setValue(CXYPad::calculateValue(
        static_cast<float>(clampNormalized(x)),
        static_cast<float>(1.0 - clampNormalized(y))
    ));
    invalid();
}

void XYPadView::getXY(double& x, double& y) const {
    float raw_x = 0.f;
    float raw_y = 0.f;
    CXYPad::calculateXY(getValue(), raw_x, raw_y);
    x = clampNormalized(raw_x);
    y = clampNormalized(1.0 - raw_y);
}

bool XYPadView::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    VSTGUI::KeyboardEvent event;
    event.type = VSTGUI::EventType::KeyDown;
    event.character = key;
    switch (key_code) {
        case Steinberg::KEY_LEFT: event.virt = VSTGUI::VirtualKey::Left; break;
        case Steinberg::KEY_UP: event.virt = VSTGUI::VirtualKey::Up; break;
        case Steinberg::KEY_RIGHT: event.virt = VSTGUI::VirtualKey::Right; break;
        case Steinberg::KEY_DOWN: event.virt = VSTGUI::VirtualKey::Down; break;
        case Steinberg::KEY_HOME: event.virt = VSTGUI::VirtualKey::Home; break;
        case Steinberg::KEY_END: event.virt = VSTGUI::VirtualKey::End; break;
        default: return false;
    }
    if ((modifiers & 1) != 0) event.modifiers.add(VSTGUI::ModifierKey::Shift);
    onKeyboardEvent(event);
    return event.consumed;
}

void XYPadView::draw(VSTGUI::CDrawContext* context) {
    const auto style = styles.resolve(ComponentKind::xy_pad, visualState());
    const auto bounds = getViewSize();
    context->setDrawMode(VSTGUI::kAntiAliasing);
    context->setFillColor(style.background);
    context->setFrameColor(style.border);
    context->setLineWidth(style.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);
    context->setFrameColor(style.border);
    context->setLineWidth(1.0);
    context->drawLine(
        VSTGUI::CPoint(bounds.left + bounds.getWidth() * 0.5, bounds.top),
        VSTGUI::CPoint(bounds.left + bounds.getWidth() * 0.5, bounds.bottom)
    );
    context->drawLine(
        VSTGUI::CPoint(bounds.left, bounds.top + bounds.getHeight() * 0.5),
        VSTGUI::CPoint(bounds.right, bounds.top + bounds.getHeight() * 0.5)
    );
    double x = 0.0;
    double y = 0.0;
    getXY(x, y);
    const double center_x = bounds.left + bounds.getWidth() * x;
    const double center_y = bounds.bottom - bounds.getHeight() * y;
    const double radius = std::max(5.0, style.thumb_radius);
    context->setFillColor(style.foreground);
    context->setFrameColor(style.accent);
    context->setLineWidth(style.frame_width);
    context->drawEllipse(
        VSTGUI::CRect(center_x - radius, center_y - radius, center_x + radius, center_y + radius),
        VSTGUI::kDrawFilledAndStroked
    );
    setDirty(false);
}

void XYPadView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    pressed = event.buttonState.isLeft();
    invalid();
    CXYPad::onMouseDownEvent(event);
}

void XYPadView::onMouseUpEvent(VSTGUI::MouseUpEvent& event) {
    pressed = false;
    invalid();
    CXYPad::onMouseUpEvent(event);
}

void XYPadView::onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) {
    pressed = false;
    invalid();
    CXYPad::onMouseCancelEvent(event);
}

void XYPadView::onMouseEnterEvent(VSTGUI::MouseEnterEvent& event) {
    hovered = true;
    invalid();
    CXYPad::onMouseEnterEvent(event);
}

void XYPadView::onMouseExitEvent(VSTGUI::MouseExitEvent& event) {
    hovered = false;
    invalid();
    CXYPad::onMouseExitEvent(event);
}

void XYPadView::onKeyboardEvent(VSTGUI::KeyboardEvent& event) {
    if (event.type != VSTGUI::EventType::KeyDown) return;
    double x = 0.0;
    double y = 0.0;
    getXY(x, y);
    const double step = event.modifiers.has(VSTGUI::ModifierKey::Shift) ? 0.001 : 0.01;
    uint32_t axis = 0;
    if (event.virt == VSTGUI::VirtualKey::Left) x -= step;
    else if (event.virt == VSTGUI::VirtualKey::Right) x += step;
    else if (event.virt == VSTGUI::VirtualKey::Down) { y -= step; axis = 1; }
    else if (event.virt == VSTGUI::VirtualKey::Up) { y += step; axis = 1; }
    else if (event.virt == VSTGUI::VirtualKey::Home) { x = 0.0; y = 0.0; }
    else if (event.virt == VSTGUI::VirtualKey::End) { x = 1.0; y = 1.0; }
    else return;
    if (owner) owner->selectAxis(axis);
    beginEdit();
    setXY(x, y);
    valueChanged();
    endEdit();
    event.consumed = true;
}

VisualState XYPadView::visualState() const {
    if (!getMouseEnabled()) return VisualState::disabled;
    if (isEditing()) return VisualState::editing;
    if (pressed) return VisualState::pressed;
    if (hovered) return VisualState::hovered;
    const auto* frame = getFrame();
    if (frame && frame->getFocusView() == this) return VisualState::focused;
    return VisualState::normal;
}

XYPadControl::XYPadControl(
    ZigVstguiXYPadDescription value_description,
    ZigVstguiParameterInfo x_info,
    double initial_x,
    ZigVstguiParameterInfo y_info,
    double initial_y,
    ZigVstguiCallbacks callbacks
)
: description(value_description),
  parameter_info{x_info, y_info},
  title(value_description.title ? value_description.title : "XY Pad"),
  axis_labels{
      value_description.x_label ? value_description.x_label : "X",
      value_description.y_label ? value_description.y_label : "Y"
  },
  control_model(
      value_description.x_parameter_id,
      initial_x,
      x_info.step_count,
      value_description.y_parameter_id,
      initial_y,
      y_info.step_count,
      callbacks
  ) {}

XYPadControl::~XYPadControl() {
    control_model.cancelGesture();
}

void XYPadControl::build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles) {
    if (!parent || label || pad) return;
    const auto label_style = styles.resolve(ComponentKind::title);
    label = new VSTGUI::CTextLabel(VSTGUI::CRect(), title.c_str());
    label->setFont(styles.font(TypographyRole::body));
    label->setFontColor(label_style.foreground);
    label->setBackColor(label_style.background);
    label->setFrameColor(label_style.border);
    parent->addView(label);
    label_component.bind(label);
    label_component.accessibility().setRole(AccessibilityRole::group);
    label_component.accessibility().setName(title);
    label_component.accessibility().setReadOnly(true);

    pad = new XYPadView(VSTGUI::CRect(), this, styles);
    parent->addView(pad);
    pad->registerViewListener(this);
    pad_component.bind(pad);
    pad_component.setFocusable(true);
    for (uint32_t axis = 0; axis < 2; ++axis) {
        auto& accessibility = axis_accessibility[axis];
        accessibility.setRole(AccessibilityRole::slider);
        accessibility.setName(title + " " + axis_labels[axis]);
        accessibility.setDescription(axis == 0 ? "Horizontal axis" : "Vertical axis");
        accessibility.setActionHandler(
            this,
            accessibilityAction,
            actionMask(AccessibilityAction::focus) |
                actionMask(AccessibilityAction::increment) |
                actionMask(AccessibilityAction::decrement) |
                actionMask(AccessibilityAction::set_value)
        );
    }
    syncView();
}

void XYPadControl::clear() {
    control_model.cancelGesture();
    if (pad) pad->unregisterViewListener(this);
    label_component.clear();
    pad_component.clear();
    for (auto& accessibility : axis_accessibility) accessibility.clearActionHandler();
    label = nullptr;
    pad = nullptr;
}

void XYPadControl::setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& pad_bounds) {
    label_component.setBounds(label_bounds);
    pad_component.setBounds(pad_bounds);
}

bool XYPadControl::setParameter(uint32_t parameter_id, double value) {
    if (!control_model.hostChanged(parameter_id, value)) return false;
    syncView();
    return true;
}

bool XYPadControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    return pad && pad->handleKey(key, key_code, modifiers);
}

VSTGUI::CView* XYPadControl::focusView() const {
    return pad;
}

void XYPadControl::setFocusedView(VSTGUI::CView* view) {
    const bool focused = pad && view == pad;
    pad_component.setFocused(focused);
    axis_accessibility[0].setFocused(focused && selected_axis == 0);
    axis_accessibility[1].setFocused(focused && selected_axis == 1);
}

const AccessibilityNode& XYPadControl::axisAccessibility(uint32_t axis) const {
    return axis_accessibility[std::min(axis, 1u)];
}

void XYPadControl::selectAxis(uint32_t axis) {
    selected_axis = std::min(axis, 1u);
    const bool focused = pad && pad->getFrame() && pad->getFrame()->getFocusView() == pad;
    axis_accessibility[0].setFocused(focused && selected_axis == 0);
    axis_accessibility[1].setFocused(focused && selected_axis == 1);
}

void XYPadControl::controlBeginEdit(VSTGUI::CControl*) {
    if (control_model.beginGesture()) pad_component.setEditing(true);
}

void XYPadControl::valueChanged(VSTGUI::CControl*) {
    if (!pad) return;
    double x = 0.0;
    double y = 0.0;
    pad->getXY(x, y);
    if (!control_model.performEdit(x, y)) control_model.cancelGesture();
    syncView();
}

void XYPadControl::controlEndEdit(VSTGUI::CControl*) {
    control_model.endGesture();
    pad_component.setEditing(false);
}

void XYPadControl::viewLostFocus(VSTGUI::CView* view) {
    if (view != pad) return;
    pad_component.setFocused(false);
    axis_accessibility[0].setFocused(false);
    axis_accessibility[1].setFocused(false);
}

void XYPadControl::viewTookFocus(VSTGUI::CView* view) {
    if (view != pad) return;
    pad_component.setFocused(true);
    selectAxis(selected_axis);
}

const MultiParameterControlModel& XYPadControl::model() const {
    return control_model;
}

bool XYPadControl::accessibilityAction(
    void* userdata,
    const AccessibilityNode& node,
    const AccessibilityActionRequest& request
) {
    auto* control = static_cast<XYPadControl*>(userdata);
    return control && control->performAccessibilityAction(node, request);
}

bool XYPadControl::performAccessibilityAction(
    const AccessibilityNode& node,
    const AccessibilityActionRequest& request
) {
    const uint32_t axis = &node == &axis_accessibility[1] ? 1 : 0;
    if (request.action == AccessibilityAction::focus) {
        if (!pad || !pad->getFrame()) return false;
        selectAxis(axis);
        pad->getFrame()->setFocusView(pad);
        selectAxis(axis);
        return true;
    }
    double values[] = {control_model.acceptedValue(0), control_model.acceptedValue(1)};
    const double step = parameter_info[axis].step_count > 0
        ? 1.0 / static_cast<double>(parameter_info[axis].step_count)
        : 0.01;
    if (request.action == AccessibilityAction::increment) values[axis] += step;
    else if (request.action == AccessibilityAction::decrement) values[axis] -= step;
    else if (request.action == AccessibilityAction::set_value) values[axis] = request.value;
    else return false;
    selectAxis(axis);
    if (!control_model.beginGesture()) return false;
    const bool accepted = control_model.performEdit(values[0], values[1]);
    if (accepted) control_model.endGesture();
    else control_model.cancelGesture();
    syncView();
    return accepted;
}

std::string XYPadControl::formattedValue(uint32_t axis, double normalized) const {
    char text[256] {};
    const auto& callbacks = control_model.callbacks();
    const int32_t written = callbacks.format_value
        ? callbacks.format_value(
            callbacks.userdata,
            control_model.parameterId(axis),
            clampNormalized(normalized),
            text,
            sizeof(text)
        )
        : -1;
    if (validCallbackTextOutput(text, sizeof(text), written)) return text;
    std::snprintf(text, sizeof(text), "%.3f", clampNormalized(normalized));
    return text;
}

void XYPadControl::syncView() {
    if (pad) pad->setXY(control_model.acceptedValue(0), control_model.acceptedValue(1));
    syncAccessibility();
}

void XYPadControl::syncAccessibility() {
    for (uint32_t axis = 0; axis < 2; ++axis) {
        const double value = control_model.acceptedValue(axis);
        axis_accessibility[axis].setRange(0.0, 1.0, value);
        axis_accessibility[axis].setValueText(formattedValue(axis, value));
    }
}

}
