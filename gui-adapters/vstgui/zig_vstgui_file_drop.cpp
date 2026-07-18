#include "zig_vstgui_file_drop.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cfileselector.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/events.h"
#include "vstgui/lib/idatapackage.h"

#include <algorithm>
#include <cctype>
#include <cstdio>

namespace ZigVstgui {

namespace {

constexpr uint32_t actionMask(AccessibilityAction action) {
    return static_cast<uint32_t>(action);
}

const char* pickerLabel(const ZigVstguiFileDropDescription& description) {
    return description.picker_label && description.picker_label[0] != 0
        ? description.picker_label : "Choose Audio File";
}

const char* pickerTitle(const ZigVstguiFileDropDescription& description) {
    return description.picker_title && description.picker_title[0] != 0
        ? description.picker_title : "Choose Audio File";
}

std::string lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

}

FileDropView::FileDropView(
    const VSTGUI::CRect& size,
    ZigVstguiFileDropDescription value_description,
    ZigVstguiCallbacks value_callbacks,
    const ThemeResolver& value_styles,
    AccessibilityNode* value_accessibility,
    FileDropControl* value_owner
)
: CView(size), description(value_description), callbacks(value_callbacks), styles(value_styles),
  accessibility(value_accessibility), owner(value_owner), title(value_description.title),
  prompt(value_description.prompt), picker_label(pickerLabel(value_description)) {
    for (uint32_t index = 0; index < description.extension_count; ++index) {
        extensions[index] = lower(description.extensions[index]);
    }
    syncAccessibility();
}

void FileDropView::draw(VSTGUI::CDrawContext* context) {
    const auto bounds = getViewSize();
    const auto normal = styles.resolve(ComponentKind::xy_pad);
    const auto active = styles.resolve(ComponentKind::xy_pad, VisualState::hovered);
    const auto disabled = styles.resolve(ComponentKind::xy_pad, VisualState::disabled);
    const bool rejected = current_status == FileDropStatus::rejected_type ||
        current_status == FileDropStatus::rejected_count ||
        current_status == FileDropStatus::rejected_path ||
        current_status == FileDropStatus::handler_failed;
    context->setFillColor(description.enabled == 0 ? disabled.background :
        current_status == FileDropStatus::acceptable ? active.background : normal.background);
    const bool focused = getFrame() && getFrame()->getFocusView() == this;
    context->setFrameColor(rejected ? VSTGUI::CColor(220, 55, 45, 255) :
        current_status == FileDropStatus::acceptable || current_status == FileDropStatus::accepted
            ? active.accent : focused ? normal.accent : normal.border);
    context->setLineWidth(rejected || current_status != FileDropStatus::idle || focused ? 2.0 : normal.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);
    context->setFont(styles.font(TypographyRole::body));
    context->setFontColor(description.enabled == 0 ? disabled.foreground : normal.foreground);
    VSTGUI::CRect title_bounds = bounds;
    title_bounds.bottom = title_bounds.top + bounds.getHeight() * 0.38;
    context->drawString(title.c_str(), title_bounds, VSTGUI::kCenterText);
    context->setFont(styles.font(TypographyRole::value));
    VSTGUI::CRect status_bounds = bounds;
    status_bounds.top = title_bounds.bottom;
    if (current_status == FileDropStatus::idle) status_bounds.bottom = bounds.top + bounds.getHeight() * 0.74;
    context->drawString(statusText(), status_bounds, VSTGUI::kCenterText);
    if (current_status == FileDropStatus::idle) {
        context->setFont(styles.font(TypographyRole::body));
        context->setFontColor(description.enabled == 0 ? disabled.foreground : styles.theme().colors.text_secondary);
        VSTGUI::CRect prompt_bounds = bounds;
        prompt_bounds.top = status_bounds.bottom;
        context->drawString(prompt.c_str(), prompt_bounds, VSTGUI::kCenterText);
    }
    setDirty(false);
}

VSTGUI::DragOperation FileDropView::onDragEnter(VSTGUI::DragEventData event_data) {
    if (description.enabled == 0 || !inspectPackage(event_data.drag)) return VSTGUI::DragOperation::None;
    return VSTGUI::DragOperation::Copy;
}

VSTGUI::DragOperation FileDropView::onDragMove(VSTGUI::DragEventData) {
    return current_status == FileDropStatus::acceptable ? VSTGUI::DragOperation::Copy : VSTGUI::DragOperation::None;
}

void FileDropView::onDragLeave(VSTGUI::DragEventData) {
    setStatus(FileDropStatus::idle);
    path_count = 0;
}

bool FileDropView::onDrop(VSTGUI::DragEventData event_data) {
    if (description.enabled == 0 || !inspectPackage(event_data.drag)) return false;
    return dispatchInspected();
}

void FileDropView::onMouseDownEvent(VSTGUI::MouseDownEvent& event) {
    if (description.enabled == 0 || !event.buttonState.isLeft() || !owner) return;
    if (getFrame()) getFrame()->setFocusView(this);
    event.consumed = owner->activatePicker();
}

void FileDropView::onKeyboardEvent(VSTGUI::KeyboardEvent& event) {
    if (event.type != VSTGUI::EventType::KeyDown || !owner) return;
    int16_t key_code = 0;
    if (event.virt == VSTGUI::VirtualKey::Return) key_code = Steinberg::KEY_RETURN;
    else if (event.virt == VSTGUI::VirtualKey::Space) key_code = Steinberg::KEY_SPACE;
    if (owner->handleKey(event.character, key_code, 0)) event.consumed = true;
}

FileDropStatus FileDropView::inspectPaths(const char* const* values, uint32_t count) {
    path_count = 0;
    if (!values || count == 0 || count > description.maximum_files) {
        setStatus(FileDropStatus::rejected_count);
        return current_status;
    }
    for (uint32_t index = 0; index < count; ++index) {
        if (!values[index]) {
            setStatus(FileDropStatus::rejected_path);
            return current_status;
        }
        const std::size_t length = std::char_traits<char>::length(values[index]);
        if (length == 0 || length > ZIG_VSTGUI_MAX_DROP_PATH_BYTES) {
            setStatus(FileDropStatus::rejected_path);
            return current_status;
        }
        paths[index].assign(values[index], length);
        if (!accepts(paths[index])) {
            setStatus(FileDropStatus::rejected_type);
            return current_status;
        }
        path_count += 1;
    }
    setStatus(FileDropStatus::acceptable);
    return current_status;
}

bool FileDropView::dispatchInspected() {
    if (current_status != FileDropStatus::acceptable || path_count == 0 || !callbacks.drop_files) return false;
    std::array<const char*, ZIG_VSTGUI_MAX_DROP_FILES> pointers {};
    for (uint32_t index = 0; index < path_count; ++index) pointers[index] = paths[index].c_str();
    const bool accepted = callbacks.drop_files(callbacks.userdata, description.drop_id, pointers.data(), path_count) == 0;
    setStatus(accepted ? FileDropStatus::accepted : FileDropStatus::handler_failed);
    return accepted;
}

void FileDropView::cancelSelection() {
    path_count = 0;
    setStatus(FileDropStatus::idle);
}

FileDropStatus FileDropView::status() const { return current_status; }
uint32_t FileDropView::inspectedCount() const { return path_count; }
const std::string& FileDropView::inspectedPath(uint32_t index) const { return paths[index]; }

bool FileDropView::inspectPackage(VSTGUI::IDataPackage* package) {
    if (!package) {
        setStatus(FileDropStatus::rejected_count);
        return false;
    }
    const uint32_t count = package->getCount();
    if (count == 0 || count > description.maximum_files) {
        setStatus(FileDropStatus::rejected_count);
        return false;
    }
    std::array<const char*, ZIG_VSTGUI_MAX_DROP_FILES> pointers {};
    std::array<std::string, ZIG_VSTGUI_MAX_DROP_FILES> copied;
    for (uint32_t index = 0; index < count; ++index) {
        if (package->getDataType(index) != VSTGUI::IDataPackage::kFilePath) {
            setStatus(FileDropStatus::rejected_type);
            return false;
        }
        const void* data = nullptr;
        VSTGUI::IDataPackage::Type type;
        const uint32_t size = package->getData(index, data, type);
        if (!data || size == 0 || size > ZIG_VSTGUI_MAX_DROP_PATH_BYTES || type != VSTGUI::IDataPackage::kFilePath) {
            setStatus(FileDropStatus::rejected_path);
            return false;
        }
        const auto* bytes = static_cast<const char*>(data);
        const uint32_t length = bytes[size - 1] == 0 ? size - 1 : size;
        if (length == 0 || std::find(bytes, bytes + length, '\0') != bytes + length) {
            setStatus(FileDropStatus::rejected_path);
            return false;
        }
        copied[index].assign(bytes, length);
        pointers[index] = copied[index].c_str();
    }
    return inspectPaths(pointers.data(), count) == FileDropStatus::acceptable;
}

bool FileDropView::accepts(const std::string& path) const {
    const std::string normalized = lower(path);
    for (uint32_t index = 0; index < description.extension_count; ++index) {
        const auto& extension = extensions[index];
        if (normalized.size() >= extension.size() &&
            normalized.compare(normalized.size() - extension.size(), extension.size(), extension) == 0) return true;
    }
    return false;
}

void FileDropView::setStatus(FileDropStatus next) {
    current_status = next;
    syncAccessibility();
    invalid();
}

void FileDropView::syncAccessibility() {
    if (!accessibility) return;
    accessibility->setValueText(statusText());
}

const char* FileDropView::statusText() const {
    if (description.enabled == 0) return "File import disabled";
    switch (current_status) {
        case FileDropStatus::idle: return picker_label.c_str();
        case FileDropStatus::acceptable: return "Release to import";
        case FileDropStatus::rejected_type: return "Unsupported file type";
        case FileDropStatus::rejected_count: return "Too many files";
        case FileDropStatus::rejected_path: return "Invalid file path";
        case FileDropStatus::handler_failed: return "Import failed. Drop again to retry";
        case FileDropStatus::accepted: return "Import complete";
    }
    return prompt.c_str();
}

struct FileDropControl::PickerLifetime {
    FileDropControl* owner {nullptr};
};

FileDropControl::FileDropControl(ZigVstguiFileDropDescription value_description, ZigVstguiCallbacks value_callbacks)
: description(value_description), callbacks(value_callbacks) {}

void FileDropControl::build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles) {
    if (!parent || view) return;
    auto& accessibility = component.accessibility();
    accessibility.setRole(AccessibilityRole::button);
    accessibility.setName(pickerLabel(description));
    accessibility.setDescription("Opens the system file picker. You can also drag supported files onto this control.");
    accessibility.setReadOnly(false);
    accessibility.setEnabled(description.enabled != 0);
    accessibility.setActionHandler(
        this,
        accessibilityAction,
        actionMask(AccessibilityAction::focus) | actionMask(AccessibilityAction::press)
    );
    view = new FileDropView(VSTGUI::CRect(), description, callbacks, styles, &accessibility, this);
    parent->addView(view);
    view->registerViewListener(this);
    component.bind(view);
    component.setEnabled(description.enabled != 0);
    component.setFocusable(true);
}

