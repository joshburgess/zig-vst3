const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivsttestplugprovider = @import("pluginterfaces/vst/ivsttestplugprovider.zig");
const istringresult = @import("pluginterfaces/base/istringresult.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn TestPlugProvider(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivsttestplugprovider.ITestPlugProvider = .{ .vtable = &provider_vtable },
        iface2: ivsttestplugprovider.ITestPlugProvider2 = .{ .vtable = &provider2_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        component: ?*ivstcomponent.IComponent = null,
        controller: ?*ivsteditcontroller.IEditController = null,
        factory: ?*ipluginbase.IPluginFactory = null,
        release_count: types.uint32 = 0,
        last_released_component: ?*ivstcomponent.IComponent = null,
        last_released_controller: ?*ivsteditcontroller.IEditController = null,

        pub fn asProvider(self: *Self) *ivsttestplugprovider.ITestPlugProvider {
            return &self.iface;
        }

        pub fn asProvider2(self: *Self) *ivsttestplugprovider.ITestPlugProvider2 {
            return &self.iface2;
        }

        const ownerFromProvider = interface_map.ownerFromField(Self, ivsttestplugprovider.ITestPlugProvider, "iface");
        const ownerFromProvider2 = interface_map.ownerFromField(Self, ivsttestplugprovider.ITestPlugProvider2, "iface2");

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ivsttestplugprovider.itest_plug_provider_iid, .ptr = &self.iface },
                .{ .iid = &ivsttestplugprovider.itest_plug_provider2_iid, .ptr = &self.iface2 },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, providerAddRef, &entries, requested_iid, out);
        }

        fn providerQuery(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            return ownerFromProvider(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn provider2Query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromProvider2(ptr);
            return self.queryCanonical(&self.iface, requested_iid, out);
        }

        fn providerAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromProvider(ptr).ref_count, "FUnknown");
        }

        fn provider2AddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromProvider2(ptr).ref_count, "FUnknown");
        }

        fn providerRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromProvider(ptr).ref_count, "ITestPlugProvider");
        }

        fn provider2Release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromProvider2(ptr).ref_count, "ITestPlugProvider2");
        }

        fn getComponent(ptr: *anyopaque) callconv(.c) ?*ivstcomponent.IComponent {
            const self = ownerFromProvider(ptr);
            return componentFor(self);
        }

        fn provider2GetComponent(ptr: *anyopaque) callconv(.c) ?*ivstcomponent.IComponent {
            const self = ownerFromProvider2(ptr);
            return componentFor(self);
        }

        fn componentFor(self: *Self) ?*ivstcomponent.IComponent {
            const component = if (@hasDecl(Config, "getComponent")) Config.getComponent(self) else self.component;
            if (component) |value| _ = value.vtable.addRef(value);
            return component;
        }

        fn getController(ptr: *anyopaque) callconv(.c) ?*ivsteditcontroller.IEditController {
            const self = ownerFromProvider(ptr);
            return controllerFor(self);
        }

        fn provider2GetController(ptr: *anyopaque) callconv(.c) ?*ivsteditcontroller.IEditController {
            const self = ownerFromProvider2(ptr);
            return controllerFor(self);
        }

        fn controllerFor(self: *Self) ?*ivsteditcontroller.IEditController {
            const controller = if (@hasDecl(Config, "getController")) Config.getController(self) else self.controller;
            if (controller) |value| _ = value.vtable.addRef(value);
            return controller;
        }

        fn releasePlugIn(ptr: *anyopaque, component: ?*ivstcomponent.IComponent, controller: ?*ivsteditcontroller.IEditController) callconv(.c) types.tresult {
            return releasePlugInFor(ownerFromProvider(ptr), component, controller);
        }

        fn provider2ReleasePlugIn(ptr: *anyopaque, component: ?*ivstcomponent.IComponent, controller: ?*ivsteditcontroller.IEditController) callconv(.c) types.tresult {
            return releasePlugInFor(ownerFromProvider2(ptr), component, controller);
        }

        fn releasePlugInFor(self: *Self, component: ?*ivstcomponent.IComponent, controller: ?*ivsteditcontroller.IEditController) types.tresult {
            self.release_count +|= 1;
            self.last_released_component = component;
            self.last_released_controller = controller;
            defer releaseComponent(component);
            defer releaseController(controller);
            if (@hasDecl(Config, "releasePlugIn")) return Config.releasePlugIn(self, component, controller);
            return types.kResultOk;
        }

        fn releaseComponent(component: ?*ivstcomponent.IComponent) void {
            if (component) |value| _ = value.vtable.release(value);
        }

        fn releaseController(controller: ?*ivsteditcontroller.IEditController) void {
            if (controller) |value| _ = value.vtable.release(value);
        }

        fn getSubCategories(ptr: *anyopaque, out_raw: [*c]istringresult.IStringResult) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *istringresult.IStringResult = @ptrCast(out_raw);
            _ = ownerFromProvider(ptr);
            return subCategoriesFor(out);
        }

        fn provider2GetSubCategories(ptr: *anyopaque, out_raw: [*c]istringresult.IStringResult) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *istringresult.IStringResult = @ptrCast(out_raw);
            _ = ownerFromProvider2(ptr);
            return subCategoriesFor(out);
        }

        fn subCategoriesFor(out: *istringresult.IStringResult) types.tresult {
            if (@hasDecl(Config, "sub_categories")) out.vtable.setText(out, Config.sub_categories) else out.vtable.setText(out, "");
            return types.kResultOk;
        }

        fn getComponentUID(ptr: *anyopaque, out: ?*anyopaque) callconv(.c) types.tresult {
            const destination = out orelse return types.kInvalidArgument;
            _ = ownerFromProvider(ptr);
            return componentUidFor(destination);
        }

        fn provider2GetComponentUID(ptr: *anyopaque, out: ?*anyopaque) callconv(.c) types.tresult {
            const destination = out orelse return types.kInvalidArgument;
            _ = ownerFromProvider2(ptr);
            return componentUidFor(destination);
        }

        fn componentUidFor(out: *anyopaque) types.tresult {
            const bytes: *tuid.TUID = @ptrCast(@alignCast(out));
            if (!@hasDecl(Config, "component_uid")) {
                bytes.* = tuid.zero;
                return types.kResultFalse;
            }
            bytes.* = Config.component_uid;
            return types.kResultOk;
        }

        fn getPluginFactory(ptr: *anyopaque) callconv(.c) ?*ipluginbase.IPluginFactory {
            const self = ownerFromProvider2(ptr);
            if (@hasDecl(Config, "getPluginFactory")) return Config.getPluginFactory(self);
            return self.factory;
        }

        const provider_vtable = ivsttestplugprovider.ITestPlugProviderVTable{
            .queryInterface = providerQuery,
            .addRef = providerAddRef,
            .release = providerRelease,
            .getComponent = getComponent,
            .getController = getController,
            .releasePlugIn = releasePlugIn,
            .getSubCategories = getSubCategories,
            .getComponentUID = getComponentUID,
        };

        const provider2_vtable = ivsttestplugprovider.ITestPlugProvider2VTable{
            .queryInterface = provider2Query,
            .addRef = provider2AddRef,
            .release = provider2Release,
            .getComponent = provider2GetComponent,
            .getController = provider2GetController,
            .releasePlugIn = provider2ReleasePlugIn,
            .getSubCategories = provider2GetSubCategories,
            .getComponentUID = provider2GetComponentUID,
            .getPluginFactory = getPluginFactory,
        };
    };
}

