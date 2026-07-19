#ifndef ZIG_VSTGUI_PLATFORM_H
#define ZIG_VSTGUI_PLATFORM_H

#include "zig_vstgui_adapter.h"
#include "vstgui/lib/cframe.h"

namespace ZigVstgui {

bool openFrame(
    VSTGUI::CFrame* frame,
    void* parent,
    ZigVstguiPlatform platform,
    void* plug_frame,
    void* wayland_host
);

void prepareFrameForClose(VSTGUI::CFrame* frame);

void replacePlugFrame(void*& current, void* replacement);
void replaceWaylandHost(void*& current, void* replacement);
void releasePlatformInterfaces(void*& plug_frame, void*& wayland_host);

}

#endif
