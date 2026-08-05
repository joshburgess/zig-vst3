const std = @import("std");
const fixed_string = @import("fixed_string.zig");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const types = @import("pluginterfaces/base/types.zig");
const tuid = @import("tuid.zig");
const vst_index = @import("vst_index.zig");

pub const vst_sdk_version = "VST 3.8.0";

pub const FactoryInfo = struct {
    vendor: []const u8,
    url: []const u8 = "",
    email: []const u8 = "",
    flags: types.int32 = 0,
};

pub const ClassInfo = struct {
    pub const CreateFn = *const fn (types.FIDString, *?*anyopaque) callconv(.c) types.tresult;

    cid: tuid.TUID,
    cardinality: types.int32 = ipluginbase.PClassInfo.kManyInstances,
    category: []const u8,
    name: []const u8,
    class_flags: types.uint32 = 0,
    sub_categories: []const u8 = "",
    vendor: []const u8 = "",
    version: []const u8 = "",
    sdk_version: []const u8 = vst_sdk_version,
    create: ?CreateFn = null,
};

pub fn StaticFactory(comptime info: FactoryInfo, comptime classes: []const ClassInfo) type {
    return struct {
        const Self = @This();

        pub const Instance = extern struct {
            iface: ipluginbase.IPluginFactory = .{ .vtable = &vtable },
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        };

        pub var instance = Instance{};

        pub fn getPluginFactory() ?*ipluginbase.IPluginFactory {
            return &instance.iface;
        }

        const vtable = ipluginbase.IPluginFactoryVTable{
            .queryInterface = queryInterface,
            .addRef = addRef,
            .release = release,
            .getFactoryInfo = getFactoryInfo,
            .countClasses = countClasses,
            .getClassInfo = getClassInfo,
            .createInstance = createInstance,
        };

        const owner = interface_map.ownerFromField(Instance, ipluginbase.IPluginFactory, "iface");

        fn queryInterface(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ipluginbase.iplugin_factory_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseStaticRef(&owner(ptr).ref_count);
        }

        fn getFactoryInfo(_: *anyopaque, out: [*c]ipluginbase.PFactoryInfo) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            fillFactoryInfo(info, @ptrCast(out));
            return types.kResultOk;
        }

        fn countClasses(_: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(classes.len);
        }

        fn getClassInfo(_: *anyopaque, index: types.int32, out: [*c]ipluginbase.PClassInfo) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *ipluginbase.PClassInfo = @ptrCast(out);
            const class = classAt(index) orelse return failClassInfo(output);
            fillClassInfo(class, output);
            return types.kResultOk;
        }

        fn createInstance(_: *anyopaque, cid: ?types.FIDString, requested_iid: ?types.FIDString, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *?*anyopaque = @ptrCast(out);
            output.* = null;
            const class_id = cid orelse return types.kInvalidArgument;
            const interface_id = requested_iid orelse return types.kInvalidArgument;
            return createClassInstance(classes, class_id, interface_id, output);
        }

        fn classAt(index: types.int32) ?ClassInfo {
            return classAtIndex(classes, index);
        }

        comptime {
            _ = Self;
            vst_index.requireInt32Length(classes.len, "VST3 factory class count");
        }
    };
}

