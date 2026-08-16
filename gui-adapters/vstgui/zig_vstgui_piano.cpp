#include "zig_vstgui_piano.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ZigVstgui {

namespace {

bool blackKey(uint32_t pitch) {
    switch (pitch % 12) {
        case 1: case 3: case 6: case 8: case 10: return true;
        default: return false;
    }
}

uint32_t whiteBefore(uint32_t first, uint32_t pitch) {
    uint32_t count = 0;
    for (uint32_t note = first; note < pitch; ++note) if (!blackKey(note)) count += 1;
    return count;
}

std::string noteName(uint32_t pitch) {
    static const char* names[] = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
    char text[16] {};
    std::snprintf(text, sizeof(text), "%s%d", names[pitch % 12], static_cast<int>(pitch / 12) - 1);
    return text;
}

}

PianoView::PianoView(const VSTGUI::CRect& size, PianoControl* value_owner, const ThemeResolver& value_styles)
: CView(size), owner(value_owner), styles(value_styles) {
    setWantsFocus(true);
}

void PianoView::draw(VSTGUI::CDrawContext* context) {
    const auto bounds = getViewSize();
    const auto normal = styles.resolve(ComponentKind::xy_pad);
    const auto pressed = styles.resolve(ComponentKind::xy_pad, VisualState::pressed);
    const auto focused = styles.resolve(ComponentKind::xy_pad, VisualState::focused);
    const auto& colors = styles.theme().colors;
    const uint32_t first = owner->firstNote();
    const uint32_t end = first + owner->noteCount();
    const uint32_t white_count = whiteBefore(first, end);
    if (white_count == 0) return;
    const double white_width = bounds.getWidth() / white_count;
    context->setDrawMode(VSTGUI::kAntiAliasing);
    uint32_t white_index = 0;
    for (uint32_t pitch = first; pitch < end; ++pitch) {
        if (blackKey(pitch)) continue;
        const VSTGUI::CRect key(
            bounds.left + white_index * white_width,
            bounds.top,
            bounds.left + (white_index + 1) * white_width,
            bounds.bottom
        );
        context->setFillColor(owner->notePressed(pitch) ? pressed.accent : colors.surface_raised);
        context->setFrameColor(normal.border);
        context->setLineWidth(1.0);
        context->drawRect(key, VSTGUI::kDrawFilledAndStroked);
        if (pitch == owner->selectedNote()) {
            context->setFrameColor(focused.accent);
            context->setLineWidth(2.0);
            context->drawRect(key, VSTGUI::kDrawStroked);
        }
        if (pitch % 12 == 0 && white_width >= 18.0) {
            context->setFont(styles.font(TypographyRole::value));
            context->setFontColor(colors.text_primary);
            context->drawString(noteName(pitch).c_str(), key, VSTGUI::kCenterText);
        }
        white_index += 1;
    }
    const double black_width = std::max(5.0, white_width * 0.62);
    const double black_height = bounds.getHeight() * 0.62;
    for (uint32_t pitch = first; pitch < end; ++pitch) {
        if (!blackKey(pitch)) continue;
        const double center = bounds.left + whiteBefore(first, pitch) * white_width;
        const VSTGUI::CRect key(center - black_width * 0.5, bounds.top, center + black_width * 0.5, bounds.top + black_height);
        context->setFillColor(owner->notePressed(pitch) ? pressed.accent : colors.text_primary);
        context->setFrameColor(pitch == owner->selectedNote() ? focused.accent : normal.border);
        context->setLineWidth(pitch == owner->selectedNote() ? 2.0 : 1.0);
        context->drawRect(key, VSTGUI::kDrawFilledAndStroked);
    }
    setDirty(false);
}

void PianoView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (!event.buttonState.isLeft()) return;
    const int pitch = owner->hitTest(event.mousePosition);
    if (pitch < 0) return;
    const auto bounds = getViewSize();
    const double velocity = std::clamp(0.25 + 0.75 * ((event.mousePosition.y - bounds.top) / bounds.getHeight()), 0.25, 1.0);
    owner->pointerPress(static_cast<uint32_t>(pitch), velocity);
    if (getFrame()) getFrame()->setFocusView(this);
    event.consumed = true;
}

void PianoView::onMouseMoveEvent(VSTGUI::MouseMoveEvent& event) {
    if (!event.buttonState.isLeft()) return;
    const int pitch = owner->hitTest(event.mousePosition);
    if (pitch < 0) return;
    owner->pointerPress(static_cast<uint32_t>(pitch), 0.8);
    event.consumed = true;
}

void PianoView::onMouseUpEvent(VSTGUI::MouseUpEvent& event) {
    owner->pointerRelease();
    event.consumed = true;
}

void PianoView::onMouseCancelEvent(VSTGUI::MouseCancelEvent& event) {
    owner->pointerRelease();
    event.consumed = true;
}

