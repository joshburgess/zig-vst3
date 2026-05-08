const gain_controller = @import("gain_controller.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstautomationstate = @import("pluginterfaces/vst/ivstautomationstate.zig");
const ivstdataexchange = @import("pluginterfaces/vst/ivstdataexchange.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_host_application = @import("vst_host_application.zig");
const vst_host_context = @import("vst_host_context.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0xA74E7A0D, 0x6B234163, 0xA0A83EBF, 0xD06F1401);

const GainProcessor = struct {
    pub fn process(_: GainProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(gain_controller.gain());
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

const Effect = zig_plug_effect.SimpleStereoEffect(struct {
    pub const component_name = "GainComponent";
    pub const controller_cid = gain_controller.cid;
    pub const Processor = GainProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        gain_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return gain_controller.readGainState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return gain_controller.writeGainState(state);
    }
});

pub const create = Effect.create;

pub fn setChannelContextInfos(attributes: ?*ivstattributes.IAttributeList) types.tresult {
    return Effect.setChannelContextInfos(attributes);
}

pub fn setAutomationState(state: types.int32) types.tresult {
    return Effect.setAutomationState(state);
}

pub fn openDataExchangeQueue(block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
    return Effect.openDataExchangeQueue(block_size, num_blocks, alignment, user_context_id, out);
}

pub fn closeDataExchangeQueue(queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
    return Effect.closeDataExchangeQueue(queue_id);
}

test "gain component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "gain component exposes process context requirements" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iprocess_context_requirements_iid, &requirements_out),
    );
    try std.testing.expect(requirements_out != null);
    const requirements: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(requirements_out.?));
    defer _ = requirements.vtable.release(requirements);

    try std.testing.expectEqual(@as(types.uint32, 0), requirements.vtable.getProcessContextRequirements(requirements));

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var processor_requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.queryInterface(processor, &ivstaudioprocessor.iprocess_context_requirements_iid, &processor_requirements_out),
    );
    try std.testing.expect(processor_requirements_out != null);
    const processor_requirements: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(processor_requirements_out.?));
    defer _ = processor_requirements.vtable.release(processor_requirements);

    try std.testing.expectEqual(@as(types.uint32, 0), processor_requirements.vtable.getProcessContextRequirements(processor_requirements));
}

test "gain component queries host application during initialize" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const HostApplication = vst_host_application.HostApplication("Test Host", struct {});

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var host = HostApplication{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 4), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), host.release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);
}

test "gain component stores channel context info listener" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const HostContext = vst_host_context.ChannelContextHost("Test Host", struct {});

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    try std.testing.expectEqual(types.kResultFalse, setChannelContextInfos(null));

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, setChannelContextInfos(null));
    try std.testing.expectEqual(@as(types.uint32, 1), host.channel_context_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_release_count);
}

test "gain component stores automation state host interface" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
    const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

    const HostContext = extern struct {
        const Self = @This();

        host_application: ivsthostapplication.IHostApplication = .{ .vtable = &host_vtable },
        automation_state: ivstautomationstate.IAutomationState = .{ .vtable = &automation_vtable },
        automation_add_ref_count: types.uint32 = 0,
        automation_release_count: types.uint32 = 0,
        last_state: types.int32 = ivstautomationstate.AutomationStates.kNoAutomation,

        const host_vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = queryFromHost,
            .addRef = addRefFromHost,
            .release = releaseFromHost,
            .getName = getName,
            .createInstance = createInstance,
        };

        const automation_vtable = ivstautomationstate.IAutomationStateVTable{
            .queryInterface = queryFromAutomation,
            .addRef = addRefFromAutomation,
            .release = releaseFromAutomation,
            .setAutomationState = setAutomationStateCallback,
        };

        fn ownerFromHost(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("host_application", iface);
        }

        fn ownerFromAutomation(ptr: *anyopaque) *Self {
            const iface: *ivstautomationstate.IAutomationState = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("automation_state", iface);
        }

        fn queryFromHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHost(ptr);
            if (std.mem.eql(u8, requested_iid, &ivsthostapplication.ihost_application_iid)) {
                out.* = ptr;
                return types.kResultOk;
            }
            if (std.mem.eql(u8, requested_iid, &ivstautomationstate.iautomation_state_iid)) {
                _ = addRefFromAutomation(&self.automation_state);
                out.* = &self.automation_state;
                return types.kResultOk;
            }
            out.* = null;
            return types.kNoInterface;
        }

        fn queryFromAutomation(_: *anyopaque, _: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            out.* = null;
            return types.kNoInterface;
        }

        fn addRefFromHost(_: *anyopaque) callconv(.C) types.uint32 {
            return 1;
        }

        fn releaseFromHost(_: *anyopaque) callconv(.C) types.uint32 {
            return 1;
        }

        fn addRefFromAutomation(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromAutomation(ptr);
            self.automation_add_ref_count += 1;
            return self.automation_add_ref_count + 1;
        }

        fn releaseFromAutomation(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromAutomation(ptr);
            self.automation_release_count += 1;
            return 1;
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
            out[0] = 0;
            return types.kResultOk;
        }

        fn createInstance(_: *anyopaque, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            out.* = null;
            return types.kNoInterface;
        }

        fn setAutomationStateCallback(ptr: *anyopaque, state: types.int32) callconv(.C) types.tresult {
            ownerFromAutomation(ptr).last_state = state;
            return types.kResultOk;
        }
    };

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    try std.testing.expectEqual(types.kResultFalse, setAutomationState(ivstautomationstate.AutomationStates.kReadState));

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, &host.host_application));
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, setAutomationState(ivstautomationstate.AutomationStates.kReadWriteState));
    try std.testing.expectEqual(ivstautomationstate.AutomationStates.kReadWriteState, host.last_state);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_release_count);
}