pub fn StaticFactory3(comptime info: FactoryInfo, comptime classes: []const ClassInfo) type {
    return struct {
        const Self = @This();

        pub const Instance = extern struct {
            iface: ipluginbase.IPluginFactory3 = .{ .vtable = &vtable },
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
            host_context: ?*funknown.Header = null,
        };

        pub var instance = Instance{};

        pub fn getPluginFactory() ?*ipluginbase.IPluginFactory {
            return @ptrCast(&instance.iface);
        }

        pub fn getPluginFactory3() *ipluginbase.IPluginFactory3 {
            return &instance.iface;
        }

        const vtable = ipluginbase.IPluginFactory3VTable{
            .queryInterface = queryInterface,
            .addRef = addRef,
            .release = release,
            .getFactoryInfo = getFactoryInfo,
            .countClasses = countClasses,
            .getClassInfo = getClassInfo,
            .createInstance = createInstance,
            .getClassInfo2 = getClassInfo2,
            .getClassInfoUnicode = getClassInfoUnicode,
            .setHostContext = setHostContext,
        };

        const owner = interface_map.ownerFromField(Instance, ipluginbase.IPluginFactory3, "iface");

        fn queryInterface(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ipluginbase.iplugin_factory_iid, .ptr = ptr },
                .{ .iid = &ipluginbase.iplugin_factory2_iid, .ptr = ptr },
                .{ .iid = &ipluginbase.iplugin_factory3_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseStaticRef(&owner(ptr).ref_count);
        }

        fn getFactoryInfo(_: *anyopaque, out: [*c]ipluginbase.PFactoryInfo) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *ipluginbase.PFactoryInfo = @ptrCast(out);
            fillFactoryInfo(info, output);
            return types.kResultOk;
        }

        fn countClasses(_: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(classes.len);
        }

        fn getClassInfo(_: *anyopaque, index: types.int32, out: [*c]ipluginbase.PClassInfo) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *ipluginbase.PClassInfo = @ptrCast(out);
            const class = classAt(index) orelse return failClassInfo(output);
            fillClassInfo(class, output);
            return types.kResultOk;
        }

        fn createInstance(_: *anyopaque, cid: ?types.FIDString, requested_iid: ?types.FIDString, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *?*anyopaque = @ptrCast(out);
            output.* = null;
            const class_id = cid orelse return types.kInvalidArgument;
            const interface_id = requested_iid orelse return types.kInvalidArgument;
            return createClassInstance(classes, class_id, interface_id, output);
        }

        fn getClassInfo2(_: *anyopaque, index: types.int32, out: [*c]ipluginbase.PClassInfo2) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *ipluginbase.PClassInfo2 = @ptrCast(out);
            const class = classAt(index) orelse return failClassInfo(output);
            fillClassInfo2(info, class, output);
            return types.kResultOk;
        }

        fn getClassInfoUnicode(_: *anyopaque, index: types.int32, out: [*c]ipluginbase.PClassInfoW) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *ipluginbase.PClassInfoW = @ptrCast(out);
            const class = classAt(index) orelse return failClassInfo(output);
            fillClassInfoUnicode(info, class, output);
            return types.kResultOk;
        }

        fn setHostContext(ptr: *anyopaque, context: ?*funknown.Header) callconv(.c) types.tresult {
            owner(ptr).host_context = context;
            return types.kResultOk;
        }

        fn classAt(index: types.int32) ?ClassInfo {
            return classAtIndex(classes, index);
        }

        comptime {
            _ = Self;
            vst_index.requireInt32Length(classes.len, "VST3 factory class count");
        }
    };
}

fn matchesClassId(cid: types.FIDString, class: ClassInfo) bool {
    return std.mem.eql(u8, cid[0..tuid.byte_count], &class.cid);
}

fn classAtIndex(comptime classes: []const ClassInfo, index: types.int32) ?ClassInfo {
    if (comptime classes.len == 0) return null;
    const class_index = vst_index.bounded(index, classes.len) orelse return null;
    return classes[class_index];
}

fn failClassInfo(out: anytype) types.tresult {
    out.* = .{};
    return types.kInvalidArgument;
}

fn createClassInstance(comptime classes: []const ClassInfo, cid: types.FIDString, requested_iid: types.FIDString, out: *?*anyopaque) types.tresult {
    for (classes) |class| {
        if (matchesClassId(cid, class)) {
            if (class.create) |create| {
                const result = create(requested_iid, out);
                if (result != types.kResultOk) out.* = null;
                return result;
            }
            break;
        }
    }

    out.* = null;
    return types.kNoInterface;
}

fn releaseStaticRef(ref_count: *std.atomic.Value(types.uint32)) types.uint32 {
    while (true) {
        const previous = ref_count.load(.monotonic);
        if (previous <= 1) return 1;

        const next = previous - 1;
        if (ref_count.cmpxchgWeak(previous, next, .release, .monotonic)) |_| {
            continue;
        }

        return next;
    }
}

fn classVendor(info: FactoryInfo, class: ClassInfo) []const u8 {
    return if (class.vendor.len == 0) info.vendor else class.vendor;
}

fn fillFactoryInfo(info: FactoryInfo, out: *ipluginbase.PFactoryInfo) void {
    out.* = .{ .flags = info.flags };
    fixed_string.copyAsciiZ(&out.vendor, info.vendor);
    fixed_string.copyAsciiZ(&out.url, info.url);
    fixed_string.copyAsciiZ(&out.email, info.email);
}

