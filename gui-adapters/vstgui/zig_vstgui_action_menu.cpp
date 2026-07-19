#include "zig_vstgui_action_menu.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/events.h"

#include <algorithm>
#include <new>

namespace ZigVstgui {

namespace {

constexpr double panel_width = 252.0;
constexpr double row_height = 28.0;
constexpr double separator_height = 10.0;
constexpr double panel_padding = 6.0;
constexpr double status_height = 24.0;

constexpr uint32_t actionMask(AccessibilityAction action) {
    return static_cast<uint32_t>(action);
}

}

ActionMenuView::ActionMenuView(
    const ZigVstguiActionMenuDescription& description,
    ZigVstguiCallbacks value_callbacks,
    const ThemeResolver& value_styles,
    AccessibilityNode* value_accessibility,
    ActionMenuControl* value_owner
)
: CView(VSTGUI::CRect()),
  title(description.title ? description.title : "Menu"),
  menu_id(description.menu_id),
  callbacks(value_callbacks),
  styles(value_styles),
  accessibility(value_accessibility),
  owner(value_owner) {
    if (menu_id == 0 || !description.title || description.title[0] == 0 || !description.items || description.item_count == 0 ||
        description.item_count > ZIG_VSTGUI_MAX_MENU_ITEMS) return;
    entry_count = description.item_count;
    for (uint32_t index = 0; index < entry_count; ++index) {
        const auto& item = description.items[index];
        auto& entry = entries[index];
        entry.id = item.item_id;
        entry.kind = item.kind;
        entry.enabled = item.enabled != 0;
        entry.destructive = item.destructive != 0;
        entry.checked_state_id = item.checked_state_id;
        entry.checked = item.initial_checked != 0;
        if (item.kind == ZIG_VSTGUI_MENU_SEPARATOR) {
            if (item.item_id != 0 || item.label || item.enabled || item.destructive ||
                item.checked_state_id != 0 || item.initial_checked) return;
            continue;
        }
        if (item.kind < ZIG_VSTGUI_MENU_ACTION || item.kind > ZIG_VSTGUI_MENU_TOGGLE ||
            item.item_id == 0 || !item.label || item.label[0] == 0) return;
        if ((item.kind == ZIG_VSTGUI_MENU_ACTION && item.checked_state_id != 0) ||
            (item.kind == ZIG_VSTGUI_MENU_TOGGLE && (item.checked_state_id == 0 || item.destructive))) return;
        entry.label = item.label;
        const std::string destructive_prefix = entry.destructive ? "! " : "";
        entry.display_unchecked = entry.kind == ZIG_VSTGUI_MENU_TOGGLE
            ? "[ ] " + destructive_prefix + entry.label
            : destructive_prefix + entry.label;
        entry.display_checked = entry.kind == ZIG_VSTGUI_MENU_TOGGLE
            ? "[x] " + destructive_prefix + entry.label
            : entry.display_unchecked;
        for (uint32_t previous = 0; previous < index; ++previous) {
            if (entries[previous].kind != ZIG_VSTGUI_MENU_SEPARATOR && entries[previous].id == entry.id) return;
        }
    }
    valid_description = true;
    setWantsFocus(true);
    setVisible(false);
    if (accessibility) {
        accessibility->setRole(AccessibilityRole::choice);
        accessibility->setName(title);
        accessibility->setDescription("Press to open. Use arrow keys to choose, Enter to run, and Escape to close");
    }
    syncAccessibility();
}

bool ActionMenuView::valid() const {
    return valid_description;
}

bool ActionMenuView::selectable(std::size_t index) const {
    return index < entry_count && entries[index].kind != ZIG_VSTGUI_MENU_SEPARATOR && entries[index].enabled;
}

void ActionMenuView::open() {
    if (open_state) return;
    open_state = true;
    status.clear();
    selected.reset();
    for (std::size_t index = 0; index < entry_count; ++index) {
        if (selectable(index)) {
            selected = index;
            break;
        }
    }
    setVisible(true);
    if (getFrame()) getFrame()->setFocusView(this);
    updateLayout();
    syncAccessibility();
    invalid();
}

void ActionMenuView::close(bool restore_focus) {
    if (!open_state) return;
    open_state = false;
    setVisible(false);
    syncAccessibility();
    if (owner) {
        owner->setFocusedView(restore_focus ? owner->focusView() : nullptr);
        if (restore_focus && owner->focusView() && getFrame()) getFrame()->setFocusView(owner->focusView());
    }
}

bool ActionMenuView::isOpen() const {
    return open_state;
}

bool ActionMenuView::selectRelative(bool next) {
    if (!open_state) return false;
    const std::size_t start = selected.value_or(next ? entry_count - 1 : 0);
    for (std::size_t offset = 1; offset <= entry_count; ++offset) {
        const std::size_t candidate = next
            ? (start + offset) % entry_count
            : (start + entry_count - offset % entry_count) % entry_count;
        if (!selectable(candidate)) continue;
        selected = candidate;
        status.clear();
        updateLayout();
        syncAccessibility();
        invalid();
        return true;
    }
    return false;
}

bool ActionMenuView::selectBoundary(bool last) {
    if (!open_state) return false;
    for (std::size_t offset = 0; offset < entry_count; ++offset) {
        const std::size_t candidate = last ? entry_count - 1 - offset : offset;
        if (!selectable(candidate)) continue;
        selected = candidate;
        status.clear();
        updateLayout();
        syncAccessibility();
        invalid();
        return true;
    }
    return false;
}

bool ActionMenuView::activateSelected() {
    if (!selected || !selectable(*selected)) return false;
    auto& entry = entries[*selected];
    const bool checked = entry.kind == ZIG_VSTGUI_MENU_TOGGLE ? !entry.checked : false;
    const bool accepted = callbacks.invoke_menu_action &&
        callbacks.invoke_menu_action(callbacks.userdata, menu_id, entry.id, checked ? 1 : 0) == 0;
    if (!accepted) {
        status = "Action failed. Press Enter to retry";
        updateLayout();
        syncAccessibility();
        invalid();
        return true;
    }
    if (entry.kind == ZIG_VSTGUI_MENU_TOGGLE) {
        entry.checked = checked;
        if (!callbacks.store_editor_bool ||
            callbacks.store_editor_bool(callbacks.userdata, entry.checked_state_id, checked ? 1 : 0) != 0) {
            entry.checked = !checked;
            status = "Could not save the change. Press Enter to retry";
            updateLayout();
            syncAccessibility();
            invalid();
            return true;
        }
    }
    close(true);
    return true;
}

bool ActionMenuView::handleKey(uint16_t, int16_t key_code, int16_t) {
    if (!open_state) return false;
    if (key_code == Steinberg::KEY_UP) return selectRelative(false);
    if (key_code == Steinberg::KEY_DOWN) return selectRelative(true);
    if (key_code == Steinberg::KEY_HOME) return selectBoundary(false);
    if (key_code == Steinberg::KEY_END) return selectBoundary(true);
    if (key_code == Steinberg::KEY_RETURN || key_code == Steinberg::KEY_ENTER || key_code == Steinberg::KEY_SPACE) {
        return activateSelected();
    }
    if (key_code == Steinberg::KEY_ESCAPE) {
        close(true);
        return true;
    }
    if (key_code == Steinberg::KEY_TAB) return true;
    return false;
}

void ActionMenuView::setLayout(const VSTGUI::CRect& value_editor_bounds, const VSTGUI::CRect& value_anchor_bounds) {
    editor_bounds = value_editor_bounds;
    anchor_bounds = value_anchor_bounds;
    updateLayout();
}

void ActionMenuView::updateLayout() {
    setViewSize(editor_bounds, true);
    setMouseableArea(editor_bounds);
    rows_height = 0.0;
    for (uint32_t index = 0; index < entry_count; ++index) {
        rows_height += entries[index].kind == ZIG_VSTGUI_MENU_SEPARATOR ? separator_height : row_height;
    }
    const double message_height = status.empty() ? 0.0 : status_height;
    const double maximum_height = std::max(1.0, editor_bounds.getHeight() - 16.0);
    const double height = std::min(panel_padding * 2.0 + rows_height + message_height, maximum_height);
    visible_rows_height = std::max(0.0, height - panel_padding * 2.0 - message_height);
    const double maximum_scroll = std::max(0.0, rows_height - visible_rows_height);
    content_scroll = std::clamp(content_scroll, 0.0, maximum_scroll);
    if (selected) {
        double selected_top = 0.0;
        for (std::size_t index = 0; index < *selected; ++index) {
            selected_top += entries[index].kind == ZIG_VSTGUI_MENU_SEPARATOR ? separator_height : row_height;
        }
        const double selected_bottom = selected_top +
            (entries[*selected].kind == ZIG_VSTGUI_MENU_SEPARATOR ? separator_height : row_height);
        if (selected_top < content_scroll) content_scroll = selected_top;
        else if (selected_bottom > content_scroll + visible_rows_height) {
            content_scroll = selected_bottom - visible_rows_height;
        }
        content_scroll = std::clamp(content_scroll, 0.0, maximum_scroll);
    }
    const double width = std::min(panel_width, std::max(1.0, editor_bounds.getWidth() - 16.0));
    const double left = std::clamp(anchor_bounds.left, editor_bounds.left + 8.0, editor_bounds.right - width - 8.0);
    double top = anchor_bounds.bottom + 4.0;
    if (top + height > editor_bounds.bottom - 8.0) top = anchor_bounds.top - height - 4.0;
    top = std::clamp(top, editor_bounds.top + 8.0, editor_bounds.bottom - height - 8.0);
    panel_bounds = VSTGUI::CRect(left, top, left + width, top + height);
    invalid();
}

uint32_t ActionMenuView::selectedItem() const {
    return selected ? entries[*selected].id : 0;
}

bool ActionMenuView::itemChecked(uint32_t item_id) const {
    for (uint32_t index = 0; index < entry_count; ++index) {
        if (entries[index].id == item_id) return entries[index].checked;
    }
    return false;
}

const std::string& ActionMenuView::statusText() const {
    return status;
}

std::optional<std::size_t> ActionMenuView::rowAt(double y) const {
    const double rows_top = panel_bounds.top + panel_padding;
    if (y < rows_top || y >= rows_top + visible_rows_height) return std::nullopt;
    const double content_y = y - rows_top + content_scroll;
    double top = 0.0;
    for (std::size_t index = 0; index < entry_count; ++index) {
        const double height = entries[index].kind == ZIG_VSTGUI_MENU_SEPARATOR ? separator_height : row_height;
        if (content_y >= top && content_y < top + height) return index;
        top += height;
    }
    return std::nullopt;
}

void ActionMenuView::syncAccessibility() {
    if (!accessibility) return;
    std::string value = open_state ? "Open" : "Collapsed";
    if (open_state && selected) {
        const auto& entry = entries[*selected];
        value += ". " + entry.label;
        if (entry.kind == ZIG_VSTGUI_MENU_TOGGLE) value += entry.checked ? ", checked" : ", not checked";
    }
    if (!status.empty()) value += ". " + status;
    accessibility->setValueText(value);
    accessibility->setSelected(open_state);
}

void ActionMenuView::draw(VSTGUI::CDrawContext* context) {
    if (!context || !open_state) return;
    const auto style = styles.resolve(ComponentKind::dropdown, VisualState::normal);
    const auto selected_style = styles.resolve(ComponentKind::dropdown, VisualState::focused);
    const VSTGUI::ConcatClip clip(*context, panel_bounds);
    if (clip.isEmpty()) return;
    context->setFillColor(style.background);
    context->setFrameColor(style.border);
    context->setLineWidth(style.frame_width);
    context->drawRect(panel_bounds, VSTGUI::kDrawFilledAndStroked);
    context->setFont(styles.font(TypographyRole::body));
    {
        const VSTGUI::ConcatClip rows_clip(*context, VSTGUI::CRect(
            panel_bounds.left,
            panel_bounds.top + panel_padding,
            panel_bounds.right,
            panel_bounds.top + panel_padding + visible_rows_height
        ));
        if (!rows_clip.isEmpty()) {
            double top = panel_bounds.top + panel_padding - content_scroll;
            for (std::size_t index = 0; index < entry_count; ++index) {
                const auto& entry = entries[index];
                if (entry.kind == ZIG_VSTGUI_MENU_SEPARATOR) {
                    context->setFrameColor(style.border);
                    context->drawLine(
                        VSTGUI::CPoint(panel_bounds.left + 8.0, top + separator_height * 0.5),
                        VSTGUI::CPoint(panel_bounds.right - 8.0, top + separator_height * 0.5)
                    );
                    top += separator_height;
                    continue;
                }
                const VSTGUI::CRect row(panel_bounds.left + 4.0, top, panel_bounds.right - 4.0, top + row_height);
                if (selected && *selected == index) {
                    context->setFillColor(selected_style.accent);
                    context->drawRect(row, VSTGUI::kDrawFilled);
                }
                const bool selected_entry = selected && *selected == index;
                context->setFontColor(
                    !entry.enabled
                        ? styles.theme().colors.text_secondary
                        : selected_entry ? styles.resolve(ComponentKind::editor).background : style.foreground
                );
                const auto& label = entry.checked ? entry.display_checked : entry.display_unchecked;
                context->drawString(
                    label.c_str(),
                    VSTGUI::CRect(row.left + 8.0, row.top, row.right - 8.0, row.bottom),
                    VSTGUI::kLeftText
                );
                top += row_height;
            }
        }
    }
    if (!status.empty()) {
        context->setFontColor(style.foreground);
        context->drawString(
            status.c_str(),
            VSTGUI::CRect(
                panel_bounds.left + 8.0,
                panel_bounds.bottom - panel_padding - status_height,
                panel_bounds.right - 8.0,
                panel_bounds.bottom - panel_padding
            ),
            VSTGUI::kLeftText
        );
    }
}

void ActionMenuView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (!open_state || !event.buttonState.isLeft()) return;
    if (!panel_bounds.pointInside(event.mousePosition)) {
        close(true);
        event.consumed = true;
        return;
    }
    const auto row = rowAt(event.mousePosition.y);
    if (!row) {
        event.consumed = true;
        return;
    }
    if (selectable(*row)) {
        selected = *row;
        status.clear();
        updateLayout();
        syncAccessibility();
        invalid();
        activateSelected();
    }
    event.consumed = true;
}

