const std = @import("std");
const fixed_string = @import("fixed_string.zig");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const vst_index = @import("vst_index.zig");

pub fn ContextMenuTarget(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstcontextmenu.IContextMenuTarget = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        last_tag: types.int32 = 0,
        execute_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *ivstcontextmenu.IContextMenuTarget {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, ivstcontextmenu.IContextMenuTarget, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstcontextmenu.icontext_menu_target_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IContextMenuTarget");
        }

        fn executeMenuItem(ptr: *anyopaque, tag: types.int32) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.last_tag = tag;
            self.execute_count +|= 1;
            if (@hasDecl(Config, "executeMenuItem")) {
                return Config.executeMenuItem(tag);
            }
            return types.kResultOk;
        }

        const vtable = ivstcontextmenu.IContextMenuTargetVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .executeMenuItem = executeMenuItem,
        };
    };
}

pub fn ContextMenu(comptime max_items: usize) type {
    if (max_items == 0) @compileError("ContextMenu requires at least one item slot");
    vst_index.requireInt32Capacity(max_items, "ContextMenu item count");

    return extern struct {
        const Self = @This();

        const Entry = extern struct {
            occupied: bool = false,
            item: ivstcontextmenu.IContextMenuItem = .{},
            target: ?*ivstcontextmenu.IContextMenuTarget = null,

            fn isOccupied(self: Entry) bool {
                return self.occupied;
            }

            fn matches(self: Entry, item: *const ivstcontextmenu.IContextMenuItem, target: ?*ivstcontextmenu.IContextMenuTarget) bool {
                return self.isOccupied() and itemsEqual(self.item, item.*) and self.target == target;
            }

            fn set(self: *Entry, item: *const ivstcontextmenu.IContextMenuItem, target: ?*ivstcontextmenu.IContextMenuTarget) void {
                self.occupied = true;
                self.item = item.*;
                self.target = target;
                if (target) |value| _ = value.vtable.addRef(value);
            }

            fn clear(self: *Entry) void {
                if (self.target) |value| _ = value.vtable.release(value);
                self.* = .{};
            }
        };

        iface: ivstcontextmenu.IContextMenu = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        entries: [max_items]Entry = [_]Entry{.{}} ** max_items,
        popup_count: types.uint32 = 0,
        last_x: types.UCoord = 0,
        last_y: types.UCoord = 0,

        pub fn asInterface(self: *Self) *ivstcontextmenu.IContextMenu {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, ivstcontextmenu.IContextMenu, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries_for_query = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstcontextmenu.icontext_menu_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries_for_query, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IContextMenu");
        }

        fn getItemCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(owner(ptr).occupiedCount());
        }

        pub fn occupiedCount(self: *const Self) usize {
            var count: usize = 0;
            for (&self.entries) |*entry| {
                if (entry.isOccupied()) count += 1;
            }
            return count;
        }

        pub fn occupiedByIndex(self: *Self, index: types.int32) ?*Entry {
            if (index < 0) return null;
            const wanted_index: usize = @intCast(index);
            var current: usize = 0;
            for (&self.entries) |*entry| {
                if (entry.isOccupied()) {
                    if (current == wanted_index) return entry;
                    current += 1;
                }
            }
            return null;
        }

        fn failItemLookup(out: *ivstcontextmenu.IContextMenuItem, target_out: *?*ivstcontextmenu.IContextMenuTarget) types.tresult {
            out.* = .{};
            target_out.* = null;
            return types.kInvalidArgument;
        }

        fn getItem(ptr: *anyopaque, index: types.int32, out: *ivstcontextmenu.IContextMenuItem, target_out: *?*ivstcontextmenu.IContextMenuTarget) callconv(.c) types.tresult {
            const entry = owner(ptr).occupiedByIndex(index) orelse return failItemLookup(out, target_out);
            out.* = entry.item;
            target_out.* = entry.target;
            if (entry.target) |target| _ = target.vtable.addRef(target);
            return types.kResultOk;
        }

        fn appendItem(self: *Self, item: *const ivstcontextmenu.IContextMenuItem, target: ?*ivstcontextmenu.IContextMenuTarget) ?*Entry {
            for (&self.entries) |*entry| {
                if (!entry.isOccupied()) {
                    entry.set(item, target);
                    return entry;
                }
            }
            return null;
        }

        fn addItem(ptr: *anyopaque, item: *const ivstcontextmenu.IContextMenuItem, target: ?*ivstcontextmenu.IContextMenuTarget) callconv(.c) types.tresult {
            _ = owner(ptr).appendItem(item, target) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn itemsEqual(a: ivstcontextmenu.IContextMenuItem, b: ivstcontextmenu.IContextMenuItem) bool {
            return a.tag == b.tag and
                a.flags == b.flags and
                std.mem.eql(vsttypes.TChar, std.mem.sliceTo(&a.name, 0), std.mem.sliceTo(&b.name, 0));
        }

        fn matchingItem(self: *Self, item: *const ivstcontextmenu.IContextMenuItem, target: ?*ivstcontextmenu.IContextMenuTarget) ?*Entry {
            for (&self.entries) |*entry| {
                if (entry.matches(item, target)) return entry;
            }
            return null;
        }

        fn removeItem(ptr: *anyopaque, item: *const ivstcontextmenu.IContextMenuItem, target: ?*ivstcontextmenu.IContextMenuTarget) callconv(.c) types.tresult {
            const entry = owner(ptr).matchingItem(item, target) orelse return types.kResultFalse;
            entry.clear();
            return types.kResultOk;
        }

        fn popup(ptr: *anyopaque, x: types.UCoord, y: types.UCoord) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.popup_count +|= 1;
            self.last_x = x;
            self.last_y = y;
            return types.kResultOk;
        }

        const vtable = ivstcontextmenu.IContextMenuVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getItemCount = getItemCount,
            .getItem = getItem,
            .addItem = addItem,
            .removeItem = removeItem,
            .popup = popup,
        };
    };
}

