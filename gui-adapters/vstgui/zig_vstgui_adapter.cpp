#include "zig_vstgui_adapter.h"

#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cgradient.h"
#include "vstgui/lib/controls/cbuttons.h"
#include "vstgui/lib/controls/cslider.h"
#include "vstgui/lib/controls/ctextedit.h"
#include "vstgui/lib/controls/ctextlabel.h"
#include "vstgui/lib/controls/icontrollistener.h"
#include "vstgui/lib/events.h"
#include "vstgui/lib/vstguiinit.h"

#include "pluginterfaces/base/keycodes.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cctype>
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

namespace {

using namespace VSTGUI;

constexpr int32_t kGainTag = 1;
constexpr int32_t kValueTag = 2;
constexpr int32_t kResizeTag = 3;

std::atomic<uint32_t> editor_count {0};

struct RenderMetrics {
    uint64_t draw_count {0};
    uint64_t draw_total_ns {0};
    uint64_t draw_max_ns {0};
    double invalidated_area {0.0};
    uint64_t open_count {0};
    uint64_t close_count {0};
    uint64_t resize_count {0};
    uint64_t scale_count {0};
    uint64_t parameter_update_count {0};
};

class ProfiledContainer final : public CViewContainer {
public:
    ProfiledContainer(const CRect& size, RenderMetrics* value_metrics)
    : CViewContainer(size), metrics(value_metrics) {}

    void drawRect(CDrawContext* context, const CRect& update_rect) override {
        if (!metrics) {
            CViewContainer::drawRect(context, update_rect);
            return;
        }
        const auto start = std::chrono::steady_clock::now();
        CViewContainer::drawRect(context, update_rect);
        const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now() - start
        ).count();
        const auto elapsed_ns = static_cast<uint64_t>(std::max<int64_t>(elapsed, 0));
        metrics->draw_count += 1;
        metrics->draw_total_ns += elapsed_ns;
        metrics->draw_max_ns = std::max(metrics->draw_max_ns, elapsed_ns);
        metrics->invalidated_area += std::max(0.0, update_rect.getWidth()) * std::max(0.0, update_rect.getHeight());
    }

private:
    RenderMetrics* metrics;
};

double clampNormalized(double value) {
    return std::clamp(value, 0.0, 1.0);
}

struct EditorListener final : IControlListener {
    uint32_t parameter_id;
    ZigVstguiCallbacks callbacks;
    CSlider* slider {nullptr};
    CTextEdit* value_edit {nullptr};
    CTextButton* resize_button {nullptr};
    ZigVstguiResizeCallbacks resize_callbacks {};
    bool updating {false};
    double accepted_value {0.0};
    uint32_t current_width {400};
    uint32_t current_height {300};

    EditorListener(uint32_t id, ZigVstguiCallbacks value_callbacks)
    : parameter_id(id), callbacks(value_callbacks) {}

    void controlBeginEdit(CControl*) override {
        if (!updating && callbacks.begin_edit) callbacks.begin_edit(callbacks.userdata, parameter_id);
    }

    void valueChanged(CControl* control) override {
        if (updating) return;
        if (control->getTag() == kResizeTag) {
            if (control->getValue() != control->getMax()) return;
            const bool expanded = current_width >= 520 || current_height >= 360;
            const uint32_t requested_width = expanded ? 400 : 640;
            const uint32_t requested_height = expanded ? 300 : 420;
            if (!resize_callbacks.request_resize ||
                resize_callbacks.request_resize(resize_callbacks.userdata, requested_width, requested_height) != 0) {
                if (resize_button) resize_button->setTitle("Resize unavailable");
            }
            return;
        }
        const double requested = clampNormalized(control->getValueNormalized());
        if (callbacks.perform_edit && callbacks.perform_edit(callbacks.userdata, parameter_id, requested) == 0) {
            setValue(requested);
        } else {
            setValue(accepted_value);
        }
    }

    void controlEndEdit(CControl*) override {
        if (!updating && callbacks.end_edit) callbacks.end_edit(callbacks.userdata, parameter_id);
    }

    void setValue(double value) {
        updating = true;
        accepted_value = clampNormalized(value);
        const float normalized = static_cast<float>(accepted_value);
        if (slider) {
            slider->setValueNormalized(normalized);
            slider->invalid();
        }
        if (value_edit) {
            value_edit->setValueNormalized(normalized);
            value_edit->invalid();
        }
        updating = false;
    }

    void setSize(uint32_t width, uint32_t height) {
        current_width = width;
        current_height = height;
        if (resize_button) {
            const bool expanded = width >= 520 || height >= 360;
            resize_button->setTitle(expanded ? "Compact" : "Expand");
        }
    }
};

