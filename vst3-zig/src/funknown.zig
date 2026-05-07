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
    ref_count: std.atomic.Value(uint32),
    destroy: ?*const fn (*anyopaque) callconv(.C) void,

    pub fn init(vtable: *const VTable, destroy: ?*const fn (*anyopaque) callconv(.C) void) Header {
        return .{
            .vtable = vtable,
            .ref_count = std.atomic.Value(uint32).init(1),
            .destroy = destroy,
        };
    }
};

pub const TestObject = extern struct {
    unknown: Header = Header.init(&test_vtable, null),
    query_count: uint32 = 0,
    destroy_count: uint32 = 0,

    pub fn asUnknown(self: *TestObject) *Header {
        return &self.unknown;
    }

    pub fn refCount(self: *const TestObject) uint32 {
        return @constCast(&self.unknown.ref_count).load(.monotonic);
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
        _ = addRef(ptr);
        out.* = ptr;
        return kResultOk;
    }

    out.* = null;
    return kNoInterface;
}

pub fn addRef(ptr: *anyopaque) callconv(.C) uint32 {
    const header: *Header = @ptrCast(@alignCast(ptr));
    return header.ref_count.fetchAdd(1, .monotonic) + 1;
}

pub fn release(ptr: *anyopaque) callconv(.C) uint32 {
    const header: *Header = @ptrCast(@alignCast(ptr));
    const next = decrementRefCount(&header.ref_count, "FUnknown");
    if (next == 0) {
        _ = header.ref_count.load(.acquire);
        if (header.destroy) |destroy| destroy(ptr);
    }

    return next;
}

pub fn decrementRefCount(ref_count: *std.atomic.Value(uint32), comptime owner_name: []const u8) uint32 {
    while (true) {
        const previous = ref_count.load(.monotonic);
        if (previous == 0) {
            @panic(owner_name ++ ".release called after refcount reached zero");
        }

        const next = previous - 1;
        if (ref_count.cmpxchgWeak(previous, next, .release, .monotonic)) |_| {
            continue;
        }

        return next;
    }
}

fn testAddRef(ptr: *anyopaque) callconv(.C) uint32 {
    return addRef(ptr);
}

fn testRelease(ptr: *anyopaque) callconv(.C) uint32 {
    return release(ptr);
}

fn testDestroy(ptr: *anyopaque) callconv(.C) void {
    ownerFromUnknown(ptr).destroy_count += 1;
}

pub const AllocatedTestObject = struct {
    unknown: Header = Header.init(&test_vtable, allocatedTestDestroy),
    allocator: std.mem.Allocator,
    query_count: uint32 = 0,
    destroy_count: uint32 = 0,

    pub fn create(allocator: std.mem.Allocator) !*AllocatedTestObject {
        const object = try allocator.create(AllocatedTestObject);
        object.* = .{ .allocator = allocator };
        return object;
    }

    pub fn asUnknown(self: *AllocatedTestObject) *Header {
        return &self.unknown;
    }
};

fn allocatedTestDestroy(ptr: *anyopaque) callconv(.C) void {
    const header: *Header = @ptrCast(@alignCast(ptr));
    const object: *AllocatedTestObject = @fieldParentPtr("unknown", header);
    const allocator = object.allocator;
    object.destroy_count += 1;
    allocator.destroy(object);
}

test "queryInterface returns FUnknown pointer and increments refcount" {
    var object = TestObject{};
    const unknown = object.asUnknown();
    var out: ?*anyopaque = null;

    const result = unknown.vtable.queryInterface(unknown, &iid, &out);

    try std.testing.expectEqual(kResultOk, result);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(unknown)), out);
    try std.testing.expectEqual(@as(uint32, 2), object.refCount());
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
    try std.testing.expectEqual(@as(uint32, 1), object.refCount());
}

test "addRef and release update the atomic refcount" {
    var object = TestObject{};
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 2), unknown.vtable.addRef(unknown));
    try std.testing.expectEqual(@as(uint32, 1), unknown.vtable.release(unknown));
}

test "release calls destroy when refcount reaches zero" {
    var object = TestObject{
        .unknown = Header.init(&test_vtable, testDestroy),
    };
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 0), unknown.vtable.release(unknown));
    try std.testing.expectEqual(@as(uint32, 1), object.destroy_count);
}

test "atomic refcount tolerates concurrent add and release pairs" {
    const worker_count = 8;
    const iterations = 20_000;

    const Worker = struct {
        fn run(unknown: *Header) void {
            for (0..iterations) |_| {
                _ = unknown.vtable.addRef(unknown);
                _ = unknown.vtable.release(unknown);
            }
        }
    };

    var object = TestObject{};
    const unknown = object.asUnknown();
    var threads: [worker_count]std.Thread = undefined;

    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{unknown});
    }
    for (threads) |thread| {
        thread.join();
    }

    try std.testing.expectEqual(@as(uint32, 1), object.refCount());
}

test "allocator-owned object is destroyed at refcount zero" {
    const allocator = std.testing.allocator;
    const object = try AllocatedTestObject.create(allocator);
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 0), unknown.vtable.release(unknown));
}
