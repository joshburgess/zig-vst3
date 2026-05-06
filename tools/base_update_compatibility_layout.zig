const std = @import("std");
const base = @import("vst3-zig").pluginterfaces.base;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("IDependent.kWillChange {}\n", .{@intFromEnum(base.iupdatehandler.ChangeMessage.kWillChange)});
    try stdout.print("IDependent.kChanged {}\n", .{@intFromEnum(base.iupdatehandler.ChangeMessage.kChanged)});
    try stdout.print("IDependent.kDestroyed {}\n", .{@intFromEnum(base.iupdatehandler.ChangeMessage.kDestroyed)});
    try stdout.print("IDependent.kWillDestroy {}\n", .{@intFromEnum(base.iupdatehandler.ChangeMessage.kWillDestroy)});
    try stdout.print("IDependent.kStdChangeMessageLast {}\n", .{@intFromEnum(base.iupdatehandler.kStdChangeMessageLast)});
    try stdout.print("kPluginCompatibilityClass {s}\n", .{base.iplugincompatibility.kPluginCompatibilityClass});

    try printTuid(stdout, "IUpdateHandler", base.iupdatehandler.iupdate_handler_iid);
    try printTuid(stdout, "IDependent", base.iupdatehandler.idependent_iid);
    try printTuid(stdout, "IPluginCompatibility", base.iplugincompatibility.iplugin_compatibility_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