struct GainSlider final : CSlider {
    using CSlider::CSlider;

    bool handleKey(uint16_t key, int16_t key_code, int16_t modifiers) {
        VirtualKey virtual_key = VirtualKey::None;
        switch (key_code) {
            case Steinberg::KEY_END: virtual_key = VirtualKey::End; break;
            case Steinberg::KEY_HOME: virtual_key = VirtualKey::Home; break;
            case Steinberg::KEY_LEFT: virtual_key = VirtualKey::Left; break;
            case Steinberg::KEY_UP: virtual_key = VirtualKey::Up; break;
            case Steinberg::KEY_RIGHT: virtual_key = VirtualKey::Right; break;
            case Steinberg::KEY_DOWN: virtual_key = VirtualKey::Down; break;
            default: return false;
        }
        KeyboardEvent event;
        event.type = EventType::KeyDown;
        event.character = key;
        event.virt = virtual_key;
        if ((modifiers & 1) != 0) event.modifiers.add(ModifierKey::Shift);
        if ((modifiers & 2) != 0) event.modifiers.add(ModifierKey::Alt);
        if ((modifiers & 4) != 0) event.modifiers.add(ModifierKey::Control);
        if ((modifiers & 8) != 0) event.modifiers.add(ModifierKey::Super);
        onKeyboardEvent(event);
        return event.consumed;
    }

    void draw(CDrawContext* context) override {
        CSlider::draw(context);
        const auto bounds = getViewSize();
        const auto center_x = bounds.left + bounds.getWidth() * getValueNormalized();
        const auto center_y = bounds.top + bounds.getHeight() / 2.0;
        CRect thumb(center_x - 8.0, center_y - 8.0, center_x + 8.0, center_y + 8.0);
        context->setDrawMode(kAntiAliasing);
        context->setLineWidth(2.0);
        context->setFrameColor(CColor(17, 113, 91, 255));
        context->setFillColor(CColor(238, 241, 246, 255));
        context->drawEllipse(thumb, kDrawFilledAndStroked);
    }

    void onKeyboardEvent(KeyboardEvent& event) override {
        if (event.type == EventType::KeyDown && (event.virt == VirtualKey::Home || event.virt == VirtualKey::End)) {
            beginEdit();
            setValueNormalized(event.virt == VirtualKey::Home ? 0.f : 1.f);
            valueChanged();
            endEdit();
            invalid();
            event.consumed = true;
            return;
        }
        CSlider::onKeyboardEvent(event);
    }
};

#if defined(LINUX)
class HostRunLoop final : public IRunLoop, public AtomicReferenceCounted {
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
class WaylandHost final : public Wayland::IWaylandHost, public AtomicReferenceCounted {
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

class WaylandFrame final : public Wayland::IWaylandFrame, public AtomicReferenceCounted {
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
    xdg_surface* getParentSurface(CRect& parent_size, wl_display* display) override {
        if (!frame) return nullptr;
        Steinberg::ViewRect rect {};
        auto* surface = frame->getParentSurface(rect, display);
        parent_size = CRect(rect.left, rect.top, rect.right, rect.bottom);
        return surface;
    }
    xdg_toplevel* getParentToplevel(wl_display* display) override {
        return frame ? frame->getParentToplevel(display) : nullptr;
    }
private:
    Steinberg::IWaylandFrame* frame {nullptr};
};
#endif
#endif

} // namespace

struct ZigVstguiEditor {
    CFrame* frame {nullptr};
    ProfiledContainer* content {nullptr};
    EditorListener listener;
    CTextLabel* title {nullptr};
    CTextLabel* help {nullptr};
    CSlider* slider {nullptr};
    CTextEdit* value_edit {nullptr};
    CTextButton* resize_button {nullptr};
    uint32_t width {400};
    uint32_t height {300};
    void* plug_frame {nullptr};
    void* wayland_host {nullptr};
    ZigVstguiParameterInfo parameter_info;
    RenderMetrics metrics;
    bool profile_enabled {false};

    ZigVstguiEditor(uint32_t parameter_id, double initial, ZigVstguiParameterInfo parameter_info, ZigVstguiCallbacks callbacks)
    : listener(parameter_id, callbacks), parameter_info(parameter_info) {
        if (editor_count.fetch_add(1, std::memory_order_acq_rel) == 0) VSTGUI::init(nullptr);
        profile_enabled = std::getenv("ZIG_VSTGUI_PROFILE") != nullptr;
        listener.accepted_value = clampNormalized(initial);
        buildFrame();
    }

