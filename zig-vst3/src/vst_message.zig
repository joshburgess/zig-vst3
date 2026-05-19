const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const string128 = @import("string128.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const vst_index = @import("vst_index.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn ConnectionPoint(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstmessage.IConnectionPoint = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        add_ref_count: types.uint32 = 0,
        release_count: types.uint32 = 0,
        connect_count: types.uint32 = 0,
        disconnect_count: types.uint32 = 0,
        notify_count: types.uint32 = 0,
        connected_peer: ?*ivstmessage.IConnectionPoint = null,
        last_message: ?*ivstmessage.IMessage = null,

        pub fn asInterface(self: *Self) *ivstmessage.IConnectionPoint {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstmessage.iconnection_point_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.release_count +|= 1;
            return funknown.decrementRefCount(&self.ref_count, "IConnectionPoint");
        }

        fn connect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.connect_count +|= 1;
            if (@hasDecl(Config, "connect")) {
                const result = Config.connect(self, peer);
                if (result != types.kResultOk) return result;
            }
            self.connected_peer = peer;
            return types.kResultOk;
        }

        fn disconnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.disconnect_count +|= 1;
            if (@hasDecl(Config, "disconnect")) {
                const result = Config.disconnect(self, peer);
                if (result != types.kResultOk) return result;
            }
            if (self.connected_peer == peer) self.connected_peer = null;
            return types.kResultOk;
        }

        fn notify(ptr: *anyopaque, message: ?*ivstmessage.IMessage) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.notify_count +|= 1;
            self.last_message = message;
            if (@hasDecl(Config, "notify")) return Config.notify(self, message);
            return types.kResultOk;
        }

        const vtable = ivstmessage.IConnectionPointVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .connect = connect,
            .disconnect = disconnect,
            .notify = notify,
        };
    };
}

test "connection point preserves peer when delegated connection changes fail" {
    const Config = struct {
        fn connect(_: anytype, peer: ?*ivstmessage.IConnectionPoint) types.tresult {
            return if (peer == null) types.kInvalidArgument else types.kResultFalse;
        }

        fn disconnect(_: anytype, _: ?*ivstmessage.IConnectionPoint) types.tresult {
            return types.kResultFalse;
        }
    };
    const Point = ConnectionPoint(Config);
    const Peer = ConnectionPoint(struct {});
    var point = Point{};
    var existing_peer = Peer{};
    var rejected_peer = Peer{};
    point.connected_peer = existing_peer.asInterface();
    const iface = point.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.connect(iface, rejected_peer.asInterface()));
    try std.testing.expectEqual(existing_peer.asInterface(), point.connected_peer.?);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.disconnect(iface, existing_peer.asInterface()));
    try std.testing.expectEqual(existing_peer.asInterface(), point.connected_peer.?);
}

test "connection point stores peer and ignores unrelated disconnects" {
    const Point = ConnectionPoint(struct {});
    var point = Point{};
    var peer = Point{};
    var unrelated = Point{};
    const iface = point.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.connect(iface, peer.asInterface()));
    try std.testing.expectEqual(peer.asInterface(), point.connected_peer.?);
    try std.testing.expectEqual(@as(types.uint32, 1), point.connect_count);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.disconnect(iface, unrelated.asInterface()));
    try std.testing.expectEqual(peer.asInterface(), point.connected_peer.?);
    try std.testing.expectEqual(@as(types.uint32, 1), point.disconnect_count);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.disconnect(iface, peer.asInterface()));
    try std.testing.expectEqual(@as(?*ivstmessage.IConnectionPoint, null), point.connected_peer);
    try std.testing.expectEqual(@as(types.uint32, 2), point.disconnect_count);
}

test "connection point stores notified message and supports query interface" {
    const Point = ConnectionPoint(struct {});
    const TestMessage = Message(16, 1, 4, 4);
    var point = Point{};
    var message = TestMessage{};
    const iface = point.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.notify(iface, message.asInterface()));
    try std.testing.expectEqual(message.asInterface(), point.last_message.?);
    try std.testing.expectEqual(@as(types.uint32, 1), point.notify_count);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstmessage.iconnection_point_iid, &queried));
    try std.testing.expect(queried != null);
    try std.testing.expectEqual(@as(types.uint32, 1), point.add_ref_count);
    const queried_point: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_point.vtable.release(queried_point));
    try std.testing.expectEqual(@as(types.uint32, 1), point.release_count);
}

test "connection point clears unsupported query output" {
    const Point = ConnectionPoint(struct {});
    var point = Point{};
    const iface = point.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expectEqual(@as(types.uint32, 0), point.add_ref_count);
}

