#include "zig_vstgui_preset_browser.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/events.h"
#include "vstgui/lib/cframe.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
#include <utility>

namespace ZigVstgui {

namespace {

constexpr uint32_t actionMask(AccessibilityAction action) {
    return static_cast<uint32_t>(action);
}

bool containsIgnoringCase(const std::string& value, const std::string& query) {
    return std::search(
        value.begin(), value.end(), query.begin(), query.end(),
        [](char left, char right) {
            return std::tolower(static_cast<unsigned char>(left)) ==
                std::tolower(static_cast<unsigned char>(right));
        }
    ) != value.end();
}

}

PresetBrowserView::PresetBrowserView(
    const VSTGUI::CRect& size,
    const ZigVstguiPresetBrowserDescription& description,
    ZigVstguiCallbacks value_callbacks,
    const ThemeResolver& value_styles,
    AccessibilityNode* value_accessibility
)
: CView(size),
  title(description.title ? description.title : "Presets"),
  search(description.initial_search ? description.initial_search : ""),
  callbacks(value_callbacks),
  styles(value_styles),
  accessibility(value_accessibility),
  search_state_id(description.search_state_id),
  selection_state_id(description.selection_state_id) {
    if (!description.title || !description.presets || description.preset_count == 0 ||
        description.preset_count > ZIG_VSTGUI_MAX_PRESETS || search.size() > 96 ||
        search_state_id == 0 || selection_state_id == 0 || search_state_id == selection_state_id) return;
    presets.reserve(description.preset_count);
    for (uint32_t index = 0; index < description.preset_count; ++index) {
        const auto& preset = description.presets[index];
        if (preset.preset_id == 0 || !preset.name || preset.name[0] == 0) return;
        for (const auto& previous : presets) if (previous.id == preset.preset_id) return;
        presets.push_back({preset.preset_id, preset.name});
        if (preset.preset_id == description.initial_selection) selected = index;
    }
    valid_description = true;
    setWantsFocus(true);
    syncHeader();
    ensureVisibleSelection();
    if (accessibility) {
        accessibility->setRole(AccessibilityRole::choice);
        accessibility->setName(title);
        accessibility->setDescription("Type to search, use arrow keys to choose, and press Enter to load. Double-click also loads");
        accessibility->setActionHandler(
            this,
            accessibilityAction,
            actionMask(AccessibilityAction::focus) |
                actionMask(AccessibilityAction::press) |
                actionMask(AccessibilityAction::increment) |
                actionMask(AccessibilityAction::decrement) |
                actionMask(AccessibilityAction::set_value)
        );
    }
    syncAccessibility();
}

bool PresetBrowserView::valid() const {
    return valid_description;
}

PresetBrowserView::MatchList PresetBrowserView::matches() const {
    MatchList result;
    for (std::size_t index = 0; index < presets.size(); ++index) {
        if (search.empty() || containsIgnoringCase(presets[index].name, search)) {
            result.indices[result.count++] = index;
        }
    }
    return result;
}

void PresetBrowserView::ensureVisibleSelection() {
    const auto visible = matches();
    if (visible.count == 0) {
        selected.reset();
        first_visible = 0;
        status = search.empty() ? "No presets available" : "No matches. Escape clears search";
        return;
    }
    const auto end = visible.indices.begin() + visible.count;
    if (!selected || std::find(visible.indices.begin(), end, *selected) == end) selected = visible.indices[0];
    ensureSelectionInViewport(visible);
    status.clear();
}

void PresetBrowserView::ensureSelectionInViewport(const MatchList& visible) {
    if (!selected || visible.count == 0) {
        first_visible = 0;
        return;
    }
    const auto end = visible.indices.begin() + visible.count;
    const auto position = std::find(visible.indices.begin(), end, *selected);
    if (position == end) return;
    const std::size_t selected_row = static_cast<std::size_t>(position - visible.indices.begin());
    const auto bounds = getViewSize();
    const std::size_t capacity = std::max<std::size_t>(
        1,
        static_cast<std::size_t>(std::max(0.0, (bounds.getHeight() - 54.0) / 24.0))
    );
    if (selected_row < first_visible) first_visible = selected_row;
    if (selected_row >= first_visible + capacity) first_visible = selected_row - capacity + 1;
}

bool PresetBrowserView::selectRelative(bool next) {
    const auto visible = matches();
    if (visible.count == 0) return false;
    const auto end = visible.indices.begin() + visible.count;
    auto current = std::find(visible.indices.begin(), end, selected.value_or(visible.indices[0]));
    std::size_t position = current == end ? 0 : static_cast<std::size_t>(current - visible.indices.begin());
    position = next ? (position + 1) % visible.count : (position + visible.count - 1) % visible.count;
    selected = visible.indices[position];
    ensureSelectionInViewport(visible);
    status.clear();
    persistSelection();
    syncAccessibility();
    invalid();
    return true;
}

bool PresetBrowserView::selectBoundary(bool last) {
    const auto visible = matches();
    if (visible.count == 0) return false;
    selected = last ? visible.indices[visible.count - 1] : visible.indices[0];
    ensureSelectionInViewport(visible);
    status.clear();
    persistSelection();
    syncAccessibility();
    invalid();
    return true;
}

bool PresetBrowserView::activate() {
    if (!selected) return false;
    status = "Loading " + presets[*selected].name;
    syncAccessibility();
    invalid();
    const bool loaded = callbacks.load_preset && callbacks.load_preset(callbacks.userdata, presets[*selected].id) == 0;
    status = loaded ? "Loaded " + presets[*selected].name : "Load failed. Press Enter to retry";
    syncAccessibility();
    invalid();
    return true;
}

void PresetBrowserView::replaceSearch(std::string value) {
    if (value.size() > 96 || value == search) return;
    search = std::move(value);
    syncHeader();
    ensureVisibleSelection();
    persistSearch();
    persistSelection();
    syncAccessibility();
    invalid();
}

void PresetBrowserView::syncHeader() {
    header = title + "  Search: " + (search.empty() ? "All presets" : search);
}

void PresetBrowserView::persistSearch() {
    if (callbacks.store_editor_text) callbacks.store_editor_text(callbacks.userdata, search_state_id, search.c_str());
}

void PresetBrowserView::persistSelection() {
    if (callbacks.store_editor_index) callbacks.store_editor_index(
        callbacks.userdata,
        selection_state_id,
        selected ? presets[*selected].id : 0
    );
}

void PresetBrowserView::syncAccessibility() {
    if (!accessibility) return;
    const auto visible = matches();
    std::string value = "Search " + (search.empty() ? std::string("all") : search) + ". ";
    if (selected) value += "Selected " + presets[*selected].name + ". ";
    value += status.empty() ? std::to_string(visible.count) + " results" : status;
    accessibility->setValueText(value);
    accessibility->setSelected(selected.has_value());
    if (selected && visible.count > 0) {
        const auto position = std::find(visible.indices.begin(), visible.indices.begin() + visible.count, *selected);
        accessibility->setRange(1.0, static_cast<double>(visible.count), static_cast<double>(position - visible.indices.begin() + 1));
    } else accessibility->clearRange();
}

bool PresetBrowserView::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    if ((modifiers & ~1) != 0) return false;
    if (key_code == Steinberg::KEY_UP) return selectRelative(false);
    if (key_code == Steinberg::KEY_DOWN) return selectRelative(true);
    if (key_code == Steinberg::KEY_HOME) return selectBoundary(false);
    if (key_code == Steinberg::KEY_END) return selectBoundary(true);
    if (key_code == Steinberg::KEY_RETURN) return activate();
    if (key_code == Steinberg::KEY_ESCAPE) {
        replaceSearch("");
        return true;
    }
    if (key_code == Steinberg::KEY_BACK) {
        if (!search.empty()) replaceSearch(search.substr(0, search.size() - 1));
        return true;
    }
    if (key >= 32 && key <= 126 && search.size() < 96) {
        replaceSearch(search + static_cast<char>(key));
        return true;
    }
    return false;
}