test "gain component exposes default connection point" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstmessage.iconnection_point_iid, &connection_out),
    );
    try std.testing.expect(connection_out != null);
    const connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(connection_out.?));
    defer _ = connection.vtable.release(connection);

    try std.testing.expectEqual(types.kInvalidArgument, connection.vtable.connect(connection, null));
    try std.testing.expectEqual(types.kResultFalse, connection.vtable.notify(connection, null));
    try std.testing.expectEqual(types.kResultOk, connection.vtable.disconnect(connection, null));
}

test "gain component exposes default processor capability interfaces" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");
    const ivstprefetchablesupport = @import("pluginterfaces/vst/ivstprefetchablesupport.zig");
    const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var latency_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_presentation_latency_iid, &latency_out),
    );
    try std.testing.expect(latency_out != null);
    const latency: *ivstaudioprocessor.IAudioPresentationLatency = @ptrCast(@alignCast(latency_out.?));
    defer _ = latency.vtable.release(latency);
    try std.testing.expectEqual(
        types.kResultOk,
        latency.vtable.setAudioPresentationLatencySamples(latency, @intFromEnum(ivstcomponent.BusDirections.kOutput), 0, 0),
    );

    var support_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstpluginterfacesupport.iplug_interface_support_iid, &support_out),
    );
    try std.testing.expect(support_out != null);
    const support: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(support_out.?));
    defer _ = support.vtable.release(support);
    const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
    try std.testing.expectEqual(types.kResultOk, support.vtable.isPlugInterfaceSupported(support, &ivstmessage.iconnection_point_iid));
    try std.testing.expectEqual(types.kResultOk, support.vtable.isPlugInterfaceSupported(support, &ivstaudioprocessor.iaudio_processor_iid));
    try std.testing.expectEqual(types.kResultFalse, support.vtable.isPlugInterfaceSupported(support, &ivstunits.iunit_info_iid));

    var prefetch_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstprefetchablesupport.iprefetchable_support_iid, &prefetch_out),
    );
    try std.testing.expect(prefetch_out != null);
    const prefetch: *ivstprefetchablesupport.IPrefetchableSupport = @ptrCast(@alignCast(prefetch_out.?));
    defer _ = prefetch.vtable.release(prefetch);

    var prefetchable: ivstprefetchablesupport.PrefetchableSupport = 99;
    try std.testing.expectEqual(types.kResultOk, prefetch.vtable.getPrefetchableSupport(prefetch, &prefetchable));
    try std.testing.expectEqual(@as(types.uint32, @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNeverPrefetchable)), prefetchable);
}

test "gain component exposes default data exchange receiver" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var receiver_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstdataexchange.idata_exchange_receiver_iid, &receiver_out),
    );
    try std.testing.expect(receiver_out != null);
    const receiver: *ivstdataexchange.IDataExchangeReceiver = @ptrCast(@alignCast(receiver_out.?));
    defer _ = receiver.vtable.release(receiver);

    var accepted: types.TBool = 1;
    receiver.vtable.queueOpened(receiver, 9, 128, &accepted);
    try std.testing.expectEqual(@as(types.TBool, 0), accepted);
    receiver.vtable.queueClosed(receiver, 9);
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 9, 0, null, 0);

    var support_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstpluginterfacesupport.iplug_interface_support_iid, &support_out),
    );
    try std.testing.expect(support_out != null);
    const support: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(support_out.?));
    defer _ = support.vtable.release(support);
    try std.testing.expectEqual(types.kResultOk, support.vtable.isPlugInterfaceSupported(support, &ivstdataexchange.idata_exchange_receiver_iid));

    var queue_id: ivstdataexchange.DataExchangeQueueID = 0;
    try std.testing.expectEqual(types.kResultFalse, openDataExchangeQueue(128, 2, 8, 9, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);
}

