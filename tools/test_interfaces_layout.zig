const std = @import("std");
const test_interfaces = @import("vst3-zig").pluginterfaces.@"test".itest;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("kTestClass {s}\n", .{test_interfaces.kTestClass});
    try printTuid(stdout, "ITest", test_interfaces.itest_iid);
    try printTuid(stdout, "ITestResult", test_interfaces.itest_result_iid);
    try printTuid(stdout, "ITestSuite", test_interfaces.itest_suite_iid);
    try printTuid(stdout, "ITestFactory", test_interfaces.itest_factory_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
