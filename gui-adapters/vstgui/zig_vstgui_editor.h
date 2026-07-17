#ifndef ZIG_VSTGUI_EDITOR_H
#define ZIG_VSTGUI_EDITOR_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cframe.h"
#include "vstgui/lib/controls/ctextlabel.h"

struct ZigVstguiEditor {
    ZigVstguiEditor(
        uint32_t parameter_id,
        double initial,
        ZigVstguiParameterInfo parameter_info,
        ZigVstguiCallbacks callbacks
    );
    ~ZigVstguiEditor();

    bool open(void* parent, ZigVstguiPlatform platform);
    void close();
    bool resize(uint32_t width, uint32_t height);
    bool setScale(double scale);
    void setParameter(double normalized);
    bool keyDown(uint16_t key, int16_t key_code, int16_t modifiers);
    void setFocus(bool focused);
    void setPlugFrame(void* frame);
    void setWaylandHost(void* host);
    void setResizeCallbacks(ZigVstguiResizeCallbacks callbacks);

private:
    void buildFrame();
    void clearFrameReferences();
    void layout();
    void reportMetrics() const;

    VSTGUI::CFrame* frame {nullptr};
    ZigVstgui::ProfiledContainer* content {nullptr};
    VSTGUI::CTextLabel* title {nullptr};
    VSTGUI::CTextLabel* help {nullptr};
    ZigVstgui::Component title_component;
    ZigVstgui::Component help_component;
    ZigVstgui::ParameterControl parameter_control;
    ZigVstgui::ResizeControl resize_control;
    ZigVstgui::ThemeResolver theme_resolver;
    uint32_t width {400};
    uint32_t height {300};
    void* plug_frame {nullptr};
    void* wayland_host {nullptr};
    ZigVstguiParameterInfo parameter_info;
    ZigVstgui::RenderMetrics metrics;
    bool profile_enabled {false};
};

#endif
