const std = @import("std");
const units = @import("zig-vst3").pluginterfaces.vst.ivstunits;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try stdout.print("kRootUnitId {}\n", .{units.kRootUnitId});
    try stdout.print("kNoParentUnitId {}\n", .{units.kNoParentUnitId});
    try stdout.print("kNoProgramListId {}\n", .{units.kNoProgramListId});
    try stdout.print("kAllProgramInvalid {}\n", .{units.kAllProgramInvalid});

    try printType(stdout, "UnitInfo", units.UnitInfo);
    try printOffset(stdout, "UnitInfo", "id", units.UnitInfo, "id");
    try printOffset(stdout, "UnitInfo", "parentUnitId", units.UnitInfo, "parentUnitId");
    try printOffset(stdout, "UnitInfo", "name", units.UnitInfo, "name");
    try printOffset(stdout, "UnitInfo", "programListId", units.UnitInfo, "programListId");

    try printType(stdout, "ProgramListInfo", units.ProgramListInfo);
    try printOffset(stdout, "ProgramListInfo", "id", units.ProgramListInfo, "id");
    try printOffset(stdout, "ProgramListInfo", "name", units.ProgramListInfo, "name");
    try printOffset(stdout, "ProgramListInfo", "programCount", units.ProgramListInfo, "programCount");

    try printType(stdout, "IUnitHandler", units.IUnitHandler);
    try printType(stdout, "IUnitHandler2", units.IUnitHandler2);
    try printType(stdout, "IUnitInfo", units.IUnitInfo);
    try printType(stdout, "IProgramListData", units.IProgramListData);
    try printType(stdout, "IUnitData", units.IUnitData);

    try printTuid(stdout, "IUnitHandler", units.iunit_handler_iid);
    try printTuid(stdout, "IUnitHandler2", units.iunit_handler2_iid);
    try printTuid(stdout, "IUnitInfo", units.iunit_info_iid);
    try printTuid(stdout, "IProgramListData", units.iprogram_list_data_iid);
    try printTuid(stdout, "IUnitData", units.iunit_data_iid);
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