void PianoView::onMouseEnterEvent(VSTGUI::MouseEnterEvent& event) {
    hovered = true;
    invalid();
    CView::onMouseEnterEvent(event);
}

void PianoView::onMouseExitEvent(VSTGUI::MouseExitEvent& event) {
    hovered = false;
    invalid();
    CView::onMouseExitEvent(event);
}

PianoControl::PianoControl(ZigVstguiPianoDescription value_description, ZigVstguiCallbacks value_callbacks)
: description(value_description), callbacks(value_callbacks), title(value_description.title ? value_description.title : "Keyboard"),
  selected_note(value_description.first_note) {
    key_notes.fill(-1);
}

PianoControl::~PianoControl() {
    releaseAll();
}

void PianoControl::build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles) {
    if (!parent || label || keyboard) return;
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
    keyboard = new PianoView(VSTGUI::CRect(), this, styles);
    parent->addView(keyboard);
    keyboard->registerViewListener(this);
    keyboard_component.bind(keyboard);
    keyboard_component.setFocusable(true);
    auto& accessibility = keyboard_component.accessibility();
    accessibility.setRole(AccessibilityRole::choice);
    accessibility.setName(title);
    accessibility.setDescription("Piano keyboard. Use Left and Right to select a note, then Space or Return to play it.");
    accessibility.setActionHandler(this, accessibilityAction,
        static_cast<uint32_t>(AccessibilityAction::focus) |
        static_cast<uint32_t>(AccessibilityAction::press) |
        static_cast<uint32_t>(AccessibilityAction::increment) |
        static_cast<uint32_t>(AccessibilityAction::decrement));
    syncAccessibility();
}

void PianoControl::clear() {
    releaseAll();
    if (keyboard) keyboard->unregisterViewListener(this);
    keyboard_component.accessibility().clearActionHandler();
    label_component.clear();
    keyboard_component.clear();
    label = nullptr;
    keyboard = nullptr;
}

void PianoControl::setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& keyboard_bounds) {
    label_component.setBounds(label_bounds);
    keyboard_component.setBounds(keyboard_bounds);
}

bool PianoControl::handleKey(uint16_t key, int16_t key_code, int16_t, bool pressed_state) {
    if (key_code == Steinberg::KEY_LEFT || key_code == Steinberg::KEY_RIGHT ||
        key_code == Steinberg::KEY_HOME || key_code == Steinberg::KEY_END) {
        if (!pressed_state) return true;
        if (key_code == Steinberg::KEY_HOME) select(description.first_note);
        else if (key_code == Steinberg::KEY_END) select(description.first_note + description.note_count - 1);
        else if (key_code == Steinberg::KEY_LEFT) select(selected_note == description.first_note
            ? description.first_note + description.note_count - 1 : selected_note - 1);
        else select(selected_note + 1 == description.first_note + description.note_count
            ? description.first_note : selected_note + 1);
        return true;
    }
    if (key == ' ' || key == '\r' || key_code == Steinberg::KEY_RETURN) {
        const uint8_t index = key == ' ' ? 32 : 13;
        if (pressed_state) {
            if (key_notes[index] >= 0) return true;
            if (press(selected_note, description.velocity)) key_notes[index] = static_cast<int16_t>(selected_note);
        } else {
            const int16_t active_pitch = key_notes[index];
            key_notes[index] = -1;
            if (active_pitch >= 0) release(static_cast<uint32_t>(active_pitch));
        }
        return true;
    }
    if (key > 255) return false;
    const int offset = computerOffset(key);
    if (offset < 0) return false;
    const uint32_t pitch = description.computer_base_pitch + static_cast<uint32_t>(offset);
    if (pitch < description.first_note || pitch >= description.first_note + description.note_count) return false;
    const uint8_t index = key >= 'A' && key <= 'Z'
        ? static_cast<uint8_t>(key - 'A' + 'a')
        : static_cast<uint8_t>(key);
    if (pressed_state) {
        if (key_notes[index] >= 0) return true;
        key_notes[index] = static_cast<int16_t>(pitch);
        press(pitch, description.velocity);
    } else {
        const int16_t active_pitch = key_notes[index];
        key_notes[index] = -1;
        if (active_pitch >= 0) release(static_cast<uint32_t>(active_pitch));
    }
    return true;
}

void PianoControl::releaseAll() {
    for (uint32_t pitch = 0; pitch < active.size(); ++pitch) if (active[pitch]) release(pitch);
    key_notes.fill(-1);
    pointer_note = -1;
}

VSTGUI::CView* PianoControl::focusView() const { return keyboard; }

void PianoControl::setFocusedView(VSTGUI::CView* view) {
    const bool focused = keyboard && view == keyboard;
    keyboard_component.setFocused(focused);
    keyboard_component.accessibility().setFocused(focused);
}

const AccessibilityNode& PianoControl::accessibilityNode() const { return keyboard_component.accessibility(); }

