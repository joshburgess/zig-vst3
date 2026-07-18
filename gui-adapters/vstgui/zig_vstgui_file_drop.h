#ifndef ZIG_VSTGUI_FILE_DROP_H
#define ZIG_VSTGUI_FILE_DROP_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cview.h"
#include "vstgui/lib/dragging.h"

#include <array>
#include <string>

namespace ZigVstgui {

enum class FileDropStatus {
    idle,
    acceptable,
    rejected_type,
    rejected_count,
    rejected_path,
    handler_failed,
    accepted,
};

class FileDropView final : public VSTGUI::CView, public VSTGUI::IDropTarget {
public:
    FileDropView(
        const VSTGUI::CRect& size,
        ZigVstguiFileDropDescription description,
        ZigVstguiCallbacks callbacks,
        const ThemeResolver& styles,
        AccessibilityNode* accessibility
    );

    void draw(VSTGUI::CDrawContext* context) override;
    VSTGUI::SharedPointer<VSTGUI::IDropTarget> getDropTarget() override { return this; }
    VSTGUI::DragOperation onDragEnter(VSTGUI::DragEventData event_data) override;
    VSTGUI::DragOperation onDragMove(VSTGUI::DragEventData event_data) override;
    void onDragLeave(VSTGUI::DragEventData event_data) override;
    bool onDrop(VSTGUI::DragEventData event_data) override;

    FileDropStatus inspectPaths(const char* const* paths, uint32_t count);
    bool dispatchInspected();
    FileDropStatus status() const;
    uint32_t inspectedCount() const;
    const std::string& inspectedPath(uint32_t index) const;
    CLASS_METHODS_NOCOPY(FileDropView, VSTGUI::CView)

private:
    bool inspectPackage(VSTGUI::IDataPackage* package);
    bool accepts(const std::string& path) const;
    void setStatus(FileDropStatus next);
    void syncAccessibility();
    const char* statusText() const;

    ZigVstguiFileDropDescription description {};
    ZigVstguiCallbacks callbacks {};
    const ThemeResolver& styles;
    AccessibilityNode* accessibility;
    std::string title;
    std::string prompt;
    std::array<std::string, ZIG_VSTGUI_MAX_DROP_EXTENSIONS> extensions;
    std::array<std::string, ZIG_VSTGUI_MAX_DROP_FILES> paths;
    uint32_t path_count {0};
    FileDropStatus current_status {FileDropStatus::idle};
};

class FileDropControl {
public:
    FileDropControl(ZigVstguiFileDropDescription description, ZigVstguiCallbacks callbacks);
    void build(VSTGUI::CViewContainer* parent, const ThemeResolver& styles);
    void clear();
    void setBounds(const VSTGUI::CRect& bounds);
    const AccessibilityNode& accessibilityNode() const;
    FileDropView* dropView() const;

private:
    ZigVstguiFileDropDescription description {};
    ZigVstguiCallbacks callbacks {};
    FileDropView* view {nullptr};
    Component component;
};

}

#endif
