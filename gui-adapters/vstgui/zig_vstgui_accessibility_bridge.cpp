#include "zig_vstgui_accessibility_bridge.h"

#if !defined(__APPLE__) && !defined(_WIN32)

namespace ZigVstgui {

class NativeAccessibilityBridge::Impl {};

NativeAccessibilityBridge::NativeAccessibilityBridge() = default;
NativeAccessibilityBridge::~NativeAccessibilityBridge() = default;

bool NativeAccessibilityBridge::open(VSTGUI::CFrame*, const std::vector<AccessibilityEntry>&) {
    return false;
}

void NativeAccessibilityBridge::close() {}
void NativeAccessibilityBridge::layoutChanged() {}
bool NativeAccessibilityBridge::active() const { return false; }
std::size_t NativeAccessibilityBridge::elementCount() const { return 0; }

}

#endif
