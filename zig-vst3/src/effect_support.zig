const funknown = @import("funknown.zig");
const gui_telemetry_source = @import("gui_telemetry_source.zig");
const ivstautomationstate = @import("pluginterfaces/vst/ivstautomationstate.zig");
const ivstchannelcontextinfo = @import("pluginterfaces/vst/ivstchannelcontextinfo.zig");
const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
const ivstdataexchange = @import("pluginterfaces/vst/ivstdataexchange.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn queryInterfaceAs(comptime Base: type, comptime Interface: type, source: ?*anyopaque, iid: *const tuid.TUID) ?*Interface {
    const raw = source orelse return null;
    const base: *Base = @ptrCast(@alignCast(raw));
    var out: ?*anyopaque = null;
    if (base.vtable.queryInterface(base, iid, &out) != types.kResultOk) return null;
    return if (out) |value| @ptrCast(@alignCast(value)) else null;
}

pub fn queryHostApplication(context: ?*anyopaque) ?*ivsthostapplication.IHostApplication {
    return queryInterfaceAs(funknown.Header, ivsthostapplication.IHostApplication, context, &ivsthostapplication.ihost_application_iid);
}

pub fn releaseOptionalInterface(comptime Interface: type, slot: *?*Interface) void {
    if (slot.*) |value| {
        _ = value.vtable.release(value);
        slot.* = null;
    }
}

pub fn releaseHostApplication(host_application: *?*ivsthostapplication.IHostApplication) void {
    releaseOptionalInterface(ivsthostapplication.IHostApplication, host_application);
}

pub fn queryInfoListener(context: ?*anyopaque) ?*ivstchannelcontextinfo.IInfoListener {
    return queryInterfaceAs(funknown.Header, ivstchannelcontextinfo.IInfoListener, context, &ivstchannelcontextinfo.iinfo_listener_iid);
}

pub fn releaseInfoListener(info_listener: *?*ivstchannelcontextinfo.IInfoListener) void {
    releaseOptionalInterface(ivstchannelcontextinfo.IInfoListener, info_listener);
}

pub fn queryAutomationState(context: ?*anyopaque) ?*ivstautomationstate.IAutomationState {
    return queryInterfaceAs(funknown.Header, ivstautomationstate.IAutomationState, context, &ivstautomationstate.iautomation_state_iid);
}

pub fn releaseAutomationState(automation_state: *?*ivstautomationstate.IAutomationState) void {
    releaseOptionalInterface(ivstautomationstate.IAutomationState, automation_state);
}

pub fn queryDataExchangeHandler(context: ?*anyopaque) ?*ivstdataexchange.IDataExchangeHandler {
    return queryInterfaceAs(funknown.Header, ivstdataexchange.IDataExchangeHandler, context, &ivstdataexchange.idata_exchange_handler_iid);
}

pub fn releaseDataExchangeHandler(data_exchange_handler: *?*ivstdataexchange.IDataExchangeHandler) void {
    releaseOptionalInterface(ivstdataexchange.IDataExchangeHandler, data_exchange_handler);
}

pub fn queryComponentHandler2(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandler2 {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IComponentHandler2, handler, &ivsteditcontroller.icomponent_handler2_iid);
}

pub fn queryComponentHandler3(handler: ?*anyopaque) ?*ivstcontextmenu.IComponentHandler3 {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivstcontextmenu.IComponentHandler3, handler, &ivstcontextmenu.icomponent_handler3_iid);
}

pub fn queryComponentHandlerBusActivation(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandlerBusActivation {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IComponentHandlerBusActivation, handler, &ivsteditcontroller.icomponent_handler_bus_activation_iid);
}

pub fn queryComponentHandlerSystemTime(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandlerSystemTime {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IComponentHandlerSystemTime, handler, &ivsteditcontroller.icomponent_handler_system_time_iid);
}

pub fn queryProgress(handler: ?*anyopaque) ?*ivsteditcontroller.IProgress {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IProgress, handler, &ivsteditcontroller.iprogress_iid);
}

pub fn queryUnitHandler(handler: ?*anyopaque) ?*ivstunits.IUnitHandler {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivstunits.IUnitHandler, handler, &ivstunits.iunit_handler_iid);
}

pub fn queryUnitHandler2(handler: ?*anyopaque) ?*ivstunits.IUnitHandler2 {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivstunits.IUnitHandler2, handler, &ivstunits.iunit_handler2_iid);
}

pub fn retainComponentHandler(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandler {
    const raw = handler orelse return null;
    const base: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(raw));
    _ = base.vtable.addRef(base);
    return base;
}

pub fn retainConnectionPeer(peer: *ivstmessage.IConnectionPoint) *ivstmessage.IConnectionPoint {
    _ = peer.vtable.addRef(peer);
    return peer;
}

pub fn releaseConnectionPeer(peer: *?*ivstmessage.IConnectionPoint) void {
    releaseOptionalInterface(ivstmessage.IConnectionPoint, peer);
}

pub fn releaseTelemetrySource(source: *?gui_telemetry_source.RetainedSource) void {
    const retained = source.* orelse return;
    source.* = null;
    retained.release();
}

pub fn replaceConnectionPeer(slot: *?*ivstmessage.IConnectionPoint, peer: ?*ivstmessage.IConnectionPoint) types.tresult {
    const connection_peer = peer orelse return types.kInvalidArgument;
    const next_peer = retainConnectionPeer(connection_peer);
    releaseConnectionPeer(slot);
    slot.* = next_peer;
    return types.kResultOk;
}

pub fn disconnectConnectionPeer(slot: *?*ivstmessage.IConnectionPoint, peer: ?*ivstmessage.IConnectionPoint) types.tresult {
    const connection_peer = peer orelse {
        releaseConnectionPeer(slot);
        return types.kResultOk;
    };
    const connected_peer = slot.* orelse {
        releaseConnectionPeer(slot);
        return types.kResultOk;
    };
    if (connected_peer == connection_peer) {
        releaseConnectionPeer(slot);
        return types.kResultOk;
    }
    return types.kResultFalse;
}

pub fn failOpenedDataExchangeQueue(out: *ivstdataexchange.DataExchangeQueueID, result: types.tresult) types.tresult {
    out.* = ivstdataexchange.InvalidDataExchangeQueueID;
    return result;
}

pub fn failLockedDataExchangeBlock(block: *ivstdataexchange.DataExchangeBlock, result: types.tresult) types.tresult {
    block.* = .{ .blockID = ivstdataexchange.InvalidDataExchangeBlockID };
    return result;
}

pub fn releaseComponentHandlers(controller: anytype) void {
    releaseOptionalInterface(ivstunits.IUnitHandler2, &controller.unit_handler2);
    releaseOptionalInterface(ivstunits.IUnitHandler, &controller.unit_handler);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandlerSystemTime, &controller.component_handler_system_time);
    releaseOptionalInterface(ivsteditcontroller.IProgress, &controller.progress);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandlerBusActivation, &controller.component_handler_bus_activation);
    releaseOptionalInterface(ivstcontextmenu.IComponentHandler3, &controller.component_handler3);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandler2, &controller.component_handler2);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandler, &controller.component_handler);
}
