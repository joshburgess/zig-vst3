const entry = @import("entry.zig");
const event_monitor_component = @import("event_monitor_component.zig");
const event_monitor_controller = @import("event_monitor_controller.zig");
const event_monitor_spec = @import("event_monitor_spec.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const EventMonitorFactory = factory.StaticFactory3(.{
    .vendor = event_monitor_spec.Spec.vendor,
    .url = event_monitor_spec.Spec.url,
    .email = event_monitor_spec.Spec.email,
}, &.{
    .{
        .cid = event_monitor_component.cid,
        .category = event_monitor_spec.Spec.component_category,
        .name = event_monitor_spec.component_class_name,
        .create = event_monitor_component.create,
    },
    .{
        .cid = event_monitor_controller.cid,
        .category = event_monitor_spec.Spec.controller_category,
        .name = event_monitor_spec.controller_class_name,
        .create = event_monitor_controller.create,
    },
});

pub usingnamespace entry.Exports(EventMonitorFactory);

test "event monitor export returns enumerable factory" {
    const plugin_factory = EventMonitorFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Event Monitor", std.mem.sliceTo(&class_info.name, 0));
}

test "event monitor plugin root exposes zig-plug metadata" {
    try std.testing.expectEqualStrings("zig-vst3 Event Monitor", event_monitor_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Event Monitor Controller", event_monitor_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", event_monitor_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), event_monitor_spec.Spec.ParameterSet.count);
}