void FileDropControl::clear() {
    if (picker_lifetime) picker_lifetime->owner = nullptr;
    if (picker) picker->cancel();
    picker = nullptr;
    if (view) view->unregisterViewListener(this);
    component.accessibility().clearActionHandler();
    component.clear();
    view = nullptr;
}

void FileDropControl::setBounds(const VSTGUI::CRect& bounds) { component.setBounds(bounds); }
const AccessibilityNode& FileDropControl::accessibilityNode() const { return component.accessibility(); }
FileDropView* FileDropControl::dropView() const { return view; }
VSTGUI::CView* FileDropControl::focusView() const { return view; }

bool FileDropControl::handleKey(uint16_t, int16_t key_code, int16_t) {
    if (key_code != Steinberg::KEY_RETURN && key_code != Steinberg::KEY_ENTER && key_code != Steinberg::KEY_SPACE) {
        return false;
    }
    return activatePicker();
}

bool FileDropControl::activatePicker() {
    if (!view || description.enabled == 0 || picker) return false;
    return picker_launcher
        ? picker_launcher(picker_launcher_userdata, *this)
        : openNativePicker();
}

bool FileDropControl::dispatchPickerPaths(const char* const* paths, uint32_t count) {
    if (!view || view->inspectPaths(paths, count) != FileDropStatus::acceptable) return false;
    return view->dispatchInspected();
}