int PianoControl::hitTest(const VSTGUI::CPoint& position) const {
    if (!keyboard || !std::isfinite(position.x) ||
        !std::isfinite(position.y)) return -1;
    const auto bounds = keyboard->getViewSize();
    if (!bounds.pointInside(position)) return -1;
    const uint32_t first = description.first_note;
    const uint32_t end = first + description.note_count;
    const uint32_t white_count = whiteBefore(first, end);
    if (white_count == 0) return -1;
    const double white_width = bounds.getWidth() / white_count;
    if (position.y <= bounds.top + bounds.getHeight() * 0.62) {
        const double black_width = std::max(5.0, white_width * 0.62);
        for (uint32_t pitch = first; pitch < end; ++pitch) {
            if (!blackKey(pitch)) continue;
            const double center = bounds.left + whiteBefore(first, pitch) * white_width;
            if (position.x >= center - black_width * 0.5 && position.x <= center + black_width * 0.5) {
                return static_cast<int>(pitch);
            }
        }
    }
    const uint32_t ordinal = std::min(white_count - 1, static_cast<uint32_t>((position.x - bounds.left) / white_width));
    uint32_t seen = 0;
    for (uint32_t pitch = first; pitch < end; ++pitch) {
        if (blackKey(pitch)) continue;
        if (seen++ == ordinal) return static_cast<int>(pitch);
    }
    return -1;
}

bool PianoControl::notePressed(uint32_t pitch) const { return pitch < active.size() && active[pitch]; }
uint32_t PianoControl::selectedNote() const { return selected_note; }
uint32_t PianoControl::firstNote() const { return description.first_note; }
uint32_t PianoControl::noteCount() const { return description.note_count; }

void PianoControl::pointerPress(uint32_t pitch, double velocity) {
    if (pointer_note == static_cast<int>(pitch)) return;
    pointerRelease();
    if (press(pitch, velocity)) pointer_note = static_cast<int>(pitch);
}

void PianoControl::pointerRelease() {
    if (pointer_note < 0) return;
    release(static_cast<uint32_t>(pointer_note));
    pointer_note = -1;
}

void PianoControl::viewLostFocus(VSTGUI::CView* view) {
    if (view != keyboard) return;
    releaseAll();
    setFocusedView(nullptr);
}

void PianoControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == keyboard) setFocusedView(view);
}

bool PianoControl::accessibilityAction(void* userdata, const AccessibilityNode&, const AccessibilityActionRequest& request) {
    auto* piano = static_cast<PianoControl*>(userdata);
    return piano && piano->performAccessibilityAction(request);
}

bool PianoControl::performAccessibilityAction(const AccessibilityActionRequest& request) {
    if (request.action == AccessibilityAction::focus) {
        if (!keyboard || !keyboard->getFrame()) return false;
        keyboard->getFrame()->setFocusView(keyboard);
        setFocusedView(keyboard);
        return true;
    }
    if (request.action == AccessibilityAction::increment) {
        select(selected_note + 1 == description.first_note + description.note_count ? description.first_note : selected_note + 1);
        return true;
    }
    if (request.action == AccessibilityAction::decrement) {
        select(selected_note == description.first_note ? description.first_note + description.note_count - 1 : selected_note - 1);
        return true;
    }
    if (request.action == AccessibilityAction::press) {
        if (active[selected_note]) return release(selected_note);
        return press(selected_note, description.velocity);
    }
    return false;
}

bool PianoControl::press(uint32_t pitch, double velocity) {
    if (pitch >= active.size() || active[pitch]) return false;
    if (!callbacks.send_note || callbacks.send_note(callbacks.userdata, description.channel, pitch, velocity, 1) != 0) return false;
    active[pitch] = true;
    select(pitch);
    if (keyboard) keyboard->invalid();
    return true;
}

bool PianoControl::release(uint32_t pitch) {
    if (pitch >= active.size() || !active[pitch]) return false;
    if (!callbacks.send_note || callbacks.send_note(callbacks.userdata, description.channel, pitch, 0.0, 0) != 0) return false;
    active[pitch] = false;
    if (keyboard) keyboard->invalid();
    syncAccessibility();
    return true;
}

void PianoControl::select(uint32_t pitch) {
    if (pitch < description.first_note || pitch >= description.first_note + description.note_count) return;
    selected_note = pitch;
    syncAccessibility();
    if (keyboard) keyboard->invalid();
}

void PianoControl::syncAccessibility() {
    auto& node = keyboard_component.accessibility();
    node.setRange(description.first_note, description.first_note + description.note_count - 1, selected_note);
    node.setValueText(noteName(selected_note) + (active[selected_note] ? ", playing" : ", ready"));
}

int PianoControl::computerOffset(uint16_t key) {
    const char* keys = "awsedftgyhujkolp;";
    const char normalized = key >= 'A' && key <= 'Z' ? static_cast<char>(key - 'A' + 'a') : static_cast<char>(key);
    for (int index = 0; keys[index] != 0; ++index) if (keys[index] == normalized) return index;
    return -1;
}

}
