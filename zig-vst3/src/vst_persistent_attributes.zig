const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const fvariant = @import("pluginterfaces/base/fvariant.zig");
const ipersistent = @import("pluginterfaces/base/ipersistent.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");

pub fn Persistent(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ipersistent.IPersistent = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        save_count: types.uint32 = 0,
        load_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *ipersistent.IPersistent {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, ipersistent.IPersistent, "iface");

        fn classId() tuid.TUID {
            if (!@hasDecl(Config, "class_id")) @compileError("Persistent Config requires class_id");
            return Config.class_id;
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ipersistent.ipersistent_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPersistent");
        }

        fn getClassID(_: *anyopaque, out: [*]types.char8) callconv(.c) types.tresult {
            @memcpy(out[0..tuid.byte_count], &classId());
            return types.kResultOk;
        }

        fn saveAttributes(ptr: *anyopaque, attributes: ?*ipersistent.IAttributes) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.save_count +|= 1;
            if (@hasDecl(Config, "saveAttributes")) return Config.saveAttributes(self, attributes);
            return types.kResultOk;
        }

        fn loadAttributes(ptr: *anyopaque, attributes: ?*ipersistent.IAttributes) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.load_count +|= 1;
            if (@hasDecl(Config, "loadAttributes")) return Config.loadAttributes(self, attributes);
            return types.kResultOk;
        }

        const vtable = ipersistent.IPersistentVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getClassID = getClassID,
            .saveAttributes = saveAttributes,
            .loadAttributes = loadAttributes,
        };
    };
}