pub fn AttributeList(comptime max_entries: usize, comptime max_string_chars: usize, comptime max_binary_bytes: usize) type {
    if (max_entries == 0) @compileError("AttributeList requires at least one entry");
    if (max_string_chars == 0) @compileError("AttributeList requires at least one string code unit");
    vst_index.requireUint32Capacity(max_string_chars, "AttributeList string capacity");
    vst_index.requireUint32Capacity(max_binary_bytes, "AttributeList binary capacity");

    return extern struct {
        const Self = @This();
        const Kind = enum(types.uint32) {
            empty = 0,
            int = 1,
            float = 2,
            string = 3,
            binary = 4,
        };

        const Entry = extern struct {
            id: ?ivstattributes.AttrID = null,
            kind: Kind = .empty,
            int_value: types.int64 = 0,
            float_value: f64 = 0,
            string_value: [max_string_chars]vsttypes.TChar = [_]vsttypes.TChar{0} ** max_string_chars,
            binary_value: [max_binary_bytes]u8 = [_]u8{0} ** max_binary_bytes,
            binary_size: types.uint32 = 0,
        };

        iface: ivstattributes.IAttributeList = .{ .vtable = &attribute_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        entries: [max_entries]Entry = [_]Entry{.{}} ** max_entries,

        pub fn asInterface(self: *Self) *ivstattributes.IAttributeList {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstattributes.IAttributeList = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries_for_query = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstattributes.iattribute_list_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries_for_query, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IAttributeList");
        }

        fn findEntry(self: *Self, id: ivstattributes.AttrID) ?*Entry {
            const wanted = std.mem.span(id);
            for (&self.entries) |*entry| {
                if (entry.id) |existing| {
                    if (std.mem.eql(u8, wanted, std.mem.span(existing))) return entry;
                }
            }
            return null;
        }

        fn slotFor(self: *Self, id: ivstattributes.AttrID) ?*Entry {
            if (self.findEntry(id)) |entry| return entry;
            for (&self.entries) |*entry| {
                if (entry.kind == .empty) {
                    entry.id = id;
                    return entry;
                }
            }
            return null;
        }

        fn setInt(ptr: *anyopaque, id: ivstattributes.AttrID, value: types.int64) callconv(.c) types.tresult {
            const entry = owner(ptr).slotFor(id) orelse return types.kResultFalse;
            entry.kind = .int;
            entry.int_value = value;
            return types.kResultOk;
        }

        fn failInt(out: *types.int64, result: types.tresult) types.tresult {
            out.* = 0;
            return result;
        }

        fn getInt(ptr: *anyopaque, id: ivstattributes.AttrID, out: *types.int64) callconv(.c) types.tresult {
            const entry = owner(ptr).findEntry(id) orelse return failInt(out, types.kResultFalse);
            if (entry.kind != .int) return failInt(out, types.kInvalidArgument);
            out.* = entry.int_value;
            return types.kResultOk;
        }

        fn setFloat(ptr: *anyopaque, id: ivstattributes.AttrID, value: f64) callconv(.c) types.tresult {
            const entry = owner(ptr).slotFor(id) orelse return types.kResultFalse;
            entry.kind = .float;
            entry.float_value = value;
            return types.kResultOk;
        }

        fn failFloat(out: *f64, result: types.tresult) types.tresult {
            out.* = 0;
            return result;
        }

        fn getFloat(ptr: *anyopaque, id: ivstattributes.AttrID, out: *f64) callconv(.c) types.tresult {
            const entry = owner(ptr).findEntry(id) orelse return failFloat(out, types.kResultFalse);
            if (entry.kind != .float) return failFloat(out, types.kInvalidArgument);
            out.* = entry.float_value;
            return types.kResultOk;
        }

        fn setString(ptr: *anyopaque, id: ivstattributes.AttrID, value: [*:0]const vsttypes.TChar) callconv(.c) types.tresult {
            const entry = owner(ptr).slotFor(id) orelse return types.kResultFalse;
            entry.kind = .string;
            @memset(&entry.string_value, 0);
            const len = @min(std.mem.len(value), max_string_chars - 1);
            @memcpy(entry.string_value[0..len], value[0..len]);
            return types.kResultOk;
        }

        fn getString(ptr: *anyopaque, id: ivstattributes.AttrID, out: [*]vsttypes.TChar, size: types.uint32) callconv(.c) types.tresult {
            if (size == 0) return types.kInvalidArgument;
            @memset(out[0..size], 0);
            const entry = owner(ptr).findEntry(id) orelse {
                return types.kResultFalse;
            };
            if (entry.kind != .string) {
                return types.kInvalidArgument;
            }
            const len = @min(std.mem.len(@as([*:0]const vsttypes.TChar, @ptrCast(&entry.string_value))), size - 1);
            @memcpy(out[0..len], entry.string_value[0..len]);
            return types.kResultOk;
        }

        fn setBinary(ptr: *anyopaque, id: ivstattributes.AttrID, value: ?*const anyopaque, size: types.uint32) callconv(.c) types.tresult {
            if (size > max_binary_bytes) return types.kResultFalse;
            if (size > 0 and value == null) return types.kInvalidArgument;
            const entry = owner(ptr).slotFor(id) orelse return types.kResultFalse;
            entry.kind = .binary;
            entry.binary_size = size;
            @memset(&entry.binary_value, 0);
            if (size > 0) {
                const source = value orelse return types.kInvalidArgument;
                const bytes: [*]const u8 = @ptrCast(source);
                @memcpy(entry.binary_value[0..size], bytes[0..size]);
            }
            return types.kResultOk;
        }

        fn failBinary(out: *?*const anyopaque, size: *types.uint32, result: types.tresult) types.tresult {
            out.* = null;
            size.* = 0;
            return result;
        }

        fn getBinary(ptr: *anyopaque, id: ivstattributes.AttrID, out: *?*const anyopaque, size: *types.uint32) callconv(.c) types.tresult {
            const entry = owner(ptr).findEntry(id) orelse return failBinary(out, size, types.kResultFalse);
            if (entry.kind != .binary) return failBinary(out, size, types.kInvalidArgument);
            out.* = &entry.binary_value;
            size.* = entry.binary_size;
            return types.kResultOk;
        }

        const attribute_vtable = ivstattributes.IAttributeListVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .setInt = setInt,
            .getInt = getInt,
            .setFloat = setFloat,
            .getFloat = getFloat,
            .setString = setString,
            .getString = getString,
            .setBinary = setBinary,
            .getBinary = getBinary,
        };
    };
}

