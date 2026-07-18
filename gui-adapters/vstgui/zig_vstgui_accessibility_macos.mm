#include "zig_vstgui_accessibility_bridge.h"

#import <AppKit/AppKit.h>

#include "vstgui/lib/platform/iplatformframe.h"

#include <memory>
#include <utility>

namespace {

NSString* string(const std::string& value) {
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding];
}

NSString* role(ZigVstgui::AccessibilityRole value) {
    switch (value) {
        case ZigVstgui::AccessibilityRole::slider: return NSAccessibilitySliderRole;
        case ZigVstgui::AccessibilityRole::button: return NSAccessibilityButtonRole;
        case ZigVstgui::AccessibilityRole::toggle: return NSAccessibilityCheckBoxRole;
        case ZigVstgui::AccessibilityRole::choice: return NSAccessibilityPopUpButtonRole;
        case ZigVstgui::AccessibilityRole::text_field: return NSAccessibilityTextFieldRole;
        case ZigVstgui::AccessibilityRole::meter: return NSAccessibilityProgressIndicatorRole;
        case ZigVstgui::AccessibilityRole::graph: return NSAccessibilityGroupRole;
        case ZigVstgui::AccessibilityRole::group: return NSAccessibilityGroupRole;
    }
}

}

@interface ZigVstguiAccessibilityElement : NSAccessibilityElement
@property(nonatomic, assign) const ZigVstgui::AccessibilityNode* semanticNode;
@property(nonatomic, assign) const VSTGUI::CView* vstguiView;
@end

@implementation ZigVstguiAccessibilityElement

- (BOOL)isAccessibilityElement {
    return self.vstguiView && self.vstguiView->isVisible();
}

- (NSString*)accessibilityRole {
    return self.semanticNode ? role(self.semanticNode->role()) : NSAccessibilityGroupRole;
}

- (NSString*)accessibilityLabel {
    return self.semanticNode ? string(self.semanticNode->name()) : @"";
}

- (NSString*)accessibilityHelp {
    if (!self.semanticNode || self.semanticNode->description().empty()) return nil;
    return string(self.semanticNode->description());
}

- (id)accessibilityValue {
    if (!self.semanticNode) return nil;
    const auto& node = *self.semanticNode;
    if (node.role() == ZigVstgui::AccessibilityRole::toggle) return @(node.state().checked);
    if (node.range().present) return @(node.range().current);
    return node.valueText().empty() ? nil : string(node.valueText());
}

- (NSString*)accessibilityValueDescription {
    if (!self.semanticNode || self.semanticNode->valueText().empty()) return nil;
    return string(self.semanticNode->valueText());
}

- (id)accessibilityMinValue {
    if (!self.semanticNode || !self.semanticNode->range().present) return nil;
    return @(self.semanticNode->range().minimum);
}

- (id)accessibilityMaxValue {
    if (!self.semanticNode || !self.semanticNode->range().present) return nil;
    return @(self.semanticNode->range().maximum);
}

- (BOOL)isAccessibilityEnabled {
    return self.semanticNode && self.semanticNode->state().enabled;
}

- (BOOL)isAccessibilityFocused {
    return self.semanticNode && self.semanticNode->state().focused;
}

- (void)setAccessibilityFocused:(BOOL)focused {
    if (focused && self.semanticNode) {
        self.semanticNode->perform(ZigVstgui::AccessibilityAction::focus);
    }
}

- (BOOL)accessibilityPerformPress {
    return self.semanticNode &&
        self.semanticNode->perform(ZigVstgui::AccessibilityAction::press);
}

- (BOOL)accessibilityPerformIncrement {
    return self.semanticNode &&
        self.semanticNode->perform(ZigVstgui::AccessibilityAction::increment);
}

- (BOOL)accessibilityPerformDecrement {
    return self.semanticNode &&
        self.semanticNode->perform(ZigVstgui::AccessibilityAction::decrement);
}

