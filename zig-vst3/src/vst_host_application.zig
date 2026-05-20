const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");

pub fn HostApplication(comptime name: []const u8, comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivsthostapplication.IHostApplication = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        query_count: types.uint32 = 0,
        add_ref_count: types.uint32 = 0,
        release_count: types.uint32 = 0,
        create_instance_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *ivsthostapplication.IHostApplication {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, ivsthostapplication.IHostApplication, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            owner(ptr).query_count +|= 1;
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivsthostapplication.ihost_application_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.release_count +|= 1;
            return funknown.decrementRefCount(&self.ref_count, "IHostApplication");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.copyPtr(out, name);
            return types.kResultOk;
        }

        fn failCreatedInstance(out: *?*anyopaque, result: types.tresult) types.tresult {
            out.* = null;
            return result;
        }

        fn createInstance(ptr: *anyopaque, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.create_instance_count +|= 1;
            out.* = null;
            if (@hasDecl(Config, "createInstance")) {
                const result = Config.createInstance(self, cid, iid, out);
                if (result != types.kResultOk) return failCreatedInstance(out, result);
                return result;
            }
            return types.kResultFalse;
        }

        const vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getName = getName,
            .createInstance = createInstance,
        };
    };
}

pub fn WrapperMarker(comptime Interface: type, comptime VTable: type, comptime iid: *const tuid.TUID, comptime owner_name: []const u8) type {
    return extern struct {
        const Self = @This();

        iface: Interface = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *Interface {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, Interface, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, owner_name);
        }

        const vtable = VTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
        };
    };
}

pub const Vst3ToVst2Wrapper = WrapperMarker(ivsthostapplication.IVst3ToVst2Wrapper, ivsthostapplication.IVst3ToVst2WrapperVTable, &ivsthostapplication.ivst3_to_vst2_wrapper_iid, "IVst3ToVst2Wrapper");
pub const Vst3ToAUWrapper = WrapperMarker(ivsthostapplication.IVst3ToAUWrapper, ivsthostapplication.IVst3ToAUWrapperVTable, &ivsthostapplication.ivst3_to_au_wrapper_iid, "IVst3ToAUWrapper");
pub const Vst3ToAAXWrapper = WrapperMarker(ivsthostapplication.IVst3ToAAXWrapper, ivsthostapplication.IVst3ToAAXWrapperVTable, &ivsthostapplication.ivst3_to_aax_wrapper_iid, "IVst3ToAAXWrapper");

pub fn WrapperMPESupport(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivsthostapplication.IVst3WrapperMPESupport = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        mpe_input_enabled: types.TBool = 0,
        master_channel: types.int32 = 0,
        member_begin_channel: types.int32 = 0,
        member_end_channel: types.int32 = 0,

        pub fn asInterface(self: *Self) *ivsthostapplication.IVst3WrapperMPESupport {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, ivsthostapplication.IVst3WrapperMPESupport, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivsthostapplication.ivst3_wrapper_mpe_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IVst3WrapperMPESupport");
        }

        fn enableMPEInputProcessing(ptr: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "enableMPEInputProcessing")) {
                const result = Config.enableMPEInputProcessing(self, state);
                if (result != types.kResultOk) return result;
            }
            self.mpe_input_enabled = state;
            return types.kResultOk;
        }

        fn setMPEInputDeviceSettings(ptr: *anyopaque, master_channel: types.int32, member_begin_channel: types.int32, member_end_channel: types.int32) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "setMPEInputDeviceSettings")) {
                const result = Config.setMPEInputDeviceSettings(self, master_channel, member_begin_channel, member_end_channel);
                if (result != types.kResultOk) return result;
            }
            self.master_channel = master_channel;
            self.member_begin_channel = member_begin_channel;
            self.member_end_channel = member_end_channel;
            return types.kResultOk;
        }

        const vtable = ivsthostapplication.IVst3WrapperMPESupportVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .enableMPEInputProcessing = enableMPEInputProcessing,
            .setMPEInputDeviceSettings = setMPEInputDeviceSettings,
        };
    };
}

test "host application exposes name and create-instance hook" {
    const Host = HostApplication("Test Host", struct {
        pub fn createInstance(_: anytype, _: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            if (!std.mem.eql(u8, iid, &funknown.iid)) return types.kNoInterface;
            out.* = @ptrFromInt(0x10);
            return types.kResultOk;
        }
    });
    var host = Host{};
    const iface = host.asInterface();

    var name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getName(iface, &name));
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("Test Host"), std.mem.sliceTo(&name, 0));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[10]);

    var created: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.createInstance(iface, &funknown.iid, &funknown.iid, &created));
    try std.testing.expect(created != null);
    try std.testing.expectEqual(@as(types.uint32, 1), host.create_instance_count);
}

