const std = @import("std");
const funknown = @import("funknown.zig");
const tuid = @import("tuid.zig");

pub const Entry = struct {
    iid: *const tuid.TUID,
    ptr: *anyopaque,
};

pub fn query(
    unknown: *funknown.Header,
    entries: []const Entry,
    requested_iid: *const tuid.TUID,
    out: *?*anyopaque,
) funknown.tresult {
    return queryWithAddRef(unknown, unknown.vtable.addRef, entries, requested_iid, out);
}

pub fn queryWithAddRef(
    add_ref_ptr: *anyopaque,
    add_ref: *const fn (*anyopaque) callconv(.C) funknown.uint32,
    entries: []const Entry,
    requested_iid: *const tuid.TUID,
    out: *?*anyopaque,
) funknown.tresult {
    for (entries) |entry| {
        if (std.mem.eql(u8, requested_iid, entry.iid)) {
            _ = add_ref(add_ref_ptr);
            out.* = entry.ptr;
            return funknown.kResultOk;
        }
    }

    out.* = null;
    return funknown.kNoInterface;
}

fn testAddRef(ptr: *anyopaque) callconv(.C) funknown.uint32 {
    const object: *funknown.TestObject = @ptrCast(@alignCast(ptr));
    return object.asUnknown().vtable.addRef(object.asUnknown());
}

test "query returns matching interface and increments canonical refcount" {
    var object = funknown.TestObject{};
    var alternate: funknown.Header = funknown.Header.init(&funknown.test_vtable, null);
    var out: ?*anyopaque = null;

    const entries = [_]Entry{
        .{
            .iid = &funknown.iid,
            .ptr = &alternate,
        },
    };

    try std.testing.expectEqual(funknown.kResultOk, query(object.asUnknown(), &entries, &funknown.iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&alternate)), out);
    try std.testing.expectEqual(@as(funknown.uint32, 2), object.refCount());
}

test "query clears output for missing interface" {
    var object = funknown.TestObject{};
    var out: ?*anyopaque = object.asUnknown();
    const missing_iid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);

    try std.testing.expectEqual(funknown.kNoInterface, query(object.asUnknown(), &.{}, &missing_iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.refCount());
}

test "queryWithAddRef uses caller supplied canonical pointer" {
    var object = funknown.TestObject{};
    var alternate: funknown.Header = funknown.Header.init(&funknown.test_vtable, null);
    var out: ?*anyopaque = null;

    const entries = [_]Entry{
        .{
            .iid = &funknown.iid,
            .ptr = &alternate,
        },
    };

    try std.testing.expectEqual(funknown.kResultOk, queryWithAddRef(&object, testAddRef, &entries, &funknown.iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&alternate)), out);
    try std.testing.expectEqual(@as(funknown.uint32, 2), object.refCount());
}
