const std = @import("std");
const channel = @import("vst3-zig").pluginterfaces.vst.ivstchannelcontextinfo;
const physical = @import("vst3-zig").pluginterfaces.vst.ivstphysicalui;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("PhysicalUITypeIDs.kPUIXMovement {}\n", .{@intFromEnum(physical.PhysicalUITypeIDs.kPUIXMovement)});
    try stdout.print("PhysicalUITypeIDs.kPUITypeCount {}\n", .{@intFromEnum(physical.PhysicalUITypeIDs.kPUITypeCount)});
    try stdout.print("PhysicalUITypeIDs.kInvalidPUITypeID {}\n", .{@intFromEnum(physical.PhysicalUITypeIDs.kInvalidPUITypeID)});
    try stdout.print("ChannelPluginLocation.kPreVolumeFader {}\n", .{@intFromEnum(channel.ChannelContext.ChannelPluginLocation.kPreVolumeFader)});
    try stdout.print("ChannelPluginLocation.kUsedAsPanner {}\n", .{@intFromEnum(channel.ChannelContext.ChannelPluginLocation.kUsedAsPanner)});
    try stdout.print("ChannelContext.GetBlue {}\n", .{channel.ChannelContext.getBlue(0x11223344)});
    try stdout.print("ChannelContext.GetGreen {}\n", .{channel.ChannelContext.getGreen(0x11223344)});
    try stdout.print("ChannelContext.GetRed {}\n", .{channel.ChannelContext.getRed(0x11223344)});
    try stdout.print("ChannelContext.GetAlpha {}\n", .{channel.ChannelContext.getAlpha(0x11223344)});
    try stdout.print("ChannelContext.kChannelUIDKey {s}\n", .{std.mem.span(channel.ChannelContext.kChannelUIDKey)});
    try stdout.print("ChannelContext.kChannelNameKey {s}\n", .{std.mem.span(channel.ChannelContext.kChannelNameKey)});
    try stdout.print("ChannelContext.kChannelPluginLocationKey {s}\n", .{std.mem.span(channel.ChannelContext.kChannelPluginLocationKey)});

    try printType(stdout, "PhysicalUIMap", physical.PhysicalUIMap);
    try printOffset(stdout, "PhysicalUIMap", "physicalUITypeID", physical.PhysicalUIMap, "physicalUITypeID");
    try printOffset(stdout, "PhysicalUIMap", "noteExpressionTypeID", physical.PhysicalUIMap, "noteExpressionTypeID");
    try printType(stdout, "PhysicalUIMapList", physical.PhysicalUIMapList);
    try printOffset(stdout, "PhysicalUIMapList", "count", physical.PhysicalUIMapList, "count");
    try printOffset(stdout, "PhysicalUIMapList", "map", physical.PhysicalUIMapList, "map");

    try printTuid(stdout, "INoteExpressionPhysicalUIMapping", physical.inote_expression_physical_ui_mapping_iid);
    try printTuid(stdout, "IInfoListener", channel.iinfo_listener_iid);
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