test "gain component stores data exchange handler" {
    const std = @import("std");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
    const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

    const HostContext = extern struct {
        const Self = @This();

        host_application: ivsthostapplication.IHostApplication = .{ .vtable = &host_vtable },
        data_exchange_handler: ivstdataexchange.IDataExchangeHandler = .{ .vtable = &data_exchange_vtable },
        add_ref_count: types.uint32 = 0,
        release_count: types.uint32 = 0,
        open_count: types.uint32 = 0,
        close_count: types.uint32 = 0,
        last_user_context_id: ivstdataexchange.DataExchangeUserContextID = 0,

        const host_vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = queryFromHost,
            .addRef = addRefFromHost,
            .release = releaseFromHost,
            .getName = getName,
            .createInstance = createInstance,
        };

        const data_exchange_vtable = ivstdataexchange.IDataExchangeHandlerVTable{
            .queryInterface = queryFromDataExchange,
            .addRef = addRefFromDataExchange,
            .release = releaseFromDataExchange,
            .openQueue = openQueue,
            .closeQueue = closeQueue,
            .lockBlock = lockBlock,
            .freeBlock = freeBlock,
        };

        fn ownerFromHost(ptr: *anyopaque) *Self {
            const iface: *ivsthostapplication.IHostApplication = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("host_application", iface);
        }

        fn ownerFromDataExchange(ptr: *anyopaque) *Self {
            const iface: *ivstdataexchange.IDataExchangeHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("data_exchange_handler", iface);
        }

        fn queryFromHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHost(ptr);
            if (std.mem.eql(u8, requested_iid, &ivsthostapplication.ihost_application_iid)) {
                out.* = ptr;
                return types.kResultOk;
            }
            if (std.mem.eql(u8, requested_iid, &ivstdataexchange.idata_exchange_handler_iid)) {
                _ = addRefFromDataExchange(&self.data_exchange_handler);
                out.* = &self.data_exchange_handler;
                return types.kResultOk;
            }
            out.* = null;
            return types.kNoInterface;
        }

        fn queryFromDataExchange(_: *anyopaque, _: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            out.* = null;
            return types.kNoInterface;
        }

        fn addRefFromHost(_: *anyopaque) callconv(.C) types.uint32 {
            return 1;
        }

        fn releaseFromHost(_: *anyopaque) callconv(.C) types.uint32 {
            return 1;
        }

        fn addRefFromDataExchange(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromDataExchange(ptr);
            self.add_ref_count += 1;
            return self.add_ref_count + 1;
        }

        fn releaseFromDataExchange(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromDataExchange(ptr);
            self.release_count += 1;
            return 1;
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
            out[0] = 0;
            return types.kResultOk;
        }

        fn createInstance(_: *anyopaque, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            out.* = null;
            return types.kNoInterface;
        }

        fn openQueue(ptr: *anyopaque, processor: ?*ivstaudioprocessor.IAudioProcessor, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) callconv(.C) types.tresult {
            const self = ownerFromDataExchange(ptr);
            self.open_count += 1;
            self.last_user_context_id = user_context_id;
            if (processor == null or block_size != 128 or num_blocks != 2 or alignment != 8) {
                out.* = ivstdataexchange.InvalidDataExchangeQueueID;
                return types.kInvalidArgument;
            }
            out.* = 44;
            return types.kResultOk;
        }

        fn closeQueue(ptr: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID) callconv(.C) types.tresult {
            const self = ownerFromDataExchange(ptr);
            self.close_count += 1;
            return if (queue_id == 44) types.kResultOk else types.kInvalidArgument;
        }

        fn lockBlock(_: *anyopaque, _: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) callconv(.C) types.tresult {
            block.* = .{ .blockID = 7 };
            return types.kResultOk;
        }

        fn freeBlock(_: *anyopaque, _: ivstdataexchange.DataExchangeQueueID, _: ivstdataexchange.DataExchangeBlockID, _: types.TBool) callconv(.C) types.tresult {
            return types.kResultOk;
        }
    };

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, &host.host_application));
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);

    var queue_id: ivstdataexchange.DataExchangeQueueID = 0;
    try std.testing.expectEqual(types.kResultOk, openDataExchangeQueue(128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), queue_id);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 77), host.last_user_context_id);
    try std.testing.expectEqual(types.kResultOk, closeDataExchangeQueue(queue_id));
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);
}
