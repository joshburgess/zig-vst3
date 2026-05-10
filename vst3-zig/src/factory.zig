const std = @import("std");
const funknown = @import("funknown.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const types = @import("pluginterfaces/base/types.zig");
const tuid = @import("tuid.zig");

pub const FactoryInfo = struct {
    vendor: []const u8,
    url: []const u8 = "",
    email: []const u8 = "",
    flags: types.int32 = 0,
};

pub const ClassInfo = struct {
    pub const CreateFn = *const fn (types.FIDString, *?*anyopaque) callconv(.C) types.tresult;

    cid: tuid.TUID,
    cardinality: types.int32 = ipluginbase.PClassInfo.kManyInstances,
    category: []const u8,
    name: []const u8,
    class_flags: types.uint32 = 0,
    sub_categories: []const u8 = "",
    vendor: []const u8 = "",
    version: []const u8 = "",
    sdk_version: []const u8 = "",
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

        fn owner(ptr: *anyopaque) *Instance {
            const iface: *ipluginbase.IPluginFactory = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn queryInterface(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            if (std.mem.eql(u8, requested_iid, &funknown.iid) or
                std.mem.eql(u8, requested_iid, &ipluginbase.iplugin_factory_iid))
            {
                _ = addRef(ptr);
                out.* = ptr;
                return types.kResultOk;
            }

            out.* = null;
            return types.kNoInterface;
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPluginFactory");
        }

        fn getFactoryInfo(_: *anyopaque, out: *ipluginbase.PFactoryInfo) callconv(.C) types.tresult {
            out.* = .{ .flags = info.flags };
            copyZ(&out.vendor, info.vendor);
            copyZ(&out.url, info.url);
            copyZ(&out.email, info.email);
            return types.kResultOk;
        }

        fn countClasses(_: *anyopaque) callconv(.C) types.int32 {
            return @intCast(classes.len);
        }

        fn getClassInfo(_: *anyopaque, index: types.int32, out: *ipluginbase.PClassInfo) callconv(.C) types.tresult {
            if (comptime classes.len == 0) {
                out.* = .{};
                return types.kInvalidArgument;
            } else {
                if (index < 0 or index >= classes.len) {
                    out.* = .{};
                    return types.kInvalidArgument;
                }

                const class = classes[@intCast(index)];
                out.* = .{
                    .cid = class.cid,
                    .cardinality = class.cardinality,
                };
                copyZ(&out.category, class.category);
                copyZ(&out.name, class.name);
                return types.kResultOk;
            }
        }

        fn createInstance(_: *anyopaque, cid: types.FIDString, requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
            for (classes) |class| {
                if (std.mem.eql(u8, cid[0..16], &class.cid)) {
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

        comptime {
            _ = Self;
            if (classes.len > std.math.maxInt(types.int32)) {
                @compileError("VST3 factory class count exceeds int32 range");
            }
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

        fn owner(ptr: *anyopaque) *Instance {
            const iface: *ipluginbase.IPluginFactory3 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn queryInterface(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            if (std.mem.eql(u8, requested_iid, &funknown.iid) or
                std.mem.eql(u8, requested_iid, &ipluginbase.iplugin_factory_iid) or
                std.mem.eql(u8, requested_iid, &ipluginbase.iplugin_factory2_iid) or
                std.mem.eql(u8, requested_iid, &ipluginbase.iplugin_factory3_iid))
            {
                _ = addRef(ptr);
                out.* = ptr;
                return types.kResultOk;
            }

            out.* = null;
            return types.kNoInterface;
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPluginFactory3");
        }

        fn getFactoryInfo(_: *anyopaque, out: *ipluginbase.PFactoryInfo) callconv(.C) types.tresult {
            out.* = .{ .flags = info.flags };
            copyZ(&out.vendor, info.vendor);
            copyZ(&out.url, info.url);
            copyZ(&out.email, info.email);
            return types.kResultOk;
        }

        fn countClasses(_: *anyopaque) callconv(.C) types.int32 {
            return @intCast(classes.len);
        }

        fn getClassInfo(_: *anyopaque, index: types.int32, out: *ipluginbase.PClassInfo) callconv(.C) types.tresult {
            const class = classAt(index) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            out.* = .{
                .cid = class.cid,
                .cardinality = class.cardinality,
            };
            copyZ(&out.category, class.category);
            copyZ(&out.name, class.name);
            return types.kResultOk;
        }

        fn createInstance(_: *anyopaque, cid: types.FIDString, requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
            for (classes) |class| {
                if (std.mem.eql(u8, cid[0..16], &class.cid)) {
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

        fn getClassInfo2(_: *anyopaque, index: types.int32, out: *ipluginbase.PClassInfo2) callconv(.C) types.tresult {
            const class = classAt(index) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            out.* = .{
                .cid = class.cid,
                .cardinality = class.cardinality,
                .classFlags = class.class_flags,
            };
            copyZ(&out.category, class.category);
            copyZ(&out.name, class.name);
            copyZ(&out.subCategories, class.sub_categories);
            copyZ(&out.vendor, if (class.vendor.len == 0) info.vendor else class.vendor);
            copyZ(&out.version, class.version);
            copyZ(&out.sdkVersion, class.sdk_version);
            return types.kResultOk;
        }

        fn getClassInfoUnicode(_: *anyopaque, index: types.int32, out: *ipluginbase.PClassInfoW) callconv(.C) types.tresult {
            const class = classAt(index) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            out.* = .{
                .cid = class.cid,
                .cardinality = class.cardinality,
                .classFlags = class.class_flags,
            };
            copyZ(&out.category, class.category);
            copyZ16(&out.name, class.name);
            copyZ(&out.subCategories, class.sub_categories);
            copyZ16(&out.vendor, if (class.vendor.len == 0) info.vendor else class.vendor);
            copyZ16(&out.version, class.version);
            copyZ16(&out.sdkVersion, class.sdk_version);
            return types.kResultOk;
        }

        fn setHostContext(ptr: *anyopaque, context: ?*funknown.Header) callconv(.C) types.tresult {
            owner(ptr).host_context = context;
            return types.kResultOk;
        }

        fn classAt(index: types.int32) ?ClassInfo {
            if (comptime classes.len == 0) {
                return null;
            } else {
                if (index < 0 or index >= classes.len) return null;
                return classes[@intCast(index)];
            }
        }

        comptime {
            _ = Self;
            if (classes.len > std.math.maxInt(types.int32)) {
                @compileError("VST3 factory class count exceeds int32 range");
            }
        }
    };
}

fn copyZ(dest: anytype, source: []const u8) void {
    const N = @typeInfo(@TypeOf(dest.*)).array.len;
    @memset(dest, 0);
    const len = @min(source.len, N - 1);
    @memcpy(dest[0..len], source[0..len]);
}

fn copyZ16(dest: anytype, source: []const u8) void {
    const N = @typeInfo(@TypeOf(dest.*)).array.len;
    @memset(dest, 0);
    const len = @min(source.len, N - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
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

test "static factory dispatches createInstance by class id" {
    const Create = struct {
        fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
            if (!std.mem.eql(u8, requested_iid[0..16], &funknown.iid)) return types.kNoInterface;
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
        fn create(_: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
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
            .sdk_version = "VST 3.8.0",
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
    try std.testing.expectEqualStrings("VST 3.8.0", std.mem.sliceTo(&info2.sdkVersion, 0));

    var info_w = ipluginbase.PClassInfoW{};
    try std.testing.expectEqual(types.kResultOk, factory.vtable.getClassInfoUnicode(factory, 0, &info_w));
    try std.testing.expectEqualSlices(types.char16, std.unicode.utf8ToUtf16LeStringLiteral("Test Plug-in"), std.mem.sliceTo(&info_w.name, 0));
    try std.testing.expectEqualSlices(types.char16, std.unicode.utf8ToUtf16LeStringLiteral("Test Vendor"), std.mem.sliceTo(&info_w.vendor, 0));
}

test "static factory 3 clears invalid metadata and stores host context" {
    const TestFactory = StaticFactory3(.{ .vendor = "Test Vendor" }, &.{});
    const factory = TestFactory.getPluginFactory3();
    var info2 = ipluginbase.PClassInfo2{ .classFlags = 77 };
    var info_w = ipluginbase.PClassInfoW{ .classFlags = 77 };

    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfo2(factory, 0, &info2));
    try std.testing.expectEqual(@as(types.uint32, 0), info2.classFlags);
    try std.testing.expectEqual(types.kInvalidArgument, factory.vtable.getClassInfoUnicode(factory, -1, &info_w));
    try std.testing.expectEqual(@as(types.uint32, 0), info_w.classFlags);

    var host = funknown.TestObject{};
    try std.testing.expectEqual(types.kResultOk, factory.vtable.setHostContext(factory, host.asUnknown()));
    try std.testing.expectEqual(host.asUnknown(), TestFactory.instance.host_context.?);
}
