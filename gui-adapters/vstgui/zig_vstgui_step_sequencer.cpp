#include "zig_vstgui_step_sequencer.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ZigVstgui {

namespace {

uint32_t firstSetBit(uint32_t value) {
    uint32_t index = 0;
    while ((value & 1u) == 0u) {
        value >>= 1u;
        ++index;
    }
    return index;
}

uint32_t countSetBits(uint32_t value) {
    uint32_t count = 0;
    while (value != 0) {
        value &= value - 1u;
        ++count;
    }
    return count;
}

}

StepSequencerView::StepSequencerView(
    const VSTGUI::CRect& size,
    StepSequencerControl* value_owner,
    const ThemeResolver& value_styles
)
: CView(size), owner(value_owner), styles(value_styles) {
    setWantsFocus(true);
}

void StepSequencerView::draw(VSTGUI::CDrawContext* context) {
    const auto bounds = getViewSize();
    const auto normal = styles.resolve(ComponentKind::xy_pad);
    const auto pressed = styles.resolve(ComponentKind::xy_pad, VisualState::pressed);
    const auto focused = styles.resolve(ComponentKind::xy_pad, VisualState::focused);
    const auto disabled = styles.resolve(ComponentKind::xy_pad, VisualState::disabled);
    const auto& colors = styles.theme().colors;
    const uint32_t count = owner->stepCount();
    if (count == 0) return;
    const double gap = 4.0;
    const double width = std::max(1.0, (bounds.getWidth() - gap * (count - 1)) / count);
    context->setDrawMode(VSTGUI::kAntiAliasing);
    context->setFont(styles.font(TypographyRole::value));
    for (uint32_t step = 0; step < count; ++step) {
        const double left = bounds.left + step * (width + gap);
        VSTGUI::CRect cell(left, bounds.top, left + width, bounds.bottom);
        const bool active = owner->stepActive(step);
        const bool selected = owner->stepSelected(step);
        context->setFillColor(!owner->enabled() ? disabled.background : active ? pressed.accent : normal.background);
        context->setFrameColor(!owner->enabled() ? disabled.border : selected ? focused.accent : normal.border);
        context->setLineWidth(selected ? 2.0 : normal.frame_width);
        context->drawRect(cell, VSTGUI::kDrawFilledAndStroked);
        if (static_cast<int32_t>(step) == owner->playhead()) {
            VSTGUI::CRect marker(cell.left + 3.0, cell.top + 3.0, cell.right - 3.0, cell.top + 7.0);
            context->setFillColor(colors.text_primary);
            context->drawRect(marker, VSTGUI::kDrawFilled);
        }
        if (owner->editFailed() && step == owner->cursor()) {
            VSTGUI::CRect error(cell.left + 3.0, cell.bottom - 7.0, cell.right - 3.0, cell.bottom - 3.0);
            context->setFillColor(VSTGUI::CColor(220, 55, 45, 255));
            context->drawRect(error, VSTGUI::kDrawFilled);
        }
        if (width >= 25.0) {
            char number[8] {};
            std::snprintf(number, sizeof(number), "%u", step + 1);
            context->setFontColor(active ? colors.surface : colors.text_primary);
            context->drawString(number, cell, VSTGUI::kCenterText);
        }
    }
    setDirty(false);
}

void StepSequencerView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (!event.buttonState.isLeft()) return;
    const int step = owner->hitTest(event.mousePosition);
    if (step < 0) return;
    const bool range = event.modifiers.has(VSTGUI::ModifierKey::Shift);
    const bool additive = event.modifiers.has(VSTGUI::ModifierKey::Control) ||
        event.modifiers.has(VSTGUI::ModifierKey::Super);
    owner->pointerBegin(static_cast<uint32_t>(step), additive, range);
    if (getFrame()) getFrame()->setFocusView(this);
    event.consumed = true;
}

void StepSequencerView::onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) {
    if (!event.buttonState.isLeft()) return;
    const int step = owner->hitTest(event.mousePosition);
    if (step < 0) return;
    owner->pointerPaint(static_cast<uint32_t>(step));
    event.consumed = true;
}