test "host application clears failed delegated create-instance output" {
    const Host = HostApplication("Test Host", struct {
        pub fn createInstance(_: anytype, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            out.* = @ptrFromInt(0x10);
            return types.kNoInterface;
        }
    });
    var host = Host{};
    const iface = host.asInterface();

    var created: ?*anyopaque = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.createInstance(iface, &funknown.iid, &funknown.iid, &created));
    try std.testing.expectEqual(@as(?*anyopaque, null), created);
    try std.testing.expectEqual(@as(types.uint32, 1), host.create_instance_count);
}

test "host application clears unsupported query and default create-instance outputs" {
    const Host = HostApplication("Test Host", struct {});
    var host = Host{};
    const iface = host.asInterface();

    var queried: ?*anyopaque = iface;
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 0), host.add_ref_count);

    var created: ?*anyopaque = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.createInstance(iface, &funknown.iid, &funknown.iid, &created));
    try std.testing.expectEqual(@as(?*anyopaque, null), created);
    try std.testing.expectEqual(@as(types.uint32, 1), host.create_instance_count);
}

test "host application tracks successful query refcounts" {
    const Host = HostApplication("Test Host", struct {});
    var host = Host{};
    const iface = host.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivsthostapplication.ihost_application_iid, &queried));
    try std.testing.expect(queried != null);
    try std.testing.expectEqual(@as(types.uint32, 1), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), host.release_count);

    const queried_host: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_host.vtable.release(queried_host));
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);
}

test "host application zero-fills and truncates String128 names" {
    const long_name =
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyz";
    const Host = HostApplication(long_name, struct {});
    var host = Host{};
    const iface = host.asInterface();
    var name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.getName(iface, &name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[string128.payload_units]);
    for (name[0..string128.payload_units], 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, long_name[index]), char);
    }
}

test "wrapper marker supports query interface" {
    var wrapper = Vst3ToVst2Wrapper{};
    const iface = wrapper.asInterface();
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivsthostapplication.ivst3_to_vst2_wrapper_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *ivsthostapplication.IVst3ToVst2Wrapper = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_iface.vtable.release(queried_iface));

    var au_wrapper = Vst3ToAUWrapper{};
    var queried_au: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, au_wrapper.asInterface().vtable.queryInterface(au_wrapper.asInterface(), &ivsthostapplication.ivst3_to_au_wrapper_iid, &queried_au));
    try std.testing.expect(queried_au != null);
    const au_iface: *ivsthostapplication.IVst3ToAUWrapper = @ptrCast(@alignCast(queried_au.?));
    try std.testing.expectEqual(@as(types.uint32, 1), au_iface.vtable.release(au_iface));

    var aax_wrapper = Vst3ToAAXWrapper{};
    var queried_aax: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, aax_wrapper.asInterface().vtable.queryInterface(aax_wrapper.asInterface(), &ivsthostapplication.ivst3_to_aax_wrapper_iid, &queried_aax));
    try std.testing.expect(queried_aax != null);
    const aax_iface: *ivsthostapplication.IVst3ToAAXWrapper = @ptrCast(@alignCast(queried_aax.?));
    try std.testing.expectEqual(@as(types.uint32, 1), aax_iface.vtable.release(aax_iface));
}

test "wrapper marker clears unsupported query output" {
    var wrapper = Vst3ToVst2Wrapper{};
    const iface = wrapper.asInterface();
    var queried: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "wrapper MPE support clears unsupported query output" {
    const MPE = WrapperMPESupport(struct {});
    var support = MPE{};
    const iface = support.asInterface();
    var queried: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "wrapper MPE support stores latest settings" {
    const MPE = WrapperMPESupport(struct {});
    var support = MPE{};
    const iface = support.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.enableMPEInputProcessing(iface, 1));
    try std.testing.expectEqual(@as(types.TBool, 1), support.mpe_input_enabled);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setMPEInputDeviceSettings(iface, 1, 2, 15));
    try std.testing.expectEqual(@as(types.int32, 1), support.master_channel);
    try std.testing.expectEqual(@as(types.int32, 2), support.member_begin_channel);
    try std.testing.expectEqual(@as(types.int32, 15), support.member_end_channel);
}

test "wrapper MPE support preserves accepted state when delegated hooks reject changes" {
    const MPE = WrapperMPESupport(struct {
        pub fn enableMPEInputProcessing(_: anytype, _: types.TBool) types.tresult {
            return types.kResultFalse;
        }

        pub fn setMPEInputDeviceSettings(_: anytype, _: types.int32, _: types.int32, _: types.int32) types.tresult {
            return types.kResultFalse;
        }
    });
    var support = MPE{};
    const iface = support.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.enableMPEInputProcessing(iface, 1));
    try std.testing.expectEqual(@as(types.TBool, 0), support.mpe_input_enabled);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.setMPEInputDeviceSettings(iface, 1, 2, 15));
    try std.testing.expectEqual(@as(types.int32, 0), support.master_channel);
    try std.testing.expectEqual(@as(types.int32, 0), support.member_begin_channel);
    try std.testing.expectEqual(@as(types.int32, 0), support.member_end_channel);
}