    void buildFrame() {
        if (frame) return;
        frame = new CFrame(CRect(0, 0, width, height), nullptr);
        frame->setBackgroundColor(CColor(22, 25, 31, 255));
        frame->setFocusDrawingEnabled(true);
        frame->setFocusColor(CColor(89, 201, 165, 255));
        frame->setFocusWidth(2.0);
        content = new ProfiledContainer(CRect(0, 0, width, height), profile_enabled ? &metrics : nullptr);
        content->setBackgroundColor(CColor(22, 25, 31, 255));
        frame->addView(content);

        title = new CTextLabel(CRect(), parameter_info.title ? parameter_info.title : "Parameter");
        title->setFont(kNormalFontVeryBig);
        title->setFontColor(CColor(238, 241, 246, 255));
        title->setBackColor(CColor(22, 25, 31, 255));
        title->setFrameColor(CColor(22, 25, 31, 255));
        content->addView(title);

#if defined(__APPLE__)
        help = new CTextLabel(CRect(), "Drag | Arrows | Fn+Left/Right limits | Command-click resets");
#else
        help = new CTextLabel(CRect(), "Drag | Arrows | Home/End | Control-click resets");
#endif
        help->setFontColor(CColor(157, 166, 181, 255));
        help->setBackColor(CColor(22, 25, 31, 255));
        help->setFrameColor(CColor(22, 25, 31, 255));
        content->addView(help);

        slider = new GainSlider(
            CRect(),
            &listener,
            kGainTag,
            0,
            1,
            nullptr,
            nullptr
        );
        slider->setMin(0.f);
        slider->setMax(1.f);
        slider->setDefaultValue(static_cast<float>(clampNormalized(parameter_info.default_normalized)));
        slider->setWheelInc(parameter_info.step_count > 0 ? 1.f / static_cast<float>(parameter_info.step_count) : 0.01f);
        slider->setDrawStyle(CSlider::kDrawFrame | CSlider::kDrawBack | CSlider::kDrawValue);
        slider->setFrameWidth(2.0);
        slider->setFrameColor(CColor(73, 82, 97, 255));
        slider->setBackColor(CColor(37, 42, 51, 255));
        slider->setValueColor(CColor(17, 113, 91, 255));
        slider->setWantsFocus(true);
        content->addView(slider);

        value_edit = new CTextEdit(CRect(), &listener, kValueTag, "");
        value_edit->setMin(0.f);
        value_edit->setMax(1.f);
        value_edit->setDefaultValue(static_cast<float>(clampNormalized(parameter_info.default_normalized)));
        value_edit->setFontColor(CColor(238, 241, 246, 255));
        value_edit->setBackColor(CColor(37, 42, 51, 255));
        value_edit->setFrameColor(CColor(89, 201, 165, 255));
        value_edit->setRoundRectRadius(8);
        value_edit->setValueToStringFunction([](float value, char text[256], CParamDisplay* display) {
            auto* callback = static_cast<EditorListener*>(display->getListener());
            if (callback && callback->callbacks.format_value) {
                return callback->callbacks.format_value(
                    callback->callbacks.userdata,
                    callback->parameter_id,
                    static_cast<double>(value),
                    text,
                    256
                ) >= 0;
            }
            std::snprintf(text, 256, "%.3f", static_cast<double>(value));
            return true;
        });
        value_edit->setStringToValueFunction([](UTF8StringPtr text, float& value, CTextEdit* edit) {
            if (!text) return false;
            auto* callback = static_cast<EditorListener*>(edit->getListener());
            double parsed = 0.0;
            if (!callback || !callback->callbacks.parse_value ||
                callback->callbacks.parse_value(
                    callback->callbacks.userdata,
                    callback->parameter_id,
                    text,
                    &parsed
                ) != 0) return false;
            value = static_cast<float>(clampNormalized(parsed));
            return true;
        });
        content->addView(value_edit);

        resize_button = new CTextButton(CRect(), &listener, kResizeTag, "Expand");
        resize_button->setTextColor(CColor(238, 241, 246, 255));
        resize_button->setTextColorHighlighted(CColor(238, 241, 246, 255));
        resize_button->setFrameColor(CColor(89, 201, 165, 255));
        resize_button->setFrameColorHighlighted(CColor(124, 232, 197, 255));
        resize_button->setGradient(owned(CGradient::create(0, 1, CColor(29, 83, 70, 255), CColor(22, 62, 53, 255))));
        resize_button->setGradientHighlighted(owned(CGradient::create(0, 1, CColor(39, 125, 101, 255), CColor(29, 83, 70, 255))));
        resize_button->setRoundRadius(8);
        content->addView(resize_button);

        listener.slider = slider;
        listener.value_edit = value_edit;
        listener.resize_button = resize_button;
        listener.setSize(width, height);
        layout();
        listener.setValue(listener.accepted_value);
    }