fn fillClassInfo(class: ClassInfo, out: *ipluginbase.PClassInfo) void {
    out.* = .{
        .cid = class.cid,
        .cardinality = class.cardinality,
    };
    fixed_string.copyAsciiZ(&out.category, class.category);
    fixed_string.copyAsciiZ(&out.name, class.name);
}

fn fillClassInfo2(info: FactoryInfo, class: ClassInfo, out: *ipluginbase.PClassInfo2) void {
    out.* = .{
        .cid = class.cid,
        .cardinality = class.cardinality,
        .classFlags = class.class_flags,
    };
    fixed_string.copyAsciiZ(&out.category, class.category);
    fixed_string.copyAsciiZ(&out.name, class.name);
    fixed_string.copyAsciiZ(&out.subCategories, class.sub_categories);
    fixed_string.copyAsciiZ(&out.vendor, classVendor(info, class));
    fixed_string.copyAsciiZ(&out.version, class.version);
    fixed_string.copyAsciiZ(&out.sdkVersion, class.sdk_version);
}

fn fillClassInfoUnicode(info: FactoryInfo, class: ClassInfo, out: *ipluginbase.PClassInfoW) void {
    out.* = .{
        .cid = class.cid,
        .cardinality = class.cardinality,
        .classFlags = class.class_flags,
    };
    fixed_string.copyAsciiZ(&out.category, class.category);
    fixed_string.copyAsciiToUtf16Z(&out.name, class.name);
    fixed_string.copyAsciiZ(&out.subCategories, class.sub_categories);
    fixed_string.copyAsciiToUtf16Z(&out.vendor, classVendor(info, class));
    fixed_string.copyAsciiToUtf16Z(&out.version, class.version);
    fixed_string.copyAsciiToUtf16Z(&out.sdkVersion, class.sdk_version);
}

test "static factory exposes metadata and class count" {
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
        },
    });

    const factory = TestFactory.getPluginFactory().?;
    var factory_info: ipluginbase.PFactoryInfo = .{};
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(types.kResultOk, factory.vtable.getFactoryInfo(factory, &factory_info));
    try std.testing.expectEqualStrings("Test Vendor", std.mem.sliceTo(&factory_info.vendor, 0));
    try std.testing.expectEqual(@as(types.int32, 1), factory.vtable.countClasses(factory));
    try std.testing.expectEqual(types.kResultOk, factory.vtable.getClassInfo(factory, 0, &class_info));
    try std.testing.expectEqualStrings("Audio Module Class", std.mem.sliceTo(&class_info.category, 0));
    try std.testing.expectEqualStrings("Test Plug-in", std.mem.sliceTo(&class_info.name, 0));
}

test "static factory truncates fixed-size metadata strings" {
    const long = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
    const TestFactory = StaticFactory(.{
        .vendor = long,
        .url = long,
        .email = long,
        .flags = 7,
    }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = long,
            .name = long,
        },
    });

    const factory = TestFactory.getPluginFactory().?;
    var factory_info: ipluginbase.PFactoryInfo = .{};
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(types.kResultOk, factory.vtable.getFactoryInfo(factory, &factory_info));
    try std.testing.expectEqual(@as(u8, 'a'), factory_info.vendor[0]);
    try std.testing.expectEqual(long[62], factory_info.vendor[62]);
    try std.testing.expectEqual(@as(u8, 0), factory_info.vendor[63]);
    try std.testing.expectEqual(@as(types.int32, 7), factory_info.flags);

    try std.testing.expectEqual(types.kResultOk, factory.vtable.getClassInfo(factory, 0, &class_info));
    try std.testing.expectEqual(@as(u8, 'a'), class_info.category[0]);
    try std.testing.expectEqual(long[30], class_info.category[30]);
    try std.testing.expectEqual(@as(u8, 0), class_info.category[31]);
    try std.testing.expectEqual(@as(u8, 'a'), class_info.name[0]);
    try std.testing.expectEqual(long[62], class_info.name[62]);
    try std.testing.expectEqual(@as(u8, 0), class_info.name[63]);
}

test "static factory clears invalid class info outputs" {
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory().?;
    var class_info = ipluginbase.PClassInfo{
        .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
        .cardinality = 7,
    };

    try std.testing.expectEqual(@as(types.int32, 0), factory.vtable.countClasses(factory));
    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo(factory, 0, &class_info));
    try std.testing.expectEqual(@as(types.int32, 0), class_info.cardinality);

    const NonEmptyFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
        },
    });
    const non_empty = NonEmptyFactory.getPluginFactory().?;
    class_info.cardinality = 7;
    try std.testing.expectEqual(types.kInvalidArgument, non_empty.vtable.getClassInfo(non_empty, -1, &class_info));
    try std.testing.expectEqual(@as(types.int32, 0), class_info.cardinality);
    class_info.cardinality = 7;
    try std.testing.expectEqual(types.kInvalidArgument, non_empty.vtable.getClassInfo(non_empty, 1, &class_info));
    try std.testing.expectEqual(@as(types.int32, 0), class_info.cardinality);
}

