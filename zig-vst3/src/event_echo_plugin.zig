const entry = @import("entry.zig");
const event_echo_component = @import("event_echo_component.zig");
const event_echo_controller = @import("event_echo_controller.zig");
const event_echo_spec = @import("event_echo_spec.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const EventEchoFactory = factory.StaticFactory3(.{
    .vendor = event_echo_spec.Spec.vendor,
    .url = event_echo_spec.Spec.url,
    .email = event_echo_spec.Spec.email,
}, &.{
    .{
        .cid = event_echo_component.cid,
        .category = event_echo_spec.Spec.component_category,
        .name = event_echo_spec.component_class_name,
        .create = event_echo_component.create,
    },
    .{
        .cid = event_echo_controller.cid,
        .category = event_echo_spec.Spec.controller_category,
        .name = event_echo_spec.controller_class_name,
        .create = event_echo_controller.create,
    },
});

pub usingnamespace entry.Exports(EventEchoFactory);

test "event echo export returns enumerable factory" {
    const plugin_factory = EventEchoFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Event Echo", std.mem.sliceTo(&class_info.name, 0));
}

test "event echo plugin root exposes zig-vst3-plugin metadata" {
    try std.testing.expectEqualStrings("zig-vst3 Event Echo", event_echo_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Event Echo Controller", event_echo_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", event_echo_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), event_echo_spec.Spec.ParameterSet.count);
}
