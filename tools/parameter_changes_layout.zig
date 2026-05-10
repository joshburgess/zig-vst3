const std = @import("std");
const parameter_changes = @import("zig-vst3").pluginterfaces.vst.ivstparameterchanges;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printType(stdout, "IParamValueQueue", parameter_changes.IParamValueQueue);
    try printType(stdout, "IParameterChanges", parameter_changes.IParameterChanges);

    try printTuid(stdout, "IParamValueQueue", parameter_changes.iparam_value_queue_iid);
    try printTuid(stdout, "IParameterChanges", parameter_changes.iparameter_changes_iid);
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
