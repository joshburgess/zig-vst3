const std = @import("std");
const representation = @import("vst3-zig").pluginterfaces.vst.ivstrepresentation;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("RepresentationInfo.kNameSize {}\n", .{representation.RepresentationInfo.kNameSize});
    try printType(stdout, "RepresentationInfo", representation.RepresentationInfo);
    try printOffset(stdout, "RepresentationInfo", "vendor", representation.RepresentationInfo, "vendor");
    try printOffset(stdout, "RepresentationInfo", "name", representation.RepresentationInfo, "name");
    try printOffset(stdout, "RepresentationInfo", "version", representation.RepresentationInfo, "version");
    try printOffset(stdout, "RepresentationInfo", "host", representation.RepresentationInfo, "host");

    try stdout.print("LayerType.kKnob {}\n", .{@intFromEnum(representation.LayerType.kKnob)});
    try stdout.print("LayerType.kFader {}\n", .{@intFromEnum(representation.LayerType.kFader)});
    try stdout.print("LayerType.kEndOfLayerType {}\n", .{@intFromEnum(representation.LayerType.kEndOfLayerType)});
    try stdout.print("LayerType.layerTypeFIDString.0 {s}\n", .{representation.LayerType.fidStrings[0].?});
    try stdout.print("LayerType.layerTypeFIDString.7 {s}\n", .{representation.LayerType.fidStrings[7].?});

    try printTuid(stdout, "IXmlRepresentationController", representation.ixml_representation_controller_iid);
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
