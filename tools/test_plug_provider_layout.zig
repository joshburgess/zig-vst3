const std = @import("std");
const test_provider = @import("vst3-zig").pluginterfaces.vst.ivsttestplugprovider;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printTuid(stdout, "ITestPlugProvider", test_provider.itest_plug_provider_iid);
    try printTuid(stdout, "ITestPlugProvider2", test_provider.itest_plug_provider2_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