test "test plug provider returns configured metadata" {
    const String = @import("vst_string_result.zig").StringResult(32, 8);
    const expected_component_uid = tuid.inlineUid(0x01234567, 0x89ABCDEF, 0x10203040, 0x50607080);
    const Provider = TestPlugProvider(struct {
        pub const component_uid = tuid.inlineUid(0x01234567, 0x89ABCDEF, 0x10203040, 0x50607080);
        pub const sub_categories = "Fx|Tools";
    });
    var provider = Provider{};
    var string = String{};
    const iface = provider.asProvider();

    var out_uid: tuid.TUID = tuid.zero;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getSubCategories(iface, null));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getComponentUID(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getSubCategories(iface, string.asResult()));
    try std.testing.expectEqualStrings("Fx|Tools", string.text8Span());
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getComponentUID(iface, &out_uid));
    try std.testing.expectEqualSlices(u8, &expected_component_uid, &out_uid);
}

test "test plug provider tracks released plugin pair" {
    const Provider = TestPlugProvider(struct {});
    var provider = Provider{};
    const iface = provider.asProvider();

    try std.testing.expectEqual(@as(?*ivstcomponent.IComponent, null), iface.vtable.getComponent(iface));
    try std.testing.expectEqual(@as(?*ivsteditcontroller.IEditController, null), iface.vtable.getController(iface));

    const gain_component = @import("gain_component.zig");
    const gain_controller = @import("gain_controller.zig");
    var component_out: ?*anyopaque = null;
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, gain_component.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expectEqual(types.kResultOk, gain_controller.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    const controller: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = component.vtable.release(component);
    defer _ = controller.vtable.release(controller);

    provider.component = component;
    provider.controller = controller;
    const retained_component = iface.vtable.getComponent(iface).?;
    const retained_controller = iface.vtable.getController(iface).?;
    try std.testing.expectEqual(component, retained_component);
    try std.testing.expectEqual(controller, retained_controller);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.releasePlugIn(iface, retained_component, retained_controller));
    try std.testing.expectEqual(@as(types.uint32, 1), provider.release_count);
    try std.testing.expectEqual(component, provider.last_released_component.?);
    try std.testing.expectEqual(controller, provider.last_released_controller.?);
}

