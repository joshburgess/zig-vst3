#include "zig_vstgui_editor.h"

#include "pluginterfaces/base/keycodes.h"

#import <AppKit/AppKit.h>

#include <cmath>

namespace {

void beginEdit(void*, uint32_t) {}
int32_t performEdit(void*, uint32_t, double) { return 0; }
void endEdit(void*, uint32_t) {}
double loadMeter(void*, uint32_t) { return 0.5; }

id elementNamed(NSArray* elements, NSString* name) {
    for (id element in elements) {
        if ([[element accessibilityLabel] isEqualToString:name]) return element;
    }
    return nil;
}

}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        auto* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 420)];
        const ZigVstguiParameterDescription parameters[] = {
            {10, 0.25, {"Gain", "dB", 0, 0.5, "Output gain"}, ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER},
            {20, 0.0, {"Bypass", "", 1, 0.0, "Bypass processing"}, ZIG_VSTGUI_CONTROL_TOGGLE},
            {30, 0.0, {"Mode", "", 2, 0.0, "Processing mode"}, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN},
        };
        const ZigVstguiMeterDescription meters[] = {{"Level", ZIG_VSTGUI_METER_PEAK, 0, 0}};
        const ZigVstguiGraphPoint points[] = {{0.0, 0.0}, {1.0, 1.0}};
        const ZigVstguiGraphDescription graphs[] = {{
            "Transfer",
            ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION,
            ZIG_VSTGUI_GRAPH_PRIMARY,
            {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Input"},
            {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Output"},
            points,
            2,
            0,
            0,
            0,
        }};
        ZigVstguiCallbacks callbacks {nullptr, beginEdit, performEdit, endEdit};
        ZigVstguiSkinDescription skin {};
        skin.editor_title = "Accessibility Test";
        ZigVstguiEditor editor(parameters, 3, callbacks, meters, 1, {nullptr, loadMeter}, skin, graphs, 1, {});
        if (!editor.open((__bridge void*)parent, ZIG_VSTGUI_PLATFORM_MACOS)) return 1;
        if (!editor.nativeAccessibilityActive() || editor.nativeAccessibilityElementCount() != 9) return 2;
        auto* native_view = parent.subviews.lastObject;
        if (!native_view) return 3;
        NSArray* children = native_view.accessibilityChildren;
        if (children.count != 9) return 4;
        id gain = elementNamed(children, @"Gain (dB)");
        id bypass = elementNamed(children, @"Bypass");
        id exact = elementNamed(children, @"Gain (dB) value");
        id mode = elementNamed(children, @"Mode");
        id meter = elementNamed(children, @"Level");
        id graph = elementNamed(children, @"Transfer");
        id resize = elementNamed(children, @"Editor size");
        if (!gain || !bypass || !exact || !mode || !meter || !graph || !resize) return 5;
        if (![[gain accessibilityRole] isEqualToString:NSAccessibilitySliderRole]) return 6;
        if (![[bypass accessibilityRole] isEqualToString:NSAccessibilityCheckBoxRole]) return 7;
        if (![[exact accessibilityRole] isEqualToString:NSAccessibilityTextFieldRole]) return 8;
        if (![[mode accessibilityRole] isEqualToString:NSAccessibilityPopUpButtonRole]) return 16;
        if (![[meter accessibilityRole] isEqualToString:NSAccessibilityProgressIndicatorRole]) return 17;
        if (![[graph accessibilityRole] isEqualToString:NSAccessibilityGroupRole]) return 18;
        if (![[resize accessibilityRole] isEqualToString:NSAccessibilityButtonRole]) return 19;
        if (std::abs([[gain accessibilityValue] doubleValue] - 0.25) > 1e-9) return 9;
        if (![gain accessibilityValueDescription]) return 10;
        if (!editor.setParameter(10, 0.75)) return 11;
        if (std::abs([[gain accessibilityValue] doubleValue] - 0.75) > 1e-9) return 12;
        if (!editor.setParameter(20, 1.0) || ![[bypass accessibilityValue] boolValue]) return 20;
        if (!editor.keyDown(0, Steinberg::KEY_TAB, 0) || ![gain isAccessibilityFocused]) return 21;
        const NSRect initial_frame = [gain accessibilityFrameInParentSpace];
        if (!editor.resize(640, 420)) return 13;
        const NSRect resized_frame = [gain accessibilityFrameInParentSpace];
        if (NSEqualRects(initial_frame, resized_frame)) return 14;
        editor.close();
        if (native_view.accessibilityChildren.count != 0 || editor.nativeAccessibilityActive()) return 15;
    }
    return 0;
}
