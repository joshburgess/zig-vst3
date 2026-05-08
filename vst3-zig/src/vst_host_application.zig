const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

fn copyString128(dest: [*]vsttypes.TChar, source: []const u8) void {
    @memset(dest[0..128], 0);
    const len = @min(source.len, 127);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

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

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            owner(ptr).query_count += 1;
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivsthostapplication.ihost_application_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = owner(ptr);
            self.add_ref_count += 1;
            return self.ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = owner(ptr);
            self.release_count += 1;
            return funknown.decrementRefCount(&self.ref_count, "IHostApplication");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
            copyString128(out, name);
            return types.kResultOk;
        }

        fn createInstance(ptr: *anyopaque, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.create_instance_count += 1;
            if (@hasDecl(Config, "createInstance")) return Config.createInstance(self, cid, iid, out);
            out.* = null;
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

        fn owner(ptr: *anyopaque) *Self {
            const iface: *Interface = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
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

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IVst3WrapperMPESupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivsthostapplication.ivst3_wrapper_mpe_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IVst3WrapperMPESupport");
        }

        fn enableMPEInputProcessing(ptr: *anyopaque, state: types.TBool) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.mpe_input_enabled = state;
            if (@hasDecl(Config, "enableMPEInputProcessing")) return Config.enableMPEInputProcessing(self, state);
            return types.kResultOk;
        }

        fn setMPEInputDeviceSettings(ptr: *anyopaque, master_channel: types.int32, member_begin_channel: types.int32, member_end_channel: types.int32) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.master_channel = master_channel;
            self.member_begin_channel = member_begin_channel;
            self.member_end_channel = member_end_channel;
            if (@hasDecl(Config, "setMPEInputDeviceSettings")) {
                return Config.setMPEInputDeviceSettings(self, master_channel, member_begin_channel, member_end_channel);
            }
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

    var name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** 128;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getName(iface, &name));
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("Test Host"), std.mem.sliceTo(&name, 0));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[10]);

    var created: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.createInstance(iface, &funknown.iid, &funknown.iid, &created));
    try std.testing.expect(created != null);
    try std.testing.expectEqual(@as(types.uint32, 1), host.create_instance_count);
}

test "wrapper marker supports query interface" {
    var wrapper = Vst3ToVst2Wrapper{};
    const iface = wrapper.asInterface();
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivsthostapplication.ivst3_to_vst2_wrapper_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *ivsthostapplication.IVst3ToVst2Wrapper = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_iface.vtable.release(queried_iface));
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