pub fn Attributes(comptime max_entries: usize, comptime max_binary_bytes: usize) type {
    if (max_entries == 0) @compileError("Attributes requires at least one entry");
    vst_index.requireInt32Capacity(max_entries, "Attributes entry count");
    vst_index.requireUint32Capacity(max_binary_bytes, "Attributes binary payload size");

    return extern struct {
        const Self = @This();

        const Entry = extern struct {
            id: ?ipersistent.IAttrID = null,
            value: fvariant.FVariant = .{},
            queued: bool = false,
            binary: [max_binary_bytes]u8 = [_]u8{0} ** max_binary_bytes,
            binary_size: types.uint32 = 0,
            owns_binary: bool = false,

            fn isOccupied(self: *const Entry) bool {
                return self.id != null;
            }

            fn matchesID(self: *const Entry, id: ipersistent.IAttrID) bool {
                const existing = self.id orelse return false;
                return std.mem.eql(u8, std.mem.span(existing), std.mem.span(id));
            }

            fn hasBinaryPayload(self: *const Entry) bool {
                return self.binary_size > 0;
            }

            fn needsBinaryOutputBuffer(self: *const Entry, out: ?*anyopaque) bool {
                return self.hasBinaryPayload() and out == null;
            }

            fn resetValue(self: *Entry, value: fvariant.FVariant) void {
                self.value = value;
                self.queued = false;
                @memset(&self.binary, 0);
                self.binary_size = 0;
                self.owns_binary = false;
            }
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

        const ownerFromAttributes = interface_map.ownerFromField(Self, ipersistent.IAttributes, "iface");
        const ownerFromAttributes2 = interface_map.ownerFromField(Self, ipersistent.IAttributes2, "iface2");

        fn findEntry(self: *Self, id: ipersistent.IAttrID) ?*Entry {
            for (&self.entries) |*entry| {
                if (entry.matchesID(id)) return entry;
            }
            return null;
        }

        fn slotFor(self: *Self, id: ipersistent.IAttrID) ?*Entry {
            if (self.findEntry(id)) |entry| return entry;
            for (&self.entries) |*entry| {
                if (!entry.isOccupied()) {
                    entry.id = id;
                    return entry;
                }
            }
            return null;
        }

        fn missingInputBuffer(size: types.uint32, data: ?*anyopaque) bool {
            return size > 0 and data == null;
        }

        pub fn attributeCount(self: *const Self) usize {
            var count: usize = 0;
            for (&self.entries) |*entry| {
                if (entry.isOccupied()) count += 1;
            }
            return count;
        }

        pub fn attributeIDByIndex(self: *const Self, index: types.int32) ?ipersistent.IAttrID {
            const wanted_index = vst_index.bounded(index, self.attributeCount()) orelse return null;
            var current: usize = 0;
            for (&self.entries) |*entry| {
                if (entry.id) |id| {
                    if (current == wanted_index) return id;
                    current += 1;
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

        fn attributesQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return ownerFromAttributes(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn attributes2Query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromAttributes2(ptr);
            return self.queryCanonical(&self.iface, requested_iid, out);
        }

        fn attributesAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromAttributes(ptr).ref_count, "FUnknown");
        }

        fn attributes2AddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromAttributes2(ptr).ref_count, "FUnknown");
        }

        fn attributesRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromAttributes(ptr).ref_count, "IAttributes");
        }

        fn attributes2Release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromAttributes2(ptr).ref_count, "IAttributes2");
        }

        fn set(ptr: *anyopaque, id: ipersistent.IAttrID, value: *const fvariant.FVariant) callconv(.c) types.tresult {
            const entry = ownerFromAttributes(ptr).slotFor(id) orelse return types.kResultFalse;
            entry.resetValue(value.*);
            return types.kResultOk;
        }

        fn queue(ptr: *anyopaque, id: ipersistent.IAttrID, value: *const fvariant.FVariant) callconv(.c) types.tresult {
            const result = set(ptr, id, value);
            if (result != types.kResultOk) return result;
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return types.kResultFalse;
            entry.queued = true;
            return types.kResultOk;
        }

        fn setBinaryData(ptr: *anyopaque, id: ipersistent.IAttrID, data: ?*anyopaque, size: types.uint32, copy: bool) callconv(.c) types.tresult {
            if (missingInputBuffer(size, data)) return types.kInvalidArgument;
            if (copy and size > max_binary_bytes) return types.kResultFalse;
            const entry = ownerFromAttributes(ptr).slotFor(id) orelse return types.kResultFalse;
            if (copy) {
                entry.resetValue(.{ .type = fvariant.kObject, .value = .{ .object = &entry.binary } });
                if (size > 0) {
                    const source = data orelse return types.kInvalidArgument;
                    const bytes: [*]const u8 = @ptrCast(source);
                    @memcpy(entry.binary[0..size], bytes[0..size]);
                }
                entry.binary_size = size;
                entry.owns_binary = true;
            } else {
                entry.resetValue(.{ .type = fvariant.kObject, .value = .{ .object = data } });
                entry.binary_size = size;
            }
            return types.kResultOk;
        }

        fn failVariant(out: *fvariant.FVariant) types.tresult {
            out.* = .{};
            return types.kResultFalse;
        }

        fn get(ptr: *anyopaque, id: ipersistent.IAttrID, out: *fvariant.FVariant) callconv(.c) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return failVariant(out);
            out.* = entry.value;
            return types.kResultOk;
        }

        fn unqueue(ptr: *anyopaque, id: ipersistent.IAttrID, out: *fvariant.FVariant) callconv(.c) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return failVariant(out);
            if (!entry.queued) return failVariant(out);
            entry.queued = false;
            out.* = entry.value;
            return types.kResultOk;
        }

        fn getQueueItemCount(ptr: *anyopaque, id: ipersistent.IAttrID) callconv(.c) types.int32 {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return 0;
            return if (entry.queued) 1 else 0;
        }

        fn resetQueue(ptr: *anyopaque, id: ipersistent.IAttrID) callconv(.c) types.tresult {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return types.kResultFalse;
            entry.queued = false;
            return types.kResultOk;
        }

        fn resetAllQueues(ptr: *anyopaque) callconv(.c) types.tresult {
            for (&ownerFromAttributes(ptr).entries) |*entry| {
                entry.queued = false;
            }
            return types.kResultOk;
        }

        fn clearBinaryOutput(out: ?*anyopaque, size: types.uint32) void {
            if (out) |buffer| {
                if (size > 0) {
                    const bytes: [*]u8 = @ptrCast(buffer);
                    @memset(bytes[0..size], 0);
                }
            }
        }

        fn getBinaryData(ptr: *anyopaque, id: ipersistent.IAttrID, out: ?*anyopaque, size: types.uint32) callconv(.c) types.tresult {
            clearBinaryOutput(out, size);
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return types.kResultFalse;
            if (entry.binary_size > size) return types.kResultFalse;
            if (entry.needsBinaryOutputBuffer(out)) return types.kInvalidArgument;
            if (entry.hasBinaryPayload()) {
                const buffer = out orelse return types.kInvalidArgument;
                const bytes: [*]u8 = @ptrCast(buffer);
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

        fn getBinaryDataSize(ptr: *anyopaque, id: ipersistent.IAttrID) callconv(.c) types.uint32 {
            const entry = ownerFromAttributes(ptr).findEntry(id) orelse return 0;
            return entry.binary_size;
        }

        fn countAttributes(ptr: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(ownerFromAttributes2(ptr).attributeCount());
        }

        fn getAttributeID(ptr: *anyopaque, index: types.int32) callconv(.c) ipersistent.IAttrID {
            return ownerFromAttributes2(ptr).attributeIDByIndex(index) orelse "";
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

test "persistent object returns class ID and counts save load calls" {
    const expected_class_id = tuid.inlineUid(0x01234567, 0x89ABCDEF, 0x10325476, 0x98BADCFE);
    const Object = Persistent(struct {
        pub const class_id = tuid.inlineUid(0x01234567, 0x89ABCDEF, 0x10325476, 0x98BADCFE);
    });
    var object = Object{};
    const iface = object.asInterface();

    var out: tuid.TUID = tuid.zero;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getClassID(iface, &out));
    try std.testing.expectEqualSlices(u8, &expected_class_id, &out);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.saveAttributes(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.loadAttributes(iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), object.save_count);
    try std.testing.expectEqual(@as(types.uint32, 1), object.load_count);
}

test "persistent object delegates save and load hooks" {
    const Object = Persistent(struct {
        pub const class_id = tuid.inlineUid(0x10203040, 0x50607080, 0x90A0B0C0, 0xD0E0F000);

        pub fn saveAttributes(self: anytype, attributes: ?*ipersistent.IAttributes) types.tresult {
            _ = self;
            return if (attributes == null) types.kInvalidArgument else types.kResultOk;
        }

        pub fn loadAttributes(self: anytype, attributes: ?*ipersistent.IAttributes) types.tresult {
            _ = self;
            return if (attributes == null) types.kInvalidArgument else types.kResultOk;
        }
    });
    const Store = Attributes(1, 1);
    var object = Object{};
    var store = Store{};
    const iface = object.asInterface();

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.saveAttributes(iface, null));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.loadAttributes(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.saveAttributes(iface, store.asAttributes()));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.loadAttributes(iface, store.asAttributes()));
    try std.testing.expectEqual(@as(types.uint32, 2), object.save_count);
    try std.testing.expectEqual(@as(types.uint32, 2), object.load_count);
}