- (void)setAccessibilityValue:(id)value {
    if (!self.semanticNode || !value) return;
    if ([value isKindOfClass:[NSNumber class]]) {
        self.semanticNode->perform(
            ZigVstgui::AccessibilityAction::set_value,
            [value doubleValue]
        );
        return;
    }
    if ([value isKindOfClass:[NSString class]]) {
        self.semanticNode->perform(
            ZigVstgui::AccessibilityAction::set_value,
            0.0,
            [(NSString*)value UTF8String]
        );
    }
}

- (NSRect)accessibilityFrameInParentSpace {
    if (!self.vstguiView) return NSZeroRect;
    const auto size = self.vstguiView->getViewSize();
    VSTGUI::CRect bounds(0.0, 0.0, size.getWidth(), size.getHeight());
    self.vstguiView->translateToGlobal(bounds, true);
    return NSMakeRect(bounds.left, bounds.top, bounds.getWidth(), bounds.getHeight());
}

@end

namespace ZigVstgui {

struct MacObserver {
    const AccessibilityNode* node {nullptr};
    __weak ZigVstguiAccessibilityElement* element {nil};
};

void accessibilityChanged(void* userdata, AccessibilityChange change) {
    auto* observer = static_cast<MacObserver*>(userdata);
    auto* element = observer ? observer->element : nil;
    if (!element) return;
    NSString* notification = NSAccessibilityValueChangedNotification;
    if (change == AccessibilityChange::focus) notification = NSAccessibilityFocusedUIElementChangedNotification;
    if (change == AccessibilityChange::role || change == AccessibilityChange::name ||
        change == AccessibilityChange::description) notification = NSAccessibilityLayoutChangedNotification;
    NSAccessibilityPostNotification(element, notification);
}

class NativeAccessibilityBridge::Impl {
public:
    NSView* root {nil};
    NSArray<ZigVstguiAccessibilityElement*>* elements {nil};
    std::vector<std::unique_ptr<MacObserver>> observers;
};

NativeAccessibilityBridge::NativeAccessibilityBridge() = default;
NativeAccessibilityBridge::~NativeAccessibilityBridge() { close(); }

bool NativeAccessibilityBridge::open(VSTGUI::CFrame* frame, const std::vector<AccessibilityEntry>& entries) {
    close();
    if (!frame || !frame->getPlatformFrame()) return false;
    auto* native_view = (__bridge NSView*)frame->getPlatformFrame()->getPlatformRepresentation();
    if (!native_view) return false;
    auto next = std::make_unique<Impl>();
    next->root = native_view;
    NSMutableArray<ZigVstguiAccessibilityElement*>* elements =
        [[NSMutableArray alloc] initWithCapacity:entries.size()];
    for (const auto& entry : entries) {
        if (!entry.node || !entry.view) continue;
        auto* element = [[ZigVstguiAccessibilityElement alloc] init];
        element.semanticNode = entry.node;
        element.vstguiView = entry.view;
        element.accessibilityParent = native_view;
        [elements addObject:element];
        auto observer = std::make_unique<MacObserver>();
        observer->node = entry.node;
        observer->element = element;
        entry.node->setObserver(observer.get(), accessibilityChanged);
        next->observers.push_back(std::move(observer));
    }
    next->elements = [elements copy];
    native_view.accessibilityChildren = next->elements;
    NSAccessibilityPostNotification(native_view, NSAccessibilityLayoutChangedNotification);
    impl = std::move(next);
    return true;
}

void NativeAccessibilityBridge::close() {
    if (!impl) return;
    for (const auto& observer : impl->observers) observer->node->setObserver(nullptr, nullptr);
    if (impl->root) {
        impl->root.accessibilityChildren = nil;
        NSAccessibilityPostNotification(impl->root, NSAccessibilityLayoutChangedNotification);
    }
    impl.reset();
}

void NativeAccessibilityBridge::layoutChanged() {
    if (impl && impl->root) NSAccessibilityPostNotification(impl->root, NSAccessibilityLayoutChangedNotification);
}

bool NativeAccessibilityBridge::active() const {
    return impl && impl->root;
}

std::size_t NativeAccessibilityBridge::elementCount() const {
    return impl ? impl->elements.count : 0;
}

}