test "context menu target stores executed tags" {
    const Target = ContextMenuTarget(struct {});
    var target = Target{};
    const iface = target.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.executeMenuItem(iface, 42));
    try std.testing.expectEqual(@as(types.int32, 42), target.last_tag);
    try std.testing.expectEqual(@as(types.uint32, 1), target.execute_count);
}

test "context menu target delegates execution and supports query interface" {
    const Target = ContextMenuTarget(struct {
        pub fn executeMenuItem(tag: types.int32) types.tresult {
            return if (tag == 7) types.kResultOk else types.kResultFalse;
        }
    });
    var target = Target{};
    const iface = target.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.executeMenuItem(iface, 3));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.executeMenuItem(iface, 7));
    try std.testing.expectEqual(@as(types.uint32, 2), target.execute_count);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstcontextmenu.icontext_menu_target_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_target: *ivstcontextmenu.IContextMenuTarget = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_target.vtable.release(queried_target));
}

test "context menu target clears unsupported query output" {
    const Target = ContextMenuTarget(struct {});
    var target = Target{};
    const iface = target.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "context menu stores items and retains targets" {
    const Menu = ContextMenu(2);
    const Target = ContextMenuTarget(struct {});
    var menu = Menu{};
    var target = Target{};
    const iface = menu.asInterface();
    const target_iface = target.asInterface();
    var item = ivstcontextmenu.IContextMenuItem{ .tag = 7 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &item, target_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), target.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getItemCount(iface));

    var out_item: ivstcontextmenu.IContextMenuItem = .{};
    var out_target: ?*ivstcontextmenu.IContextMenuTarget = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getItem(iface, 0, &out_item, &out_target));
    try std.testing.expectEqual(@as(types.int32, 7), out_item.tag);
    try std.testing.expect(out_target != null);
    try std.testing.expectEqual(@as(types.uint32, 3), target.ref_count.load(.monotonic));
    _ = out_target.?.vtable.release(out_target.?);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.removeItem(iface, &item, target_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), target.ref_count.load(.monotonic));
}

test "context menu clears failed item lookups and rejects full storage" {
    const Menu = ContextMenu(1);
    const Target = ContextMenuTarget(struct {});
    var menu = Menu{};
    var first = Target{};
    var second = Target{};
    const iface = menu.asInterface();
    var item = ivstcontextmenu.IContextMenuItem{ .tag = 7 };
    var extra = ivstcontextmenu.IContextMenuItem{ .tag = 8 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &item, first.asInterface()));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addItem(iface, &extra, second.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), second.ref_count.load(.monotonic));

    var out_item = ivstcontextmenu.IContextMenuItem{ .tag = 99 };
    var out_target: ?*ivstcontextmenu.IContextMenuTarget = second.asInterface();
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getItem(iface, 1, &out_item, &out_target));
    try std.testing.expectEqual(@as(types.int32, 0), out_item.tag);
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenuTarget, null), out_target);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.removeItem(iface, &extra, first.asInterface()));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.removeItem(iface, &item, first.asInterface()));
    try std.testing.expect(!menu.entries[0].occupied);
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenuTarget, null), menu.entries[0].target);
    try std.testing.expectEqual(@as(types.int32, 0), menu.entries[0].item.tag);
}

