const std = @import("std");
const ara_vst3 = @import("ara_vst3.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_factory = @import("factory.zig");

pub fn MainFactoryRegistration(comptime Config: type) type {
    comptime validateConfig(Config);

    return struct {
        const Self = @This();

        pub var instance = ara_vst3.MainFactory.init(Config.factory);

        pub const class_info = vst_factory.ClassInfo{
            .cid = Config.cid,
            .cardinality = ipluginbase.PClassInfo.kManyInstances,
            .category = ara_vst3.main_factory_class,
            .name = Config.name,
            .vendor = if (@hasDecl(Config, "vendor"))
                Config.vendor
            else
                "",
            .version = if (@hasDecl(Config, "version"))
                Config.version
            else
                "",
            .sdk_version = if (@hasDecl(Config, "sdk_version"))
                Config.sdk_version
            else
                vst_factory.vst_sdk_version,
            .create = create,
        };

        pub fn asInterface() *ara_vst3.IMainFactory {
            return instance.asInterface();
        }

        fn create(
            requested_iid: types.FIDString,
            out: *?*anyopaque,
        ) callconv(.c) types.tresult {
            const iface = instance.asInterface();
            return iface.vtable.queryInterface(
                iface,
                @ptrCast(requested_iid),
                out,
            );
        }

        comptime {
            _ = Self;
        }
    };
}

pub fn appendMainFactoryClass(
    comptime product_classes: []const vst_factory.ClassInfo,
    comptime Registration: type,
) [product_classes.len + 1]vst_factory.ClassInfo {
    if (!@hasDecl(Registration, "class_info"))
        @compileError(
            "ARA class-list assembly requires a main factory registration",
        );
    if (@TypeOf(Registration.class_info) != vst_factory.ClassInfo)
        @compileError(
            "ARA main factory registration has invalid class metadata",
        );
    comptime var result: [product_classes.len + 1]vst_factory.ClassInfo =
        undefined;
    inline for (product_classes, 0..) |class_info, index| {
        if (comptime std.mem.eql(
            u8,
            &class_info.cid,
            &Registration.class_info.cid,
        ))
            @compileError(
                "ARA main factory class ID duplicates a product class ID",
            );
        result[index] = class_info;
    }
    result[product_classes.len] = Registration.class_info;
    return result;
}

fn validateConfig(comptime Config: type) void {
    if (!@hasDecl(Config, "cid"))
        @compileError("ARA main factory registration requires cid");
    if (!@hasDecl(Config, "name"))
        @compileError("ARA main factory registration requires name");
    if (!@hasDecl(Config, "factory"))
        @compileError("ARA main factory registration requires factory");
    if (@TypeOf(Config.cid) != [16]u8)
        @compileError("ARA main factory registration cid must be a TUID");
    if (@TypeOf(Config.factory) != *const ara_vst3.Factory)
        @compileError(
            "ARA main factory registration factory has the wrong type",
        );
    if (Config.name.len == 0)
        @compileError("ARA main factory registration name is empty");
}

test "ARA main factory registration publishes matching metadata and factory" {
    const raw_factory: *const ara_vst3.Factory =
        @ptrFromInt(0x1000);
    const Registration = MainFactoryRegistration(struct {
        pub const cid = [_]u8{
            0x00, 0x11, 0x22, 0x33,
            0x44, 0x55, 0x66, 0x77,
            0x88, 0x99, 0xAA, 0xBB,
            0xCC, 0xDD, 0xEE, 0xFF,
        };
        pub const name = "ARA Test";
        pub const factory = raw_factory;
        pub const vendor = "Test Vendor";
        pub const version = "1.0";
    });
    const product_cid = [_]u8{
        0x10, 0x11, 0x12, 0x13,
        0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B,
        0x1C, 0x1D, 0x1E, 0x1F,
    };
    const Product = struct {
        pub const classes = appendMainFactoryClass(
            &.{
                vst_factory.ClassInfo{
                    .cid = product_cid,
                    .category = "Audio Module Class",
                    .name = "Product",
                },
            },
            Registration,
        );
    };
    const ProductFactory = vst_factory.StaticFactory(
        .{ .vendor = "Test Vendor" },
        &Product.classes,
    );
    const product_factory = ProductFactory.getPluginFactory().?;
    try std.testing.expectEqual(
        @as(types.int32, 2),
        product_factory.vtable.countClasses(product_factory),
    );
    var info: ipluginbase.PClassInfo = .{};
    try std.testing.expectEqual(
        types.kResultOk,
        product_factory.vtable.getClassInfo(
            product_factory,
            1,
            &info,
        ),
    );
    try std.testing.expectEqualStrings(
        ara_vst3.main_factory_class,
        std.mem.sliceTo(&info.category, 0),
    );
    try std.testing.expectEqualStrings(
        "ARA Test",
        std.mem.sliceTo(&info.name, 0),
    );

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        product_factory.vtable.createInstance(
            product_factory,
            @ptrCast(&Registration.class_info.cid),
            @ptrCast(&ara_vst3.main_factory_iid),
            &out,
        ),
    );
    const main_factory: *ara_vst3.IMainFactory =
        @ptrCast(@alignCast(out orelse
            return error.TestUnexpectedResult));
    try std.testing.expect(
        main_factory.vtable.getFactory(main_factory) == raw_factory,
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        main_factory.vtable.release(main_factory),
    );

    out = @ptrFromInt(0x2000);
    try std.testing.expectEqual(
        types.kNoInterface,
        product_factory.vtable.createInstance(
            product_factory,
            @ptrCast(&Registration.class_info.cid),
            @ptrCast(&ipluginbase.iplugin_factory_iid),
            &out,
        ),
    );
    try std.testing.expect(out == null);
}
