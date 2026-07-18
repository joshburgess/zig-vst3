#include "zig_vstgui_text_progress.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <new>

namespace ZigVstgui {

bool EditableLabelControl::build(VSTGUI::CViewContainer* parent,
    const ZigVstguiEditableLabelDescription& value_description, ZigVstguiCallbacks value_callbacks,
    const ThemeResolver& styles) {
    if (!parent || label || edit || message) return false;
    description = value_description;
    callbacks = value_callbacks;
    accepted_text = description.initial_text;
    error_text = description.error_text;
    const auto label_style = styles.resolve(ComponentKind::title);
    const auto value_style = styles.resolve(ComponentKind::value_field);

    label = new (std::nothrow) VSTGUI::CTextLabel(VSTGUI::CRect(), description.label);
    edit = new (std::nothrow) VSTGUI::CTextEdit(VSTGUI::CRect(), this, 0, accepted_text.c_str());
    message = new (std::nothrow) VSTGUI::CTextLabel(VSTGUI::CRect(), error_text.c_str());
    if (!label || !edit || !message) return false;

    label->setFont(styles.font(TypographyRole::body));
    label->setFontColor(label_style.foreground);
    label->setBackColor(label_style.background);
    label->setHoriAlign(VSTGUI::kLeftText);
    edit->setFont(styles.font(TypographyRole::value));
    edit->setFontColor(value_style.foreground);
    edit->setBackColor(value_style.background);
    edit->setFrameColor(value_style.border);
    edit->setFrameWidth(value_style.frame_width);
    edit->setRoundRectRadius(value_style.radius);
    edit->setPlaceholderString(description.placeholder);
    message->setFont(styles.font(TypographyRole::body));
    message->setFontColor(VSTGUI::CColor(196, 72, 72, 255));
    message->setBackColor(label_style.background);
    message->setHoriAlign(VSTGUI::kLeftText);

    parent->addView(label);
    parent->addView(edit);
    parent->addView(message);
    edit->registerViewListener(this);
    label_component.bind(label);
    edit_component.bind(edit);
    message_component.bind(message);
    label_component.accessibility().setRole(AccessibilityRole::group);
    label_component.accessibility().setName(description.label);
    label_component.accessibility().setReadOnly(true);
    edit_component.setFocusable(true);
    edit_component.setEnabled(description.enabled != 0);
    edit_component.accessibility().setRole(AccessibilityRole::text_field);
    edit_component.accessibility().setName(description.accessible_label);
    edit_component.accessibility().setValueText(accepted_text);
    edit_component.accessibility().setActionHandler(this, accessibilityAction,
        static_cast<uint32_t>(AccessibilityAction::focus) |
        static_cast<uint32_t>(AccessibilityAction::set_value));
    message_component.accessibility().setRole(AccessibilityRole::group);
    message_component.accessibility().setName(error_text);
    message_component.accessibility().setReadOnly(true);
    showError(false);
    return true;
}

void EditableLabelControl::clear() {
    if (edit) edit->unregisterViewListener(this);
    edit_component.accessibility().clearActionHandler();
    label_component.clear();
    edit_component.clear();
    message_component.clear();
    label = nullptr;
    edit = nullptr;
    message = nullptr;
}

void EditableLabelControl::setBounds(const VSTGUI::CRect& label_bounds,
    const VSTGUI::CRect& edit_bounds, const VSTGUI::CRect& message_bounds) {
    label_component.setBounds(label_bounds);
    edit_component.setBounds(edit_bounds);
    message_component.setBounds(message_bounds);
}

bool EditableLabelControl::refresh() {
    if (!edit || edit->isEditing() || !callbacks.load_editor_text) return false;
    char text[97] {};
    if (callbacks.load_editor_text(callbacks.userdata, description.field_id, text,
            std::min<uint32_t>(description.maximum_bytes + 1, sizeof(text))) < 0) return false;
    if (accepted_text == text) return false;
    accepted_text = text;
    edit->setText(accepted_text.c_str());
    edit_component.accessibility().setValueText(accepted_text);
    showError(false);
    return true;
}

bool EditableLabelControl::handleKey(uint16_t key, int16_t key_code) {
    if (!edit) return false;
    if (key_code == Steinberg::KEY_ESCAPE || key == 27) {
        edit->setText(accepted_text.c_str());
        showError(false);
        return true;
    }
    return false;
}

VSTGUI::CView* EditableLabelControl::focusView() const { return edit; }

void EditableLabelControl::setFocusedView(VSTGUI::CView* view) {
    edit_component.setFocused(view && view == edit);
}

const AccessibilityNode& EditableLabelControl::accessibilityNode() const {
    return edit_component.accessibility();
}

void EditableLabelControl::valueChanged(VSTGUI::CControl*) {
    if (edit) commit(edit->getText().getString().c_str());
}

void EditableLabelControl::viewLostFocus(VSTGUI::CView* view) {
    if (view == edit) setFocusedView(nullptr);
}

void EditableLabelControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == edit) setFocusedView(view);
}

