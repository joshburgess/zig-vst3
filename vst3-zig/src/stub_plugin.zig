const entry = @import("entry.zig");
const factory = @import("factory.zig");
const tuid = @import("tuid.zig");

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
