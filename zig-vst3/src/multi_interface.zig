const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const tuid = @import("tuid.zig");

pub const test_a_iid = tuid.inlineUid(0x11111111, 0x11111111, 0x11111111, 0x11111111);
pub const test_b_iid = tuid.inlineUid(0x22222222, 0x22222222, 0x22222222, 0x22222222);
pub const test_c_iid = tuid.inlineUid(0x33333333, 0x33333333, 0x33333333, 0x33333333);

pub const TestAVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) funknown.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    release: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    callA: *const fn (*anyopaque) callconv(.c) funknown.uint32,
};

pub const TestBVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) funknown.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    release: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    callB: *const fn (*anyopaque) callconv(.c) funknown.uint32,
};

pub const TestCVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) funknown.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    release: *const fn (*anyopaque) callconv(.c) funknown.uint32,
    callC: *const fn (*anyopaque) callconv(.c) funknown.uint32,
};

pub const InterfaceHeader = extern struct {
    vtable: *const anyopaque,
};

pub const TestObject = extern struct {
    unknown: funknown.Header = funknown.Header.init(&unknown_vtable, null),
    a: InterfaceHeader = .{ .vtable = &a_vtable },
    b: InterfaceHeader = .{ .vtable = &b_vtable },
    c: InterfaceHeader = .{ .vtable = &c_vtable },
    a_calls: funknown.uint32 = 0,
    b_calls: funknown.uint32 = 0,
    c_calls: funknown.uint32 = 0,

    pub fn asUnknown(self: *TestObject) *funknown.Header {
        return &self.unknown;
    }
};

const unknown_vtable = funknown.VTable{
    .queryInterface = queryFromUnknown,
    .addRef = addRefFromUnknown,
    .release = releaseFromUnknown,
};

const a_vtable = TestAVTable{
    .queryInterface = queryFromA,
    .addRef = addRefFromA,
    .release = releaseFromA,
    .callA = callA,
};

const b_vtable = TestBVTable{
    .queryInterface = queryFromB,
    .addRef = addRefFromB,
    .release = releaseFromB,
    .callB = callB,
};

const c_vtable = TestCVTable{
    .queryInterface = queryFromC,
    .addRef = addRefFromC,
    .release = releaseFromC,
    .callC = callC,
};

fn objectFromUnknown(ptr: *anyopaque) *TestObject {
    const header: *funknown.Header = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("unknown", header);
}

fn objectFromA(ptr: *anyopaque) *TestObject {
    const header: *InterfaceHeader = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("a", header);
}

fn objectFromB(ptr: *anyopaque) *TestObject {
    const header: *InterfaceHeader = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("b", header);
}

fn objectFromC(ptr: *anyopaque) *TestObject {
    const header: *InterfaceHeader = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("c", header);
}

fn query(object: *TestObject, requested_iid: *const tuid.TUID, out: *?*anyopaque) funknown.tresult {
    const entries = [_]interface_map.Entry{
        interface_map.fieldEntry("unknown", object, &funknown.iid),
        interface_map.fieldEntry("a", object, &test_a_iid),
        interface_map.fieldEntry("b", object, &test_b_iid),
        interface_map.fieldEntry("c", object, &test_c_iid),
    };
    return interface_map.query(&object.unknown, &entries, requested_iid, out);
}

fn queryFromUnknown(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) funknown.tresult {
    return query(objectFromUnknown(ptr), requested_iid, out);
}

fn queryFromA(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) funknown.tresult {
    return query(objectFromA(ptr), requested_iid, out);
}

fn queryFromB(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) funknown.tresult {
    return query(objectFromB(ptr), requested_iid, out);
}

fn queryFromC(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) funknown.tresult {
    return query(objectFromC(ptr), requested_iid, out);
}

fn addRefFromUnknown(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    return funknown.addRef(ptr);
}

fn releaseFromUnknown(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    return funknown.release(ptr);
}

fn addRefFromA(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromA(ptr);
    return object.unknown.vtable.addRef(&object.unknown);
}

fn releaseFromA(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromA(ptr);
    return object.unknown.vtable.release(&object.unknown);
}

fn addRefFromB(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromB(ptr);
    return object.unknown.vtable.addRef(&object.unknown);
}

fn releaseFromB(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromB(ptr);
    return object.unknown.vtable.release(&object.unknown);
}

fn addRefFromC(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromC(ptr);
    return object.unknown.vtable.addRef(&object.unknown);
}

fn releaseFromC(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromC(ptr);
    return object.unknown.vtable.release(&object.unknown);
}

fn callA(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromA(ptr);
    object.a_calls += 1;
    return object.a_calls;
}

fn callB(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromB(ptr);
    object.b_calls += 1;
    return object.b_calls;
}

fn callC(ptr: *anyopaque) callconv(.c) funknown.uint32 {
    const object = objectFromC(ptr);
    object.c_calls += 1;
    return object.c_calls;
}

test "queryInterface returns distinct interface pointers for one object" {
    var object = TestObject{};
    const unknown = object.asUnknown();
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(funknown.kResultOk, unknown.vtable.queryInterface(unknown, &test_a_iid, &out));
    const a: *InterfaceHeader = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&object.a)), out.?);
    try std.testing.expectEqual(@as(funknown.uint32, 1), @as(*const TestAVTable, @ptrCast(@alignCast(a.vtable))).callA(a));

    try std.testing.expectEqual(funknown.kResultOk, @as(*const TestAVTable, @ptrCast(@alignCast(a.vtable))).queryInterface(a, &test_b_iid, &out));
    const b: *InterfaceHeader = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(funknown.uint32, 1), @as(*const TestBVTable, @ptrCast(@alignCast(b.vtable))).callB(b));

    try std.testing.expectEqual(funknown.kResultOk, @as(*const TestBVTable, @ptrCast(@alignCast(b.vtable))).queryInterface(b, &test_c_iid, &out));
    const c: *InterfaceHeader = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(funknown.uint32, 1), @as(*const TestCVTable, @ptrCast(@alignCast(c.vtable))).callC(c));

    try std.testing.expectEqual(@as(funknown.uint32, 1), object.a_calls);
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.b_calls);
    try std.testing.expectEqual(@as(funknown.uint32, 1), object.c_calls);
    try std.testing.expectEqual(@as(funknown.uint32, 4), object.unknown.ref_count.load(.monotonic));
}
