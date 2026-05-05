const std = @import("std");
const tuid = @import("vst3-zig").tuid;

const Entry = struct {
    name: []const u8,
    bytes: tuid.TUID,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const entries = [_]Entry{
        .{ .name = "FUnknown", .bytes = tuid.inlineUid(0x00000000, 0x00000000, 0xC0000000, 0x00000046) },
        .{ .name = "IPluginBase", .bytes = tuid.inlineUid(0x22888DDB, 0x156E45AE, 0x8358B348, 0x08190625) },
        .{ .name = "IComponent", .bytes = tuid.inlineUid(0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802) },
        .{ .name = "IAudioProcessor", .bytes = tuid.inlineUid(0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D) },
        .{ .name = "IEditController", .bytes = tuid.inlineUid(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E) },
    };

    for (entries) |entry| {
        try stdout.print("{s}", .{entry.name});
        for (entry.bytes) |byte| {
            try stdout.print(" {X:0>2}", .{byte});
        }
        try stdout.writeByte('\n');
    }
}