bool EditableLabelControl::accessibilityAction(void* userdata, const AccessibilityNode&,
    const AccessibilityActionRequest& request) {
    auto* self = static_cast<EditableLabelControl*>(userdata);
    if (!self || !self->edit) return false;
    if (request.action == AccessibilityAction::focus) {
        if (!self->edit->getFrame()) return false;
        self->edit->getFrame()->setFocusView(self->edit);
        return true;
    }
    if (request.action == AccessibilityAction::set_value) return self->commit(request.text);
    return false;
}

bool EditableLabelControl::commit(const char* text) {
    if (!text || !callbacks.store_editor_text || std::char_traits<char>::length(text) > description.maximum_bytes) {
        showError(true);
        return false;
    }
    if (callbacks.store_editor_text(callbacks.userdata, description.field_id, text) != 0) {
        showError(true);
        return false;
    }
    accepted_text = text;
    if (edit) edit->setText(accepted_text.c_str());
    edit_component.accessibility().setValueText(accepted_text);
    showError(false);
    return true;
}

void EditableLabelControl::showError(bool visible) {
    message_component.setVisible(visible);
    edit_component.accessibility().setDescription(visible ? error_text : "");
}

ProgressView::ProgressView(const VSTGUI::CRect& size,
    const ZigVstguiProgressIndicatorDescription& value_description, ZigVstguiCallbacks value_callbacks,
    const ThemeResolver& value_styles, AccessibilityNode* value_accessibility)
: CView(size), description(value_description), callbacks(value_callbacks), styles(value_styles),
  accessibility(value_accessibility) {}

bool ProgressView::tick() {
    if (!callbacks.load_progress) return false;
    ZigVstguiProgressSnapshot next {};
    if (callbacks.load_progress(callbacks.userdata, description.source_id, &next) != 0 ||
        next.mode < ZIG_VSTGUI_PROGRESS_DETERMINATE || next.mode > ZIG_VSTGUI_PROGRESS_INDETERMINATE ||
        next.state < ZIG_VSTGUI_PROGRESS_IDLE || next.state > ZIG_VSTGUI_PROGRESS_FAILED ||
        !std::isfinite(next.value) || next.value < 0.0 || next.value > 1.0 ||
        (next.state == ZIG_VSTGUI_PROGRESS_COMPLETE && next.value != 1.0) ||
        (next.mode == ZIG_VSTGUI_PROGRESS_INDETERMINATE && next.state != ZIG_VSTGUI_PROGRESS_RUNNING)) return false;
    const bool animated = next.mode == ZIG_VSTGUI_PROGRESS_INDETERMINATE;
    const bool changed = !initialized || next.mode != current.mode || next.state != current.state ||
        next.value != current.value || next.generation != current.generation;
    current = next;
    initialized = true;
    if (animated) phase = std::fmod(phase + 0.08, 1.0);
    if (!changed && !animated) return false;
    updateAccessibility();
    invalid();
    return true;
}

void ProgressView::draw(VSTGUI::CDrawContext* context) {
    const auto bounds = getViewSize();
    const auto style = styles.resolve(ComponentKind::meter);
    context->setFillColor(style.background);
    context->setFrameColor(style.border);
    context->setLineWidth(style.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);
    VSTGUI::CRect fill = bounds;
    if (current.mode == ZIG_VSTGUI_PROGRESS_INDETERMINATE) {
        const double segment = bounds.getWidth() * 0.28;
        fill.left = bounds.left + (bounds.getWidth() + segment) * phase - segment;
        fill.right = fill.left + segment;
        fill.bound(bounds);
    } else {
        fill.right = fill.left + fill.getWidth() * current.value;
    }
    context->setFillColor(current.state == ZIG_VSTGUI_PROGRESS_FAILED
        ? VSTGUI::CColor(196, 72, 72, 255) : style.accent);
    context->drawRect(fill, VSTGUI::kDrawFilled);
    context->setFont(styles.font(TypographyRole::body));
    context->setFontColor(style.foreground);
    context->drawString(stateText(), bounds, VSTGUI::kCenterText);
    setDirty(false);
}

