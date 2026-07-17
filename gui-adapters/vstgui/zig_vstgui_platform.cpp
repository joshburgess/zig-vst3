#include "zig_vstgui_platform.h"

#include <new>

#if defined(LINUX)
#define INIT_CLASS_IID
#include "pluginterfaces/base/funknownimpl.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/gui/iwaylandframe.h"
#undef INIT_CLASS_IID
#include "vstgui/lib/platform/platform_x11.h"
#if VSTGUI_ENABLE_WAYLAND_SUPPORT
#include "vstgui/lib/platform/platform_wayland.h"
#endif
#include <vector>
#endif

namespace ZigVstgui {

#if defined(LINUX)
namespace {

class HostRunLoop final : public VSTGUI::IRunLoop, public VSTGUI::AtomicReferenceCounted {
public:
    struct EventHandler final : Steinberg::U::Implements<Steinberg::U::Directly<Steinberg::Linux::IEventHandler>> {
        explicit EventHandler(VSTGUI::IEventHandler* value) : handler(value) {}
        void PLUGIN_API onFDIsSet(Steinberg::Linux::FileDescriptor) override {
            if (handler) handler->onEvent();
        }
        VSTGUI::IEventHandler* handler;
    };

    struct TimerHandler final : Steinberg::U::Implements<Steinberg::U::Directly<Steinberg::Linux::ITimerHandler>> {
        explicit TimerHandler(VSTGUI::ITimerHandler* value) : handler(value) {}
        void PLUGIN_API onTimer() override {
            if (handler) handler->onTimer();
        }
        VSTGUI::ITimerHandler* handler;
    };

    explicit HostRunLoop(Steinberg::FUnknown* frame) {
        if (frame) frame->queryInterface(Steinberg::Linux::IRunLoop::iid, reinterpret_cast<void**>(&run_loop));
    }

    ~HostRunLoop() override {
        for (auto* entry : event_handlers) {
            if (run_loop) run_loop->unregisterEventHandler(entry);
            entry->release();
        }
        for (auto* entry : timer_handlers) {
            if (run_loop) run_loop->unregisterTimer(entry);
            entry->release();
        }
        if (run_loop) run_loop->release();
    }

    bool valid() const { return run_loop != nullptr; }

    bool registerEventHandler(int fd, VSTGUI::IEventHandler* handler) override {
        if (!run_loop || !handler) return false;
        auto* entry = new (std::nothrow) EventHandler(handler);
        if (!entry) return false;
        if (run_loop->registerEventHandler(entry, fd) != Steinberg::kResultOk) {
            entry->release();
            return false;
        }
        event_handlers.push_back(entry);
        return true;
    }

    bool unregisterEventHandler(VSTGUI::IEventHandler* handler) override {
        if (!run_loop) return false;
        for (auto it = event_handlers.begin(); it != event_handlers.end(); ++it) {
            if ((*it)->handler != handler) continue;
            const bool accepted = run_loop->unregisterEventHandler(*it) == Steinberg::kResultOk;
            (*it)->release();
            event_handlers.erase(it);
            return accepted;
        }
        return false;
    }

    bool registerTimer(uint64_t interval, VSTGUI::ITimerHandler* handler) override {
        if (!run_loop || !handler) return false;
        auto* entry = new (std::nothrow) TimerHandler(handler);
        if (!entry) return false;
        if (run_loop->registerTimer(entry, interval) != Steinberg::kResultOk) {
            entry->release();
            return false;
        }
        timer_handlers.push_back(entry);
        return true;
    }

