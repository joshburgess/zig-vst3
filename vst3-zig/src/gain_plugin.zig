const entry = @import("entry.zig");
const factory = @import("factory.zig");
const gain_component = @import("gain_component.zig");
const gain_controller = @import("gain_controller.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const StubFactory = factory.StaticFactory(.{
    .vendor = "zig-vst3",
    .url = "https://github.com/joshburgess/zig-vst3",
}, &.{
    .{
        .cid = gain_component.cid,
        .category = "Audio Module Class",
        .name = "zig-vst3 Gain",
        .create = gain_component.create,
    },
    .{
        .cid = gain_controller.cid,
        .category = "Component Controller Class",
        .name = "zig-vst3 Gain Controller",
        .create = gain_controller.create,
    },
});

pub usingnamespace entry.Exports(StubFactory);

test "gain export returns enumerable factory" {
    const plugin_factory = StubFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Gain", std.mem.sliceTo(&class_info.name, 0));
}
