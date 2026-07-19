#include "zig_vstgui_editor.h"

#include "pluginterfaces/base/keycodes.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

struct CallbackState {
    uint32_t begin_count {0};
    uint32_t perform_count {0};
    uint32_t end_count {0};
    uint32_t draw_count {0};
    std::string editor_text {"Studio Plate"};
    std::string live_text {"48 kHz, mono"};
};

void beginEdit(void* userdata, uint32_t) {
    static_cast<CallbackState*>(userdata)->begin_count += 1;
}
int32_t performEdit(void* userdata, uint32_t, double) {
    static_cast<CallbackState*>(userdata)->perform_count += 1;
    return 0;
}
void endEdit(void* userdata, uint32_t) {
    static_cast<CallbackState*>(userdata)->end_count += 1;
}
int32_t parseValue(void*, uint32_t, const char* text, double* value) {
    if (!text || !value) return -1;
    char* end = nullptr;
    const double parsed = std::strtod(text, &end);
    if (end == text || *end != '\0') return -1;
    *value = parsed;
    return 0;
}
double loadMeter(void*, uint32_t) { return 0.5; }
int32_t storeEditorText(void* userdata, uint32_t field_id, const char* text) {
    if (field_id != 11 || !text || text[0] == '\0') return -1;
    static_cast<CallbackState*>(userdata)->editor_text = text;
    return 0;
}
int32_t loadEditorText(void* userdata, uint32_t field_id, char* output, uint32_t capacity) {
    if ((field_id != 11 && field_id != 12) || !output || capacity == 0) return -1;
    const auto* state = static_cast<CallbackState*>(userdata);
    const auto& text = field_id == 11 ? state->editor_text : state->live_text;
    if (text.size() >= capacity) return -1;
    std::memcpy(output, text.c_str(), text.size() + 1);
    return 0;
}
int32_t loadProgress(void*, uint32_t source_id, ZigVstguiProgressSnapshot* snapshot) {
    if (source_id != 7 || !snapshot) return -1;
    *snapshot = {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_RUNNING, 0.42, 1};
    return 0;
}

int32_t drawParameter(void* userdata, const ZigVstguiDrawRequest* request, ZigVstguiCanvas* canvas) {
    if (!userdata || !request || !canvas) return -1;
    static_cast<CallbackState*>(userdata)->draw_count += 1;
    if (request->parameter_id != 20 || request->component != ZIG_VSTGUI_DRAW_TOGGLE) return 0;
    return zig_vstgui_canvas_draw_asset(canvas, 1, 6.0, 6.0, 26.0, 26.0, 1.f);
}

id elementNamed(NSArray* elements, NSString* name) {
    for (id element in elements) {
        if ([[element accessibilityLabel] isEqualToString:name]) return element;
    }
    return nil;
}

void* nativeFramePointer(NSView* view) {
    if (!view) return nullptr;
    auto* frame_ivar = class_getInstanceVariable(object_getClass(view), "_nsViewFrame");
    if (!frame_ivar) return nullptr;
    auto* storage = reinterpret_cast<void**>(
        reinterpret_cast<std::byte*>((__bridge void*)view) + ivar_getOffset(frame_ivar)
    );
    return *storage;
}

}

