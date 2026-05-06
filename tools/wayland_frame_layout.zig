const std = @import("std");
const wayland = @import("vst3-zig").pluginterfaces.gui.iwaylandframe;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printType(stdout, "IWaylandHost", wayland.IWaylandHost);
    try printType(stdout, "IWaylandFrame", wayland.IWaylandFrame);

    try printTuid(stdout, "IWaylandHost", wayland.iwayland_host_iid);
    try printTuid(stdout, "IWaylandFrame", wayland.iwayland_frame_iid);
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
