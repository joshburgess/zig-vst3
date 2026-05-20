const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstautomationstate = @import("pluginterfaces/vst/ivstautomationstate.zig");
const ivstchannelcontextinfo = @import("pluginterfaces/vst/ivstchannelcontextinfo.zig");
const ivstdataexchange = @import("pluginterfaces/vst/ivstdataexchange.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");

fn failCreatedInstance(out: *?*anyopaque, result: types.tresult) types.tresult {
    out.* = null;
    return result;
}

fn createHostInstance(comptime Config: type, self: anytype, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
    out.* = null;
    if (@hasDecl(Config, "createInstance")) {
        const result = Config.createInstance(self, cid, iid, out);
        if (result != types.kResultOk) return failCreatedInstance(out, result);
        return result;
    }
    return types.kResultFalse;
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

        fn queryHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
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

        fn queryInfo(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromInfo(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.info_listener },
                .{ .iid = &ivstchannelcontextinfo.iinfo_listener_iid, .ptr = &self.info_listener },
            };
            return interface_map.queryWithAddRef(&self.info_listener, addRefInfo, &entries, requested_iid, out);
        }

        fn addRefHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHost(ptr).host_ref_count, "FUnknown");
        }

        fn releaseHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHost(ptr).host_ref_count, "IHostApplication");
        }

        fn addRefInfo(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromInfo(ptr);
            self.info_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.info_ref_count, "FUnknown");
        }

        fn releaseInfo(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromInfo(ptr);
            self.info_release_count +|= 1;
            return funknown.decrementRefCount(&self.info_ref_count, "IInfoListener");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.copyPtr(out, name);
            return types.kResultOk;
        }

        fn createInstance(ptr: *anyopaque, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHost(ptr);
            return createHostInstance(Config, self, cid, iid, out);
        }

        fn setChannelContextInfos(ptr: *anyopaque, attributes: ?*ivstattributes.IAttributeList) callconv(.c) types.tresult {
            const self = ownerFromInfo(ptr);
            self.channel_context_count +|= 1;
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

pub fn AutomationStateHost(comptime name: []const u8, comptime Config: type) type {
    return extern struct {
        const Self = @This();

        host_application: ivsthostapplication.IHostApplication = .{ .vtable = &host_vtable },
        automation_state: ivstautomationstate.IAutomationState = .{ .vtable = &automation_vtable },
        host_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        automation_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        automation_add_ref_count: types.uint32 = 0,
        automation_release_count: types.uint32 = 0,
        last_state: types.int32 = ivstautomationstate.AutomationStates.kNoAutomation,

        pub fn asHostApplication(self: *Self) *ivsthostapplication.IHostApplication {
            return &self.host_application;
        }

        pub fn asAutomationState(self: *Self) *ivstautomationstate.IAutomationState {
            return &self.automation_state;
        }

        fn ownerFromHost(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("host_application", iface);
        }

        fn ownerFromAutomation(ptr: *anyopaque) *Self {
            const iface: *ivstautomationstate.IAutomationState = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("automation_state", iface);
        }

        fn queryHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHost(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.host_application },
                .{ .iid = &ivsthostapplication.ihost_application_iid, .ptr = &self.host_application },
                .{ .iid = &ivstautomationstate.iautomation_state_iid, .ptr = &self.automation_state },
            };
            if (std.mem.eql(u8, requested_iid, &ivstautomationstate.iautomation_state_iid)) {
                return interface_map.queryWithAddRef(&self.automation_state, addRefAutomation, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.host_application, addRefHost, &entries, requested_iid, out);
        }

        fn queryAutomation(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromAutomation(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.automation_state },
                .{ .iid = &ivstautomationstate.iautomation_state_iid, .ptr = &self.automation_state },
            };
            return interface_map.queryWithAddRef(&self.automation_state, addRefAutomation, &entries, requested_iid, out);
        }

        fn addRefHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHost(ptr).host_ref_count, "FUnknown");
        }

        fn releaseHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHost(ptr).host_ref_count, "IHostApplication");
        }

        fn addRefAutomation(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromAutomation(ptr);
            self.automation_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.automation_ref_count, "FUnknown");
        }

        fn releaseAutomation(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromAutomation(ptr);
            self.automation_release_count +|= 1;
            return funknown.decrementRefCount(&self.automation_ref_count, "IAutomationState");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.copyPtr(out, name);
            return types.kResultOk;
        }

        fn createInstance(ptr: *anyopaque, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHost(ptr);
            return createHostInstance(Config, self, cid, iid, out);
        }

        fn setAutomationState(ptr: *anyopaque, state: types.int32) callconv(.c) types.tresult {
            const self = ownerFromAutomation(ptr);
            self.last_state = state;
            if (@hasDecl(Config, "setAutomationState")) return Config.setAutomationState(self, state);
            return types.kResultOk;
        }

        const host_vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = queryHost,
            .addRef = addRefHost,
            .release = releaseHost,
            .getName = getName,
            .createInstance = createInstance,
        };

        const automation_vtable = ivstautomationstate.IAutomationStateVTable{
            .queryInterface = queryAutomation,
            .addRef = addRefAutomation,
            .release = releaseAutomation,
            .setAutomationState = setAutomationState,
        };
    };
}