void ActionMenuView::onKeyboardEvent(VSTGUI::KeyboardEvent& event) {
    if (event.type != VSTGUI::EventType::KeyDown) return;
    int16_t key_code = 0;
    switch (event.virt) {
        case VSTGUI::VirtualKey::Up: key_code = Steinberg::KEY_UP; break;
        case VSTGUI::VirtualKey::Down: key_code = Steinberg::KEY_DOWN; break;
        case VSTGUI::VirtualKey::Home: key_code = Steinberg::KEY_HOME; break;
        case VSTGUI::VirtualKey::End: key_code = Steinberg::KEY_END; break;
        case VSTGUI::VirtualKey::Return: key_code = Steinberg::KEY_RETURN; break;
        case VSTGUI::VirtualKey::Escape: key_code = Steinberg::KEY_ESCAPE; break;
        case VSTGUI::VirtualKey::Space: key_code = Steinberg::KEY_SPACE; break;
        case VSTGUI::VirtualKey::Tab: key_code = Steinberg::KEY_TAB; break;
        default: break;
    }
    if (handleKey(event.character, key_code, 0)) event.consumed = true;
}

bool ActionMenuControl::build(
    VSTGUI::CViewContainer* parent,
    const ZigVstguiActionMenuDescription& description,
    ZigVstguiCallbacks callbacks,
    const ThemeResolver& styles
) {
    if (!parent || trigger || menu) return false;
    menu = new (std::nothrow) ActionMenuView(description, callbacks, styles, &component.accessibility(), this);
    if (!menu || !menu->valid()) {
        if (menu) menu->forget();
        menu = nullptr;
        return false;
    }
    const auto style = styles.resolve(ComponentKind::dropdown);
    const auto pressed = styles.resolve(ComponentKind::dropdown, VisualState::pressed);
    trigger = new (std::nothrow) VSTGUI::CTextButton(VSTGUI::CRect(), this, 0, description.title);
    if (!trigger) {
        menu->forget();
        menu = nullptr;
        return false;
    }
    trigger->setFont(styles.font(TypographyRole::body));
    trigger->setTextColor(style.foreground);
    trigger->setTextColorHighlighted(pressed.foreground);
    trigger->setFrameColor(style.border);
    trigger->setFrameColorHighlighted(pressed.border);
    trigger->setFrameWidth(style.frame_width);
    trigger->setRoundRadius(style.radius);
    parent->addView(trigger);
    parent->addView(menu);
    trigger->registerViewListener(this);
    component.bind(trigger);
    component.setFocusable(true);
    component.accessibility().setActionHandler(
        this,
        accessibilityAction,
        actionMask(AccessibilityAction::focus) |
            actionMask(AccessibilityAction::press) |
            actionMask(AccessibilityAction::increment) |
            actionMask(AccessibilityAction::decrement)
    );
    return true;
}