const ZigVstguiProgressSnapshot& ProgressView::snapshot() const { return current; }

void ProgressView::updateAccessibility() {
    if (!accessibility) return;
    char value[128] {};
    if (current.mode == ZIG_VSTGUI_PROGRESS_DETERMINATE && current.state == ZIG_VSTGUI_PROGRESS_RUNNING) {
        std::snprintf(value, sizeof(value), "%s, %.0f%%", stateText(), current.value * 100.0);
        accessibility->setRange(0.0, 1.0, current.value);
    } else {
        std::snprintf(value, sizeof(value), "%s", stateText());
        accessibility->clearRange();
    }
    accessibility->setValueText(value);
}

const char* ProgressView::stateText() const {
    switch (current.state) {
        case ZIG_VSTGUI_PROGRESS_RUNNING: return description.running_text;
        case ZIG_VSTGUI_PROGRESS_COMPLETE: return description.complete_text;
        case ZIG_VSTGUI_PROGRESS_FAILED: return description.failure_text;
        default: return description.idle_text;
    }
}

ProgressIndicatorControl::~ProgressIndicatorControl() {
    stop();
    if (timer) timer->forget();
}

bool ProgressIndicatorControl::build(VSTGUI::CViewContainer* parent,
    const ZigVstguiProgressIndicatorDescription& description, ZigVstguiCallbacks callbacks,
    const ThemeResolver& styles) {
    if (!parent || label || progress) return false;
    const auto label_style = styles.resolve(ComponentKind::title);
    label = new (std::nothrow) VSTGUI::CTextLabel(VSTGUI::CRect(), description.label);
    if (!label) return false;
    label->setFont(styles.font(TypographyRole::body));
    label->setFontColor(label_style.foreground);
    label->setBackColor(label_style.background);
    label->setHoriAlign(VSTGUI::kLeftText);
    parent->addView(label);
    label_component.bind(label);
    label_component.accessibility().setRole(AccessibilityRole::group);
    label_component.accessibility().setName(description.label);
    label_component.accessibility().setReadOnly(true);

    progress_component.accessibility().setRole(AccessibilityRole::meter);
    progress_component.accessibility().setName(description.accessible_label);
    progress_component.accessibility().setReadOnly(true);
    progress = new (std::nothrow) ProgressView(VSTGUI::CRect(), description, callbacks, styles,
        &progress_component.accessibility());
    if (!progress) return false;
    parent->addView(progress);
    progress_component.bind(progress);
    const uint32_t interval = std::max<uint32_t>(1, 1000 / description.maximum_refresh_hz);
    timer = new (std::nothrow) VSTGUI::CVSTGUITimer(
        [this](VSTGUI::CVSTGUITimer*) { tick(); }, interval, false);
    tick();
    return timer != nullptr;
}

void ProgressIndicatorControl::clear() {
    stop();
    label_component.clear();
    progress_component.clear();
    label = nullptr;
    progress = nullptr;
}

void ProgressIndicatorControl::setBounds(const VSTGUI::CRect& label_bounds,
    const VSTGUI::CRect& progress_bounds) {
    label_component.setBounds(label_bounds);
    progress_component.setBounds(progress_bounds);
}

void ProgressIndicatorControl::start() {
    if (timer && timer->start()) active = true;
}

void ProgressIndicatorControl::stop() {
    if (timer) timer->stop();
    active = false;
}

bool ProgressIndicatorControl::running() const { return active; }
bool ProgressIndicatorControl::tick() { return progress && progress->tick(); }
const AccessibilityNode& ProgressIndicatorControl::accessibilityNode() const {
    return progress_component.accessibility();
}
VSTGUI::CView* ProgressIndicatorControl::accessibilityView() const { return progress; }
const ProgressView* ProgressIndicatorControl::progressView() const { return progress; }

}