pub fn DataExchangeHost(comptime name: []const u8, comptime Config: type) type {
    return extern struct {
        const Self = @This();

        host_application: ivsthostapplication.IHostApplication = .{ .vtable = &host_vtable },
        data_exchange_handler: ivstdataexchange.IDataExchangeHandler = .{ .vtable = &data_exchange_vtable },
        host_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        data_exchange_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        add_ref_count: types.uint32 = 0,
        release_count: types.uint32 = 0,
        open_count: types.uint32 = 0,
        close_count: types.uint32 = 0,
        last_user_context_id: ivstdataexchange.DataExchangeUserContextID = 0,
        last_queue_id: ivstdataexchange.DataExchangeQueueID = ivstdataexchange.InvalidDataExchangeQueueID,

        pub fn asHostApplication(self: *Self) *ivsthostapplication.IHostApplication {
            return &self.host_application;
        }

        pub fn asDataExchangeHandler(self: *Self) *ivstdataexchange.IDataExchangeHandler {
            return &self.data_exchange_handler;
        }

        fn ownerFromHost(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("host_application", iface);
        }

        fn ownerFromDataExchange(ptr: *anyopaque) *Self {
            const iface: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("data_exchange_handler", iface);
        }

        fn queryHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHost(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.host_application },
                .{ .iid = &ivsthostapplication.ihost_application_iid, .ptr = &self.host_application },
                .{ .iid = &ivstdataexchange.idata_exchange_handler_iid, .ptr = &self.data_exchange_handler },
            };
            if (std.mem.eql(u8, requested_iid, &ivstdataexchange.idata_exchange_handler_iid)) {
                return interface_map.queryWithAddRef(&self.data_exchange_handler, addRefDataExchange, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.host_application, addRefHost, &entries, requested_iid, out);
        }

        fn queryDataExchange(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.data_exchange_handler },
                .{ .iid = &ivstdataexchange.idata_exchange_handler_iid, .ptr = &self.data_exchange_handler },
            };
            return interface_map.queryWithAddRef(&self.data_exchange_handler, addRefDataExchange, &entries, requested_iid, out);
        }

        fn addRefHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHost(ptr).host_ref_count, "FUnknown");
        }

        fn releaseHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHost(ptr).host_ref_count, "IHostApplication");
        }

        fn addRefDataExchange(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromDataExchange(ptr);
            self.add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.data_exchange_ref_count, "FUnknown");
        }

        fn releaseDataExchange(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromDataExchange(ptr);
            self.release_count +|= 1;
            return funknown.decrementRefCount(&self.data_exchange_ref_count, "IDataExchangeHandler");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.copyPtr(out, name);
            return types.kResultOk;
        }

        fn createInstance(ptr: *anyopaque, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHost(ptr);
            return createHostInstance(Config, self, cid, iid, out);
        }

        fn failOpenedQueue(out: *ivstdataexchange.DataExchangeQueueID, result: types.tresult) types.tresult {
            out.* = ivstdataexchange.InvalidDataExchangeQueueID;
            return result;
        }

        fn openQueue(ptr: *anyopaque, processor: ?*ivstaudioprocessor.IAudioProcessor, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            self.open_count +|= 1;
            self.last_user_context_id = user_context_id;
            out.* = ivstdataexchange.InvalidDataExchangeQueueID;
            if (@hasDecl(Config, "openQueue")) {
                const result = Config.openQueue(self, processor, block_size, num_blocks, alignment, user_context_id, out);
                if (result != types.kResultOk) return failOpenedQueue(out, result);
                return result;
            }
            return types.kResultFalse;
        }

        fn closeQueue(ptr: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            self.close_count +|= 1;
            if (@hasDecl(Config, "closeQueue")) {
                const result = Config.closeQueue(self, queue_id);
                if (result != types.kResultOk) return result;
            }
            self.last_queue_id = queue_id;
            return types.kResultOk;
        }

        fn failLockedBlock(block: *ivstdataexchange.DataExchangeBlock, result: types.tresult) types.tresult {
            block.* = .{};
            return result;
        }

        fn lockBlock(ptr: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            block.* = .{};
            if (@hasDecl(Config, "lockBlock")) {
                const result = Config.lockBlock(self, queue_id, block);
                if (result != types.kResultOk) return failLockedBlock(block, result);
                return result;
            }
            return types.kResultOk;
        }

        fn freeBlock(ptr: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID, block_id: ivstdataexchange.DataExchangeBlockID, flags: types.TBool) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            if (@hasDecl(Config, "freeBlock")) return Config.freeBlock(self, queue_id, block_id, flags);
            return types.kResultOk;
        }

        const host_vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = queryHost,
            .addRef = addRefHost,
            .release = releaseHost,
            .getName = getName,
            .createInstance = createInstance,
        };

        const data_exchange_vtable = ivstdataexchange.IDataExchangeHandlerVTable{
            .queryInterface = queryDataExchange,
            .addRef = addRefDataExchange,
            .release = releaseDataExchange,
            .openQueue = openQueue,
            .closeQueue = closeQueue,
            .lockBlock = lockBlock,
            .freeBlock = freeBlock,
        };
    };
}

