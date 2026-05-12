const std = @import("std");
const base = @import("zig-vst3").pluginterfaces.base;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try printType(stdout, "IStringResult", base.istringresult.IStringResult);
    try printType(stdout, "IString", base.istringresult.IString);
    try printType(stdout, "IErrorContext", base.ierrorcontext.IErrorContext);

    try printTuid(stdout, "IStringResult", base.istringresult.istring_result_iid);
    try printTuid(stdout, "IString", base.istringresult.istring_iid);
    try printTuid(stdout, "IErrorContext", base.ierrorcontext.ierror_context_iid);
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