void ActionMenuControl::clear() {
    if (trigger) trigger->unregisterViewListener(this);
    component.accessibility().clearActionHandler();
    component.clear();
    trigger = nullptr;
    menu = nullptr;
}

void ActionMenuControl::setBounds(const VSTGUI::CRect& trigger_bounds, const VSTGUI::CRect& editor_bounds) {
    component.setBounds(trigger_bounds);
    if (menu) menu->setLayout(editor_bounds, trigger_bounds);
}

void ActionMenuControl::setOpenCoordinator(void* userdata, WillOpenCallback callback) {
    coordinator_userdata = userdata;
    will_open = callback;
}

void ActionMenuControl::open() {
    if (!menu || menu->isOpen()) return;
    if (will_open) will_open(coordinator_userdata, this);
    menu->open();
    setFocusedView(menu);
}

void ActionMenuControl::close(bool restore_focus) {
    if (menu) menu->close(restore_focus);
}

bool ActionMenuControl::handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
    if (menu && menu->isOpen()) return menu->handleKey(key, key_code, modifiers);
    if (key_code == Steinberg::KEY_RETURN || key_code == Steinberg::KEY_ENTER || key_code == Steinberg::KEY_SPACE ||
        key_code == Steinberg::KEY_DOWN) {
        open();
        return true;
    }
    return false;
}