test "static factory rejects null callback arguments" {
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory().?;
    const cid = tuid.inlineUid(
        0x11111111,
        0x22222222,
        0x33333333,
        0x44444444,
    );
    var out: ?*anyopaque = @ptrFromInt(0x1);

    try std.testing.expectEqual(
        types.kInvalidArgument,
        factory.vtable.getFactoryInfo(factory, null),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        factory.vtable.getClassInfo(factory, 0, null),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        factory.vtable.createInstance(factory, null, @ptrCast(&funknown.iid), &out),
    );
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
    out = @ptrFromInt(0x1);
    try std.testing.expectEqual(
        types.kInvalidArgument,
        factory.vtable.createInstance(factory, @ptrCast(&cid), null, &out),
    );
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
    try std.testing.expectEqual(
        types.kInvalidArgument,
        factory.vtable.createInstance(
            factory,
            @ptrCast(&cid),
            @ptrCast(&funknown.iid),
            null,
        ),
    );
}

test "static factory rejects generated invalid class indexes" {
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
        },
        .{
            .cid = tuid.inlineUid(0x55555555, 0x66666666, 0x77777777, 0x88888888),
            .category = "Audio Module Class",
            .name = "Second Plug-in",
        },
    });
    const factory = TestFactory.getPluginFactory().?;
    const invalid_indexes = [_]types.int32{ -2, -1, 2, 3, std.math.maxInt(types.int32) };

    for (invalid_indexes) |index| {
        var class_info = ipluginbase.PClassInfo{
            .cid = tuid.inlineUid(0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD),
            .cardinality = 7,
        };

        try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo(factory, index, &class_info));
        try std.testing.expectEqualSlices(u8, &tuid.zero, &class_info.cid);
        try std.testing.expectEqual(@as(types.int32, 0), class_info.cardinality);
        try std.testing.expectEqual(@as(u8, 0), class_info.category[0]);
        try std.testing.expectEqual(@as(u8, 0), class_info.name[0]);
    }
}

test "static factory dispatches createInstance by class id" {
    const Create = struct {
        fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.c) types.tresult {
            if (!std.mem.eql(u8, requested_iid[0..tuid.byte_count], &funknown.iid)) return types.kNoInterface;
            out.* = @ptrFromInt(0x1);
            return types.kResultOk;
        }
    };
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
            .create = Create.create,
        },
    });

    const factory = TestFactory.getPluginFactory().?;
    const cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, factory.vtable.createInstance(factory, @ptrCast(&cid), @ptrCast(&funknown.iid), &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1)), out);
}

test "static factory clears failed create outputs" {
    const Create = struct {
        fn create(_: types.FIDString, out: *?*anyopaque) callconv(.c) types.tresult {
            out.* = @ptrFromInt(0x1);
            return types.kNoInterface;
        }
    };
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
            .create = Create.create,
        },
    });

    const factory = TestFactory.getPluginFactory().?;
    const cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    const missing_cid = tuid.inlineUid(0x55555555, 0x66666666, 0x77777777, 0x88888888);
    var out: ?*anyopaque = @ptrFromInt(0x2);

    try std.testing.expectEqual(types.kNoInterface, factory.vtable.createInstance(factory, @ptrCast(&cid), @ptrCast(&funknown.iid), &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);

    out = @ptrFromInt(0x2);
    try std.testing.expectEqual(types.kNoInterface, factory.vtable.createInstance(factory, @ptrCast(&missing_cid), @ptrCast(&funknown.iid), &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
}

test "static factory implements queryInterface for FUnknown and IPluginFactory" {
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory().?;
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, factory.vtable.queryInterface(factory, &funknown.iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(factory)), out);
    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));

    out = null;
    try std.testing.expectEqual(types.kResultOk, factory.vtable.queryInterface(factory, &ipluginbase.iplugin_factory_iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(factory)), out);
    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));

    out = @ptrFromInt(0x1);
    try std.testing.expectEqual(types.kNoInterface, factory.vtable.queryInterface(factory, &ipluginbase.iplugin_factory2_iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
}

test "static factory release keeps singleton alive" {
    const TestFactory = StaticFactory(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory().?;

    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));
    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));
}