void StepSequencerView::onMouseUpEvent(VSTGUI::MouseUpEvent& event) {
    owner->pointerEnd();
    event.consumed = true;
}

void StepSequencerView::onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) {
    owner->pointerEnd();
    event.consumed = true;
}

StepSequencerControl::StepSequencerControl(
    ZigVstguiStepSequencerDescription value_description,
    ZigVstguiCallbacks value_callbacks,
    MeterSource value_telemetry
)
: description(value_description), callbacks(value_callbacks), telemetry(value_telemetry),
  title(value_description.title ? value_description.title : "Step Sequencer"),
  active_mask(value_description.initial_active_mask & validMask()),
  selection_mask(value_description.initial_selection_mask & validMask()) {
    for (uint32_t step = 0; step < description.step_count; ++step) {
        parameter_ids[step] = description.parameter_ids[step];
    }
    if (selection_mask != 0) cursor_step = firstSetBit(selection_mask);
    anchor_step = cursor_step;
}

StepSequencerControl::~StepSequencerControl() {
    stop();
    if (timer) timer->forget();
}

void StepSequencerControl::build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles) {
    if (!parent || label || sequencer) return;
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

    sequencer = new StepSequencerView(VSTGUI::CRect(), this, styles);
    parent->addView(sequencer);
    sequencer->registerViewListener(this);
    sequencer_component.bind(sequencer);
    sequencer_component.setFocusable(true);
    sequencer_component.setEnabled(description.enabled != 0);
    auto& accessibility = sequencer_component.accessibility();
    accessibility.setRole(AccessibilityRole::choice);
    accessibility.setName(title);
    accessibility.setDescription("Step pattern. Use Left and Right to move, Shift with arrows to select a range, and Space to toggle selected steps.");
    accessibility.setReadOnly(description.enabled == 0);
    accessibility.setActionHandler(
        this,
        accessibilityAction,
        static_cast<uint32_t>(AccessibilityAction::focus) |
            static_cast<uint32_t>(AccessibilityAction::press) |
            static_cast<uint32_t>(AccessibilityAction::increment) |
            static_cast<uint32_t>(AccessibilityAction::decrement)
    );
    if (description.playhead_source_id != 0 && !timer) {
        timer = new VSTGUI::CVSTGUITimer(
            [this](VSTGUI::CVSTGUITimer*) { tick(); },
            static_cast<uint32_t>(1000 / description.maximum_refresh_hz),
            false
        );
    }
    syncAccessibility();
    tick();
}

void StepSequencerControl::clear() {
    stop();
    if (sequencer) sequencer->unregisterViewListener(this);
    sequencer_component.accessibility().clearActionHandler();
    label_component.clear();
    sequencer_component.clear();
    label = nullptr;
    sequencer = nullptr;
}

void StepSequencerControl::setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& sequencer_bounds) {
    label_component.setBounds(label_bounds);
    sequencer_component.setBounds(sequencer_bounds);
}

void StepSequencerControl::start() { if (timer) timer->start(); }
void StepSequencerControl::stop() { if (timer) timer->stop(); }

bool StepSequencerControl::tick() {
    if (description.playhead_source_id == 0 || !telemetry.load) return false;
    const double value = telemetry.load(telemetry.userdata, description.playhead_source_id);
    int32_t next = -1;
    if (std::isfinite(value) && value >= 0.0) {
        next = std::min(static_cast<int32_t>(description.step_count - 1), static_cast<int32_t>(std::floor(value)));
    }
    if (next == playhead_step) return false;
    playhead_step = next;
    syncAccessibility();
    if (sequencer) sequencer->invalid();
    return true;
}

bool StepSequencerControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    if (description.enabled == 0) return false;
    const bool shift = (modifiers & 1) != 0;
    const bool command = (modifiers & 4) != 0 || (modifiers & 8) != 0;
    if (key_code == Steinberg::KEY_LEFT || key_code == Steinberg::KEY_RIGHT) {
        move(key_code == Steinberg::KEY_LEFT, shift);
        return true;
    }
    if (key_code == Steinberg::KEY_HOME || key_code == Steinberg::KEY_END) {
        select(key_code == Steinberg::KEY_HOME ? 0 : description.step_count - 1, false, shift);
        return true;
    }
    if (key_code == Steinberg::KEY_SPACE || key == ' ') {
        toggleSelected();
        return true;
    }
    if (key_code == Steinberg::KEY_ESCAPE) {
        selection_mask = 1u << cursor_step;
        anchor_step = cursor_step;
        storeSelection();
        syncAccessibility();
        if (sequencer) sequencer->invalid();
        return true;
    }
    if (command && (key == 'a' || key == 'A')) {
        selection_mask = validMask();
        storeSelection();
        syncAccessibility();
        if (sequencer) sequencer->invalid();
        return true;
    }
    return false;
}

