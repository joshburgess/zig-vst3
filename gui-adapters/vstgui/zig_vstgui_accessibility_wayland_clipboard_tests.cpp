#include "zig_vstgui_accessibility_clipboard.h"

#if defined(__linux__) || defined(ZIG_VSTGUI_WAYLAND_CLIPBOARD_TEST_PLATFORM)

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

extern "C" {
const uint8_t* zv3_wayland_fake_captured(std::size_t* length);
void zv3_wayland_fake_cancel_source(void);
}

namespace {

bool require(bool condition, const char* message) {
    if (condition) return true;
    std::fprintf(stderr, "Wayland clipboard test failed: %s\n", message);
    return false;
}

}

int main() {
    if (setenv("WAYLAND_DISPLAY", "test-wayland-0", 1) != 0 ||
        unsetenv("DISPLAY") != 0) {
        std::fputs("Wayland clipboard test could not set its environment\n", stderr);
        return 1;
    }
    auto clipboard = ZigVstgui::createLinuxAccessibilityClipboard();
    if (!require(clipboard != nullptr, "provider was not constructed")) return 1;

    std::string received;
    if (!require(
            clipboard->readText(received, 1024) &&
                received == u8"outside Δ selection",
            "external UTF-8 selection was not read"
        ))
        return 1;

    received = "preserved";
    if (!require(
            !clipboard->readText(received, 4) && received == "preserved",
            "bounded read changed its destination"
        ))
        return 1;

    const std::string owned = u8"owned Ω selection";
    if (!require(clipboard->writeText(owned), "selection was not acquired"))
        return 1;
    std::size_t captured_length = 0;
    const auto* captured = zv3_wayland_fake_captured(&captured_length);
    if (!require(
            std::string(
                reinterpret_cast<const char*>(captured),
                captured_length
            ) == owned,
            "selection source did not transfer its retained text"
        ))
        return 1;

    received.clear();
    if (!require(
            clipboard->readText(received, 1024) && received == owned,
            "owned selection was not readable"
        ))
        return 1;

    const std::string embedded_nul("invalid\0text", 12);
    if (!require(
            !clipboard->writeText(embedded_nul),
            "embedded NUL text was accepted"
        ))
        return 1;
    const std::string invalid_utf8("\xC3\x28", 2);
    if (!require(
            !clipboard->writeText(invalid_utf8),
            "invalid UTF-8 text was accepted"
        ))
        return 1;
    if (!require(
            !clipboard->writeText(std::string(1024 * 1024 + 1, 'x')),
            "oversized text was accepted"
        ))
        return 1;

    if (!require(clipboard->writeText(""), "empty selection was rejected"))
        return 1;
    received = "not empty";
    if (!require(
            clipboard->readText(received, 0) && received.empty(),
            "empty selection did not round trip"
        ))
        return 1;

    zv3_wayland_fake_cancel_source();
    clipboard->dispatch();
    received = "preserved";
    if (!require(
            !clipboard->readText(received, 1024) && received == "preserved",
            "cancelled ownership remained readable"
        ))
        return 1;

    clipboard.reset();
    if (setenv("ZV3_WAYLAND_FAKE_NO_MANAGER", "1", 1) != 0) {
        std::fputs("Wayland clipboard test could not disable data control\n", stderr);
        return 1;
    }
    auto unavailable = ZigVstgui::createLinuxAccessibilityClipboard();
    received = "preserved";
    if (!require(
            unavailable != nullptr &&
                !unavailable->writeText("rejected") &&
                !unavailable->readText(received, 1024) &&
                received == "preserved",
            "missing data control did not reach the unavailable fallback"
        ))
        return 1;

    unavailable.reset();
    if (unsetenv("ZV3_WAYLAND_FAKE_NO_MANAGER") != 0 ||
        setenv("ZV3_WAYLAND_FAKE_TEXT", "\xC3\x28", 1) != 0) {
        std::fputs("Wayland clipboard test could not select malformed text\n", stderr);
        return 1;
    }
    auto malformed = ZigVstgui::createLinuxAccessibilityClipboard();
    received = "preserved";
    if (!require(
            malformed != nullptr &&
                !malformed->readText(received, 1024) &&
                received == "preserved",
            "malformed external UTF-8 changed the destination"
        ))
        return 1;

    std::puts("Linux Wayland accessibility clipboard exchange passed");
    return 0;
}

#endif
