#include "zig_vstgui_platform.h"

#include "vstgui/lib/platform/iplatformframe.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include <cstddef>

namespace ZigVstgui {

void prepareFrameForClose(VSTGUI::CFrame* frame) {
    if (!frame) return;
    auto* platform_frame = frame->getPlatformFrame();
    if (!platform_frame || platform_frame->getPlatformType() != VSTGUI::PlatformType::kNSView) return;

    auto* native_view = (__bridge NSView*)platform_frame->getPlatformRepresentation();
    if (!native_view) return;

    if (auto* frame_ivar = class_getInstanceVariable(object_getClass(native_view), "_nsViewFrame")) {
        auto* storage = reinterpret_cast<void**>(
            reinterpret_cast<std::byte*>((__bridge void*)native_view) + ivar_getOffset(frame_ivar)
        );
        *storage = nullptr;
    }

    [[NSNotificationCenter defaultCenter] removeObserver:native_view];
    for (NSTrackingArea* area in native_view.trackingAreas.copy) {
        [native_view removeTrackingArea:area];
    }
    for (CALayer* layer in native_view.layer.sublayers.copy) {
        if (layer.delegate == static_cast<id<CALayerDelegate>>(native_view)) {
            layer.delegate = nil;
            [layer removeFromSuperlayer];
        }
    }
}

}
