const std = @import("std");
const base = @import("vst3-zig").pluginterfaces.base;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printTuid(stdout, "IStringResult", base.istringresult.istring_result_iid);
    try printTuid(stdout, "IString", base.istringresult.istring_iid);
    try printTuid(stdout, "IErrorContext", base.ierrorcontext.ierror_context_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
