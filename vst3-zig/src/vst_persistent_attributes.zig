const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const fvariant = @import("pluginterfaces/base/fvariant.zig");
const ipersistent = @import("pluginterfaces/base/ipersistent.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn Attributes(comptime max_entries: usize, comptime max_binary_bytes: usize) type {
    if (max_entries == 0) @compileError("Attributes requires at least one entry");

    return extern struct {
        const Self = @This();

        const Entry = extern struct {
            id: ?ipersistent.IAttrID = null,
            value: fvariant.FVariant = .{},
            queued: bool = false,
            binary: [max_binary_bytes]u8 = [_]u8{0} ** max_binary_bytes,
            binary_size: types.uint32 = 0,
            owns_binary: bool = false,
        };

        iface: ipersistent.IAttributes = .{ .vtable = &attributes_vtable },
        iface2: ipersistent.IAttributes2 = .{ .vtable = &attributes2_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        entries: [max_entries]Entry = [_]Entry{.{}} ** max_entries,

        pub fn asAttributes(self: *Self) *ipersistent.IAttributes {
            return &self.iface;
        }

        pub fn asAttributes2(self: *Self) *ipersistent.IAttributes2 {
            return &self.iface2;
        }

        fn ownerFromAttributes(ptr: *anyopaque) *Self {
            const iface: *ipersistent.IAttributes = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn ownerFromAttributes2(ptr: *anyopaque) *Self {
            const iface: *ipersistent.IAttributes2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface2", iface);
        }

        fn findEntry(self: *Self, id: ipersistent.IAttrID) ?*Entry {
            const wanted = std.mem.span(id);
            for (&self.entries) |*entry| {
                if (entry.id) |existing| {
                    if (std.mem.eql(u8, wanted, std.mem.span(existing))) return entry;
                }
            }
            return null;
        }

        fn slotFor(self: *Self, id: ipersistent.IAttrID) ?*Entry {
            if (self.findEntry(id)) |entry| return entry;
            for (&self.entries) |*entry| {
                if (entry.id == null) {
                    entry.id = id;
                    return entry;
                }
            }
            return null;
        }

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries_for_query = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ipersistent.iattributes_iid, .ptr = &self.iface },
                .{ .iid = &ipersistent.iattributes2_iid, .ptr = &self.iface2 },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, attributesAddRef, &entries_for_query, requested_iid, out);
        }

        fn attributesQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            return ownerFromAttributes(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn attributes2Query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromAttributes2(ptr);
            return self.queryCanonical(&self.iface, requested_iid, out);
        }

        fn attributesAddRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromAttributes(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn attributes2AddRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromAttributes2(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn attributesRelease(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromAttributes(ptr).ref_count, "IAttributes");
        }

        fn attributes2Release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromAttributes2(ptr).ref_count, "IAttributes2");
        }

        fn set(ptr: *anyopaque, id: ipersistent.IAttrID, value: *const fvariant.FVariant) callconv(.C) types.tresult {
            const entry = ownerFromAttributes(ptr).slotFor(id) orelse return types.kResultFalse;
            entry.value = value.*;
            entry.owns_binary = false;
            entry.binary_size = 0;
            return types.kResultOk;
        }

        fn queue(ptr: *anyopaque, id: ipersistent.IAttrID, value: *const fvariant.FVariant) callconv(.C) types.tresult {
            const result = set(ptr, id, value);
            if (result != types.kResultOk) return result;
            ownerFromAttributes(ptr).findEntry(id).?.queued = true;
            return types.kResultOk;
        }

        fn setBinaryData(ptr: *anyopaque, id: ipersistent.IAttrID, data: ?*anyopaque, size: types.uint32, copy: bool) callconv(.C) types.tresult {
            if (size > 0 and data == null) return types.kInvalidArgument;
            const entry = ownerFromAttributes(ptr).slotFor(id) orelse return types.kResultFalse;
            if (copy) {
                if (size > max_binary_bytes) return types.kResultFalse;
                if (size > 0) {
                    const bytes: [*]const u8 = @ptrCast(data.?);
                    @memcpy(entry.binary[0..size], bytes[0..size]);
                }
                entry.value = .{ .type = fvariant.kObject, .value = .{ .object = &entry.binary } };
                entry.binary_size = size;
                entry.owns_binary = true;
            } else {
                entry.value = .{ .type = fvariant.kObject, .value = .{ .object = data } };
                entry.binary_size = size;
                entry.owns_binary = false;
            }
            return types.kResultOk;
        }

        fn get(ptr: *anyopaque, id: ipersistent.IAttrID, out: *fvariant.FVariant) callconv(.C) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse {
                out.* = .{};
                return types.kResultFalse;
            };
            out.* = entry.value;
            return types.kResultOk;
        }

        fn unqueue(ptr: *anyopaque, id: ipersistent.IAttrID, out: *fvariant.FVariant) callconv(.C) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse {
                out.* = .{};
                return types.kResultFalse;
            };
            if (!entry.queued) {
                out.* = .{};
                return types.kResultFalse;
            }
            entry.queued = false;
            out.* = entry.value;
            return types.kResultOk;
        }

        fn getQueueItemCount(ptr: *anyopaque, id: ipersistent.IAttrID) callconv(.C) types.int32 {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return 0;
            return if (entry.queued) 1 else 0;
        }

        fn resetQueue(ptr: *anyopaque, id: ipersistent.IAttrID) callconv(.C) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return types.kResultFalse;
            entry.queued = false;
            return types.kResultOk;
        }

        fn resetAllQueues(ptr: *anyopaque) callconv(.C) types.tresult {
            for (&ownerFromAttributes(ptr).entries) |*entry| {
                entry.queued = false;
            }
            return types.kResultOk;
        }

        fn getBinaryData(ptr: *anyopaque, id: ipersistent.IAttrID, out: ?*anyopaque, size: types.uint32) callconv(.C) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return types.kResultFalse;
            if (entry.binary_size > size) return types.kResultFalse;
            if (entry.binary_size > 0 and out == null) return types.kInvalidArgument;
            if (entry.binary_size > 0) {
                const bytes: [*]u8 = @ptrCast(out.?);
                if (entry.owns_binary) {
                    @memcpy(bytes[0..entry.binary_size], entry.binary[0..entry.binary_size]);
                } else if (entry.value.value.object) |object| {
                    const source: [*]const u8 = @ptrCast(object);
                    @memcpy(bytes[0..entry.binary_size], source[0..entry.binary_size]);
                } else {
                    return types.kResultFalse;
                }
            }
            return types.kResultOk;
        }

        fn getBinaryDataSize(ptr: *anyopaque, id: ipersistent.IAttrID) callconv(.C) types.uint32 {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return 0;
            return entry.binary_size;
        }

        fn countAttributes(ptr: *anyopaque) callconv(.C) types.int32 {
            var count: types.int32 = 0;
            for (&ownerFromAttributes2(ptr).entries) |*entry| {
                if (entry.id != null) count += 1;
            }
            return count;
        }

        fn getAttributeID(ptr: *anyopaque, index: types.int32) callconv(.C) ipersistent.IAttrID {
            if (index < 0) return "";
            var current: types.int32 = 0;
            for (&ownerFromAttributes2(ptr).entries) |*entry| {
                if (entry.id) |id| {
                    if (current == index) return id;
                    current += 1;
                }
            }
            return "";
        }

        const attributes_vtable = ipersistent.IAttributesVTable{
            .queryInterface = attributesQuery,
            .addRef = attributesAddRef,
            .release = attributesRelease,
            .set = set,
            .queue = queue,
            .setBinaryData = setBinaryData,
            .get = get,
            .unqueue = unqueue,
            .getQueueItemCount = getQueueItemCount,
            .resetQueue = resetQueue,
            .resetAllQueues = resetAllQueues,
            .getBinaryData = getBinaryData,
            .getBinaryDataSize = getBinaryDataSize,
        };

        const attributes2_vtable = ipersistent.IAttributes2VTable{
            .queryInterface = attributes2Query,
            .addRef = attributes2AddRef,
            .release = attributes2Release,
            .set = set,
            .queue = queue,
            .setBinaryData = setBinaryData,
            .get = get,
            .unqueue = unqueue,
            .getQueueItemCount = getQueueItemCount,
            .resetQueue = resetQueue,
            .resetAllQueues = resetAllQueues,
            .getBinaryData = getBinaryData,
            .getBinaryDataSize = getBinaryDataSize,
            .countAttributes = countAttributes,
            .getAttributeID = getAttributeID,
        };
    };
}

