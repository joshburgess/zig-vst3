const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const types = @import("pluginterfaces/base/types.zig");
const interface_map = @import("interface_map.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_plug_bridge = @import("zig_plug_bridge.zig");

pub fn ReflectedEditController(comptime Config: type) type {
    return struct {
        const Self = @This();
        const Params = Config.Params;

        const Controller = extern struct {
            iface: ivsteditcontroller.IEditController = .{ .vtable = &controller_vtable },
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        };

        var controller = Controller{};
        var parameter_state = zig_plug_bridge.ParameterState(Params).init(Config.parameter_set);
        var parameters = zig_plug_bridge.ParameterController(Params){
            .set = Config.parameter_set,
            .state = &parameter_state,
        };

        pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
            return query(&controller.iface, @ptrCast(requested_iid), out);
        }

        pub fn getNormalized(id: vsttypes.ParamID) vsttypes.ParamValue {
            return parameters.getNormalized(id);
        }

        pub fn setNormalized(id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            return parameters.setNormalized(id, value);
        }

        pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
            parameters.applyChanges(changes);
        }

        pub fn readState(state: ?*ibstream.IBStream) types.tresult {
            return parameters.readState(state);
        }

        pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
            return parameters.writeState(state);
        }

        const controller_vtable = ivsteditcontroller.IEditControllerVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .initialize = initialize,
            .terminate = terminate,
            .setComponentState = setComponentState,
            .setState = setState,
            .getState = getState,
            .getParameterCount = getParameterCount,
            .getParameterInfo = getParameterInfo,
            .getParamStringByValue = getParamStringByValue,
            .getParamValueByString = getParamValueByString,
            .normalizedParamToPlain = normalizedParamToPlain,
            .plainParamToNormalized = plainParamToNormalized,
            .getParamNormalized = getParamNormalized,
            .setParamNormalized = setParamNormalized,
            .setComponentHandler = setComponentHandler,
            .createView = createView,
        };

        fn owner(ptr: *anyopaque) *Controller {
            const iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ipluginbase.iplugin_base_iid, .ptr = ptr },
                .{ .iid = &ivsteditcontroller.iedit_controller_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, Config.controller_name);
        }

        fn initialize(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn terminate(_: *anyopaque) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn setComponentState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
            return Self.readState(state);
        }

        fn setState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
            return Self.readState(state);
        }

        fn getState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
            return Self.writeState(state);
        }

        fn getParameterCount(_: *anyopaque) callconv(.C) types.int32 {
            return parameters.parameterCount();
        }

        fn getParameterInfo(_: *anyopaque, index: types.int32, out: *ivsteditcontroller.ParameterInfo) callconv(.C) types.tresult {
            return parameters.parameterInfo(index, out);
        }

        fn getParamStringByValue(_: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
            return parameters.stringByValue(id, value, out);
        }

        fn getParamValueByString(_: *anyopaque, id: vsttypes.ParamID, text: [*]vsttypes.TChar, out: *vsttypes.ParamValue) callconv(.C) types.tresult {
            return parameters.valueByString(id, text, out);
        }

        fn normalizedParamToPlain(_: *anyopaque, id: vsttypes.ParamID, normalized: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
            return parameters.plainFromNormalized(id, normalized);
        }

        fn plainParamToNormalized(_: *anyopaque, id: vsttypes.ParamID, plain: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
            return parameters.normalizedFromPlain(id, plain);
        }

        fn getParamNormalized(_: *anyopaque, id: vsttypes.ParamID) callconv(.C) vsttypes.ParamValue {
            return parameters.getNormalized(id);
        }

        fn setParamNormalized(_: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.C) types.tresult {
            return parameters.setNormalized(id, value);
        }

        fn setComponentHandler(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn createView(_: *anyopaque, _: types.FIDString) callconv(.C) ?*iplugview.IPlugView {
            return null;
        }
    };
}