pub fn StreamAttributes(comptime max_file_name_chars: usize, comptime max_attributes: usize, comptime max_string_chars: usize, comptime max_binary_bytes: usize) type {
    if (max_file_name_chars == 0) @compileError("StreamAttributes requires at least one file-name code unit");

    return extern struct {
        const Self = @This();
        const Attributes = AttributeList(max_attributes, max_string_chars, max_binary_bytes);

        iface: ivstattributes.IStreamAttributes = .{ .vtable = &stream_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        file_name: [max_file_name_chars]vsttypes.TChar = [_]vsttypes.TChar{0} ** max_file_name_chars,
        attributes: Attributes = .{},

        pub fn asInterface(self: *Self) *ivstattributes.IStreamAttributes {
            return &self.iface;
        }

        pub fn setFileName(self: *Self, value: [*:0]const vsttypes.TChar) void {
            @memset(&self.file_name, 0);
            const len = @min(std.mem.len(value), max_file_name_chars - 1);
            @memcpy(self.file_name[0..len], value[0..len]);
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstattributes.IStreamAttributes = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries_for_query = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstattributes.istream_attributes_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries_for_query, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IStreamAttributes");
        }

        fn getFileName(ptr: *anyopaque, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            const self = owner(ptr);
            string128.clearPtr(out);
            const len = std.mem.len(@as([*:0]const vsttypes.TChar, @ptrCast(&self.file_name)));
            const copy_len = @min(len, string128.payload_units);
            @memcpy(out[0..copy_len], self.file_name[0..copy_len]);
            return types.kResultOk;
        }

        fn getAttributes(ptr: *anyopaque) callconv(.c) ?*ivstattributes.IAttributeList {
            return owner(ptr).attributes.asInterface();
        }

        const stream_vtable = ivstattributes.IStreamAttributesVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getFileName = getFileName,
            .getAttributes = getAttributes,
        };
    };
}

