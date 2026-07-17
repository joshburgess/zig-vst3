#include "zig_vstgui_meters.h"

#include "vstgui/lib/cdrawcontext.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ZigVstgui {

MeterBallistics::MeterBallistics(double hold_ms, double decay_per_second)
: hold_duration_ms(std::max(0.0, hold_ms)),
  decay_per_ms(std::max(0.0, decay_per_second) / 1000.0) {}

bool MeterBallistics::update(double input, double elapsed_ms) {
    const double next = std::isfinite(input) ? std::clamp(input, 0.0, 1.0) : 0.0;
    const double elapsed = std::isfinite(elapsed_ms) ? std::max(0.0, elapsed_ms) : 0.0;
    const double old_level = displayed_level;
    const double old_peak = held_peak;
    displayed_level = next >= displayed_level
        ? next
        : std::max(next, displayed_level - decay_per_ms * elapsed);
    if (next >= held_peak) {
        held_peak = next;
        hold_remaining_ms = hold_duration_ms;
    } else if (hold_remaining_ms > elapsed) {
        hold_remaining_ms -= elapsed;
    } else {
        const double decay_elapsed = elapsed - hold_remaining_ms;
        hold_remaining_ms = 0.0;
        held_peak = std::max(displayed_level, held_peak - decay_per_ms * decay_elapsed);
    }
    return displayed_level != old_level || held_peak != old_peak;
}

void MeterBallistics::reset() {
    displayed_level = 0.0;
    held_peak = 0.0;
    hold_remaining_ms = 0.0;
}

double MeterBallistics::level() const {
    return displayed_level;
}

double MeterBallistics::peak() const {
    return held_peak;
}

MeterView::MeterView(
    const VSTGUI::CRect& size,
    MeterVariant value_variant,
    uint32_t value_first_source,
    uint32_t value_second_source,
    MeterSource value_source,
    const ThemeResolver& value_styles,
    AccessibilityNode* value_accessibility
)
: CView(size),
  variant(value_variant),
  first_source(value_first_source),
  second_source(value_second_source),
  source(value_source),
  styles(value_styles),
  accessibility(value_accessibility) {}

bool MeterView::tick(double elapsed_ms) {
    if (!source.load) return false;
    const bool first_changed = first.update(source.load(source.userdata, first_source), elapsed_ms);
    const bool second_changed = variant == MeterVariant::stereo &&
        second.update(source.load(source.userdata, second_source), elapsed_ms);
    if (!first_changed && !second_changed) return false;
    updateAccessibility();
    invalid();
    return true;
}

void MeterView::draw(VSTGUI::CDrawContext* context) {
    const auto bounds = getViewSize();
    if (variant == MeterVariant::stereo) {
        const double gap = 4.0;
        const double half = (bounds.getWidth() - gap) / 2.0;
        drawBar(context, VSTGUI::CRect(bounds.left, bounds.top, bounds.left + half, bounds.bottom), first);
        drawBar(context, VSTGUI::CRect(bounds.left + half + gap, bounds.top, bounds.right, bounds.bottom), second);
    } else {
        drawBar(context, bounds, first);
    }
    setDirty(false);
}

double MeterView::level(uint32_t channel) const {
    return channel == 0 ? first.level() : second.level();
}

double MeterView::peak(uint32_t channel) const {
    return channel == 0 ? first.peak() : second.peak();
}

void MeterView::updateAccessibility() {
    if (!accessibility) return;
    const double primary = first.level();
    char text[96] {};
    if (variant == MeterVariant::stereo) {
        std::snprintf(text, sizeof(text), "Left %.0f%%, Right %.0f%%", primary * 100.0, second.level() * 100.0);
    } else if (variant == MeterVariant::gain_reduction) {
        std::snprintf(text, sizeof(text), "%.1f dB reduction", primary * 24.0);
    } else {
        const double db = primary > 0.0 ? 20.0 * std::log10(primary) : -96.0;
        std::snprintf(text, sizeof(text), "%.1f dB", db);
    }
    accessibility->setValueText(text);
    accessibility->setRange(0.0, 1.0, primary);
}

void MeterView::drawBar(
    VSTGUI::CDrawContext* context,
    const VSTGUI::CRect& bounds,
    const MeterBallistics& value
) {
    const auto style = styles.resolve(ComponentKind::meter);
    context->setFillColor(style.background);
    context->setFrameColor(style.border);
    context->setLineWidth(style.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);
    const double amount = std::clamp(value.level(), 0.0, 1.0);
    VSTGUI::CRect fill = bounds;
    if (variant == MeterVariant::gain_reduction) {
        fill.bottom = fill.top + fill.getHeight() * amount;
    } else {
        fill.top = fill.bottom - fill.getHeight() * amount;
    }
    context->setFillColor(style.accent);
    context->drawRect(fill, VSTGUI::kDrawFilled);
    const double peak_y = variant == MeterVariant::gain_reduction
        ? bounds.top + bounds.getHeight() * value.peak()
        : bounds.bottom - bounds.getHeight() * value.peak();
    context->setFrameColor(style.foreground);
    context->drawLine(VSTGUI::CPoint(bounds.left, peak_y), VSTGUI::CPoint(bounds.right, peak_y));
}

MeterControl::~MeterControl() {
    stop();
    if (timer) timer->forget();
}

void MeterControl::build(
    VSTGUI::CViewContainer* parent,
    const char* title,
    MeterVariant variant,
    uint32_t first_source,
    uint32_t second_source,
    MeterSource source,
    const ThemeResolver& styles
) {
    if (!parent || label || meter) return;
    const auto label_style = styles.resolve(ComponentKind::title);
    label = new VSTGUI::CTextLabel(VSTGUI::CRect(), title ? title : "Meter");
    label->setFont(styles.font(TypographyRole::body));
    label->setFontColor(label_style.foreground);
    label->setBackColor(label_style.background);
    label->setFrameColor(label_style.border);
    parent->addView(label);
    label_component.bind(label);
    label_component.accessibility().setRole(AccessibilityRole::group);
    label_component.accessibility().setName(title ? title : "Meter");
    label_component.accessibility().setReadOnly(true);

    meter_component.accessibility().setRole(AccessibilityRole::meter);
    meter_component.accessibility().setName(title ? title : "Meter");
    meter_component.accessibility().setDescription("Audio level");
    meter_component.accessibility().setReadOnly(true);
    meter = new MeterView(
        VSTGUI::CRect(),
        variant,
        first_source,
        second_source,
        source,
        styles,
        &meter_component.accessibility()
    );
    parent->addView(meter);
    meter_component.bind(meter);
    if (!timer) timer = new VSTGUI::CVSTGUITimer([this](VSTGUI::CVSTGUITimer*) { tick(); }, 33, false);
    tick(0.0);
}

void MeterControl::clear() {
    stop();
    label_component.clear();
    meter_component.clear();
    label = nullptr;
    meter = nullptr;
}

void MeterControl::setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& meter_bounds) {
    label_component.setBounds(label_bounds);
    meter_component.setBounds(meter_bounds);
}

void MeterControl::setLabelVisible(bool visible) {
    label_component.setVisible(visible);
}

void MeterControl::start() {
    if (timer && timer->start()) active = true;
}

void MeterControl::stop() {
    if (timer) timer->stop();
    active = false;
}

bool MeterControl::running() const {
    return active;
}

bool MeterControl::tick(double elapsed_ms) {
    return meter && meter->tick(elapsed_ms);
}

const AccessibilityNode& MeterControl::accessibilityNode() const {
    return meter_component.accessibility();
}

const MeterView* MeterControl::meterView() const {
    return meter;
}

}