test "context menu indexes only occupied slots and reuses removed storage" {
    const Menu = ContextMenu(3);
    var menu = Menu{};
    const iface = menu.asInterface();
    var first = ivstcontextmenu.IContextMenuItem{ .tag = 10 };
    var second = ivstcontextmenu.IContextMenuItem{ .tag = 20 };
    var third = ivstcontextmenu.IContextMenuItem{ .tag = 30 };
    var replacement = ivstcontextmenu.IContextMenuItem{ .tag = 40 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &first, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &second, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &third, null));
    try std.testing.expectEqual(@as(usize, 3), menu.occupiedCount());
    try std.testing.expectEqual(types.kResultOk, iface.vtable.removeItem(iface, &second, null));
    try std.testing.expectEqual(@as(usize, 2), menu.occupiedCount());
    try std.testing.expectEqual(@as(types.int32, 2), iface.vtable.getItemCount(iface));
    try std.testing.expectEqual(@as(types.int32, 10), menu.occupiedByIndex(0).?.item.tag);
    try std.testing.expectEqual(@as(types.int32, 30), menu.occupiedByIndex(1).?.item.tag);
    try std.testing.expect(menu.occupiedByIndex(2) == null);

    var out_item: ivstcontextmenu.IContextMenuItem = .{};
    var out_target: ?*ivstcontextmenu.IContextMenuTarget = undefined;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getItem(iface, 0, &out_item, &out_target));
    try std.testing.expectEqual(@as(types.int32, 10), out_item.tag);
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenuTarget, null), out_target);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getItem(iface, 1, &out_item, &out_target));
    try std.testing.expectEqual(@as(types.int32, 30), out_item.tag);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &replacement, null));
    try std.testing.expectEqual(@as(types.int32, 3), iface.vtable.getItemCount(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getItem(iface, 1, &out_item, &out_target));
    try std.testing.expectEqual(@as(types.int32, 40), out_item.tag);
}

test "context menu removal matches the full item payload" {
    const Menu = ContextMenu(2);
    var menu = Menu{};
    const iface = menu.asInterface();
    var first = ivstcontextmenu.IContextMenuItem{
        .tag = 10,
        .flags = ivstcontextmenu.IContextMenuItem.Flags.kIsChecked,
    };
    var second = ivstcontextmenu.IContextMenuItem{
        .tag = 10,
        .flags = ivstcontextmenu.IContextMenuItem.Flags.kIsDisabled,
    };
    fixed_string.copyAsciiToUtf16Z(&first.name, "first");
    fixed_string.copyAsciiToUtf16Z(&second.name, "second");

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &first, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &second, null));

    var mismatched = first;
    mismatched.flags = second.flags;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.removeItem(iface, &mismatched, null));
    try std.testing.expectEqual(@as(types.int32, 2), iface.vtable.getItemCount(iface));

    try std.testing.expectEqual(types.kResultOk, iface.vtable.removeItem(iface, &second, null));
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getItemCount(iface));
    try std.testing.expectEqual(@as(types.int32, 10), menu.occupiedByIndex(0).?.item.tag);
    try std.testing.expectEqual(ivstcontextmenu.IContextMenuItem.Flags.kIsChecked, menu.occupiedByIndex(0).?.item.flags);
}

test "context menu rejects negative item indexes without touching retained targets" {
    const Menu = ContextMenu(1);
    const Target = ContextMenuTarget(struct {});
    var menu = Menu{};
    var target = Target{};
    const iface = menu.asInterface();
    var item = ivstcontextmenu.IContextMenuItem{ .tag = 7 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addItem(iface, &item, target.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), target.ref_count.load(.monotonic));

    var out_item = ivstcontextmenu.IContextMenuItem{ .tag = 99 };
    var out_target: ?*ivstcontextmenu.IContextMenuTarget = target.asInterface();
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getItem(iface, -1, &out_item, &out_target));
    try std.testing.expectEqual(@as(types.int32, 0), out_item.tag);
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenuTarget, null), out_target);
    try std.testing.expectEqual(@as(types.uint32, 2), target.ref_count.load(.monotonic));
}

test "context menu records popup coordinates and supports query interface" {
    const Menu = ContextMenu(1);
    var menu = Menu{};
    const iface = menu.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.popup(iface, 12, 34));
    try std.testing.expectEqual(@as(types.uint32, 1), menu.popup_count);
    try std.testing.expectEqual(@as(types.UCoord, 12), menu.last_x);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstcontextmenu.icontext_menu_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_menu: *ivstcontextmenu.IContextMenu = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_menu.vtable.release(queried_menu));
}

test "context menu clears unsupported query output" {
    const Menu = ContextMenu(1);
    var menu = Menu{};
    const iface = menu.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
