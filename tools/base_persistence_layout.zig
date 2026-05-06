const std = @import("std");
const base = @import("vst3-zig").pluginterfaces.base;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("FVariant.kEmpty {}\n", .{base.fvariant.FVariant.kEmpty});
    try stdout.print("FVariant.kInteger {}\n", .{base.fvariant.FVariant.kInteger});
    try stdout.print("FVariant.kFloat {}\n", .{base.fvariant.FVariant.kFloat});
    try stdout.print("FVariant.kString8 {}\n", .{base.fvariant.FVariant.kString8});
    try stdout.print("FVariant.kObject {}\n", .{base.fvariant.FVariant.kObject});
    try stdout.print("FVariant.kOwner {}\n", .{base.fvariant.FVariant.kOwner});
    try stdout.print("FVariant.kString16 {}\n", .{base.fvariant.FVariant.kString16});
    try printType(stdout, "FVariant", base.fvariant.FVariant);
    try printOffset(stdout, "FVariant", "type", base.fvariant.FVariant, "type");
    try printOffset(stdout, "FVariant", "intValue", base.fvariant.FVariant, "value");

    try printTuid(stdout, "ICloneable", base.icloneable.icloneable_iid);
    try printTuid(stdout, "IPersistent", base.ipersistent.ipersistent_iid);
    try printTuid(stdout, "IAttributes", base.ipersistent.iattributes_iid);
    try printTuid(stdout, "IAttributes2", base.ipersistent.iattributes2_iid);
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