pub fn Message(comptime max_message_id_bytes: usize, comptime max_attributes: usize, comptime max_string_chars: usize, comptime max_binary_bytes: usize) type {
    if (max_message_id_bytes == 0) @compileError("Message requires at least one message-id byte");

    return extern struct {
        const Self = @This();
        const Attributes = AttributeList(max_attributes, max_string_chars, max_binary_bytes);

        iface: ivstmessage.IMessage = .{ .vtable = &message_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        message_id: [max_message_id_bytes]types.char8 = [_]types.char8{0} ** max_message_id_bytes,
        attributes: Attributes = .{},

        pub fn asInterface(self: *Self) *ivstmessage.IMessage {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstmessage.IMessage = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries_for_query = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstmessage.imessage_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries_for_query, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IMessage");
        }

        fn getMessageID(ptr: *anyopaque) callconv(.c) types.FIDString {
            return @ptrCast(&owner(ptr).message_id);
        }

        fn setMessageID(ptr: *anyopaque, value: types.FIDString) callconv(.c) void {
            const self = owner(ptr);
            @memset(&self.message_id, 0);
            const len = @min(std.mem.len(value), max_message_id_bytes - 1);
            @memcpy(self.message_id[0..len], value[0..len]);
        }

        fn getAttributes(ptr: *anyopaque) callconv(.c) ?*ivstattributes.IAttributeList {
            return owner(ptr).attributes.asInterface();
        }

        const message_vtable = ivstmessage.IMessageVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getMessageID = getMessageID,
            .setMessageID = setMessageID,
            .getAttributes = getAttributes,
        };
    };
}

test "attribute list stores scalar string and binary values" {
    const List = AttributeList(4, 16, 8);
    var list = List{};
    const iface = list.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setInt(iface, "count", 7));
    var int_value: types.int64 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getInt(iface, "count", &int_value));
    try std.testing.expectEqual(@as(types.int64, 7), int_value);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setFloat(iface, "ratio", 0.5));
    var float_value: f64 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getFloat(iface, "ratio", &float_value));
    try std.testing.expectEqual(@as(f64, 0.5), float_value);

    const text: [6:0]vsttypes.TChar = .{ 'h', 'e', 'l', 'l', 'o', 0 };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setString(iface, "text", &text));
    var text_out: [16]vsttypes.TChar = [_]vsttypes.TChar{'x'} ** 16;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getString(iface, "text", &text_out, text_out.len));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'h'), text_out[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'o'), text_out[4]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text_out[5]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text_out[6]);

    const bytes = [_]u8{ 1, 2, 3 };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setBinary(iface, "data", &bytes, bytes.len));
    var binary_out: ?*const anyopaque = null;
    var binary_size: types.uint32 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getBinary(iface, "data", &binary_out, &binary_size));
    try std.testing.expectEqual(@as(types.uint32, bytes.len), binary_size);
    const binary_bytes: [*]const u8 = @ptrCast(binary_out.?);
    try std.testing.expectEqual(@as(u8, 1), binary_bytes[0]);
    try std.testing.expectEqual(@as(u8, 3), binary_bytes[2]);

    const shorter_bytes = [_]u8{9};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setBinary(iface, "data", &shorter_bytes, shorter_bytes.len));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getBinary(iface, "data", &binary_out, &binary_size));
    try std.testing.expectEqual(@as(types.uint32, shorter_bytes.len), binary_size);
    const shorter_binary_bytes: [*]const u8 = @ptrCast(binary_out.?);
    try std.testing.expectEqual(@as(u8, 9), shorter_binary_bytes[0]);
    try std.testing.expectEqual(@as(u8, 0), shorter_binary_bytes[1]);
    try std.testing.expectEqual(@as(u8, 0), shorter_binary_bytes[2]);
}

test "attribute list rejects full storage and clears failed outputs" {
    const List = AttributeList(1, 4, 2);
    var list = List{};
    const iface = list.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setInt(iface, "one", 1));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.setFloat(iface, "two", 2.0));

    var int_value: types.int64 = 77;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getInt(iface, "missing", &int_value));
    try std.testing.expectEqual(@as(types.int64, 0), int_value);

    var float_value: f64 = 3.0;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getFloat(iface, "one", &float_value));
    try std.testing.expectEqual(@as(f64, 0), float_value);

    const bytes = [_]u8{ 1, 2, 3 };
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.setBinary(iface, "one", &bytes, bytes.len));

    var binary_out: ?*const anyopaque = @ptrFromInt(0x1000);
    var binary_size: types.uint32 = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getBinary(iface, "one", &binary_out, &binary_size));
    try std.testing.expectEqual(@as(?*const anyopaque, null), binary_out);
    try std.testing.expectEqual(@as(types.uint32, 0), binary_size);
}