void FileDropControl::setPickerLauncher(void* userdata, PickerLauncher launcher) {
    picker_launcher_userdata = userdata;
    picker_launcher = launcher;
}

void FileDropControl::viewLostFocus(VSTGUI::CView* focused_view) {
    if (focused_view == view) component.setFocused(false);
}

void FileDropControl::viewTookFocus(VSTGUI::CView* focused_view) {
    if (focused_view == view) component.setFocused(true);
}

bool FileDropControl::accessibilityAction(
    void* userdata,
    const AccessibilityNode&,
    const AccessibilityActionRequest& request
) {
    auto* self = static_cast<FileDropControl*>(userdata);
    return self && self->performAccessibilityAction(request);
}

bool FileDropControl::performAccessibilityAction(const AccessibilityActionRequest& request) {
    if (!view || description.enabled == 0) return false;
    if (request.action == AccessibilityAction::focus) {
        if (!view->getFrame()) return false;
        view->getFrame()->setFocusView(view);
        return true;
    }
    return request.action == AccessibilityAction::press && activatePicker();
}

bool FileDropControl::openNativePicker() {
    if (!view || !view->getFrame()) return false;
    auto* next = VSTGUI::CNewFileSelector::create(view->getFrame(), VSTGUI::CNewFileSelector::kSelectFile);
    if (!next) return false;
    next->setTitle(pickerTitle(description));
    next->setAllowMultiFileSelection(description.maximum_files > 1);
    for (uint32_t index = 0; index < description.extension_count; ++index) {
        const char* extension = description.extensions[index];
        next->addFileExtension(VSTGUI::CFileExtension(extension + 1, extension + 1));
    }
    picker = next;
    picker_lifetime = std::make_shared<PickerLifetime>();
    picker_lifetime->owner = this;
    const auto lifetime = picker_lifetime;
    const bool started = next->run([lifetime](VSTGUI::CNewFileSelector* completed) {
        if (lifetime && lifetime->owner) lifetime->owner->pickerFinished(completed);
    });
    next->forget();
    if (!started) {
        picker = nullptr;
        next->forget();
    }
    return started;
}

void FileDropControl::pickerFinished(VSTGUI::CNewFileSelector* completed) {
    if (!view || completed != picker) return;
    picker = nullptr;
    const uint32_t count = completed->getNumSelectedFiles();
    if (count == 0) view->cancelSelection();
    else {
        std::array<const char*, ZIG_VSTGUI_MAX_DROP_FILES> paths {};
        for (uint32_t index = 0; index < std::min(count, static_cast<uint32_t>(paths.size())); ++index) {
            paths[index] = completed->getSelectedFile(index);
        }
        dispatchPickerPaths(paths.data(), count);
    }
    if (view->getFrame()) view->getFrame()->setFocusView(view);
}

}
