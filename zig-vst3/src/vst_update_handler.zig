const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iupdatehandler = @import("pluginterfaces/base/iupdatehandler.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn Dependent(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: iupdatehandler.IDependent = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        last_changed: ?*anyopaque = null,
        last_message: types.int32 = 0,
        update_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *iupdatehandler.IDependent {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *iupdatehandler.IDependent = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iupdatehandler.idependent_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IDependent");
        }

        fn update(ptr: *anyopaque, changed: ?*anyopaque, message: types.int32) callconv(.C) void {
            const self = owner(ptr);
            self.last_changed = changed;
            self.last_message = message;
            self.update_count += 1;
            if (@hasDecl(Config, "update")) {
                Config.update(changed, message);
            }
        }

        const vtable = iupdatehandler.IDependentVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .update = update,
        };
    };
}

pub fn UpdateHandler(comptime max_dependents: usize) type {
    if (max_dependents == 0) @compileError("UpdateHandler requires at least one dependent slot");

    return extern struct {
        const Self = @This();

        const Entry = extern struct {
            changed: ?*anyopaque = null,
            dependent: ?*iupdatehandler.IDependent = null,
            deferred: bool = false,
            deferred_message: types.int32 = 0,
        };

        iface: iupdatehandler.IUpdateHandler = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        entries: [max_dependents]Entry = [_]Entry{.{}} ** max_dependents,

        pub fn asInterface(self: *Self) *iupdatehandler.IUpdateHandler {
            return &self.iface;
        }

        pub fn dependentCount(self: *const Self) usize {
            var count: usize = 0;
            for (&self.entries) |*entry| {
                if (entry.dependent != null) count += 1;
            }
            return count;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *iupdatehandler.IUpdateHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn findEntry(self: *Self, changed: ?*anyopaque, dependent: ?*iupdatehandler.IDependent) ?*Entry {
            for (&self.entries) |*entry| {
                if (entry.changed == changed and entry.dependent == dependent) return entry;
            }
            return null;
        }

        fn slotFor(self: *Self, changed: ?*anyopaque, dependent: ?*iupdatehandler.IDependent) ?*Entry {
            if (self.findEntry(changed, dependent)) |entry| return entry;
            for (&self.entries) |*entry| {
                if (entry.dependent == null) {
                    entry.changed = changed;
                    entry.dependent = dependent;
                    return entry;
                }
            }
            return null;
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries_for_query = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iupdatehandler.iupdate_handler_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries_for_query, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IUpdateHandler");
        }

        fn addDependent(ptr: *anyopaque, changed: ?*anyopaque, dependent: ?*iupdatehandler.IDependent) callconv(.C) types.tresult {
            const dep = dependent orelse return types.kInvalidArgument;
            const self = owner(ptr);
            if (self.findEntry(changed, dep) != null) return types.kResultOk;
            _ = self.slotFor(changed, dep) orelse return types.kResultFalse;
            _ = dep.vtable.addRef(dep);
            return types.kResultOk;
        }

        fn removeDependent(ptr: *anyopaque, changed: ?*anyopaque, dependent: ?*iupdatehandler.IDependent) callconv(.C) types.tresult {
            const dep = dependent orelse return types.kInvalidArgument;
            const entry = owner(ptr).findEntry(changed, dep) orelse return types.kResultFalse;
            entry.* = .{};
            _ = dep.vtable.release(dep);
            return types.kResultOk;
        }

        fn triggerUpdates(ptr: *anyopaque, changed: ?*anyopaque, message: types.int32) callconv(.C) types.tresult {
            for (&owner(ptr).entries) |*entry| {
                if (entry.dependent != null and entry.changed == changed) {
                    entry.dependent.?.vtable.update(entry.dependent.?, changed, message);
                    entry.deferred = false;
                    entry.deferred_message = 0;
                }
            }
            return types.kResultOk;
        }

        fn deferUpdates(ptr: *anyopaque, changed: ?*anyopaque, message: types.int32) callconv(.C) types.tresult {
            var matched = false;
            for (&owner(ptr).entries) |*entry| {
                if (entry.dependent != null and entry.changed == changed) {
                    entry.deferred = true;
                    entry.deferred_message = message;
                    matched = true;
                }
            }
            return if (matched) types.kResultOk else types.kResultFalse;
        }

        const vtable = iupdatehandler.IUpdateHandlerVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .addDependent = addDependent,
            .removeDependent = removeDependent,
            .triggerUpdates = triggerUpdates,
            .deferUpdates = deferUpdates,
        };
    };
}

test "update handler registers triggers and removes dependents" {
    const Handler = UpdateHandler(2);
    const Dep = Dependent(struct {});
    var handler = Handler{};
    var dependent = Dep{};
    var changed: u32 = 1;
    const iface = handler.asInterface();
    const dep_iface = dependent.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addDependent(iface, &changed, dep_iface));
    try std.testing.expectEqual(@as(usize, 1), handler.dependentCount());
    try std.testing.expectEqual(@as(types.uint32, 2), dependent.ref_count.load(.monotonic));

    try std.testing.expectEqual(types.kResultOk, iface.vtable.triggerUpdates(iface, &changed, @intFromEnum(iupdatehandler.ChangeMessage.kChanged)));
    try std.testing.expectEqual(@as(types.uint32, 1), dependent.update_count);
    try std.testing.expectEqual(@intFromEnum(iupdatehandler.ChangeMessage.kChanged), dependent.last_message);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.removeDependent(iface, &changed, dep_iface));
    try std.testing.expectEqual(@as(usize, 0), handler.dependentCount());
    try std.testing.expectEqual(@as(types.uint32, 1), dependent.ref_count.load(.monotonic));
}

test "update handler records deferred updates" {
    const Handler = UpdateHandler(1);
    const Dep = Dependent(struct {});
    var handler = Handler{};
    var dependent = Dep{};
    const iface = handler.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addDependent(iface, null, dependent.asInterface()));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.deferUpdates(iface, null, 123));
    try std.testing.expect(handler.entries[0].deferred);
    try std.testing.expectEqual(@as(types.int32, 123), handler.entries[0].deferred_message);
}

test "update handler rejects invalid dependents and full storage without retaining" {
    const Handler = UpdateHandler(1);
    const Dep = Dependent(struct {});
    var handler = Handler{};
    var first = Dep{};
    var rejected = Dep{};
    const iface = handler.asInterface();

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.addDependent(iface, null, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addDependent(iface, null, first.asInterface()));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addDependent(iface, null, first.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), first.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addDependent(iface, null, rejected.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), rejected.ref_count.load(.monotonic));

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.removeDependent(iface, null, null));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.removeDependent(iface, null, rejected.asInterface()));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.deferUpdates(iface, @ptrFromInt(0x1000), 1));
}

test "update handler supports query interface" {
    const Handler = UpdateHandler(1);
    var handler = Handler{};
    const iface = handler.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iupdatehandler.iupdate_handler_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_handler: *iupdatehandler.IUpdateHandler = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_handler.vtable.release(queried_handler));
}