    ~ZigVstguiEditor() {
        close();
        if (frame) frame->forget();
        if (profile_enabled && (metrics.draw_count != 0 || metrics.open_count != 0)) {
            const double average_us = metrics.draw_count == 0
                ? 0.0
                : static_cast<double>(metrics.draw_total_ns) / static_cast<double>(metrics.draw_count) / 1000.0;
            std::fprintf(
                stderr,
                "zig-vstgui profile: draws=%llu average_us=%.3f max_us=%.3f invalidated_pixels=%.0f opens=%llu closes=%llu resizes=%llu scales=%llu parameter_updates=%llu\n",
                static_cast<unsigned long long>(metrics.draw_count),
                average_us,
                static_cast<double>(metrics.draw_max_ns) / 1000.0,
                metrics.invalidated_area,
                static_cast<unsigned long long>(metrics.open_count),
                static_cast<unsigned long long>(metrics.close_count),
                static_cast<unsigned long long>(metrics.resize_count),
                static_cast<unsigned long long>(metrics.scale_count),
                static_cast<unsigned long long>(metrics.parameter_update_count)
            );
        }
#if defined(LINUX)
        if (plug_frame) static_cast<Steinberg::FUnknown*>(plug_frame)->release();
        if (wayland_host) static_cast<Steinberg::FUnknown*>(wayland_host)->release();
#endif
        if (editor_count.fetch_sub(1, std::memory_order_acq_rel) == 1) VSTGUI::exit();
    }

    bool open(void* parent, ZigVstguiPlatform platform) {
        if (!frame) buildFrame();
        if (!frame || (!parent && platform != ZIG_VSTGUI_PLATFORM_WAYLAND)) return false;
        PlatformType native_type;
        switch (platform) {
            case ZIG_VSTGUI_PLATFORM_MACOS: native_type = PlatformType::kNSView; break;
            case ZIG_VSTGUI_PLATFORM_WINDOWS: native_type = PlatformType::kHWND; break;
            case ZIG_VSTGUI_PLATFORM_X11: native_type = PlatformType::kX11EmbedWindowID; break;
            case ZIG_VSTGUI_PLATFORM_WAYLAND: native_type = PlatformType::kWaylandSurfaceID; break;
            default: return false;
        }
#if defined(LINUX)
        if (platform == ZIG_VSTGUI_PLATFORM_X11) {
            auto run_loop = owned(new HostRunLoop(static_cast<Steinberg::FUnknown*>(plug_frame)));
            if (!run_loop->valid()) return false;
            X11::FrameConfig config;
            config.runLoop = run_loop;
            const bool opened = frame->open(parent, native_type, &config);
            if (opened) metrics.open_count += 1;
            return opened;
        }
#if VSTGUI_ENABLE_WAYLAND_SUPPORT
        if (platform == ZIG_VSTGUI_PLATFORM_WAYLAND) {
            auto run_loop = owned(new HostRunLoop(static_cast<Steinberg::FUnknown*>(plug_frame)));
            auto host = owned(new WaylandHost(static_cast<Steinberg::FUnknown*>(wayland_host)));
            auto host_frame = owned(new WaylandFrame(static_cast<Steinberg::FUnknown*>(plug_frame)));
            if (!run_loop->valid() || !host->valid() || !host_frame->valid()) return false;
            Wayland::FrameConfig config;
            config.runLoop = run_loop;
            config.waylandHost = host;
            config.waylandFrame = host_frame;
            const bool opened = frame->open(&config, native_type, &config);
            if (opened) metrics.open_count += 1;
            return opened;
        }
#endif
#endif
        const bool opened = frame->open(parent, native_type);
        if (opened) metrics.open_count += 1;
        return opened;
    }

    void close() {
        if (!frame || !frame->getPlatformFrame()) return;
        metrics.close_count += 1;
        frame->close();
        frame = nullptr;
        content = nullptr;
        title = nullptr;
        help = nullptr;
        slider = nullptr;
        value_edit = nullptr;
        resize_button = nullptr;
        listener.slider = nullptr;
        listener.value_edit = nullptr;
        listener.resize_button = nullptr;
    }