VSTGUI::CView* ActionMenuControl::focusView() const {
    return menu && menu->isOpen() ? static_cast<VSTGUI::CView*>(menu) : static_cast<VSTGUI::CView*>(trigger);
}

void ActionMenuControl::setFocusedView(VSTGUI::CView* view) {
    const bool focused = view && (view == trigger || view == menu);
    component.setFocused(focused);
    component.accessibility().setFocused(focused);
}

const AccessibilityNode& ActionMenuControl::accessibilityNode() const {
    return component.accessibility();
}

ActionMenuView* ActionMenuControl::menuView() {
    return menu;
}

const ActionMenuView* ActionMenuControl::menuView() const {
    return menu;
}

void ActionMenuControl::valueChanged(VSTGUI::CControl*) {
    if (menu && menu->isOpen()) close(true);
    else open();
}

void ActionMenuControl::viewLostFocus(VSTGUI::CView* view) {
    if (view == trigger && (!menu || !menu->isOpen())) setFocusedView(nullptr);
}

void ActionMenuControl::viewTookFocus(VSTGUI::CView* view) {
    if (view == trigger) setFocusedView(view);
}

bool ActionMenuControl::accessibilityAction(
    void* userdata,
    const AccessibilityNode&,
    const AccessibilityActionRequest& request
) {
    auto* self = static_cast<ActionMenuControl*>(userdata);
    return self && self->performAccessibilityAction(request);
}

bool ActionMenuControl::performAccessibilityAction(const AccessibilityActionRequest& request) {
    switch (request.action) {
        case AccessibilityAction::focus:
            if (!trigger || !trigger->getFrame()) return false;
            trigger->getFrame()->setFocusView(focusView());
            return true;
        case AccessibilityAction::press:
            if (menu && menu->isOpen()) return menu->handleKey(0, Steinberg::KEY_RETURN, 0);
            open();
            return true;
        case AccessibilityAction::increment:
            if (!menu || !menu->isOpen()) open();
            return menu && menu->handleKey(0, Steinberg::KEY_DOWN, 0);
        case AccessibilityAction::decrement:
            if (!menu || !menu->isOpen()) open();
            return menu && menu->handleKey(0, Steinberg::KEY_UP, 0);
        default: return false;
    }
}

}