int main() {
    @autoreleasepool {
        if (objc_getClass("ZigVstguiAccessibilityElement")) return 33;
        [NSApplication sharedApplication];
        auto* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 420)];
        const ZigVstguiParameterDescription parameters[] = {
            {10, 0.25, {"Gain", "dB", 0, 0.5, "Output gain"}, ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER},
            {20, 0.0, {"Bypass", "", 1, 0.0, "Bypass processing"}, ZIG_VSTGUI_CONTROL_TOGGLE},
            {30, 0.0, {"Mode", "", 2, 0.0, "Processing mode"}, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN},
        };
        const ZigVstguiMeterDescription meters[] = {{"Level", ZIG_VSTGUI_METER_PEAK, 0, 0}};
        const ZigVstguiGraphPoint points[] = {{0.0, 0.0}, {1.0, 1.0}};
        ZigVstguiGraphDescription graphs[] = {{
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
        graphs[0].viewport = {
            1, ZIG_VSTGUI_VIEWPORT_HORIZONTAL, 1.0, 8.0, 1.0, 0.0, 0.0, 1.25, 0.1, 0, 0, 0,
        };
        graphs[0].range_selection = {1, 0.2, 0.8, 0.1, 0.05, 0, 0};
        CallbackState state;
        static constexpr char test_svg[] =
            "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 20 20'>"
            "<path d='M3 10l4 4 10-10' fill='none' stroke='#00a889' stroke-width='3'/></svg>";
        const ZigVstguiAssetDescription assets[] = {{
            1,
            reinterpret_cast<const uint8_t*>(test_svg),
            static_cast<uint32_t>(sizeof(test_svg) - 1),
            ZIG_VSTGUI_ASSET_SVG,
            ZIG_VSTGUI_ASSET_CONTAIN,
        }};
        ZigVstguiCallbacks callbacks {};
        callbacks.userdata = &state;
        callbacks.begin_edit = beginEdit;
        callbacks.perform_edit = performEdit;
        callbacks.end_edit = endEdit;
        callbacks.parse_value = parseValue;
        callbacks.store_editor_text = storeEditorText;
        callbacks.load_editor_text = loadEditorText;
        callbacks.load_progress = loadProgress;
        ZigVstguiSkinDescription skin {};
        skin.assets = assets;
        skin.asset_count = 1;
        skin.fonts = {"Avenir Next", "Avenir Next", "Menlo", "Arial"};
        skin.drawing = {&state, drawParameter};
        skin.editor_title = "Accessibility Test";
        const ZigVstguiEditableLabelDescription editable[] = {
            {11, "IR Name", "Impulse response name", "Name this impulse response",
                "Enter an IR name", "Studio Plate", 48, 1},
            {12, "Format", "Impulse response format", "", "Value unavailable",
                "48 kHz, mono", 48, 1, 1, 10},
        };
        const ZigVstguiProgressIndicatorDescription progress {
            7, "Import", "Impulse response import progress", "Choose an IR to begin",
            "Importing IR", "IR ready", "Import failed", 20,
        };
        ZigVstguiEditor editor(
            parameters, 3, callbacks, meters, 1, {nullptr, loadMeter}, skin, graphs, 1, {},
            nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0,
            nullptr, 0, editable, 2, &progress, 1
        );
        if (!editor.open((__bridge void*)parent, ZIG_VSTGUI_PLATFORM_MACOS)) return 1;
        if (!editor.nativeAccessibilityActive() || editor.nativeAccessibilityElementCount() != 12) return 2;
        auto* native_view = parent.subviews.lastObject;
        if (!native_view) return 3;
        [native_view setNeedsDisplay:YES];
        [native_view displayIfNeeded];
        if (state.draw_count == 0) return 40;
        NSArray* children = native_view.accessibilityChildren;
        if (children.count != 12) return 4;
        id gain = elementNamed(children, @"Gain (dB)");
        id bypass = elementNamed(children, @"Bypass");
        id exact = elementNamed(children, @"Gain (dB) value");
        id mode = elementNamed(children, @"Mode");
        id meter = elementNamed(children, @"Level");
        id graph = elementNamed(children, @"Transfer");
        id editable_name = elementNamed(children, @"Impulse response name");
        id live_value = elementNamed(children, @"Impulse response format");
        id progress_element = elementNamed(children, @"Impulse response import progress");
        id resize = elementNamed(children, @"Editor size");
        if (!gain || !bypass || !exact || !mode || !meter || !graph || !editable_name || !live_value || !progress_element || !resize) return 5;
        const char* element_class_name = object_getClassName(gain);
        if (!element_class_name ||
            std::strncmp(
                element_class_name,
                "ZigVstguiAccessibilityElement_",
                sizeof("ZigVstguiAccessibilityElement_") - 1
            ) != 0 ||
            std::strcmp(element_class_name, "ZigVstguiAccessibilityElement") == 0) return 34;
        if (![[gain accessibilityRole] isEqualToString:NSAccessibilitySliderRole]) return 6;
        if (![[bypass accessibilityRole] isEqualToString:NSAccessibilityCheckBoxRole]) return 7;
        if (![[exact accessibilityRole] isEqualToString:NSAccessibilityTextFieldRole]) return 8;
        if (![[mode accessibilityRole] isEqualToString:NSAccessibilityPopUpButtonRole]) return 16;
        if (![[meter accessibilityRole] isEqualToString:NSAccessibilityProgressIndicatorRole]) return 17;
        if (![[graph accessibilityRole] isEqualToString:NSAccessibilityGroupRole]) return 18;
        if (![[editable_name accessibilityRole] isEqualToString:NSAccessibilityTextFieldRole]) return 26;
        if (![[live_value accessibilityRole] isEqualToString:NSAccessibilityTextFieldRole]) return 31;
        [live_value setAccessibilityValue:@"Changed"];
        if (state.live_text != "48 kHz, mono" ||
            ![[live_value accessibilityValue] isEqualToString:@"48 kHz, mono"]) return 32;
        if (![[progress_element accessibilityRole] isEqualToString:NSAccessibilityProgressIndicatorRole]) return 27;
        if (![[resize accessibilityRole] isEqualToString:NSAccessibilityButtonRole]) return 19;
        if (std::abs([[gain accessibilityValue] doubleValue] - 0.25) > 1e-9) return 9;
        if (![gain accessibilityValueDescription]) return 10;
        if (!editor.setParameter(10, 0.75)) return 11;
        if (std::abs([[gain accessibilityValue] doubleValue] - 0.75) > 1e-9) return 12;
        if (!editor.setParameter(20, 1.0) || ![[bypass accessibilityValue] boolValue]) return 20;
        [gain setAccessibilityFocused:YES];
        if (![gain isAccessibilityFocused]) return 21;
        [gain accessibilityPerformIncrement];
        double value = 0.0;
        if (!editor.parameterValue(10, value) || std::abs(value - 0.76) > 1e-9) return 22;
        if (![bypass accessibilityPerformPress] ||
            !editor.parameterValue(20, value) || std::abs(value) > 1e-9) return 23;
        [exact setAccessibilityValue:@"0.42"];
        if (!editor.parameterValue(10, value) || std::abs(value - 0.42) > 1e-9) return 24;
        [graph accessibilityPerformIncrement];
        if (![[graph accessibilityValueDescription] containsString:@"Selection 0.250 to 0.800"] ||
            std::abs([[graph accessibilityValue] doubleValue] - 0.25) > 1e-9) return 30;
        [editable_name setAccessibilityValue:@"Bright Hall"];
        if (state.editor_text != "Bright Hall" || ![[editable_name accessibilityValue] isEqualToString:@"Bright Hall"]) return 28;
        if (![[progress_element accessibilityValueDescription] containsString:@"42%"] ||
            std::abs([[progress_element accessibilityValue] doubleValue] - 0.42) > 1e-9) return 29;
        if (state.begin_count != 3 || state.perform_count != 3 || state.end_count != 3) return 25;
        const NSRect initial_frame = [gain accessibilityFrameInParentSpace];
        if (!editor.resize(640, 420)) return 13;
        const NSRect resized_frame = [gain accessibilityFrameInParentSpace];
        if (NSEqualRects(initial_frame, resized_frame)) return 14;
        if (!nativeFramePointer(native_view)) return 35;
        editor.close();
        if (native_view.accessibilityChildren.count != 0 || editor.nativeAccessibilityActive()) return 15;
        if (nativeFramePointer(native_view)) return 36;

        auto* retained_views = [NSMutableArray arrayWithObject:native_view];
        const uint32_t initial_draw_count = state.draw_count;
        for (uint32_t cycle = 0; cycle < 16; ++cycle) {
            if (!editor.open((__bridge void*)parent, ZIG_VSTGUI_PLATFORM_MACOS)) return 37;
            auto* cycle_view = parent.subviews.lastObject;
            if (!cycle_view || !nativeFramePointer(cycle_view)) return 38;
            [retained_views addObject:cycle_view];
            [cycle_view updateTrackingAreas];
            [cycle_view setNeedsDisplay:YES];
            [cycle_view displayIfNeeded];
            editor.close();
            if (nativeFramePointer(cycle_view)) return 39;
        }
        for (NSView* retained_view in retained_views) {
            [retained_view updateTrackingAreas];
            [retained_view setNeedsDisplay:YES];
            [retained_view displayIfNeeded];
        }
        if (state.draw_count <= initial_draw_count) return 41;
        [[NSRunLoop currentRunLoop]
            runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return 0;
}
