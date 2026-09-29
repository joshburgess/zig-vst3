const std = @import("std");
const tuid = @import("tuid.zig");

pub const tresult = i32;
pub const uint32 = u32;

pub const kResultOk: tresult = 0;
pub const kNoInterface: tresult = -1;
pub const kInvalidArgument: tresult = 2;

pub const iid = tuid.inlineUid(0x00000000, 0x00000000, 0xC0000000, 0x00000046);

pub const VTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) tresult,
    addRef: *const fn (*anyopaque) callconv(.c) uint32,
    release: *const fn (*anyopaque) callconv(.c) uint32,
};

pub const QueryArguments = struct {
    requested_iid: *const tuid.TUID,
    out: *?*anyopaque,
};

pub fn queryArguments(
    requested_iid: [*c]const tuid.TUID,
    out: [*c]?*anyopaque,
) ?QueryArguments {
    if (requested_iid == null or out == null) return null;
    return .{
        .requested_iid = @ptrCast(requested_iid),
        .out = @ptrCast(out),
    };
}

pub const Header = extern struct {
    vtable: *const VTable,
    ref_count: std.atomic.Value(uint32),
    destroy: ?*const fn (*anyopaque) callconv(.c) void,

    pub fn init(vtable: *const VTable, destroy: ?*const fn (*anyopaque) callconv(.c) void) Header {
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

fn testQueryInterface(ptr: *anyopaque, requested_iid_raw: [*c]const tuid.TUID, out_raw: [*c]?*anyopaque) callconv(.c) tresult {
    const arguments = queryArguments(requested_iid_raw, out_raw) orelse
        return kInvalidArgument;
    const requested_iid = arguments.requested_iid;
    const out = arguments.out;
    const self = ownerFromUnknown(ptr);
    self.query_count +|= 1;

    if (std.mem.eql(u8, requested_iid, &iid)) {
        _ = addRef(ptr);
        out.* = ptr;
        return kResultOk;
    }

    out.* = null;
    return kNoInterface;
}

pub fn addRef(ptr: *anyopaque) callconv(.c) uint32 {
    const header: *Header = @ptrCast(@alignCast(ptr));
    return incrementRefCount(&header.ref_count, "FUnknown");
}

pub fn release(ptr: *anyopaque) callconv(.c) uint32 {
    const header: *Header = @ptrCast(@alignCast(ptr));
    const next = decrementRefCount(&header.ref_count, "FUnknown");
    if (next == 0) {
        _ = header.ref_count.load(.acquire);
        if (header.destroy) |destroy| destroy(ptr);
    }

    return next;
}

pub fn incrementRefCount(
    ref_count: *std.atomic.Value(uint32),
    comptime _: []const u8,
) uint32 {
    while (true) {
        const previous = ref_count.load(.monotonic);
        if (previous == std.math.maxInt(uint32)) return previous;

        const next = previous + 1;
        if (ref_count.cmpxchgWeak(previous, next, .monotonic, .monotonic)) |_| {
            continue;
        }

        return next;
    }
}

pub fn decrementRefCount(
    ref_count: *std.atomic.Value(uint32),
    comptime _: []const u8,
) uint32 {
    while (true) {
        const previous = ref_count.load(.monotonic);
        if (previous == 0 or previous == std.math.maxInt(uint32))
            return std.math.maxInt(uint32);

        const next = previous - 1;
        if (ref_count.cmpxchgWeak(previous, next, .release, .monotonic)) |_| {
            continue;
        }

        return next;
    }
}

pub fn allocatorDestroyFn(comptime Object: type, comptime header_field: []const u8) *const fn (*anyopaque) callconv(.c) void {
    return struct {
        fn destroy(ptr: *anyopaque) callconv(.c) void {
            const header: *Header = @ptrCast(@alignCast(ptr));
            const object: *Object = @fieldParentPtr(header_field, header);
            const allocator = object.allocator;
            allocator.destroy(object);
        }
    }.destroy;
}

fn testAddRef(ptr: *anyopaque) callconv(.c) uint32 {
    return addRef(ptr);
}

fn testRelease(ptr: *anyopaque) callconv(.c) uint32 {
    return release(ptr);
}

fn testDestroy(ptr: *anyopaque) callconv(.c) void {
    ownerFromUnknown(ptr).destroy_count += 1;
}

pub const AllocatedTestObject = struct {
    unknown: Header = Header.init(&test_vtable, allocatorDestroyFn(AllocatedTestObject, "unknown")),
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

pub const OffsetAllocatedTestObject = struct {
    prefix: uint32 = 1234,
    unknown: Header = Header.init(&test_vtable, allocatorDestroyFn(OffsetAllocatedTestObject, "unknown")),
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*OffsetAllocatedTestObject {
        const object = try allocator.create(OffsetAllocatedTestObject);
        object.* = .{ .allocator = allocator };
        return object;
    }

    pub fn asUnknown(self: *OffsetAllocatedTestObject) *Header {
        return &self.unknown;
    }
};

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

test "queryInterface rejects null query arguments" {
    var object = TestObject{};
    const unknown = object.asUnknown();
    var out: ?*anyopaque = @ptrCast(unknown);

    try std.testing.expectEqual(
        kInvalidArgument,
        unknown.vtable.queryInterface(unknown, null, &out),
    );
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(unknown)), out);
    try std.testing.expectEqual(
        kInvalidArgument,
        unknown.vtable.queryInterface(unknown, &iid, null),
    );
    try std.testing.expectEqual(@as(uint32, 1), object.refCount());
    try std.testing.expectEqual(@as(uint32, 0), object.query_count);
}

test "addRef and release update the atomic refcount" {
    var object = TestObject{};
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 2), unknown.vtable.addRef(unknown));
    try std.testing.expectEqual(@as(uint32, 1), unknown.vtable.release(unknown));
}