bool StepSequencerControl::setParameter(uint32_t parameter_id, double normalized) {
    for (uint32_t step = 0; step < description.step_count; ++step) {
        if (parameter_ids[step] != parameter_id) continue;
        const bool active = std::isfinite(normalized) && normalized >= 0.5;
        edit_failed = false;
        if (active) active_mask |= 1u << step; else active_mask &= ~(1u << step);
        syncAccessibility();
        if (sequencer) sequencer->invalid();
        return true;
    }
    return false;
}

VSTGUI::CView* StepSequencerControl::focusView() const { return sequencer; }

void StepSequencerControl::setFocusedView(VSTGUI::CView* view) {
    const bool focused = sequencer && view == sequencer;
    sequencer_component.setFocused(focused);
    sequencer_component.accessibility().setFocused(focused);
}

const AccessibilityNode& StepSequencerControl::accessibilityNode() const {
    return sequencer_component.accessibility();
}

uint32_t StepSequencerControl::stepCount() const { return description.step_count; }
uint32_t StepSequencerControl::cursor() const { return cursor_step; }
int32_t StepSequencerControl::playhead() const { return playhead_step; }
bool StepSequencerControl::stepActive(uint32_t step) const { return step < 32 && (active_mask & (1u << step)) != 0; }
bool StepSequencerControl::stepSelected(uint32_t step) const { return step < 32 && (selection_mask & (1u << step)) != 0; }
bool StepSequencerControl::enabled() const { return description.enabled != 0; }
bool StepSequencerControl::editFailed() const { return edit_failed; }

int StepSequencerControl::hitTest(const VSTGUI::CPoint& position) const {
    if (!sequencer) return -1;
    const auto bounds = sequencer->getViewSize();
    if (!bounds.pointInside(position)) return -1;
    const double gap = 4.0;
    const double width = std::max(1.0, (bounds.getWidth() - gap * (description.step_count - 1)) / description.step_count);
    const int step = static_cast<int>((position.x - bounds.left) / (width + gap));
    if (step < 0 || static_cast<uint32_t>(step) >= description.step_count) return -1;
    const double local = position.x - bounds.left - step * (width + gap);
    return local <= width ? step : -1;
}

void StepSequencerControl::pointerBegin(uint32_t step, bool additive, bool range) {
    if (description.enabled == 0 || step >= description.step_count) return;
    select(step, additive, range);
    if (additive || range) {
        painting = false;
        return;
    }
    paint_active = !stepActive(step);
    painting = true;
    setStep(step, paint_active);
}

void StepSequencerControl::pointerPaint(uint32_t step) {
    if (!painting || step >= description.step_count || step == cursor_step) return;
    selection_mask = 1u << step;
    cursor_step = step;
    anchor_step = step;
    storeSelection();
    setStep(step, paint_active);
}

void StepSequencerControl::pointerEnd() { painting = false; }

void StepSequencerControl::viewLostFocus(VSTGUI::CView* view) {
    if (view == sequencer) setFocusedView(nullptr);
}

void StepSequencerControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == sequencer) setFocusedView(view);
}

bool StepSequencerControl::accessibilityAction(
    void* userdata,
    const AccessibilityNode&,
    const AccessibilityActionRequest& request
) {
    auto* control = static_cast<StepSequencerControl*>(userdata);
    return control && control->performAccessibilityAction(request);
}

