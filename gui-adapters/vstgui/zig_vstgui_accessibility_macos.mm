#include "zig_vstgui_accessibility_bridge.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include "vstgui/lib/platform/iplatformframe.h"

#include <cstdint>
#include <cstdio>
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

char semantic_node_key;
char vstgui_view_key;

const ZigVstgui::AccessibilityNode* semanticNode(id element) {
    id value = objc_getAssociatedObject(element, &semantic_node_key);
    return value ? static_cast<const ZigVstgui::AccessibilityNode*>([(NSValue*)value pointerValue]) : nullptr;
}

const VSTGUI::CView* vstguiView(id element) {
    id value = objc_getAssociatedObject(element, &vstgui_view_key);
    return value ? static_cast<const VSTGUI::CView*>([(NSValue*)value pointerValue]) : nullptr;
}

BOOL isAccessibilityElement(id self, SEL) {
    const auto* view = vstguiView(self);
    return view && view->isVisible();
}

NSString* accessibilityRole(id self, SEL) {
    const auto* node = semanticNode(self);
    return node ? role(node->role()) : NSAccessibilityGroupRole;
}

NSString* accessibilityLabel(id self, SEL) {
    const auto* node = semanticNode(self);
    return node ? string(node->name()) : @"";
}

NSString* accessibilityHelp(id self, SEL) {
    const auto* node = semanticNode(self);
    if (!node || node->description().empty()) return nil;
    return string(node->description());
}

id accessibilityValue(id self, SEL) {
    const auto* semantic_node = semanticNode(self);
    if (!semantic_node) return nil;
    const auto& node = *semantic_node;
    if (node.role() == ZigVstgui::AccessibilityRole::toggle) return @(node.state().checked);
    if (node.range().present) return @(node.range().current);
    return node.valueText().empty() ? nil : string(node.valueText());
}

NSString* accessibilityValueDescription(id self, SEL) {
    const auto* node = semanticNode(self);
    if (!node || node->valueText().empty()) return nil;
    return string(node->valueText());
}

id accessibilityMinValue(id self, SEL) {
    const auto* node = semanticNode(self);
    if (!node || !node->range().present) return nil;
    return @(node->range().minimum);
}

id accessibilityMaxValue(id self, SEL) {
    const auto* node = semanticNode(self);
    if (!node || !node->range().present) return nil;
    return @(node->range().maximum);
}

BOOL isAccessibilityEnabled(id self, SEL) {
    const auto* node = semanticNode(self);
    return node && node->state().enabled;
}

BOOL isAccessibilityFocused(id self, SEL) {
    const auto* node = semanticNode(self);
    return node && node->state().focused;
}

void setAccessibilityFocused(id self, SEL, BOOL focused) {
    const auto* node = semanticNode(self);
    if (focused && node) {
        node->perform(ZigVstgui::AccessibilityAction::focus);
    }
}

BOOL accessibilityPerformPress(id self, SEL) {
    const auto* node = semanticNode(self);
    return node && node->perform(ZigVstgui::AccessibilityAction::press);
}

BOOL accessibilityPerformIncrement(id self, SEL) {
    const auto* node = semanticNode(self);
    return node && node->perform(ZigVstgui::AccessibilityAction::increment);
}

BOOL accessibilityPerformDecrement(id self, SEL) {
    const auto* node = semanticNode(self);
    return node && node->perform(ZigVstgui::AccessibilityAction::decrement);
}

void setAccessibilityValue(id self, SEL, id value) {
    const auto* node = semanticNode(self);
    if (!node || !value) return;
    if ([value isKindOfClass:[NSNumber class]]) {
        node->perform(
            ZigVstgui::AccessibilityAction::set_value,
            [value doubleValue]
        );
        return;
    }
    if ([value isKindOfClass:[NSString class]]) {
        node->perform(
            ZigVstgui::AccessibilityAction::set_value,
            0.0,
            [(NSString*)value UTF8String]
        );
    }
}

NSRect accessibilityFrameInParentSpace(id self, SEL) {
    const auto* view = vstguiView(self);
    if (!view) return NSZeroRect;
    const auto size = view->getViewSize();
    VSTGUI::CRect bounds(0.0, 0.0, size.getWidth(), size.getHeight());
    view->translateToGlobal(bounds, true);
    return NSMakeRect(bounds.left, bounds.top, bounds.getWidth(), bounds.getHeight());
}

void addOverride(Class target, SEL selector, IMP implementation) {
    const auto inherited = class_getInstanceMethod([NSAccessibilityElement class], selector);
    if (inherited) class_addMethod(target, selector, implementation, method_getTypeEncoding(inherited));
}