uint32_t PresetBrowserView::selectedPreset() const {
    return selected ? presets[*selected].id : 0;
}

const std::string& PresetBrowserView::searchText() const {
    return search;
}

const std::string& PresetBrowserView::statusText() const {
    return status;
}

void PresetBrowserView::draw(VSTGUI::CDrawContext* context) {
    if (!context) return;
    const auto focused = getFrame() && getFrame()->getFocusView() == this;
    const auto style = styles.resolve(ComponentKind::value_field, focused ? VisualState::focused : VisualState::normal);
    const auto bounds = getViewSize();
    const VSTGUI::ConcatClip clip(*context, bounds);
    if (clip.isEmpty()) return;
    context->setFillColor(style.background);
    context->drawRect(bounds, VSTGUI::kDrawFilled);
    context->setFrameColor(style.border);
    context->setLineWidth(style.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawStroked);
    context->setFont(styles.font(TypographyRole::body));
    context->setFontColor(style.foreground);
    context->drawString(
        header.c_str(),
        VSTGUI::CRect(bounds.left + 8, bounds.top + 4, bounds.right - 8, bounds.top + 28),
        VSTGUI::kLeftText
    );
    const auto visible = matches();
    const double row_height = 24.0;
    ensureSelectionInViewport(visible);
    const std::size_t capacity = static_cast<std::size_t>(std::max(0.0, (bounds.getHeight() - 54.0) / row_height));
    const std::size_t remaining = visible.count > first_visible ? visible.count - first_visible : 0;
    const std::size_t row_count = std::min(remaining, capacity);
    for (std::size_t row = 0; row < row_count; ++row) {
        const auto index = visible.indices[first_visible + row];
        const VSTGUI::CRect row_bounds(bounds.left + 6, bounds.top + 30 + row * row_height, bounds.right - 6, bounds.top + 30 + (row + 1) * row_height);
        if (selected && *selected == index) {
            context->setFillColor(style.accent);
            context->drawRect(row_bounds, VSTGUI::kDrawFilled);
        }
        context->setFontColor(style.foreground);
        context->drawString(
            presets[index].name.c_str(),
            VSTGUI::CRect(row_bounds.left + 8.0, row_bounds.top, row_bounds.right - 8.0, row_bounds.bottom),
            VSTGUI::kLeftText
        );
    }
    if (visible.count == 0 || !status.empty()) {
        context->setFontColor(style.foreground);
        context->drawString(
            status.c_str(),
            VSTGUI::CRect(bounds.left + 8, bounds.bottom - 24, bounds.right - 8, bounds.bottom - 4),
            VSTGUI::kLeftText
        );
    }
}

