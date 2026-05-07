const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const stub_component = @import("stub_component.zig");
const stub_controller = @import("stub_controller.zig");
const types = @import("pluginterfaces/base/types.zig");

const StubFactory = factory.StaticFactory(.{
    .vendor = "zig-vst3",
    .url = "https://github.com/joshburgess/zig-vst3",
}, &.{
    .{
        .cid = stub_component.cid,
        .category = "Audio Module Class",
        .name = "zig-vst3 Gain",
        .create = stub_component.create,
    },
    .{
        .cid = stub_controller.cid,
        .category = "Component Controller Class",
        .name = "zig-vst3 Gain Controller",
        .create = stub_controller.create,
    },
});

pub usingnamespace entry.Exports(StubFactory);

test "stub export returns enumerable factory" {
    const plugin_factory = StubFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Gain", std.mem.sliceTo(&class_info.name, 0));
}