test "incrementRefCount updates atomic refcount" {
    var ref_count = std.atomic.Value(uint32).init(41);

    try std.testing.expectEqual(@as(uint32, 42), incrementRefCount(&ref_count, "Test"));
    try std.testing.expectEqual(@as(uint32, 42), ref_count.load(.monotonic));
}

test "decrementRefCount updates atomic refcount" {
    var ref_count = std.atomic.Value(uint32).init(42);

    try std.testing.expectEqual(@as(uint32, 41), decrementRefCount(&ref_count, "Test"));
    try std.testing.expectEqual(@as(uint32, 41), ref_count.load(.monotonic));
}

test "atomic refcount contains overflow and underflow states" {
    var saturated = std.atomic.Value(uint32).init(
        std.math.maxInt(uint32),
    );
    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        incrementRefCount(&saturated, "Test"),
    );
    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        saturated.load(.monotonic),
    );
    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        decrementRefCount(&saturated, "Test"),
    );
    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        saturated.load(.monotonic),
    );

    var empty = std.atomic.Value(uint32).init(0);
    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        decrementRefCount(&empty, "Test"),
    );
    try std.testing.expectEqual(@as(uint32, 0), empty.load(.monotonic));
}

test "concurrent malformed releases cannot wrap an atomic refcount" {
    const Shared = struct {
        ref_count: std.atomic.Value(uint32) =
            std.atomic.Value(uint32).init(1),
        results: [2]uint32 = undefined,
        round: std.atomic.Value(uint32) =
            std.atomic.Value(uint32).init(0),
        completed: std.atomic.Value(u8) =
            std.atomic.Value(u8).init(0),

        fn release(shared: *@This(), index: usize) void {
            var observed_round: uint32 = 0;
            while (true) {
                const current_round = shared.round.load(.acquire);
                if (current_round == std.math.maxInt(uint32)) return;
                if (current_round == observed_round) {
                    std.Thread.yield() catch {};
                    continue;
                }
                shared.results[index] = decrementRefCount(
                    &shared.ref_count,
                    "Test",
                );
                observed_round = current_round;
                _ = shared.completed.fetchAdd(1, .release);
            }
        }
    };

    var shared = Shared{};
    const first = try std.Thread.spawn(
        .{},
        Shared.release,
        .{ &shared, 0 },
    );
    const second = try std.Thread.spawn(
        .{},
        Shared.release,
        .{ &shared, 1 },
    );
    for (1..4_097) |round| {
        shared.ref_count.store(1, .release);
        shared.completed.store(0, .release);
        shared.round.store(@intCast(round), .release);
        while (shared.completed.load(.acquire) != 2)
            std.Thread.yield() catch {};
        try std.testing.expectEqual(
            @as(uint32, 0),
            shared.ref_count.load(.acquire),
        );
        const zero_count = @as(usize, @intFromBool(
            shared.results[0] == 0,
        )) + @as(usize, @intFromBool(shared.results[1] == 0));
        const contained_count = @as(usize, @intFromBool(
            shared.results[0] == std.math.maxInt(uint32),
        )) + @as(usize, @intFromBool(
            shared.results[1] == std.math.maxInt(uint32),
        ));
        try std.testing.expectEqual(@as(usize, 1), zero_count);
        try std.testing.expectEqual(@as(usize, 1), contained_count);
    }
    shared.round.store(std.math.maxInt(uint32), .release);
    first.join();
    second.join();
}

test "release calls destroy when refcount reaches zero" {
    var object = TestObject{
        .unknown = Header.init(&test_vtable, testDestroy),
    };
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 0), unknown.vtable.release(unknown));
    try std.testing.expectEqual(@as(uint32, 1), object.destroy_count);
}

test "release does not destroy a saturated object" {
    var object = TestObject{
        .unknown = Header.init(&test_vtable, testDestroy),
    };
    const unknown = object.asUnknown();
    unknown.ref_count.store(std.math.maxInt(uint32), .monotonic);

    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        unknown.vtable.release(unknown),
    );
    try std.testing.expectEqual(
        std.math.maxInt(uint32),
        object.refCount(),
    );
    try std.testing.expectEqual(@as(uint32, 0), object.destroy_count);
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

test "allocator destroy helper recovers object at nonzero field offset" {
    const allocator = std.testing.allocator;
    const object = try OffsetAllocatedTestObject.create(allocator);
    const unknown = object.asUnknown();

    try std.testing.expectEqual(@as(uint32, 0), unknown.vtable.release(unknown));
}