bool StepSequencerControl::performAccessibilityAction(const AccessibilityActionRequest& request) {
    if (request.action == AccessibilityAction::focus) {
        if (!sequencer || !sequencer->getFrame()) return false;
        sequencer->getFrame()->setFocusView(sequencer);
        setFocusedView(sequencer);
        return true;
    }
    if (description.enabled == 0) return false;
    if (request.action == AccessibilityAction::increment) { move(false, false); return true; }
    if (request.action == AccessibilityAction::decrement) { move(true, false); return true; }
    if (request.action == AccessibilityAction::press) { toggleSelected(); return true; }
    return false;
}

void StepSequencerControl::select(uint32_t step, bool additive, bool range) {
    if (step >= description.step_count) return;
    cursor_step = step;
    if (range) selection_mask = rangeMask(anchor_step, step);
    else if (additive) {
        selection_mask ^= 1u << step;
        anchor_step = step;
    } else {
        selection_mask = 1u << step;
        anchor_step = step;
    }
    storeSelection();
    syncAccessibility();
    if (sequencer) sequencer->invalid();
}

void StepSequencerControl::move(bool previous, bool extend) {
    const uint32_t next = previous
        ? (cursor_step == 0 ? description.step_count - 1 : cursor_step - 1)
        : (cursor_step + 1 == description.step_count ? 0 : cursor_step + 1);
    select(next, false, extend);
}

void StepSequencerControl::toggleSelected() {
    const uint32_t selected = selection_mask == 0 ? 1u << cursor_step : selection_mask;
    const bool enable = (active_mask & selected) != selected;
    for (uint32_t step = 0; step < description.step_count; ++step) {
        if ((selected & (1u << step)) != 0) setStep(step, enable);
    }
}

void StepSequencerControl::setStep(uint32_t step, bool active) {
    if (step >= description.step_count || stepActive(step) == active) return;
    const uint32_t parameter = parameter_ids[step];
    if (!callbacks.begin_edit || !callbacks.perform_edit || !callbacks.end_edit) return;
    callbacks.begin_edit(callbacks.userdata, parameter);
    const bool accepted = callbacks.perform_edit(callbacks.userdata, parameter, active ? 1.0 : 0.0) == 0;
    callbacks.end_edit(callbacks.userdata, parameter);
    edit_failed = !accepted;
    if (!accepted) {
        syncAccessibility();
        if (sequencer) sequencer->invalid();
        return;
    }
    if (active) active_mask |= 1u << step; else active_mask &= ~(1u << step);
    syncAccessibility();
    if (sequencer) sequencer->invalid();
}

void StepSequencerControl::storeSelection() {
    if (description.selection_state_id != 0 && callbacks.store_editor_index) {
        callbacks.store_editor_index(callbacks.userdata, description.selection_state_id, selection_mask);
    }
}

void StepSequencerControl::syncAccessibility() {
    char value[160] {};
    const uint32_t selected_count = countSetBits(selection_mask);
    const uint32_t active_count = countSetBits(active_mask);
    const char* status = edit_failed ? ", last edit rejected" : "";
    if (playhead_step >= 0) {
        std::snprintf(value, sizeof(value), "Step %u, %s, %u selected, %u active, playhead %u%s",
            cursor_step + 1, stepActive(cursor_step) ? "active" : "inactive",
            selected_count, active_count, static_cast<uint32_t>(playhead_step) + 1, status);
    } else {
        std::snprintf(value, sizeof(value), "Step %u, %s, %u selected, %u active, playhead stopped%s",
            cursor_step + 1, stepActive(cursor_step) ? "active" : "inactive", selected_count, active_count, status);
    }
    sequencer_component.accessibility().setValueText(value);
    sequencer_component.accessibility().setRange(1.0, description.step_count, cursor_step + 1.0);
}

uint32_t StepSequencerControl::validMask() const {
    return description.step_count >= 32 ? 0xffffffffu : (1u << description.step_count) - 1u;
}

uint32_t StepSequencerControl::rangeMask(uint32_t first, uint32_t last) const {
    const uint32_t low = std::min(first, last);
    const uint32_t high = std::max(first, last);
    const uint32_t upper = high == 31 ? 0xffffffffu : (1u << (high + 1)) - 1u;
    const uint32_t lower = low == 0 ? 0u : (1u << low) - 1u;
    return (upper & ~lower) & validMask();
}

}