test "persistent attributes store and enumerate variants" {
    const Store = Attributes(4, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const attrs2 = store.asAttributes2();
    const gain = fvariant.FVariant{ .type = fvariant.kFloat, .value = .{ .floatValue = 0.75 } };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.set(attrs, "gain", &gain));
    try std.testing.expectEqual(@as(types.int32, 1), attrs2.vtable.countAttributes(attrs2));
    try std.testing.expectEqualStrings("gain", std.mem.span(attrs2.vtable.getAttributeID(attrs2, 0)));

    var out = fvariant.FVariant{};
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.get(attrs, "gain", &out));
    try std.testing.expectEqual(fvariant.kFloat, out.type);
    try std.testing.expectEqual(@as(f64, 0.75), out.value.floatValue);
}

test "persistent attributes queue and unqueue one value per attribute" {
    const Store = Attributes(2, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const value = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 42 } };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.queue(attrs, "answer", &value));
    try std.testing.expectEqual(@as(types.int32, 1), attrs.vtable.getQueueItemCount(attrs, "answer"));

    var out = fvariant.FVariant{};
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.unqueue(attrs, "answer", &out));
    try std.testing.expectEqual(@as(types.int64, 42), out.value.intValue);
    try std.testing.expectEqual(@as(types.int32, 0), attrs.vtable.getQueueItemCount(attrs, "answer"));
}

test "persistent attributes copy binary payloads" {
    const Store = Attributes(2, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    var payload = [_]u8{ 1, 2, 3, 4 };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setBinaryData(attrs, "blob", &payload, payload.len, true));
    payload[0] = 9;

    var out = [_]u8{0} ** 4;
    try std.testing.expectEqual(@as(types.uint32, 4), attrs.vtable.getBinaryDataSize(attrs, "blob"));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.getBinaryData(attrs, "blob", &out, out.len));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &out);
}

test "persistent attributes supports attributes2 query interface" {
    const Store = Attributes(2, 8);
    var store = Store{};
    const attrs = store.asAttributes();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.queryInterface(attrs, &ipersistent.iattributes2_iid, &queried));
    try std.testing.expect(queried != null);
    const attrs2: *ipersistent.IAttributes2 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), attrs2.vtable.release(attrs2));
}