test "channel context host exposes info listener and records callbacks" {
    const Host = ChannelContextHost("Test Host", struct {});
    var host = Host{};
    var queried: ?*anyopaque = null;
    var name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.getName(host.asHostApplication(), &name));
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("Test Host"), std.mem.sliceTo(&name, 0));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[10]);

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstchannelcontextinfo.iinfo_listener_iid, &queried));
    try std.testing.expect(queried != null);
    const listener: *ivstchannelcontextinfo.IInfoListener = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, listener.vtable.setChannelContextInfos(listener, null));
    try std.testing.expectEqual(@as(types.uint32, 1), host.channel_context_count);
    try std.testing.expectEqual(@as(types.uint32, 1), listener.vtable.release(listener));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_release_count);
}

test "channel context host clears unsupported query outputs" {
    const Host = ChannelContextHost("Test Host", struct {});
    var host = Host{};

    var queried: ?*anyopaque = @ptrFromInt(0x10);
    try std.testing.expectEqual(types.kNoInterface, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstchannelcontextinfo.iinfo_listener_iid, &queried));
    const listener: *ivstchannelcontextinfo.IInfoListener = @ptrCast(@alignCast(queried.?));

    queried = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, listener.vtable.queryInterface(listener, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), listener.vtable.release(listener));
}

test "channel context host clears failed delegated create-instance output" {
    const Host = ChannelContextHost("Test Host", struct {
        pub fn createInstance(_: anytype, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            out.* = @ptrFromInt(0x10);
            return types.kNoInterface;
        }
    });
    var host = Host{};

    var created: ?*anyopaque = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, host.asHostApplication().vtable.createInstance(host.asHostApplication(), &funknown.iid, &funknown.iid, &created));
    try std.testing.expectEqual(@as(?*anyopaque, null), created);
}

