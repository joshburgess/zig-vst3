#include "zig_vstgui_accessibility_clipboard.h"

#if defined(__linux__)

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>

namespace {

bool require(bool condition, const char* message) {
    if (condition) return true;
    std::fprintf(stderr, "Linux clipboard test failed: %s\n", message);
    return false;
}

class Dispatcher {
public:
    explicit Dispatcher(
        const std::shared_ptr<ZigVstgui::AccessibilityClipboard>& value
    ) : clipboard(value), worker([this] {
        while (running.load(std::memory_order_acquire)) {
            clipboard->dispatch();
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        clipboard->dispatch();
    }) {}

    ~Dispatcher() {
        running.store(false, std::memory_order_release);
        worker.join();
    }

private:
    std::shared_ptr<ZigVstgui::AccessibilityClipboard> clipboard;
    std::atomic<bool> running {true};
    std::thread worker;
};

}

int main() {
    if (!std::getenv("DISPLAY")) {
        std::puts("Linux clipboard test skipped: DISPLAY is unavailable");
        return 0;
    }

    auto first = ZigVstgui::createLinuxAccessibilityClipboard();
    auto second = ZigVstgui::createLinuxAccessibilityClipboard();
    if (!require(first && second, "providers were not constructed")) return 1;

    const std::string initial = u8"accessibility Δ clipboard";
    if (!require(first->writeText(initial), "first provider did not own the selection"))
        return 1;
    {
        Dispatcher dispatch(first);
        std::string received;
        if (!require(
                second->readText(received, 1024) && received == initial,
                "UTF-8 selection exchange failed"
            ))
            return 1;

        received = "preserved";
        if (!require(
                !second->readText(received, 4) && received == "preserved",
                "bounded read changed its destination"
            ))
            return 1;
    }

    const std::string maximum_payload(1024 * 1024, 'x');
    if (!require(
            first->writeText(maximum_payload),
            "maximum-size selection was rejected"
        ))
        return 1;
    {
        Dispatcher dispatch(first);
        std::string received;
        if (!require(
                second->readText(received, maximum_payload.size()) &&
                    received == maximum_payload,
                "maximum-size selection exchange failed"
            ))
            return 1;
    }

    const std::string replacement = "second owner";
    if (!require(second->writeText(replacement), "selection takeover failed"))
        return 1;
    {
        Dispatcher dispatch(second);
        std::string received;
        if (!require(
                first->readText(received, 1024) && received == replacement,
                "selection takeover was not externally readable"
            ))
            return 1;
    }

    const std::string embedded_nul("invalid\0text", 12);
    if (!require(
            !first->writeText(embedded_nul),
            "embedded NUL text was accepted"
        ))
        return 1;
    const std::string invalid_utf8("\xC3\x28", 2);
    if (!require(
            !first->writeText(invalid_utf8),
            "invalid UTF-8 text was accepted"
        ))
        return 1;
    if (!require(
            !first->writeText(std::string(1024 * 1024 + 1, 'x')),
            "oversized text was accepted"
        ))
        return 1;

    std::puts("Linux X11 accessibility clipboard exchange passed");
    return 0;
}

#endif