test "attribute list replaces values and clears stale typed outputs" {
    const List = AttributeList(1, 8, 4);
    var list = List{};
    const iface = list.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setInt(iface, "value", 10));
    var int_value: types.int64 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getInt(iface, "value", &int_value));
    try std.testing.expectEqual(@as(types.int64, 10), int_value);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setFloat(iface, "value", 1.5));
    int_value = 77;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getInt(iface, "value", &int_value));
    try std.testing.expectEqual(@as(types.int64, 0), int_value);

    var float_value: f64 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getFloat(iface, "value", &float_value));
    try std.testing.expectEqual(@as(f64, 1.5), float_value);

    const text: [4:0]vsttypes.TChar = .{ 'n', 'e', 'w', 0 };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setString(iface, "value", &text));
    float_value = 2.5;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getFloat(iface, "value", &float_value));
    try std.testing.expectEqual(@as(f64, 0), float_value);

    var text_out: [8]vsttypes.TChar = [_]vsttypes.TChar{'x'} ** 8;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getString(iface, "value", &text_out, text_out.len));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'n'), text_out[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text_out[3]);
}

test "attribute list stores empty binary values and rejects null nonempty data" {
    const List = AttributeList(1, 4, 4);
    var list = List{};
    const iface = list.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setBinary(iface, "data", null, 0));
    var binary_out: ?*const anyopaque = @ptrFromInt(0x1000);
    var binary_size: types.uint32 = 99;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getBinary(iface, "data", &binary_out, &binary_size));
    try std.testing.expect(binary_out != null);
    try std.testing.expectEqual(@as(types.uint32, 0), binary_size);

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.setBinary(iface, "data", null, 1));
    binary_out = null;
    binary_size = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getBinary(iface, "data", &binary_out, &binary_size));
    try std.testing.expect(binary_out != null);
    try std.testing.expectEqual(@as(types.uint32, 0), binary_size);
}

test "message stores id and exposes attributes" {
    const TestMessage = Message(32, 4, 16, 8);
    var message = TestMessage{};
    const iface = message.asInterface();

    iface.vtable.setMessageID(iface, "parameter-change");
    try std.testing.expectEqualStrings("parameter-change", std.mem.span(iface.vtable.getMessageID(iface)));

    const attrs = iface.vtable.getAttributes(iface).?;
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setInt(attrs, "id", 42));
    var id: types.int64 = 0;
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.getInt(attrs, "id", &id));
    try std.testing.expectEqual(@as(types.int64, 42), id);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstmessage.imessage_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_message: *ivstmessage.IMessage = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_message.vtable.release(queried_message));
}

test "message clears unsupported query output" {
    const TestMessage = Message(32, 4, 16, 8);
    var message = TestMessage{};
    const iface = message.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "stream attributes expose filename and attribute list" {
    const TestStreamAttributes = StreamAttributes(32, 4, 16, 8);
    var stream_attributes = TestStreamAttributes{};
    const iface = stream_attributes.asInterface();

    const file_name: [11:0]vsttypes.TChar = .{ 'p', 'r', 'e', 's', 'e', 't', '.', 'v', 's', 't', 0 };
    stream_attributes.setFileName(&file_name);

    var file_name_out: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getFileName(iface, &file_name_out));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'p'), file_name_out[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 't'), file_name_out[9]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), file_name_out[10]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), file_name_out[11]);

    const attrs = iface.vtable.getAttributes(iface).?;
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.setInt(attrs, "version", 1));
    var version: types.int64 = 0;
    try std.testing.expectEqual(types.kResultOk, attrs.vtable.getInt(attrs, "version", &version));
    try std.testing.expectEqual(@as(types.int64, 1), version);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstattributes.istream_attributes_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_stream: *ivstattributes.IStreamAttributes = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_stream.vtable.release(queried_stream));
}

test "stream attributes truncate filename to String128 output" {
    const TestStreamAttributes = StreamAttributes(160, 1, 4, 4);
    var stream_attributes = TestStreamAttributes{};
    const iface = stream_attributes.asInterface();
    var long_name: [160:0]vsttypes.TChar = [_:0]vsttypes.TChar{'a'} ** 160;
    long_name[0] = 'f';

    stream_attributes.setFileName(&long_name);

    var file_name_out: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getFileName(iface, &file_name_out));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'f'), file_name_out[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'a'), file_name_out[string128.payload_units - 1]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), file_name_out[string128.payload_units]);
}

test "stream attributes clear unsupported query output" {
    const TestStreamAttributes = StreamAttributes(32, 4, 16, 8);
    var stream_attributes = TestStreamAttributes{};
    const iface = stream_attributes.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "attribute list clears unsupported query output" {
    const List = AttributeList(1, 4, 4);
    var list = List{};
    const iface = list.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
