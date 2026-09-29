const std = @import("std");
const funknown = @import("funknown.zig");
const tuid = @import("tuid.zig");

pub const Entry = struct {
    iid: *const tuid.TUID,
    ptr: *anyopaque,
};

pub fn fieldEntry(
    comptime field_name: []const u8,
    object: anytype,
    iid: *const tuid.TUID,
) Entry {
    return .{
        .iid = iid,
        .ptr = @ptrCast(&@field(object, field_name)),
    };
}

pub fn query(
    unknown: *funknown.Header,
    entries: []const Entry,
    requested_iid: [*c]const tuid.TUID,
    out: [*c]?*anyopaque,
) funknown.tresult {
    return queryWithAddRef(unknown, unknown.vtable.addRef, entries, requested_iid, out);
}

pub fn queryWithAddRef(
    add_ref_ptr: *anyopaque,
    add_ref: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    entries: []const Entry,
    requested_iid_raw: [*c]const tuid.TUID,
    out_raw: [*c]?*anyopaque,
) funknown.tresult {
    const arguments = funknown.queryArguments(requested_iid_raw, out_raw) orelse
        return funknown.kInvalidArgument;
    const requested_iid = arguments.requested_iid;
    const out = arguments.out;
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

pub fn matches(
    requested_iid: [*c]const tuid.TUID,
    candidate_iid: *const tuid.TUID,
) bool {
    if (requested_iid == null) return false;
    return std.mem.eql(u8, &requested_iid[0], candidate_iid);
}

pub fn DelegatedInterface(
    comptime Owner: type,
    comptime ownerFn: fn (*anyopaque) *Owner,
    comptime primary_field: []const u8,
    comptime queryFn: fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) funknown.tresult,
    comptime addRefFn: fn (*anyopaque) callconv(.c) funknown.uint32,
    comptime releaseFn: fn (*anyopaque) callconv(.c) funknown.uint32,
) type {
    return struct {
        fn primary(ptr: *anyopaque) *anyopaque {
            return @ptrCast(&@field(ownerFn(ptr), primary_field));
        }

        pub fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) funknown.tresult {
            return queryFn(primary(ptr), requested_iid, out);
        }

        pub fn addRef(ptr: *anyopaque) callconv(.c) funknown.uint32 {
            return addRefFn(primary(ptr));
        }

        pub fn release(ptr: *anyopaque) callconv(.c) funknown.uint32 {
            return releaseFn(primary(ptr));
        }
    };
}

pub fn ownerFromField(
    comptime Owner: type,
    comptime Interface: type,
    comptime field_name: []const u8,
) fn (*anyopaque) *Owner {
    return struct {
        fn owner(ptr: *anyopaque) *Owner {
            const iface: *Interface = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr(field_name, iface);
        }
    }.owner;
}

fn testAddRef(ptr: *anyopaque) callconv(.c) funknown.uint32 {
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

test "query rejects null arguments without retaining or changing output" {
    var object = funknown.TestObject{};
    var out: ?*anyopaque = object.asUnknown();

    try std.testing.expectEqual(
        funknown.kInvalidArgument,
        query(object.asUnknown(), &.{}, null, &out),
    );
    try std.testing.expectEqual(
        @as(?*anyopaque, @ptrCast(object.asUnknown())),
        out,
    );
    try std.testing.expectEqual(
        funknown.kInvalidArgument,
        query(object.asUnknown(), &.{}, &funknown.iid, null),
    );
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.refCount());
}

test "fieldEntry derives interface pointer from object field" {
    const Object = struct {
        unknown: funknown.Header = funknown.Header.init(&funknown.test_vtable, null),
        alternate: funknown.Header = funknown.Header.init(&funknown.test_vtable, null),
    };
    var object = Object{};

    const entry = fieldEntry("alternate", &object, &funknown.iid);

    try std.testing.expectEqual(&funknown.iid, entry.iid);
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&object.alternate)), entry.ptr);
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

test "queryWithAddRef returns first matching entry and retains once" {
    var object = funknown.TestObject{};
    var first: funknown.Header = funknown.Header.init(&funknown.test_vtable, null);
    var second: funknown.Header = funknown.Header.init(&funknown.test_vtable, null);
    var out: ?*anyopaque = null;

    const entries = [_]Entry{
        .{
            .iid = &funknown.iid,
            .ptr = &first,
        },
        .{
            .iid = &funknown.iid,
            .ptr = &second,
        },
    };

    try std.testing.expectEqual(funknown.kResultOk, queryWithAddRef(&object, testAddRef, &entries, &funknown.iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&first)), out);
    try std.testing.expectEqual(@as(funknown.uint32, 2), object.refCount());
}

test "ownerFromField recovers object from embedded interface" {
    const Object = extern struct {
        unknown: funknown.Header = funknown.Header.init(&funknown.test_vtable, null),
        alternate: funknown.Header = funknown.Header.init(&funknown.test_vtable, null),
    };
    var object = Object{};
    const ownerFromAlternate = ownerFromField(Object, funknown.Header, "alternate");

    try std.testing.expectEqual(&object, ownerFromAlternate(&object.alternate));
}

test "delegated interface forwards through primary interface" {
    const Object = extern struct {
        const Self = @This();
        unknown: funknown.Header = funknown.Header.init(&funknown.test_vtable, null),
        alternate: funknown.Header = funknown.Header.init(&alternate_vtable, null),
        delegated_add_ref_count: funknown.uint32 = 0,
        delegated_release_count: funknown.uint32 = 0,

        fn ownerFromAlternate(ptr: *anyopaque) *Self {
            const alternate: *funknown.Header = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("alternate", alternate);
        }

        fn primaryQuery(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) funknown.tresult {
            const unknown: *funknown.Header = @ptrCast(@alignCast(ptr));
            const entries = [_]Entry{
                .{ .iid = &funknown.iid, .ptr = unknown },
            };
            return queryWithAddRef(unknown, primaryAddRef, &entries, requested_iid, out);
        }

        fn primaryAddRef(ptr: *anyopaque) callconv(.c) funknown.uint32 {
            const unknown: *funknown.Header = @ptrCast(@alignCast(ptr));
            const self: *Self = @fieldParentPtr("unknown", unknown);
            self.delegated_add_ref_count += 1;
            return self.delegated_add_ref_count;
        }

        fn primaryRelease(ptr: *anyopaque) callconv(.c) funknown.uint32 {
            const unknown: *funknown.Header = @ptrCast(@alignCast(ptr));
            const self: *Self = @fieldParentPtr("unknown", unknown);
            self.delegated_release_count += 1;
            return self.delegated_release_count;
        }

        const Alternate = DelegatedInterface(Self, ownerFromAlternate, "unknown", primaryQuery, primaryAddRef, primaryRelease);
        const alternate_vtable = funknown.VTable{
            .queryInterface = Alternate.query,
            .addRef = Alternate.addRef,
            .release = Alternate.release,
        };
    };

    var object = Object{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(funknown.kResultOk, object.alternate.vtable.queryInterface(&object.alternate, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&object.unknown)), queried);
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.delegated_add_ref_count);

    try std.testing.expectEqual(@as(funknown.uint32, 2), object.alternate.vtable.addRef(&object.alternate));
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.alternate.vtable.release(&object.alternate));
    try std.testing.expectEqual(@as(funknown.uint32, 2), object.delegated_add_ref_count);
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.delegated_release_count);
}