pub fn SimpleStereoEffect(comptime Config: type) type {
    return struct {
        const Self = @This();

        const Component = extern struct {
            iface: ivstcomponent.IComponent = .{ .vtable = &component_vtable },
            processor: ivstaudioprocessor.IAudioProcessor = .{ .vtable = &processor_vtable },
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        };

        var component = Component{};

        pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
            return query(&component.iface, @ptrCast(requested_iid), out);
        }

        const component_vtable = ivstcomponent.IComponentVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .initialize = initialize,
            .terminate = terminate,
            .getControllerClassId = getControllerClassId,
            .setIoMode = setIoMode,
            .getBusCount = getBusCount,
            .getBusInfo = getBusInfo,
            .getRoutingInfo = getRoutingInfo,
            .activateBus = activateBus,
            .setActive = setActive,
            .setState = setState,
            .getState = getState,
        };

        fn owner(ptr: *anyopaque) *Component {
            const iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn ownerFromProcessor(ptr: *anyopaque) *Component {
            const iface: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("processor", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ipluginbase.iplugin_base_iid, .ptr = ptr },
                .{ .iid = &ivstcomponent.icomponent_iid, .ptr = ptr },
                .{ .iid = &ivstaudioprocessor.iaudio_processor_iid, .ptr = &self.processor },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn queryFromProcessor(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            return query(&ownerFromProcessor(ptr).iface, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, Config.component_name);
        }

        fn initialize(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn terminate(_: *anyopaque) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn getControllerClassId(_: *anyopaque, out: *tuid.TUID) callconv(.C) types.tresult {
            out.* = Config.controller_cid;
            return types.kResultOk;
        }

        fn setIoMode(_: *anyopaque, _: vsttypes.IoMode) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn getBusCount(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) callconv(.C) types.int32 {
            return zig_plug_bridge.StereoAudioBuses.busCount(media_type, direction);
        }

        fn getBusInfo(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) callconv(.C) types.tresult {
            return zig_plug_bridge.StereoAudioBuses.busInfo(media_type, direction, index, out);
        }

        fn getRoutingInfo(_: *anyopaque, _: *ivstcomponent.RoutingInfo, _: *ivstcomponent.RoutingInfo) callconv(.C) types.tresult {
            return types.kNoInterface;
        }

        fn activateBus(_: *anyopaque, _: vsttypes.MediaType, _: vsttypes.BusDirection, _: types.int32, _: types.TBool) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn setActive(_: *anyopaque, _: types.TBool) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn setState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
            return Config.readState(state);
        }

        fn getState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
            return Config.writeState(state);
        }

        const processor_vtable = ivstaudioprocessor.IAudioProcessorVTable{
            .queryInterface = queryFromProcessor,
            .addRef = addRefFromProcessor,
            .release = releaseFromProcessor,
            .setBusArrangements = setBusArrangements,
            .getBusArrangement = getBusArrangement,
            .canProcessSampleSize = canProcessSampleSize,
            .getLatencySamples = getLatencySamples,
            .setupProcessing = setupProcessing,
            .setProcessing = setProcessing,
            .process = process,
            .getTailSamples = getTailSamples,
        };

        fn addRefFromProcessor(ptr: *anyopaque) callconv(.C) types.uint32 {
            return addRef(&ownerFromProcessor(ptr).iface);
        }

        fn releaseFromProcessor(ptr: *anyopaque) callconv(.C) types.uint32 {
            return release(&ownerFromProcessor(ptr).iface);
        }

        fn setBusArrangements(_: *anyopaque, inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32) callconv(.C) types.tresult {
            return zig_plug_bridge.StereoAudioBuses.setArrangements(inputs, num_inputs, outputs, num_outputs);
        }

        fn getBusArrangement(_: *anyopaque, direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement) callconv(.C) types.tresult {
            return zig_plug_bridge.StereoAudioBuses.arrangement(direction, index, out);
        }

        fn canProcessSampleSize(_: *anyopaque, symbolic_sample_size: types.int32) callconv(.C) types.tresult {
            return zig_plug_bridge.RealtimeProcessorDefaults.canProcessSampleSize(symbolic_sample_size);
        }

        fn getLatencySamples(_: *anyopaque) callconv(.C) types.uint32 {
            return zig_plug_bridge.RealtimeProcessorDefaults.latencySamples();
        }

        fn setupProcessing(_: *anyopaque, _: *ivstaudioprocessor.ProcessSetup) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn setProcessing(_: *anyopaque, _: types.TBool) callconv(.C) types.tresult {
            return types.kResultOk;
        }

        fn process(_: *anyopaque, data: *ivstaudioprocessor.ProcessData) callconv(.C) types.tresult {
            var parameter_change_storage: [64]plug_process.ParameterChange = undefined;
            var event_storage: [64]plug_process.Event = undefined;
            var output_event_storage: [64]plug_process.Event = undefined;
            const parameter_changes = zig_plug_bridge.collectInputParameterChanges(data, &parameter_change_storage);
            const events = zig_plug_bridge.collectInputEvents(data, &event_storage);
            var output_events = plug_process.EventWriter.init(&output_event_storage, if (data.numSamples <= 0) 0 else @intCast(data.numSamples));
            Config.applyParameterChanges(parameter_changes);
            const result = zig_plug_bridge.processMainAudio(data, parameter_changes, events, &output_events, Config.Processor{});
            if (result != types.kResultOk) return result;
            return zig_plug_bridge.writeOutputEvents(data, output_events.events());
        }

        fn getTailSamples(_: *anyopaque) callconv(.C) types.uint32 {
            return zig_plug_bridge.RealtimeProcessorDefaults.tailSamples();
        }
    };
}