test "static factory 3 exposes factory2 and factory3 metadata" {
    const cid = comptime tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    const TestFactory = StaticFactory3(.{
        .vendor = "Test Vendor",
        .url = "https://example.test",
        .email = "dev@example.test",
        .flags = 3,
    }, &.{
        .{
            .cid = cid,
            .category = "Audio Module Class",
            .name = "Test Plug-in",
            .class_flags = 9,
            .sub_categories = "Fx|Dynamics",
            .version = "1.2.3",
        },
    });

    const factory = TestFactory.getPluginFactory3();
    var factory2_out: ?*anyopaque = null;
    var factory3_out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, factory.vtable.queryInterface(factory, &ipluginbase.iplugin_factory2_iid, &factory2_out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(factory)), factory2_out);
    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));

    try std.testing.expectEqual(types.kResultOk, factory.vtable.queryInterface(factory, &ipluginbase.iplugin_factory3_iid, &factory3_out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(factory)), factory3_out);
    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));

    var info2 = ipluginbase.PClassInfo2{};
    try std.testing.expectEqual(types.kResultOk, factory.vtable.getClassInfo2(factory, 0, &info2));
    try std.testing.expectEqualSlices(u8, &cid, &info2.cid);
    try std.testing.expectEqual(@as(types.uint32, 9), info2.classFlags);
    try std.testing.expectEqualStrings("Fx|Dynamics", std.mem.sliceTo(&info2.subCategories, 0));
    try std.testing.expectEqualStrings("Test Vendor", std.mem.sliceTo(&info2.vendor, 0));
    try std.testing.expectEqualStrings("1.2.3", std.mem.sliceTo(&info2.version, 0));
    try std.testing.expectEqualStrings(
        vst_sdk_version,
        std.mem.sliceTo(&info2.sdkVersion, 0),
    );

    var info_w = ipluginbase.PClassInfoW{};
    try std.testing.expectEqual(types.kResultOk, factory.vtable.getClassInfoUnicode(factory, 0, &info_w));
    try std.testing.expectEqualSlices(types.char16, std.unicode.utf8ToUtf16LeStringLiteral("Test Plug-in"), std.mem.sliceTo(&info_w.name, 0));
    try std.testing.expectEqualSlices(types.char16, std.unicode.utf8ToUtf16LeStringLiteral("Test Vendor"), std.mem.sliceTo(&info_w.vendor, 0));
}

test "static factory 3 release keeps singleton alive" {
    const TestFactory = StaticFactory3(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory3();

    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));
    try std.testing.expectEqual(@as(types.uint32, 1), factory.vtable.release(factory));
}

test "static factory 3 clears missing query outputs" {
    const TestFactory = StaticFactory3(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory3();
    const missing_iid = tuid.inlineUid(0x55555555, 0x66666666, 0x77777777, 0x88888888);
    var out: ?*anyopaque = @ptrFromInt(0x1);

    try std.testing.expectEqual(types.kNoInterface, factory.vtable.queryInterface(factory, &missing_iid, &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
}

test "static factory 3 dispatches and clears create outputs" {
    const Create = struct {
        fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.c) types.tresult {
            if (!std.mem.eql(u8, requested_iid[0..tuid.byte_count], &funknown.iid)) {
                out.* = @ptrFromInt(0x1);
                return types.kNoInterface;
            }
            out.* = @ptrFromInt(0x2);
            return types.kResultOk;
        }
    };
    const TestFactory = StaticFactory3(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
            .create = Create.create,
        },
    });
    const factory = TestFactory.getPluginFactory3();
    const cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    const missing_cid = tuid.inlineUid(0x55555555, 0x66666666, 0x77777777, 0x88888888);
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, factory.vtable.createInstance(factory, @ptrCast(&cid), @ptrCast(&funknown.iid), &out));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2)), out);

    try std.testing.expectEqual(types.kNoInterface, factory.vtable.createInstance(factory, @ptrCast(&cid), @ptrCast(&ipluginbase.iplugin_factory_iid), &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);

    out = @ptrFromInt(0x3);
    try std.testing.expectEqual(types.kNoInterface, factory.vtable.createInstance(factory, @ptrCast(&missing_cid), @ptrCast(&funknown.iid), &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
}

test "static factory 3 clears invalid metadata and stores host context" {
    const TestFactory = StaticFactory3(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory3();
    var info2 = ipluginbase.PClassInfo2{ .classFlags = 77 };
    var info_w = ipluginbase.PClassInfoW{ .classFlags = 77 };

    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getFactoryInfo(factory, null));
    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo(factory, 0, null));
    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo2(factory, 0, null));
    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfoUnicode(factory, 0, null));

    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo2(factory, 0, &info2));
    try std.testing.expectEqual(@as(types.uint32, 0), info2.classFlags);
    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfoUnicode(factory, -1, &info_w));
    try std.testing.expectEqual(@as(types.uint32, 0), info_w.classFlags);

    var host = funknown.TestObject{};
    try std.testing.expectEqual(types.kResultOk, factory.vtable.setHostContext(factory, host.asUnknown()));
    try std.testing.expectEqual(host.asUnknown(), TestFactory.instance.host_context.?);
}