test "test plug provider delegates component controller and release hooks through provider2" {
    const gain_component = @import("gain_component.zig");
    const gain_controller = @import("gain_controller.zig");
    var component_out: ?*anyopaque = null;
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, gain_component.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expectEqual(types.kResultOk, gain_controller.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    const controller: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = component.vtable.release(component);
    defer _ = controller.vtable.release(controller);

    const Provider = TestPlugProvider(struct {
        pub fn releasePlugIn(_: anytype, released_component: ?*ivstcomponent.IComponent, released_controller: ?*ivsteditcontroller.IEditController) types.tresult {
            return if (released_component != null and released_controller != null) types.kResultFalse else types.kInvalidArgument;
        }
    });
    var provider = Provider{};
    provider.component = component;
    provider.controller = controller;
    const provider2 = provider.asProvider2();

    const retained_component = provider2.vtable.getComponent(provider2).?;
    const retained_controller = provider2.vtable.getController(provider2).?;
    try std.testing.expectEqual(component, retained_component);
    try std.testing.expectEqual(controller, retained_controller);
    try std.testing.expectEqual(types.kResultFalse, provider2.vtable.releasePlugIn(provider2, retained_component, retained_controller));
    try std.testing.expectEqual(@as(types.uint32, 1), provider.release_count);
    try std.testing.expectEqual(component, provider.last_released_component.?);
    try std.testing.expectEqual(controller, provider.last_released_controller.?);
}

test "test plug provider reports missing component UID deterministically" {
    const Provider = TestPlugProvider(struct {});
    var provider = Provider{};
    var out_uid: tuid.TUID = [_]u8{0xAA} ** tuid.byte_count;

    try std.testing.expectEqual(types.kResultFalse, provider.asProvider().vtable.getComponentUID(provider.asProvider(), &out_uid));
    try std.testing.expectEqualSlices(u8, &tuid.zero, &out_uid);
}

test "test plug provider exposes provider2 and factory" {
    const Provider = TestPlugProvider(struct {});
    var provider = Provider{};
    const factory: *ipluginbase.IPluginFactory = @ptrFromInt(0x3000);
    provider.factory = factory;

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, provider.asProvider().vtable.queryInterface(provider.asProvider(), &ivsttestplugprovider.itest_plug_provider2_iid, &queried));
    try std.testing.expect(queried != null);
    const provider2: *ivsttestplugprovider.ITestPlugProvider2 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(factory, provider2.vtable.getPluginFactory(provider2).?);
    try std.testing.expectEqual(@as(types.uint32, 1), provider2.vtable.release(provider2));
}

test "test plug provider query interfaces share object refcount" {
    const Provider = TestPlugProvider(struct {});
    var provider = Provider{};

    var queried_provider: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, provider.asProvider2().vtable.queryInterface(provider.asProvider2(), &ivsttestplugprovider.itest_plug_provider_iid, &queried_provider));
    try std.testing.expectEqual(@as(?*anyopaque, provider.asProvider()), queried_provider);
    try std.testing.expectEqual(@as(types.uint32, 2), provider.ref_count.load(.seq_cst));

    var queried_unknown: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, provider.asProvider2().vtable.queryInterface(provider.asProvider2(), &funknown.iid, &queried_unknown));
    try std.testing.expectEqual(@as(?*anyopaque, provider.asProvider()), queried_unknown);
    try std.testing.expectEqual(@as(types.uint32, 3), provider.ref_count.load(.seq_cst));

    const provider_iface: *ivsttestplugprovider.ITestPlugProvider = @ptrCast(@alignCast(queried_provider.?));
    try std.testing.expectEqual(@as(types.uint32, 2), provider_iface.vtable.release(provider_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), provider.asProvider().vtable.release(provider.asProvider()));
}

test "test plug provider clears unsupported query output from both interfaces" {
    const Provider = TestPlugProvider(struct {});
    var provider = Provider{};

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, provider.asProvider().vtable.queryInterface(provider.asProvider(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, provider.asProvider2().vtable.queryInterface(provider.asProvider2(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
