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
                        return create(requested_iid, out);
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

fn copyZ(dest: anytype, source: []const u8) void {
    const N = @typeInfo(@TypeOf(dest.*)).array.len;
    @memset(dest, 0);
    const len = @min(source.len, N - 1);
    @memcpy(dest[0..len], source[0..len]);
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

test "static factory dispatches createInstance by class id" {
    const Create = struct {
        fn create(_: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
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
}