    void layout() {
        if (!frame) return;
        if (content) content->setViewSize(CRect(0, 0, width, height), true);
        const double margin = 24.0;
        const double right = std::max(margin + 1.0, static_cast<double>(width) - margin);
        const double track_top = std::clamp(static_cast<double>(height) * 0.42, 92.0, static_cast<double>(height) - 116.0);
        const double value_width = std::min(148.0, static_cast<double>(width) - margin * 2.0);
        const double value_left = margin;
        if (title) title->setViewSize(CRect(margin, 16, right, 52), true);
        if (help) help->setViewSize(CRect(margin, 54, right, 82), true);
        if (slider) {
            slider->setViewSize(CRect(margin, track_top, right, track_top + 52), true);
        }
        if (value_edit) value_edit->setViewSize(CRect(value_left, height - 64.0, value_left + value_width, height - 24.0), true);
        if (resize_button) resize_button->setViewSize(CRect(right - 112.0, height - 64.0, right, height - 24.0), true);
    }
};

extern "C" ZigVstguiEditor* zig_vstgui_editor_create(
    uint32_t parameter_id,
    double initial_normalized,
    ZigVstguiParameterInfo parameter_info,
    ZigVstguiCallbacks callbacks
) {
    return new (std::nothrow) ZigVstguiEditor(parameter_id, initial_normalized, parameter_info, callbacks);
}

extern "C" int32_t zig_vstgui_editor_open(ZigVstguiEditor* editor, void* parent, ZigVstguiPlatform platform) {
    return editor && editor->open(parent, platform) ? 0 : -1;
}

extern "C" void zig_vstgui_editor_close(ZigVstguiEditor* editor) {
    if (editor) editor->close();
}

extern "C" void zig_vstgui_editor_destroy(ZigVstguiEditor* editor) {
    delete editor;
}

extern "C" int32_t zig_vstgui_editor_resize(ZigVstguiEditor* editor, uint32_t width, uint32_t height) {
    if (!editor || !editor->frame || width < 320 || height < 240) return -1;
    editor->width = width;
    editor->height = height;
    if (!editor->frame->setSize(width, height)) return -1;
    editor->metrics.resize_count += 1;
    editor->listener.setSize(width, height);
    editor->layout();
    return 0;
}

extern "C" int32_t zig_vstgui_editor_set_scale(ZigVstguiEditor* editor, double scale) {
    if (!editor || !editor->frame || scale <= 0.0) return -1;
    if (!editor->frame->setZoom(scale)) return -1;
    editor->metrics.scale_count += 1;
    return 0;
}

extern "C" void zig_vstgui_editor_set_parameter(ZigVstguiEditor* editor, double normalized) {
    if (editor) {
        editor->metrics.parameter_update_count += 1;
        editor->listener.setValue(normalized);
    }
}

extern "C" int32_t zig_vstgui_editor_key_down(
    ZigVstguiEditor* editor,
    uint16_t key,
    int16_t key_code,
    int16_t modifiers
) {
    if (!editor || !editor->frame || !editor->slider) return -1;
    auto* slider = static_cast<GainSlider*>(editor->slider);
    if (!slider->handleKey(key, key_code, modifiers)) return -1;
    editor->frame->setFocusView(editor->slider);
    return 0;
}

extern "C" void zig_vstgui_editor_set_focus(ZigVstguiEditor* editor, int32_t focused) {
    if (!editor || !editor->frame) return;
    editor->frame->onActivate(focused != 0);
}

extern "C" void zig_vstgui_editor_set_frame(ZigVstguiEditor* editor, void* plug_frame) {
#if defined(LINUX)
    if (!editor || editor->plug_frame == plug_frame) return;
    if (plug_frame) static_cast<Steinberg::FUnknown*>(plug_frame)->addRef();
    if (editor->plug_frame) static_cast<Steinberg::FUnknown*>(editor->plug_frame)->release();
    editor->plug_frame = plug_frame;
#else
    (void)editor;
    (void)plug_frame;
#endif
}

extern "C" void zig_vstgui_editor_set_wayland_host(ZigVstguiEditor* editor, void* wayland_host) {
#if defined(LINUX) && VSTGUI_ENABLE_WAYLAND_SUPPORT
    if (!editor || editor->wayland_host == wayland_host) return;
    if (wayland_host) static_cast<Steinberg::FUnknown*>(wayland_host)->addRef();
    if (editor->wayland_host) static_cast<Steinberg::FUnknown*>(editor->wayland_host)->release();
    editor->wayland_host = wayland_host;
#else
    (void)editor;
    (void)wayland_host;
#endif
}

extern "C" void zig_vstgui_editor_set_resize_callbacks(ZigVstguiEditor* editor, ZigVstguiResizeCallbacks callbacks) {
    if (editor) editor->listener.resize_callbacks = callbacks;
}

extern "C" uint32_t zig_vstgui_adapter_version() {
    return 1;
}
