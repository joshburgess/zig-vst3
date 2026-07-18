#include "zig_vstgui_file_drop.h"

#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/idatapackage.h"

#include <algorithm>
#include <cctype>
#include <cstdio>

namespace ZigVstgui {

namespace {

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
    AccessibilityNode* value_accessibility
)
: CView(size), description(value_description), callbacks(value_callbacks), styles(value_styles),
  accessibility(value_accessibility), title(value_description.title), prompt(value_description.prompt) {
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
    context->setFrameColor(rejected ? VSTGUI::CColor(220, 55, 45, 255) :
        current_status == FileDropStatus::acceptable || current_status == FileDropStatus::accepted
            ? active.accent : normal.border);
    context->setLineWidth(rejected || current_status != FileDropStatus::idle ? 2.0 : normal.frame_width);
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);
    context->setFont(styles.font(TypographyRole::body));
    context->setFontColor(description.enabled == 0 ? disabled.foreground : normal.foreground);
    VSTGUI::CRect title_bounds = bounds;
    title_bounds.bottom = title_bounds.top + bounds.getHeight() * 0.46;
    context->drawString(title.c_str(), title_bounds, VSTGUI::kCenterText);
    context->setFont(styles.font(TypographyRole::value));
    VSTGUI::CRect status_bounds = bounds;
    status_bounds.top = title_bounds.bottom;
    context->drawString(statusText(), status_bounds, VSTGUI::kCenterText);
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
        case FileDropStatus::idle: return prompt.c_str();
        case FileDropStatus::acceptable: return "Release to import";
        case FileDropStatus::rejected_type: return "Unsupported file type";
        case FileDropStatus::rejected_count: return "Too many files";
        case FileDropStatus::rejected_path: return "Invalid file path";
        case FileDropStatus::handler_failed: return "Import failed. Drop again to retry";
        case FileDropStatus::accepted: return "Import complete";
    }
    return prompt.c_str();
}

FileDropControl::FileDropControl(ZigVstguiFileDropDescription value_description, ZigVstguiCallbacks value_callbacks)
: description(value_description), callbacks(value_callbacks) {}

void FileDropControl::build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles) {
    if (!parent || view) return;
    auto& accessibility = component.accessibility();
    accessibility.setRole(AccessibilityRole::group);
    accessibility.setName(description.title);
    accessibility.setDescription("File drop target. Drag supported files from the system file browser.");
    accessibility.setReadOnly(true);
    accessibility.setEnabled(description.enabled != 0);
    view = new FileDropView(VSTGUI::CRect(), description, callbacks, styles, &accessibility);
    parent->addView(view);
    component.bind(view);
    component.setEnabled(description.enabled != 0);
}

void FileDropControl::clear() {
    component.clear();
    view = nullptr;
}

void FileDropControl::setBounds(const VSTGUI::CRect& bounds) { component.setBounds(bounds); }
const AccessibilityNode& FileDropControl::accessibilityNode() const { return component.accessibility(); }
FileDropView* FileDropControl::dropView() const { return view; }

}