test "channel context host truncates names and delegates create-instance success" {
    const created_ptr: *anyopaque = @ptrFromInt(0x3000);
    const long_name = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
    const Host = ChannelContextHost(long_name, struct {
        pub fn createInstance(_: anytype, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            if (!std.mem.eql(u8, cid, &funknown.iid) or !std.mem.eql(u8, iid, &ivstchannelcontextinfo.iinfo_listener_iid)) return types.kNoInterface;
            out.* = created_ptr;
            return types.kResultOk;
        }
    });
    var host = Host{};
    var name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    var created: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.getName(host.asHostApplication(), &name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'a'), name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'w'), name[string128.payload_units - 1]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[string128.payload_units]);
    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.createInstance(host.asHostApplication(), &funknown.iid, &ivstchannelcontextinfo.iinfo_listener_iid, &created));
    try std.testing.expectEqual(created_ptr, created.?);
}

test "automation state host exposes automation state and records callbacks" {
    const Host = AutomationStateHost("Test Host", struct {});
    var host = Host{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstautomationstate.iautomation_state_iid, &queried));
    try std.testing.expect(queried != null);
    const automation: *ivstautomationstate.IAutomationState = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, automation.vtable.setAutomationState(automation, ivstautomationstate.AutomationStates.kReadWriteState));
    try std.testing.expectEqual(ivstautomationstate.AutomationStates.kReadWriteState, host.last_state);
    try std.testing.expectEqual(@as(types.uint32, 1), automation.vtable.release(automation));
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_release_count);
}

test "automation state host clears unsupported query outputs" {
    const Host = AutomationStateHost("Test Host", struct {});
    var host = Host{};

    var queried: ?*anyopaque = @ptrFromInt(0x10);
    try std.testing.expectEqual(types.kNoInterface, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstautomationstate.iautomation_state_iid, &queried));
    const automation: *ivstautomationstate.IAutomationState = @ptrCast(@alignCast(queried.?));

    queried = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, automation.vtable.queryInterface(automation, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), automation.vtable.release(automation));
}

test "automation state host clears failed delegated create-instance output" {
    const Host = AutomationStateHost("Test Host", struct {
        pub fn createInstance(_: anytype, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            out.* = @ptrFromInt(0x10);
            return types.kNoInterface;
        }
    });
    var host = Host{};

    var created: ?*anyopaque = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, host.asHostApplication().vtable.createInstance(host.asHostApplication(), &funknown.iid, &funknown.iid, &created));
    try std.testing.expectEqual(@as(?*anyopaque, null), created);
}

test "automation state host preserves delegated failure state" {
    const Host = AutomationStateHost("Test Host", struct {
        pub fn setAutomationState(_: anytype, state: types.int32) types.tresult {
            return if (state == ivstautomationstate.AutomationStates.kReadState) types.kResultFalse else types.kInvalidArgument;
        }
    });
    var host = Host{};
    const automation = host.asAutomationState();

    try std.testing.expectEqual(types.kResultFalse, automation.vtable.setAutomationState(automation, ivstautomationstate.AutomationStates.kReadState));
    try std.testing.expectEqual(ivstautomationstate.AutomationStates.kReadState, host.last_state);
}

test "data exchange host exposes handler and records queue callbacks" {
    const Host = DataExchangeHost("Test Host", struct {
        pub fn openQueue(_: anytype, processor: ?*ivstaudioprocessor.IAudioProcessor, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, _: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            if (processor == null or block_size != 128 or num_blocks != 2 or alignment != 8) {
                out.* = ivstdataexchange.InvalidDataExchangeQueueID;
                return types.kInvalidArgument;
            }
            out.* = 44;
            return types.kResultOk;
        }

        pub fn closeQueue(_: anytype, queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
            return if (queue_id == 44) types.kResultOk else types.kInvalidArgument;
        }
    });
    var host = Host{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstdataexchange.idata_exchange_handler_iid, &queried));
    try std.testing.expect(queried != null);
    const handler: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);

    var queue_id: ivstdataexchange.DataExchangeQueueID = 0;
    try std.testing.expectEqual(types.kInvalidArgument, handler.vtable.openQueue(handler, null, 128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 77), host.last_user_context_id);

    try std.testing.expectEqual(@as(types.uint32, 1), handler.vtable.release(handler));
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);
}

