#ifndef ZIG_VSTGUI_ACCESSIBILITY_CLIPBOARD_H
#define ZIG_VSTGUI_ACCESSIBILITY_CLIPBOARD_H

#include <cstddef>
#include <memory>
#include <string>

namespace ZigVstgui {

class AccessibilityClipboard {
public:
    virtual ~AccessibilityClipboard() = default;
    virtual bool writeText(const std::string& text) = 0;
    virtual bool readText(std::string& text, std::size_t maximum_bytes) = 0;
    virtual void dispatch() {}
};

#if defined(__linux__) || defined(ZIG_VSTGUI_WAYLAND_CLIPBOARD_TEST_PLATFORM)
std::shared_ptr<AccessibilityClipboard> createLinuxAccessibilityClipboard();
#endif

}

#endif
