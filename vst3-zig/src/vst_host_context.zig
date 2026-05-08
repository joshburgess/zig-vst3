const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstchannelcontextinfo = @import("pluginterfaces/vst/ivstchannelcontextinfo.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

fn copyString128(dest: [*]vsttypes.TChar, source: []const u8) void {
    const len = @min(source.len, 127);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
    dest[len] = 0;
}

pub fn ChannelContextHost(comptime name: []const u8, comptime Config: type) type {
    return extern struct {
        const Self = @This();

        host_application: ivsthostapplication.IHostApplication = .{ .vtable = &host_vtable },
        info_listener: ivstchannelcontextinfo.IInfoListener = .{ .vtable = &info_vtable },
        host_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        info_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        info_add_ref_count: types.uint32 = 0,
        info_release_count: types.uint32 = 0,
        channel_context_count: types.uint32 = 0,
        last_channel_context: ?*ivstattributes.IAttributeList = null,

        pub fn asHostApplication(self: *Self) *ivsthostapplication.IHostApplication {
            return &self.host_application;
        }

        pub fn asInfoListener(self: *Self) *ivstchannelcontextinfo.IInfoListener {
            return &self.info_listener;
        }

        fn ownerFromHost(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("host_application", iface);
        }

        fn ownerFromInfo(ptr: *anyopaque) *Self {
            const iface: *ivstchannelcontextinfo.IInfoListener = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("info_listener", iface);
        }

        fn queryHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHost(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.host_application },
                .{ .iid = &ivsthostapplication.ihost_application_iid, .ptr = &self.host_application },
                .{ .iid = &ivstchannelcontextinfo.iinfo_listener_iid, .ptr = &self.info_listener },
            };
            if (std.mem.eql(u8, requested_iid, &ivstchannelcontextinfo.iinfo_listener_iid)) {
                return interface_map.queryWithAddRef(&self.info_listener, addRefInfo, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.host_application, addRefHost, &entries, requested_iid, out);
        }

        fn queryInfo(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromInfo(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.info_listener },
                .{ .iid = &ivstchannelcontextinfo.iinfo_listener_iid, .ptr = &self.info_listener },
            };
            return interface_map.queryWithAddRef(&self.info_listener, addRefInfo, &entries, requested_iid, out);
        }

        fn addRefHost(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromHost(ptr).host_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseHost(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHost(ptr).host_ref_count, "IHostApplication");
        }

        fn addRefInfo(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromInfo(ptr);
            self.info_add_ref_count += 1;
            return self.info_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseInfo(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromInfo(ptr);
            self.info_release_count += 1;
            return funknown.decrementRefCount(&self.info_ref_count, "IInfoListener");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
            copyString128(out, name);
            return types.kResultOk;
        }

        fn createInstance(ptr: *anyopaque, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHost(ptr);
            if (@hasDecl(Config, "createInstance")) return Config.createInstance(self, cid, iid, out);
            out.* = null;
            return types.kResultFalse;
        }

        fn setChannelContextInfos(ptr: *anyopaque, attributes: ?*ivstattributes.IAttributeList) callconv(.C) types.tresult {
            const self = ownerFromInfo(ptr);
            self.channel_context_count += 1;
            self.last_channel_context = attributes;
            if (@hasDecl(Config, "setChannelContextInfos")) return Config.setChannelContextInfos(self, attributes);
            return types.kResultOk;
        }

        const host_vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = queryHost,
            .addRef = addRefHost,
            .release = releaseHost,
            .getName = getName,
            .createInstance = createInstance,
        };

        const info_vtable = ivstchannelcontextinfo.IInfoListenerVTable{
            .queryInterface = queryInfo,
            .addRef = addRefInfo,
            .release = releaseInfo,
            .setChannelContextInfos = setChannelContextInfos,
        };
    };
}

test "channel context host exposes info listener and records callbacks" {
    const Host = ChannelContextHost("Test Host", struct {});
    var host = Host{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstchannelcontextinfo.iinfo_listener_iid, &queried));
    try std.testing.expect(queried != null);
    const listener: *ivstchannelcontextinfo.IInfoListener = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, listener.vtable.setChannelContextInfos(listener, null));
    try std.testing.expectEqual(@as(types.uint32, 1), host.channel_context_count);
    try std.testing.expectEqual(@as(types.uint32, 1), listener.vtable.release(listener));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_release_count);
}