test "data exchange host clears unsupported query outputs" {
    const Host = DataExchangeHost("Test Host", struct {});
    var host = Host{};

    var queried: ?*anyopaque = @ptrFromInt(0x10);
    try std.testing.expectEqual(types.kNoInterface, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstdataexchange.idata_exchange_handler_iid, &queried));
    const handler: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));

    queried = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, handler.vtable.queryInterface(handler, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.vtable.release(handler));
}

test "host context secondary interfaces expose their own unknown identity" {
    const ChannelHost = ChannelContextHost("Channel Host", struct {});
    const AutomationHost = AutomationStateHost("Automation Host", struct {});
    const DataHost = DataExchangeHost("Data Host", struct {});
    var channel_host = ChannelHost{};
    var automation_host = AutomationHost{};
    var data_host = DataHost{};

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, channel_host.asInfoListener().vtable.queryInterface(channel_host.asInfoListener(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, channel_host.asInfoListener()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), channel_host.info_add_ref_count);
    const listener: *ivstchannelcontextinfo.IInfoListener = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), listener.vtable.release(listener));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, automation_host.asAutomationState().vtable.queryInterface(automation_host.asAutomationState(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, automation_host.asAutomationState()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), automation_host.automation_add_ref_count);
    const automation: *ivstautomationstate.IAutomationState = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), automation.vtable.release(automation));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, data_host.asDataExchangeHandler().vtable.queryInterface(data_host.asDataExchangeHandler(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, data_host.asDataExchangeHandler()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), data_host.add_ref_count);
    const data_exchange: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), data_exchange.vtable.release(data_exchange));
}

test "data exchange host preserves last accepted close queue on rejection" {
    const Host = DataExchangeHost("Test Host", struct {
        pub fn closeQueue(_: anytype, queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
            return if (queue_id == 44) types.kResultOk else types.kInvalidArgument;
        }
    });
    var host = Host{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstdataexchange.idata_exchange_handler_iid, &queried));
    const handler: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));

    try std.testing.expectEqual(types.kResultOk, handler.vtable.closeQueue(handler, 44));
    try std.testing.expectEqual(types.kInvalidArgument, handler.vtable.closeQueue(handler, 99));
    try std.testing.expectEqual(@as(types.uint32, 2), host.close_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), host.last_queue_id);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.vtable.release(handler));
}

test "data exchange host delegates successful block lifecycle" {
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrFromInt(0x1000);
    const block_data: *anyopaque = @ptrFromInt(0x2000);
    const Host = DataExchangeHost("Test Host", struct {
        pub fn openQueue(_: anytype, received_processor: ?*ivstaudioprocessor.IAudioProcessor, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            if (received_processor != processor or block_size != 256 or num_blocks != 3 or alignment != 16 or user_context_id != 99) {
                out.* = ivstdataexchange.InvalidDataExchangeQueueID;
                return types.kInvalidArgument;
            }
            out.* = 44;
            return types.kResultOk;
        }

        pub fn lockBlock(_: anytype, queue_id: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            if (queue_id != 44) return types.kInvalidArgument;
            block.* = .{
                .blockID = 12,
                .size = 256,
                .data = block_data,
            };
            return types.kResultOk;
        }

        pub fn freeBlock(_: anytype, queue_id: ivstdataexchange.DataExchangeQueueID, block_id: ivstdataexchange.DataExchangeBlockID, flags: types.TBool) types.tresult {
            return if (queue_id == 44 and block_id == 12 and flags == 1) types.kResultOk else types.kInvalidArgument;
        }

        pub fn closeQueue(_: anytype, queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
            return if (queue_id == 44) types.kResultOk else types.kInvalidArgument;
        }
    });
    var host = Host{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstdataexchange.idata_exchange_handler_iid, &queried));
    const handler: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));

    var queue_id: ivstdataexchange.DataExchangeQueueID = ivstdataexchange.InvalidDataExchangeQueueID;
    try std.testing.expectEqual(types.kResultOk, handler.vtable.openQueue(handler, processor, 256, 3, 16, 99, &queue_id));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), queue_id);
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 99), host.last_user_context_id);

    var block = ivstdataexchange.DataExchangeBlock{};
    try std.testing.expectEqual(types.kResultOk, handler.vtable.lockBlock(handler, queue_id, &block));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeBlockID, 12), block.blockID);
    try std.testing.expectEqual(@as(types.uint32, 256), block.size);
    try std.testing.expectEqual(block_data, block.data.?);
    try std.testing.expectEqual(types.kResultOk, handler.vtable.freeBlock(handler, queue_id, block.blockID, 1));
    try std.testing.expectEqual(types.kResultOk, handler.vtable.closeQueue(handler, queue_id));
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), host.last_queue_id);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.vtable.release(handler));
}