    bool unregisterTimer(VSTGUI::ITimerHandler* handler) override {
        if (!run_loop) return false;
        for (auto it = timer_handlers.begin(); it != timer_handlers.end(); ++it) {
            if ((*it)->handler != handler) continue;
            const bool accepted = run_loop->unregisterTimer(*it) == Steinberg::kResultOk;
            (*it)->release();
            timer_handlers.erase(it);
            return accepted;
        }
        return false;
    }

private:
    Steinberg::Linux::IRunLoop* run_loop {nullptr};
    std::vector<EventHandler*> event_handlers;
    std::vector<TimerHandler*> timer_handlers;
};

#if VSTGUI_ENABLE_WAYLAND_SUPPORT
class WaylandHost final : public VSTGUI::Wayland::IWaylandHost, public VSTGUI::AtomicReferenceCounted {
public:
    explicit WaylandHost(Steinberg::FUnknown* value) {
        if (value) value->queryInterface(Steinberg::IWaylandHost::iid, reinterpret_cast<void**>(&host));
    }
    ~WaylandHost() override {
        if (host) host->release();
    }
    bool valid() const { return host != nullptr; }
    wl_display* openWaylandConnection() override {
        return host ? host->openWaylandConnection() : nullptr;
    }
    bool closeWaylandConnection(wl_display* display) override {
        return host && host->closeWaylandConnection(display) == Steinberg::kResultOk;
    }
private:
    Steinberg::IWaylandHost* host {nullptr};
};

class WaylandFrame final : public VSTGUI::Wayland::IWaylandFrame, public VSTGUI::AtomicReferenceCounted {
public:
    explicit WaylandFrame(Steinberg::FUnknown* value) {
        if (value) value->queryInterface(Steinberg::IWaylandFrame::iid, reinterpret_cast<void**>(&frame));
    }
    ~WaylandFrame() override {
        if (frame) frame->release();
    }
    bool valid() const { return frame != nullptr; }
    wl_surface* getWaylandSurface(wl_display* display) override {
        return frame ? frame->getWaylandSurface(display) : nullptr;
    }
    xdg_surface* getParentSurface(VSTGUI::CRect& parent_size, wl_display* display) override {
        if (!frame) return nullptr;
        Steinberg::ViewRect rect {};
        auto* surface = frame->getParentSurface(rect, display);
        parent_size = VSTGUI::CRect(rect.left, rect.top, rect.right, rect.bottom);
        return surface;
    }
    xdg_toplevel* getParentToplevel(wl_display* display) override {
        return frame ? frame->getParentToplevel(display) : nullptr;
    }
private:
    Steinberg::IWaylandFrame* frame {nullptr};
};
#endif

void replaceInterface(void*& current, void* replacement) {
    if (current == replacement) return;
    if (replacement) static_cast<Steinberg::FUnknown*>(replacement)->addRef();
    if (current) static_cast<Steinberg::FUnknown*>(current)->release();
    current = replacement;
}

}
#endif

bool openFrame(
    VSTGUI::CFrame* frame,
    void* parent,
    ZigVstguiPlatform platform,
    void* plug_frame,
    void* wayland_host
) {
    if (!frame || (!parent && platform != ZIG_VSTGUI_PLATFORM_WAYLAND)) return false;
    VSTGUI::PlatformType native_type;
    switch (platform) {
        case ZIG_VSTGUI_PLATFORM_MACOS: native_type = VSTGUI::PlatformType::kNSView; break;
        case ZIG_VSTGUI_PLATFORM_WINDOWS: native_type = VSTGUI::PlatformType::kHWND; break;
        case ZIG_VSTGUI_PLATFORM_X11: native_type = VSTGUI::PlatformType::kX11EmbedWindowID; break;
        case ZIG_VSTGUI_PLATFORM_WAYLAND: native_type = VSTGUI::PlatformType::kWaylandSurfaceID; break;
        default: return false;
    }
#if defined(LINUX)
    if (platform == ZIG_VSTGUI_PLATFORM_X11) {
        auto run_loop = VSTGUI::owned(new HostRunLoop(static_cast<Steinberg::FUnknown*>(plug_frame)));
        if (!run_loop->valid()) return false;
        VSTGUI::X11::FrameConfig config;
        config.runLoop = run_loop;
        return frame->open(parent, native_type, &config);
    }
#if VSTGUI_ENABLE_WAYLAND_SUPPORT
    if (platform == ZIG_VSTGUI_PLATFORM_WAYLAND) {
        auto run_loop = VSTGUI::owned(new HostRunLoop(static_cast<Steinberg::FUnknown*>(plug_frame)));
        auto host = VSTGUI::owned(new WaylandHost(static_cast<Steinberg::FUnknown*>(wayland_host)));
        auto host_frame = VSTGUI::owned(new WaylandFrame(static_cast<Steinberg::FUnknown*>(plug_frame)));
        if (!run_loop->valid() || !host->valid() || !host_frame->valid()) return false;
        VSTGUI::Wayland::FrameConfig config;
        config.runLoop = run_loop;
        config.waylandHost = host;
        config.waylandFrame = host_frame;
        return frame->open(&config, native_type, &config);
    }
#endif
#endif
    return frame->open(parent, native_type);
}

void replacePlugFrame(void*& current, void* replacement) {
#if defined(LINUX)
    replaceInterface(current, replacement);
#else
    (void)current;
    (void)replacement;
#endif
}

void replaceWaylandHost(void*& current, void* replacement) {
#if defined(LINUX) && VSTGUI_ENABLE_WAYLAND_SUPPORT
    replaceInterface(current, replacement);
#else
    (void)current;
    (void)replacement;
#endif
}

void releasePlatformInterfaces(void*& plug_frame, void*& wayland_host) {
#if defined(LINUX)
    if (plug_frame) static_cast<Steinberg::FUnknown*>(plug_frame)->release();
    if (wayland_host) static_cast<Steinberg::FUnknown*>(wayland_host)->release();
#endif
    plug_frame = nullptr;
    wayland_host = nullptr;
}

}