Class accessibilityElementClass() {
    static Class element_class = [] {
        char name[80] {};
        std::snprintf(
            name,
            sizeof(name),
            "ZigVstguiAccessibilityElement_%llx",
            static_cast<unsigned long long>(reinterpret_cast<std::uintptr_t>(&accessibilityElementClass))
        );
        Class dynamic_class = objc_allocateClassPair([NSAccessibilityElement class], name, 0);
        if (!dynamic_class) return objc_getClass(name);
        addOverride(dynamic_class, @selector(isAccessibilityElement), reinterpret_cast<IMP>(&isAccessibilityElement));
        addOverride(dynamic_class, @selector(accessibilityRole), reinterpret_cast<IMP>(&accessibilityRole));
        addOverride(dynamic_class, @selector(accessibilityLabel), reinterpret_cast<IMP>(&accessibilityLabel));
        addOverride(dynamic_class, @selector(accessibilityHelp), reinterpret_cast<IMP>(&accessibilityHelp));
        addOverride(dynamic_class, @selector(accessibilityValue), reinterpret_cast<IMP>(&accessibilityValue));
        addOverride(dynamic_class, @selector(accessibilityValueDescription), reinterpret_cast<IMP>(&accessibilityValueDescription));
        addOverride(dynamic_class, @selector(accessibilityMinValue), reinterpret_cast<IMP>(&accessibilityMinValue));
        addOverride(dynamic_class, @selector(accessibilityMaxValue), reinterpret_cast<IMP>(&accessibilityMaxValue));
        addOverride(dynamic_class, @selector(isAccessibilityEnabled), reinterpret_cast<IMP>(&isAccessibilityEnabled));
        addOverride(dynamic_class, @selector(isAccessibilityFocused), reinterpret_cast<IMP>(&isAccessibilityFocused));
        addOverride(dynamic_class, @selector(setAccessibilityFocused:), reinterpret_cast<IMP>(&setAccessibilityFocused));
        addOverride(dynamic_class, @selector(accessibilityPerformPress), reinterpret_cast<IMP>(&accessibilityPerformPress));
        addOverride(dynamic_class, @selector(accessibilityPerformIncrement), reinterpret_cast<IMP>(&accessibilityPerformIncrement));
        addOverride(dynamic_class, @selector(accessibilityPerformDecrement), reinterpret_cast<IMP>(&accessibilityPerformDecrement));
        addOverride(dynamic_class, @selector(setAccessibilityValue:), reinterpret_cast<IMP>(&setAccessibilityValue));
        addOverride(dynamic_class, @selector(accessibilityFrameInParentSpace), reinterpret_cast<IMP>(&accessibilityFrameInParentSpace));
        objc_registerClassPair(dynamic_class);
        return dynamic_class;
    }();
    return element_class;
}

NSAccessibilityElement* makeAccessibilityElement(
    const ZigVstgui::AccessibilityNode* node,
    const VSTGUI::CView* view
) {
    NSAccessibilityElement* element = [[accessibilityElementClass() alloc] init];
    objc_setAssociatedObject(
        element,
        &semantic_node_key,
        [NSValue valueWithPointer:node],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        element,
        &vstgui_view_key,
        [NSValue valueWithPointer:view],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    return element;
}

}

namespace ZigVstgui {

struct MacObserver {
    const AccessibilityNode* node {nullptr};
    __weak NSAccessibilityElement* element {nil};
};

void accessibilityChanged(void* userdata, AccessibilityChange change) {
    auto* observer = static_cast<MacObserver*>(userdata);
    auto* element = observer ? observer->element : nil;
    if (!element) return;
    if (change == AccessibilityChange::text_caret ||
        change == AccessibilityChange::text_selection) return;
    NSString* notification = NSAccessibilityValueChangedNotification;
    if (change == AccessibilityChange::focus) notification = NSAccessibilityFocusedUIElementChangedNotification;
    if (change == AccessibilityChange::role || change == AccessibilityChange::name ||
        change == AccessibilityChange::description) notification = NSAccessibilityLayoutChangedNotification;
    NSAccessibilityPostNotification(element, notification);
}

class NativeAccessibilityBridge::Impl {
public:
    NSView* root {nil};
    NSArray<NSAccessibilityElement*>* elements {nil};
    std::vector<std::unique_ptr<MacObserver>> observers;
};

NativeAccessibilityBridge::NativeAccessibilityBridge() = default;
NativeAccessibilityBridge::~NativeAccessibilityBridge() { close(); }

bool NativeAccessibilityBridge::open(
    VSTGUI::CFrame* frame,
    const std::vector<AccessibilityEntry>& entries,
    std::shared_ptr<AccessibilityClipboard>
) {
    close();
    if (!frame || !frame->getPlatformFrame()) return false;
    auto* native_view = (__bridge NSView*)frame->getPlatformFrame()->getPlatformRepresentation();
    if (!native_view) return false;
    auto next = std::make_unique<Impl>();
    next->root = native_view;
    NSMutableArray<NSAccessibilityElement*>* elements =
        [[NSMutableArray alloc] initWithCapacity:entries.size()];
    for (const auto& entry : entries) {
        if (!entry.node || !entry.view) continue;
        auto* element = makeAccessibilityElement(entry.node, entry.view);
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

void NativeAccessibilityBridge::dispatch() {}

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