test "persistent object supports query interface" {
    const Object = Persistent(struct {
        pub const class_id = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    });
    var object = Object{};
    const iface = object.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ipersistent.ipersistent_iid, &queried));
    try std.testing.expect(queried != null);
    const persistent: *ipersistent.IPersistent = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), persistent.vtable.release(persistent));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), object.ref_count.load(.seq_cst));
    const queried_unknown: *ipersistent.IPersistent = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "persistent object clears unsupported query output" {
    const Object = Persistent(struct {
        pub const class_id = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    });
    var object = Object{};
    const iface = object.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "persistent attributes store and enumerate variants" {
    const Store = Attributes(4, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const attrs2 = store.asAttributes2();
    const gain = fvariant.FVariant{ .type = fvariant.kFloat, .value = .{ .floatValue = 0.75 } };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.set(attrs, "gain", &gain));
    try std.testing.expectEqual(@as(usize, 1), store.attributeCount());
    try std.testing.expectEqualStrings("gain", std.mem.span(store.attributeIDByIndex(0).?));
    try std.testing.expectEqual(@as(?ipersistent.IAttrID, null), store.attributeIDByIndex(-1));
    try std.testing.expectEqual(@as(?ipersistent.IAttrID, null), store.attributeIDByIndex(1));
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

test "persistent attributes clear queue state on direct replacement" {
    const Store = Attributes(1, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const queued = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 42 } };
    const direct = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 7 } };
    var payload = [_]u8{ 1, 2, 3 };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.queue(attrs, "value", &queued));
    try std.testing.expectEqual(@as(types.int32, 1), attrs.vtable.getQueueItemCount(attrs, "value"));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.set(attrs, "value", &direct));
    try std.testing.expectEqual(@as(types.int32, 0), attrs.vtable.getQueueItemCount(attrs, "value"));

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.queue(attrs, "value", &queued));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setBinaryData(attrs, "value", &payload, payload.len, true));
    try std.testing.expectEqual(@as(types.int32, 0), attrs.vtable.getQueueItemCount(attrs, "value"));
}

