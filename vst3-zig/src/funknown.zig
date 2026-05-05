const std = @import("std");
const tuid = @import("tuid.zig");

pub const tresult = i32;
pub const uint32 = u32;

pub const kResultOk: tresult = 0;
pub const kNoInterface: tresult = -1;

pub const iid = tuid.inlineUid(0x00000000, 0x00000000, 0xC0000000, 0x00000046);

pub const VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) tresult,
    addRef: *const fn (*anyopaque) callconv(.C) uint32,
    release: *const fn (*anyopaque) callconv(.C) uint32,
};

pub const Header = extern struct {
    vtable: *const VTable,
};

pub const TestObject = extern struct {
    unknown: Header = .{ .vtable = &test_vtable },
    ref_count: uint32 = 1,
    query_count: uint32 = 0,

    pub fn asUnknown(self: *TestObject) *Header {
        return &self.unknown;
    }
};

pub const test_vtable = VTable{
    .queryInterface = testQueryInterface,
    .addRef = testAddRef,
    .release = testRelease,
};

fn ownerFromUnknown(ptr: *anyopaque) *TestObject {
    const header: *Header = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("unknown", header);
}

fn testQueryInterface(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) tresult {
    const self = ownerFromUnknown(ptr);
    self.query_count += 1;

    if (std.mem.eql(u8, requested_iid, &iid)) {
        _ = testAddRef(ptr);
        out.* = ptr;
        return kResultOk;
    }

    out.* = null;
    return kNoInterface;
}

fn testAddRef(ptr: *anyopaque) callconv(.C) uint32 {
    const self = ownerFromUnknown(ptr);
    self.ref_count += 1;
    return self.ref_count;
}

fn testRelease(ptr: *anyopaque) callconv(.C) uint32 {
    const self = ownerFromUnknown(ptr);
    self.ref_count -= 1;
    return self.ref_count;
}

test "queryInterface returns FUnknown pointer and increments refcount" {
    var object = TestObject{};
    const unknown = object.asUnknown();
    var out: ?*anyopaque = null;

    const result = unknown.vtable.queryInterface(unknown, &iid, &out);

    try std.testing.expectEqual(kResultOk, result);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(unknown)), out);
    try std.testing.expectEqual(@as(uint32, 2), object.ref_count);
    try std.testing.expectEqual(@as(uint32, 1), object.query_count);
}

test "queryInterface rejects unknown IID" {
    var object = TestObject{};
    const unknown = object.asUnknown();
    var out: ?*anyopaque = @ptrCast(unknown);
    const missing_iid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);

    const result = unknown.vtable.queryInterface(unknown, &missing_iid, &out);

    try std.testing.expectEqual(kNoInterface, result);
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
    try std.testing.expectEqual(@as(uint32, 1), object.ref_count);
}

test "addRef and release update the prototype refcount" {
    var object = TestObject{};
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 2), unknown.vtable.addRef(unknown));
    try std.testing.expectEqual(@as(uint32, 1), unknown.vtable.release(unknown));
}
