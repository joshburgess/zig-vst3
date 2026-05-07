const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

const StubFactory = factory.StaticFactory(.{
    .vendor = "zig-vst3",
    .url = "https://github.com/joshburgess/zig-vst3",
}, &.{
    .{
        .cid = tuid.inlineUid(0xA74E7A0D, 0x6B234163, 0xA0A83EBF, 0xD06F1401),
        .category = "Audio Module Class",
        .name = "zig-vst3 Stub",
    },
});

pub usingnamespace entry.Exports(StubFactory);

test "stub export returns enumerable factory" {
    const plugin_factory = StubFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 1), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Stub", std.mem.sliceTo(&class_info.name, 0));
}
