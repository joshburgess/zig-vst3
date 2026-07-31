#ifndef ZIG_VSTGUI_ACCESSIBILITY_BRIDGE_H
#define ZIG_VSTGUI_ACCESSIBILITY_BRIDGE_H

#include "zig_vstgui_accessibility.h"

#include "vstgui/lib/cframe.h"

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace ZigVstgui {

struct AccessibilityEntry {
    const AccessibilityNode* node {nullptr};
    const VSTGUI::CView* view {nullptr};
};

class AccessibilityClipboard {
public:
    virtual ~AccessibilityClipboard() = default;
    virtual bool writeText(const std::string& text) = 0;
    virtual bool readText(std::string& text, std::size_t maximum_bytes) = 0;
};

class NativeAccessibilityBridge {
public:
    NativeAccessibilityBridge();
    ~NativeAccessibilityBridge();
    NativeAccessibilityBridge(const NativeAccessibilityBridge&) = delete;
    NativeAccessibilityBridge& operator=(const NativeAccessibilityBridge&) = delete;

    bool open(
        VSTGUI::CFrame* frame,
        const std::vector<AccessibilityEntry>& entries,
        std::shared_ptr<AccessibilityClipboard> clipboard = {}
    );
    void close();
    void dispatch();
    void layoutChanged();
    bool active() const;
    std::size_t elementCount() const;

private:
    class Impl;
    std::unique_ptr<Impl> impl;
};

}

#endif