test "data exchange host clears failed delegated outputs" {
    const Host = DataExchangeHost("Test Host", struct {
        pub fn createInstance(_: anytype, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            out.* = @ptrFromInt(0x10);
            return types.kNoInterface;
        }

        pub fn openQueue(_: anytype, _: ?*ivstaudioprocessor.IAudioProcessor, _: types.uint32, _: types.uint32, _: types.uint32, _: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            out.* = 44;
            return types.kResultFalse;
        }

        pub fn lockBlock(_: anytype, _: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            block.* = .{
                .blockID = 99,
                .size = 128,
                .data = @ptrFromInt(0x1000),
            };
            return types.kResultFalse;
        }
    });
    var host = Host{};

    var created: ?*anyopaque = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, host.asHostApplication().vtable.createInstance(host.asHostApplication(), &funknown.iid, &funknown.iid, &created));
    try std.testing.expectEqual(@as(?*anyopaque, null), created);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstdataexchange.idata_exchange_handler_iid, &queried));
    try std.testing.expect(queried != null);
    const handler: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));

    var queue_id: ivstdataexchange.DataExchangeQueueID = 88;
    try std.testing.expectEqual(types.kResultFalse, handler.vtable.openQueue(handler, null, 128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);

    var block = ivstdataexchange.DataExchangeBlock{
        .blockID = 1,
        .size = 64,
        .data = @ptrFromInt(0x2000),
    };
    try std.testing.expectEqual(types.kResultFalse, handler.vtable.lockBlock(handler, 44, &block));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeBlockID, 0), block.blockID);
    try std.testing.expectEqual(@as(types.uint32, 0), block.size);
    try std.testing.expectEqual(@as(?*anyopaque, null), block.data);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.vtable.release(handler));
}

test "data exchange host default lifecycle is deterministic" {
    const Host = DataExchangeHost("Test Host", struct {});
    var host = Host{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, host.asHostApplication().vtable.queryInterface(host.asHostApplication(), &ivstdataexchange.idata_exchange_handler_iid, &queried));
    const handler: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(queried.?));

    var queue_id: ivstdataexchange.DataExchangeQueueID = 44;
    try std.testing.expectEqual(types.kResultFalse, handler.vtable.openQueue(handler, null, 64, 1, 4, 12, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);

    var block = ivstdataexchange.DataExchangeBlock{ .blockID = 7, .size = 8, .data = @ptrFromInt(0x1000) };
    try std.testing.expectEqual(types.kResultOk, handler.vtable.lockBlock(handler, 9, &block));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeBlockID, 0), block.blockID);
    try std.testing.expectEqual(@as(types.uint32, 0), block.size);
    try std.testing.expectEqual(@as(?*anyopaque, null), block.data);
    try std.testing.expectEqual(types.kResultOk, handler.vtable.freeBlock(handler, 9, 10, 1));
    try std.testing.expectEqual(types.kResultOk, handler.vtable.closeQueue(handler, 9));
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 9), host.last_queue_id);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.vtable.release(handler));
}
