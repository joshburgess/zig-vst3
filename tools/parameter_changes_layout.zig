const std = @import("std");
const parameter_changes = @import("vst3-zig").pluginterfaces.vst.ivstparameterchanges;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printTuid(stdout, "IParamValueQueue", parameter_changes.iparam_value_queue_iid);
    try printTuid(stdout, "IParameterChanges", parameter_changes.iparameter_changes_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
