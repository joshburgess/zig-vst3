const std = @import("std");
const wayland = @import("vst3-zig").pluginterfaces.gui.iwaylandframe;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printTuid(stdout, "IWaylandHost", wayland.iwayland_host_iid);
    try printTuid(stdout, "IWaylandFrame", wayland.iwayland_frame_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
