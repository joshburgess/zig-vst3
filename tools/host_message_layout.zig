const std = @import("std");
const attributes = @import("vst3-zig").pluginterfaces.vst.ivstattributes;
const host = @import("vst3-zig").pluginterfaces.vst.ivsthostapplication;
const message = @import("vst3-zig").pluginterfaces.vst.ivstmessage;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printType(stdout, "IAttributeList", attributes.IAttributeList);
    try printType(stdout, "IStreamAttributes", attributes.IStreamAttributes);
    try printType(stdout, "IMessage", message.IMessage);
    try printType(stdout, "IConnectionPoint", message.IConnectionPoint);
    try printType(stdout, "IHostApplication", host.IHostApplication);
    try printType(stdout, "IVst3ToVst2Wrapper", host.IVst3ToVst2Wrapper);
    try printType(stdout, "IVst3ToAUWrapper", host.IVst3ToAUWrapper);
    try printType(stdout, "IVst3ToAAXWrapper", host.IVst3ToAAXWrapper);
    try printType(stdout, "IVst3WrapperMPESupport", host.IVst3WrapperMPESupport);

    try printTuid(stdout, "IAttributeList", attributes.iattribute_list_iid);
    try printTuid(stdout, "IStreamAttributes", attributes.istream_attributes_iid);
    try printTuid(stdout, "IMessage", message.imessage_iid);
    try printTuid(stdout, "IConnectionPoint", message.iconnection_point_iid);
    try printTuid(stdout, "IHostApplication", host.ihost_application_iid);
    try printTuid(stdout, "IVst3ToVst2Wrapper", host.ivst3_to_vst2_wrapper_iid);
    try printTuid(stdout, "IVst3ToAUWrapper", host.ivst3_to_au_wrapper_iid);
    try printTuid(stdout, "IVst3ToAAXWrapper", host.ivst3_to_aax_wrapper_iid);
    try printTuid(stdout, "IVst3WrapperMPESupport", host.ivst3_wrapper_mpe_support_iid);
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