test "persistent attributes reset one queue or all queues" {
    const Store = Attributes(2, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const left = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 1 } };
    const right = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 2 } };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.queue(attrs, "left", &left));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.queue(attrs, "right", &right));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.resetQueue(attrs, "left"));
    try std.testing.expectEqual(@as(types.int32, 0), attrs.vtable.getQueueItemCount(attrs, "left"));
    try std.testing.expectEqual(@as(types.int32, 1), attrs.vtable.getQueueItemCount(attrs, "right"));
    try std.testing.expectEqual(types.kResultFalse, attrs.vtable.resetQueue(attrs, "missing"));

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.resetAllQueues(attrs));
    try std.testing.expectEqual(@as(types.int32, 0), attrs.vtable.getQueueItemCount(attrs, "right"));
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

    out = [_]u8{9} ** 4;
    try std.testing.expectEqual(types.kResultFalse, attrs.vtable.getBinaryData(attrs, "missing", &out, out.len));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &out);

    out = [_]u8{9} ** 4;
    try std.testing.expectEqual(types.kResultFalse, attrs.vtable.getBinaryData(attrs, "blob", &out, 2));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 9, 9 }, &out);
}

test "persistent attributes clear stale copied binary bytes" {
    const Store = Attributes(1, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    var longer = [_]u8{ 1, 2, 3, 4 };
    var shorter = [_]u8{9};

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setBinaryData(attrs, "blob", &longer, longer.len, true));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setBinaryData(attrs, "blob", &shorter, shorter.len, true));
    try std.testing.expectEqual(@as(types.uint32, shorter.len), store.entries[0].binary_size);
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 0, 0 }, store.entries[0].binary[0..4]);
}

test "persistent attributes clear copied binary storage on value replacement" {
    const Store = Attributes(1, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    var payload = [_]u8{ 1, 2, 3, 4 };
    const value = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 5 } };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setBinaryData(attrs, "blob", &payload, payload.len, true));
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.set(attrs, "blob", &value));
    try std.testing.expectEqual(@as(types.uint32, 0), store.entries[0].binary_size);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, store.entries[0].binary[0..4]);
    try std.testing.expect(!store.entries[0].owns_binary);
}

test "persistent attributes can reference borrowed binary payloads" {
    const Store = Attributes(1, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    var payload = [_]u8{ 1, 2, 3, 4 };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setBinaryData(attrs, "blob", &payload, payload.len, false));
    payload[0] = 9;

    var out = [_]u8{0} ** 4;
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.getBinaryData(attrs, "blob", &out, out.len));
    try std.testing.expectEqualSlices(u8, &.{ 9, 2, 3, 4 }, &out);

    try std.testing.expectEqual(types.kInvalidArgument, attrs.vtable.getBinaryData(attrs, "blob", null, out.len));
}

test "persistent attributes reject oversized copied binary without creating attributes" {
    const Store = Attributes(1, 2);
    var store = Store{};
    const attrs = store.asAttributes();
    const attrs2 = store.asAttributes2();
    var payload = [_]u8{ 1, 2, 3 };

    try std.testing.expectEqual(types.kResultFalse, attrs.vtable.setBinaryData(attrs, "blob", &payload, payload.len, true));
    try std.testing.expectEqual(@as(types.uint32, 0), attrs.vtable.getBinaryDataSize(attrs, "blob"));
    try std.testing.expectEqual(@as(types.int32, 0), attrs2.vtable.countAttributes(attrs2));
}

