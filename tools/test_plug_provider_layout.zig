const std = @import("std");
const test_provider = @import("zig-vst3").pluginterfaces.vst.ivsttestplugprovider;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try printType(stdout, "ITestPlugProvider", test_provider.ITestPlugProvider);
    try printType(stdout, "ITestPlugProvider2", test_provider.ITestPlugProvider2);

    try printTuid(stdout, "ITestPlugProvider", test_provider.itest_plug_provider_iid);
    try printTuid(stdout, "ITestPlugProvider2", test_provider.itest_plug_provider2_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
