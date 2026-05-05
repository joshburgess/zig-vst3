const std = @import("std");
const learn = @import("vst3-zig").pluginterfaces.vst.ivstmidilearn;
const mapping2 = @import("vst3-zig").pluginterfaces.vst.ivstmidimapping2;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printType(stdout, "Midi2Controller", mapping2.Midi2Controller);
    try printType(stdout, "Midi2ControllerParamIDAssignment", mapping2.Midi2ControllerParamIDAssignment);
    try printOffset(stdout, "Midi2ControllerParamIDAssignment", "pId", mapping2.Midi2ControllerParamIDAssignment, "pId");
    try printOffset(stdout, "Midi2ControllerParamIDAssignment", "busIndex", mapping2.Midi2ControllerParamIDAssignment, "busIndex");
    try printOffset(stdout, "Midi2ControllerParamIDAssignment", "channel", mapping2.Midi2ControllerParamIDAssignment, "channel");
    try printOffset(stdout, "Midi2ControllerParamIDAssignment", "controller", mapping2.Midi2ControllerParamIDAssignment, "controller");
    try printType(stdout, "Midi2ControllerParamIDAssignmentList", mapping2.Midi2ControllerParamIDAssignmentList);
    try printOffset(stdout, "Midi2ControllerParamIDAssignmentList", "count", mapping2.Midi2ControllerParamIDAssignmentList, "count");
    try printOffset(stdout, "Midi2ControllerParamIDAssignmentList", "map", mapping2.Midi2ControllerParamIDAssignmentList, "map");

    try printType(stdout, "Midi1ControllerParamIDAssignment", mapping2.Midi1ControllerParamIDAssignment);
    try printOffset(stdout, "Midi1ControllerParamIDAssignment", "pId", mapping2.Midi1ControllerParamIDAssignment, "pId");
    try printOffset(stdout, "Midi1ControllerParamIDAssignment", "busIndex", mapping2.Midi1ControllerParamIDAssignment, "busIndex");
    try printOffset(stdout, "Midi1ControllerParamIDAssignment", "channel", mapping2.Midi1ControllerParamIDAssignment, "channel");
    try printOffset(stdout, "Midi1ControllerParamIDAssignment", "controller", mapping2.Midi1ControllerParamIDAssignment, "controller");
    try printType(stdout, "Midi1ControllerParamIDAssignmentList", mapping2.Midi1ControllerParamIDAssignmentList);
    try printOffset(stdout, "Midi1ControllerParamIDAssignmentList", "count", mapping2.Midi1ControllerParamIDAssignmentList, "count");
    try printOffset(stdout, "Midi1ControllerParamIDAssignmentList", "map", mapping2.Midi1ControllerParamIDAssignmentList, "map");

    try printTuid(stdout, "IMidiLearn", learn.imidi_learn_iid);
    try printTuid(stdout, "IMidiMapping2", mapping2.imidi_mapping2_iid);
    try printTuid(stdout, "IMidiLearn2", mapping2.imidi_learn2_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