void PresetBrowserView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (!event.buttonState.isLeft() ||
        !std::isfinite(event.mousePosition.x) ||
        !std::isfinite(event.mousePosition.y)) return;
    const auto visible = matches();
    const auto bounds = getViewSize();
    if (event.mousePosition.y < bounds.top + 30) return;
    const std::size_t row = static_cast<std::size_t>((event.mousePosition.y - bounds.top - 30) / 24.0);
    if (first_visible + row >= visible.count) return;
    selected = visible.indices[first_visible + row];
    status.clear();
    persistSelection();
    syncAccessibility();
    if (getFrame()) getFrame()->setFocusView(this);
    invalid();
    if (event.clickCount >= 2) activate();
    event.consumed = true;
}

void PresetBrowserView::onKeyboardEvent(VSTGUI::KeyboardEvent& event) {
    if (event.type != VSTGUI::EventType::KeyDown) return;
    int16_t key_code = 0;
    switch (event.virt) {
        case VSTGUI::VirtualKey::Up: key_code = Steinberg::KEY_UP; break;
        case VSTGUI::VirtualKey::Down: key_code = Steinberg::KEY_DOWN; break;
        case VSTGUI::VirtualKey::Home: key_code = Steinberg::KEY_HOME; break;
        case VSTGUI::VirtualKey::End: key_code = Steinberg::KEY_END; break;
        case VSTGUI::VirtualKey::Return: key_code = Steinberg::KEY_RETURN; break;
        case VSTGUI::VirtualKey::Escape: key_code = Steinberg::KEY_ESCAPE; break;
        case VSTGUI::VirtualKey::Back: key_code = Steinberg::KEY_BACK; break;
        default: break;
    }
    if (handleKey(event.character, key_code, 0)) event.consumed = true;
}

bool PresetBrowserView::accessibilityAction(void* userdata, const AccessibilityNode&, const AccessibilityActionRequest& request) {
    auto* self = static_cast<PresetBrowserView*>(userdata);
    return self && self->performAccessibilityAction(request);
}

bool PresetBrowserView::performAccessibilityAction(const AccessibilityActionRequest& request) {
    switch (request.action) {
        case AccessibilityAction::focus:
            if (getFrame()) getFrame()->setFocusView(this);
            return getFrame() != nullptr;
        case AccessibilityAction::press: return activate();
        case AccessibilityAction::increment: return selectRelative(true);
        case AccessibilityAction::decrement: return selectRelative(false);
        case AccessibilityAction::set_value:
            if (!request.text || std::strlen(request.text) > 96) return false;
            replaceSearch(request.text);
            return true;
        default: return false;
    }
}

bool PresetBrowserControl::build(VSTGUI::CViewContainer* parent, const ZigVstguiPresetBrowserDescription& description, ZigVstguiCallbacks callbacks, const ThemeResolver& styles) {
    if (!parent || browser) return false;
    browser = new (std::nothrow) PresetBrowserView(VSTGUI::CRect(), description, callbacks, styles, &component.accessibility());
    if (!browser || !browser->valid()) {
        if (browser) browser->forget();
        browser = nullptr;
        return false;
    }
    parent->addView(browser);
    browser->registerViewListener(this);
    component.bind(browser);
    component.setFocusable(true);
    return true;
}

void PresetBrowserControl::clear() {
    if (browser) browser->unregisterViewListener(this);
    component.accessibility().clearActionHandler();
    component.clear();
    browser = nullptr;
}

void PresetBrowserControl::setBounds(const VSTGUI::CRect& bounds) {
    component.setBounds(bounds);
}

bool PresetBrowserControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    return browser && browser->handleKey(key, key_code, modifiers);
}

VSTGUI::CView* PresetBrowserControl::focusView() const {
    return browser;
}

void PresetBrowserControl::setFocusedView(VSTGUI::CView* view) {
    const bool focused = browser && browser == view;
    component.setFocused(focused);
    component.accessibility().setFocused(focused);
}

const AccessibilityNode& PresetBrowserControl::accessibilityNode() const {
    return component.accessibility();
}

PresetBrowserView* PresetBrowserControl::browserView() {
    return browser;
}

const PresetBrowserView* PresetBrowserControl::browserView() const {
    return browser;
}

void PresetBrowserControl::viewLostFocus(VSTGUI::CView* view) {
    if (view == browser) setFocusedView(nullptr);
}

void PresetBrowserControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == browser) setFocusedView(view);
}

}
