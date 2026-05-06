const std = @import("std");
const context_menu = @import("vst3-zig").pluginterfaces.vst.ivstcontextmenu;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("IContextMenuItem.kIsSeparator {}\n", .{context_menu.IContextMenuItem.Flags.kIsSeparator});
    try stdout.print("IContextMenuItem.kIsDisabled {}\n", .{context_menu.IContextMenuItem.Flags.kIsDisabled});
    try stdout.print("IContextMenuItem.kIsChecked {}\n", .{context_menu.IContextMenuItem.Flags.kIsChecked});
    try stdout.print("IContextMenuItem.kIsGroupStart {}\n", .{context_menu.IContextMenuItem.Flags.kIsGroupStart});
    try stdout.print("IContextMenuItem.kIsGroupEnd {}\n", .{context_menu.IContextMenuItem.Flags.kIsGroupEnd});

    try printType(stdout, "IContextMenuItem", context_menu.IContextMenuItem);
    try printOffset(stdout, "IContextMenuItem", "name", context_menu.IContextMenuItem, "name");
    try printOffset(stdout, "IContextMenuItem", "tag", context_menu.IContextMenuItem, "tag");
    try printOffset(stdout, "IContextMenuItem", "flags", context_menu.IContextMenuItem, "flags");

    try printType(stdout, "IComponentHandler3", context_menu.IComponentHandler3);
    try printType(stdout, "IContextMenuTarget", context_menu.IContextMenuTarget);
    try printType(stdout, "IContextMenu", context_menu.IContextMenu);
    try printTuid(stdout, "IComponentHandler3", context_menu.icomponent_handler3_iid);
    try printTuid(stdout, "IContextMenuTarget", context_menu.icontext_menu_target_iid);
    try printTuid(stdout, "IContextMenu", context_menu.icontext_menu_iid);
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