test "persistent attributes reject full storage without retaining new values" {
    const Store = Attributes(1, 4);
    const Operation = enum { set, queue, binary };
    const operations = [_]Operation{ .set, .queue, .binary };
    const existing = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 1 } };
    const rejected = fvariant.FVariant{ .type = fvariant.kInteger, .value = .{ .intValue = 2 } };
    var payload = [_]u8{ 9, 8, 7 };

    inline for (operations) |operation| {
        var store = Store{};
        const attrs = store.asAttributes();
        const attrs2 = store.asAttributes2();

        try std.testing.expectEqual(types.kResultOk, attrs.vtable.set(attrs, "existing", &existing));
        try std.testing.expectEqual(types.kResultFalse, switch (operation) {
            .set => attrs.vtable.set(attrs, "rejected", &rejected),
            .queue => attrs.vtable.queue(attrs, "rejected", &rejected),
            .binary => attrs.vtable.setBinaryData(attrs, "rejected", &payload, payload.len, true),
        });

        try std.testing.expectEqual(@as(types.int32, 1), attrs2.vtable.countAttributes(attrs2));
        try std.testing.expectEqualStrings("existing", std.mem.span(attrs2.vtable.getAttributeID(attrs2, 0)));
        try std.testing.expectEqualStrings("", std.mem.span(attrs2.vtable.getAttributeID(attrs2, 1)));
        try std.testing.expectEqual(@as(types.uint32, 0), attrs.vtable.getBinaryDataSize(attrs, "rejected"));

        var out = fvariant.FVariant{};
        try std.testing.expectEqual(types.kResultFalse, attrs.vtable.get(attrs, "rejected", &out));
        try std.testing.expectEqual(fvariant.kEmpty, out.type);
    }
}

test "persistent attributes enumerate invalid indexes as empty IDs" {
    const Store = Attributes(1, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const attrs2 = store.asAttributes2();
    const value = fvariant.FVariant{ .type = fvariant.kString8, .value = .{ .string8 = "value" } };

    try std.testing.expectEqual(types.kResultOk, attrs.vtable.set(attrs, "name", &value));
    try std.testing.expectEqualStrings("", std.mem.span(attrs2.vtable.getAttributeID(attrs2, -1)));
    try std.testing.expectEqualStrings("", std.mem.span(attrs2.vtable.getAttributeID(attrs2, 1)));
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

test "persistent attributes query interfaces share object refcount" {
    const Store = Attributes(2, 8);
    var store = Store{};

    var queried_attrs: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, store.asAttributes2().vtable.queryInterface(store.asAttributes2(), &ipersistent.iattributes_iid, &queried_attrs));
    try std.testing.expectEqual(@as(?*anyopaque, store.asAttributes()), queried_attrs);
    try std.testing.expectEqual(@as(types.uint32, 2), store.ref_count.load(.seq_cst));

    var queried_unknown: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, store.asAttributes2().vtable.queryInterface(store.asAttributes2(), &funknown.iid, &queried_unknown));
    try std.testing.expectEqual(@as(?*anyopaque, store.asAttributes()), queried_unknown);
    try std.testing.expectEqual(@as(types.uint32, 3), store.ref_count.load(.seq_cst));

    const attrs: *ipersistent.IAttributes = @ptrCast(@alignCast(queried_attrs.?));
    try std.testing.expectEqual(@as(types.uint32, 2), attrs.vtable.release(attrs));
    try std.testing.expectEqual(@as(types.uint32, 1), store.asAttributes().vtable.release(store.asAttributes()));
}

test "persistent attributes clear unsupported query output from both interfaces" {
    const Store = Attributes(2, 8);
    var store = Store{};
    const attrs = store.asAttributes();
    const attrs2 = store.asAttributes2();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, attrs.vtable.queryInterface(attrs, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, attrs2.vtable.queryInterface(attrs2, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
