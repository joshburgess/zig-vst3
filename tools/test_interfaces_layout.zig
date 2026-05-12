const std = @import("std");
const test_interfaces = @import("zig-vst3").pluginterfaces.@"test".itest;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try stdout.print("kTestClass {s}\n", .{test_interfaces.kTestClass});
    try printType(stdout, "ITest", test_interfaces.ITest);
    try printType(stdout, "ITestResult", test_interfaces.ITestResult);
    try printType(stdout, "ITestSuite", test_interfaces.ITestSuite);
    try printType(stdout, "ITestFactory", test_interfaces.ITestFactory);

    try printTuid(stdout, "ITest", test_interfaces.itest_iid);
    try printTuid(stdout, "ITestResult", test_interfaces.itest_result_iid);
    try printTuid(stdout, "ITestSuite", test_interfaces.itest_suite_iid);
    try printTuid(stdout, "ITestFactory", test_interfaces.itest_factory_iid);
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