test "static factory 3 rejects generated invalid class indexes" {
    const TestFactory = StaticFactory3(.{ .vendor = "Test Vendor" }, &.{
        .{
            .cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
            .category = "Audio Module Class",
            .name = "Test Plug-in",
            .class_flags = 9,
            .sub_categories = "Fx",
            .version = "1.2.3",
            .sdk_version = "VST 3.8.0",
        },
        .{
            .cid = tuid.inlineUid(0x55555555, 0x66666666, 0x77777777, 0x88888888),
            .category = "Audio Module Class",
            .name = "Second Plug-in",
            .class_flags = 11,
            .sub_categories = "Instrument",
            .version = "4.5.6",
            .sdk_version = "VST 3.8.0",
        },
    });
    const factory = TestFactory.getPluginFactory3();
    const invalid_indexes = [_]types.int32{ -2, -1, 2, 3, std.math.maxInt(types.int32) };

    for (invalid_indexes) |index| {
        var info = ipluginbase.PClassInfo{
            .cid = tuid.inlineUid(0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD),
            .cardinality = 7,
        };
        var info2 = ipluginbase.PClassInfo2{
            .cid = tuid.inlineUid(0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD),
            .cardinality = 7,
            .classFlags = 77,
        };
        var info_w = ipluginbase.PClassInfoW{
            .cid = tuid.inlineUid(0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD),
            .cardinality = 7,
            .classFlags = 77,
        };

        try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo(factory, index, &info));
        try std.testing.expectEqualSlices(u8, &tuid.zero, &info.cid);
        try std.testing.expectEqual(@as(types.int32, 0), info.cardinality);
        try std.testing.expectEqual(@as(u8, 0), info.category[0]);
        try std.testing.expectEqual(@as(u8, 0), info.name[0]);

        try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo2(factory, index, &info2));
        try std.testing.expectEqualSlices(u8, &tuid.zero, &info2.cid);
        try std.testing.expectEqual(@as(types.int32, 0), info2.cardinality);
        try std.testing.expectEqual(@as(types.uint32, 0), info2.classFlags);
        try std.testing.expectEqual(@as(u8, 0), info2.category[0]);
        try std.testing.expectEqual(@as(u8, 0), info2.name[0]);
        try std.testing.expectEqual(@as(u8, 0), info2.subCategories[0]);
        try std.testing.expectEqual(@as(u8, 0), info2.vendor[0]);
        try std.testing.expectEqual(@as(u8, 0), info2.version[0]);
        try std.testing.expectEqual(@as(u8, 0), info2.sdkVersion[0]);

        try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfoUnicode(factory, index, &info_w));
        try std.testing.expectEqualSlices(u8, &tuid.zero, &info_w.cid);
        try std.testing.expectEqual(@as(types.int32, 0), info_w.cardinality);
        try std.testing.expectEqual(@as(types.uint32, 0), info_w.classFlags);
        try std.testing.expectEqual(@as(u8, 0), info_w.category[0]);
        try std.testing.expectEqual(@as(types.char16, 0), info_w.name[0]);
        try std.testing.expectEqual(@as(u8, 0), info_w.subCategories[0]);
        try std.testing.expectEqual(@as(types.char16, 0), info_w.vendor[0]);
        try std.testing.expectEqual(@as(types.char16, 0), info_w.version[0]);
        try std.testing.expectEqual(@as(types.char16, 0), info_w.sdkVersion[0]);
    }
}
