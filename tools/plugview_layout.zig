const std = @import("std");
const plugview = @import("zig-vst3").pluginterfaces.gui.iplugview;
const scale = @import("zig-vst3").pluginterfaces.gui.iplugviewcontentscalesupport;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Platform.kPlatformTypeHWND {s}\n", .{std.mem.span(plugview.PlatformType.kPlatformTypeHWND)});
    try stdout.print("Platform.kPlatformTypeHIView {s}\n", .{std.mem.span(plugview.PlatformType.kPlatformTypeHIView)});
    try stdout.print("Platform.kPlatformTypeNSView {s}\n", .{std.mem.span(plugview.PlatformType.kPlatformTypeNSView)});
    try stdout.print("Platform.kPlatformTypeUIView {s}\n", .{std.mem.span(plugview.PlatformType.kPlatformTypeUIView)});
    try stdout.print("Platform.kPlatformTypeX11EmbedWindowID {s}\n", .{std.mem.span(plugview.PlatformType.kPlatformTypeX11EmbedWindowID)});
    try stdout.print("Platform.kPlatformTypeWaylandSurfaceID {s}\n", .{std.mem.span(plugview.PlatformType.kPlatformTypeWaylandSurfaceID)});

    try printType(stdout, "ViewRect", plugview.ViewRect);
    try printOffset(stdout, "ViewRect", "left", plugview.ViewRect, "left");
    try printOffset(stdout, "ViewRect", "top", plugview.ViewRect, "top");
    try printOffset(stdout, "ViewRect", "right", plugview.ViewRect, "right");
    try printOffset(stdout, "ViewRect", "bottom", plugview.ViewRect, "bottom");

    try printType(stdout, "IPlugView", plugview.IPlugView);
    try printType(stdout, "IPlugFrame", plugview.IPlugFrame);
    try printType(stdout, "Linux::IEventHandler", plugview.Linux.IEventHandler);
    try printType(stdout, "Linux::ITimerHandler", plugview.Linux.ITimerHandler);
    try printType(stdout, "Linux::IRunLoop", plugview.Linux.IRunLoop);
    try printType(stdout, "IPlugViewContentScaleSupport", scale.IPlugViewContentScaleSupport);

    try printTuid(stdout, "IPlugView", plugview.iplug_view_iid);
    try printTuid(stdout, "IPlugFrame", plugview.iplug_frame_iid);
    try printTuid(stdout, "IEventHandler", plugview.ievent_handler_iid);
    try printTuid(stdout, "ITimerHandler", plugview.itimer_handler_iid);
    try printTuid(stdout, "IRunLoop", plugview.irun_loop_iid);
    try printTuid(stdout, "IPlugViewContentScaleSupport", scale.iplug_view_content_scale_support_iid);
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
