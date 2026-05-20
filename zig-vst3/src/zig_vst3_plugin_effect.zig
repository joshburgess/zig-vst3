const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const types = @import("pluginterfaces/base/types.zig");
const interface_map = @import("interface_map.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstautomationstate = @import("pluginterfaces/vst/ivstautomationstate.zig");
const ivstchannelcontextinfo = @import("pluginterfaces/vst/ivstchannelcontextinfo.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
const ivstdataexchange = @import("pluginterfaces/vst/ivstdataexchange.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const ivstmidilearn = @import("pluginterfaces/vst/ivstmidilearn.zig");
const ivstmidimapping2 = @import("pluginterfaces/vst/ivstmidimapping2.zig");
const ivstnoteexpression = @import("pluginterfaces/vst/ivstnoteexpression.zig");
const ivstparameterfunctionname = @import("pluginterfaces/vst/ivstparameterfunctionname.zig");
const ivstphysicalui = @import("pluginterfaces/vst/ivstphysicalui.zig");
const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");
const ivstprefetchablesupport = @import("pluginterfaces/vst/ivstprefetchablesupport.zig");
const ivstremapparamid = @import("pluginterfaces/vst/ivstremapparamid.zig");
const ivstrepresentation = @import("pluginterfaces/vst/ivstrepresentation.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const plug_core = @import("zig-vst3-plugin-core");
const plug_process = plug_core.process;
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");
const vst_index = @import("vst_index.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_bridge = @import("zig_vst3_plugin_bridge.zig");

const process_parameter_change_capacity = 64;
const process_event_capacity = 64;
const process_output_event_capacity = 64;

pub fn ReflectedEditController(comptime Config: type) type {
    return struct {
        const Self = @This();
        const Params = Config.Params;
        const unit_config = if (@hasDecl(Config, "unit_config")) Config.unit_config else plug_core.units.Config{};
        const UnitSet = plug_core.units.UnitSet(unit_config);
        const units = UnitSet{};

        const Controller = extern struct {
            iface: ivsteditcontroller.IEditController = .{ .vtable = &controller_vtable },
            connection_point: ivstmessage.IConnectionPoint = .{ .vtable = &connection_point_vtable },
            controller2: ivsteditcontroller.IEditController2 = .{ .vtable = &controller2_vtable },
            host_editing: ivsteditcontroller.IEditControllerHostEditing = .{ .vtable = &host_editing_vtable },
            unit_info: ivstunits.IUnitInfo = .{ .vtable = &unit_info_vtable },
            program_list_data: ivstunits.IProgramListData = .{ .vtable = &program_list_data_vtable },
            unit_data: ivstunits.IUnitData = .{ .vtable = &unit_data_vtable },
            midi_mapping: ivsteditcontroller.IMidiMapping = .{ .vtable = &midi_mapping_vtable },
            midi_learn: ivstmidilearn.IMidiLearn = .{ .vtable = &midi_learn_vtable },
            midi_mapping2: ivstmidimapping2.IMidiMapping2 = .{ .vtable = &midi_mapping2_vtable },
            midi_learn2: ivstmidimapping2.IMidiLearn2 = .{ .vtable = &midi_learn2_vtable },
            note_expression: ivstnoteexpression.INoteExpressionController = .{ .vtable = &note_expression_vtable },
            keyswitch: ivstnoteexpression.IKeyswitchController = .{ .vtable = &keyswitch_vtable },
            physical_ui_mapping: ivstphysicalui.INoteExpressionPhysicalUIMapping = .{ .vtable = &physical_ui_mapping_vtable },
            parameter_function_name: ivstparameterfunctionname.IParameterFunctionName = .{ .vtable = &parameter_function_name_vtable },
            remap_param_id: ivstremapparamid.IRemapParamID = .{ .vtable = &remap_param_id_vtable },
            xml_representation: ivstrepresentation.IXmlRepresentationController = .{ .vtable = &xml_representation_vtable },
            connected_peer: ?*ivstmessage.IConnectionPoint = null,
            component_handler: ?*ivsteditcontroller.IComponentHandler = null,
            component_handler2: ?*ivsteditcontroller.IComponentHandler2 = null,
            component_handler3: ?*ivstcontextmenu.IComponentHandler3 = null,
            component_handler_bus_activation: ?*ivsteditcontroller.IComponentHandlerBusActivation = null,
            component_handler_system_time: ?*ivsteditcontroller.IComponentHandlerSystemTime = null,
            progress: ?*ivsteditcontroller.IProgress = null,
            unit_handler: ?*ivstunits.IUnitHandler = null,
            unit_handler2: ?*ivstunits.IUnitHandler2 = null,
            host_application: ?*ivsthostapplication.IHostApplication = null,
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        };

        var controller = Controller{};
        var parameter_state = zig_vst3_plugin_bridge.ParameterState(Params).init(Config.parameter_set);
        var parameters = zig_vst3_plugin_bridge.ParameterController(Params){
            .set = Config.parameter_set,
            .state = &parameter_state,
        };

        pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.c) types.tresult {
            return query(&controller.iface, @ptrCast(requested_iid), out);
        }

        pub fn getNormalized(id: vsttypes.ParamID) vsttypes.ParamValue {
            return parameters.getNormalized(id);
        }

        pub fn setNormalized(id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            return parameters.setNormalized(id, value);
        }

        pub fn beginEdit(id: vsttypes.ParamID) types.tresult {
            const handler = controller.component_handler orelse return types.kResultFalse;
            return handler.vtable.beginEdit(handler, id);
        }

        pub fn performEdit(id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            const handler = controller.component_handler orelse return types.kResultFalse;
            const result = parameters.setNormalized(id, value);
            if (result != types.kResultOk) return result;
            return handler.vtable.performEdit(handler, id, value);
        }

        pub fn endEdit(id: vsttypes.ParamID) types.tresult {
            const handler = controller.component_handler orelse return types.kResultFalse;
            return handler.vtable.endEdit(handler, id);
        }

        pub fn setDirty(state: types.TBool) types.tresult {
            const handler = controller.component_handler2 orelse return types.kResultFalse;
            return handler.vtable.setDirty(handler, state);
        }

        pub fn requestOpenEditor(name: types.FIDString) types.tresult {
            const handler = controller.component_handler2 orelse return types.kResultFalse;
            return handler.vtable.requestOpenEditor(handler, name);
        }

        pub fn startGroupEdit() types.tresult {
            const handler = controller.component_handler2 orelse return types.kResultFalse;
            return handler.vtable.startGroupEdit(handler);
        }

        pub fn finishGroupEdit() types.tresult {
            const handler = controller.component_handler2 orelse return types.kResultFalse;
            return handler.vtable.finishGroupEdit(handler);
        }

        pub fn createContextMenu(view: ?*iplugview.IPlugView, param_id: ?*const vsttypes.ParamID) ?*ivstcontextmenu.IContextMenu {
            const handler = controller.component_handler3 orelse return null;
            return handler.vtable.createContextMenu(handler, view, param_id);
        }

        pub fn requestBusActivation(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, state: types.TBool) types.tresult {
            const handler = controller.component_handler_bus_activation orelse return types.kResultFalse;
            return handler.vtable.requestBusActivation(handler, media_type, direction, index, state);
        }

        pub fn getSystemTime(out: *types.int64) types.tresult {
            const handler = controller.component_handler_system_time orelse {
                out.* = 0;
                return types.kResultFalse;
            };
            return handler.vtable.getSystemTime(handler, out);
        }

        pub fn startProgress(progress_type: types.uint32, title: ?[*]const types.char16, out: *ivsteditcontroller.ProgressID) types.tresult {
            const progress = controller.progress orelse {
                out.* = 0;
                return types.kResultFalse;
            };
            return progress.vtable.start(progress, progress_type, title, out);
        }

        pub fn updateProgress(id: ivsteditcontroller.ProgressID, value: vsttypes.ParamValue) types.tresult {
            const progress = controller.progress orelse return types.kResultFalse;
            return progress.vtable.update(progress, id, value);
        }

        pub fn finishProgress(id: ivsteditcontroller.ProgressID) types.tresult {
            const progress = controller.progress orelse return types.kResultFalse;
            return progress.vtable.finish(progress, id);
        }

        pub fn notifyUnitSelection(unit_id: vsttypes.UnitID) types.tresult {
            const handler = controller.unit_handler orelse return types.kResultFalse;
            return handler.vtable.notifyUnitSelection(handler, unit_id);
        }

        pub fn notifyProgramListChange(list_id: vsttypes.ProgramListID, program_index: types.int32) types.tresult {
            const handler = controller.unit_handler orelse return types.kResultFalse;
            return handler.vtable.notifyProgramListChange(handler, list_id, program_index);
        }

        pub fn notifyUnitByBusChange() types.tresult {
            const handler = controller.unit_handler2 orelse return types.kResultFalse;
            return handler.vtable.notifyUnitByBusChange(handler);
        }

        pub fn openView(name: types.FIDString) ?*iplugview.IPlugView {
            return createView(&controller.iface, name);
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

        fn ownerFromController2(ptr: *anyopaque) *Controller {
            const iface: *ivsteditcontroller.IEditController2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("controller2", iface);
        }

        fn ownerFromConnectionPoint(ptr: *anyopaque) *Controller {
            const iface: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("connection_point", iface);
        }

        fn ownerFromHostEditing(ptr: *anyopaque) *Controller {
            const iface: *ivsteditcontroller.IEditControllerHostEditing = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("host_editing", iface);
        }

        fn ownerFromUnitInfo(ptr: *anyopaque) *Controller {
            const iface: *ivstunits.IUnitInfo = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("unit_info", iface);
        }

        fn ownerFromProgramListData(ptr: *anyopaque) *Controller {
            const iface: *ivstunits.IProgramListData = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("program_list_data", iface);
        }

        fn ownerFromUnitData(ptr: *anyopaque) *Controller {
            const iface: *ivstunits.IUnitData = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("unit_data", iface);
        }

        fn ownerFromMidiMapping(ptr: *anyopaque) *Controller {
            const iface: *ivsteditcontroller.IMidiMapping = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("midi_mapping", iface);
        }

        fn ownerFromMidiLearn(ptr: *anyopaque) *Controller {
            const iface: *ivstmidilearn.IMidiLearn = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("midi_learn", iface);
        }

        fn ownerFromMidiMapping2(ptr: *anyopaque) *Controller {
            const iface: *ivstmidimapping2.IMidiMapping2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("midi_mapping2", iface);
        }

        fn ownerFromMidiLearn2(ptr: *anyopaque) *Controller {
            const iface: *ivstmidimapping2.IMidiLearn2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("midi_learn2", iface);
        }

        fn ownerFromNoteExpression(ptr: *anyopaque) *Controller {
            const iface: *ivstnoteexpression.INoteExpressionController = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("note_expression", iface);
        }

        fn ownerFromKeyswitch(ptr: *anyopaque) *Controller {
            const iface: *ivstnoteexpression.IKeyswitchController = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("keyswitch", iface);
        }

        fn ownerFromPhysicalUIMapping(ptr: *anyopaque) *Controller {
            const iface: *ivstphysicalui.INoteExpressionPhysicalUIMapping = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("physical_ui_mapping", iface);
        }

        fn ownerFromParameterFunctionName(ptr: *anyopaque) *Controller {
            const iface: *ivstparameterfunctionname.IParameterFunctionName = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("parameter_function_name", iface);
        }

        fn ownerFromRemapParamID(ptr: *anyopaque) *Controller {
            const iface: *ivstremapparamid.IRemapParamID = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("remap_param_id", iface);
        }

        fn ownerFromXmlRepresentation(ptr: *anyopaque) *Controller {
            const iface: *ivstrepresentation.IXmlRepresentationController = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("xml_representation", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const entries = [_]interface_map.Entry{
                interface_map.fieldEntry("iface", self, &funknown.iid),
                interface_map.fieldEntry("iface", self, &ipluginbase.iplugin_base_iid),
                interface_map.fieldEntry("iface", self, &ivsteditcontroller.iedit_controller_iid),
                interface_map.fieldEntry("connection_point", self, &ivstmessage.iconnection_point_iid),
                interface_map.fieldEntry("controller2", self, &ivsteditcontroller.iedit_controller2_iid),
                interface_map.fieldEntry("host_editing", self, &ivsteditcontroller.iedit_controller_host_editing_iid),
                interface_map.fieldEntry("unit_info", self, &ivstunits.iunit_info_iid),
                interface_map.fieldEntry("program_list_data", self, &ivstunits.iprogram_list_data_iid),
                interface_map.fieldEntry("unit_data", self, &ivstunits.iunit_data_iid),
                interface_map.fieldEntry("midi_mapping", self, &ivsteditcontroller.imidi_mapping_iid),
                interface_map.fieldEntry("midi_learn", self, &ivstmidilearn.imidi_learn_iid),
                interface_map.fieldEntry("midi_mapping2", self, &ivstmidimapping2.imidi_mapping2_iid),
                interface_map.fieldEntry("midi_learn2", self, &ivstmidimapping2.imidi_learn2_iid),
                interface_map.fieldEntry("note_expression", self, &ivstnoteexpression.inote_expression_controller_iid),
                interface_map.fieldEntry("keyswitch", self, &ivstnoteexpression.ikeyswitch_controller_iid),
                interface_map.fieldEntry("physical_ui_mapping", self, &ivstphysicalui.inote_expression_physical_ui_mapping_iid),
                interface_map.fieldEntry("parameter_function_name", self, &ivstparameterfunctionname.iparameter_function_name_iid),
                interface_map.fieldEntry("remap_param_id", self, &ivstremapparamid.iremap_param_id_iid),
                interface_map.fieldEntry("xml_representation", self, &ivstrepresentation.ixml_representation_controller_iid),
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn queryFromOwnedInterface(comptime ownerFn: fn (*anyopaque) *Controller, ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            return query(&ownerFn(ptr).iface, requested_iid, out);
        }

        fn queryFromUnitInfo(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromUnitInfo, ptr, requested_iid, out);
        }

        fn queryFromProgramListData(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromProgramListData, ptr, requested_iid, out);
        }

        fn queryFromUnitData(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromUnitData, ptr, requested_iid, out);
        }

        fn queryFromController2(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromController2, ptr, requested_iid, out);
        }

        fn queryFromConnectionPoint(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromConnectionPoint, ptr, requested_iid, out);
        }

        fn queryFromHostEditing(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromHostEditing, ptr, requested_iid, out);
        }

        fn queryFromMidiMapping(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromMidiMapping, ptr, requested_iid, out);
        }

        fn queryFromMidiLearn(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromMidiLearn, ptr, requested_iid, out);
        }

        fn queryFromMidiMapping2(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromMidiMapping2, ptr, requested_iid, out);
        }

        fn queryFromMidiLearn2(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromMidiLearn2, ptr, requested_iid, out);
        }

        fn queryFromNoteExpression(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromNoteExpression, ptr, requested_iid, out);
        }

        fn queryFromKeyswitch(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromKeyswitch, ptr, requested_iid, out);
        }

        fn queryFromPhysicalUIMapping(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromPhysicalUIMapping, ptr, requested_iid, out);
        }

        fn queryFromParameterFunctionName(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromParameterFunctionName, ptr, requested_iid, out);
        }

        fn queryFromRemapParamID(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromRemapParamID, ptr, requested_iid, out);
        }

        fn queryFromXmlRepresentation(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromXmlRepresentation, ptr, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, Config.controller_name);
        }

        fn addRefFromOwnedInterface(comptime ownerFn: fn (*anyopaque) *Controller, ptr: *anyopaque) types.uint32 {
            return addRef(&ownerFn(ptr).iface);
        }

        fn releaseFromOwnedInterface(comptime ownerFn: fn (*anyopaque) *Controller, ptr: *anyopaque) types.uint32 {
            return release(&ownerFn(ptr).iface);
        }

        fn addRefFromUnitInfo(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromUnitInfo, ptr);
        }

        fn releaseFromUnitInfo(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromUnitInfo, ptr);
        }

        fn addRefFromProgramListData(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromProgramListData, ptr);
        }

        fn releaseFromProgramListData(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromProgramListData, ptr);
        }

        fn addRefFromUnitData(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromUnitData, ptr);
        }

        fn releaseFromUnitData(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromUnitData, ptr);
        }

        fn addRefFromController2(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromController2, ptr);
        }

        fn releaseFromController2(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromController2, ptr);
        }

        fn addRefFromConnectionPoint(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromConnectionPoint, ptr);
        }

        fn releaseFromConnectionPoint(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromConnectionPoint, ptr);
        }

        fn addRefFromHostEditing(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromHostEditing, ptr);
        }

        fn releaseFromHostEditing(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromHostEditing, ptr);
        }

        fn addRefFromMidiMapping(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromMidiMapping, ptr);
        }

        fn releaseFromMidiMapping(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromMidiMapping, ptr);
        }

        fn addRefFromMidiLearn(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromMidiLearn, ptr);
        }

        fn releaseFromMidiLearn(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromMidiLearn, ptr);
        }

        fn addRefFromMidiMapping2(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromMidiMapping2, ptr);
        }

        fn releaseFromMidiMapping2(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromMidiMapping2, ptr);
        }

        fn addRefFromMidiLearn2(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromMidiLearn2, ptr);
        }

        fn releaseFromMidiLearn2(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromMidiLearn2, ptr);
        }

        fn addRefFromNoteExpression(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromNoteExpression, ptr);
        }

        fn releaseFromNoteExpression(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromNoteExpression, ptr);
        }

        fn addRefFromKeyswitch(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromKeyswitch, ptr);
        }

        fn releaseFromKeyswitch(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromKeyswitch, ptr);
        }

        fn addRefFromPhysicalUIMapping(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromPhysicalUIMapping, ptr);
        }

        fn releaseFromPhysicalUIMapping(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromPhysicalUIMapping, ptr);
        }

        fn addRefFromParameterFunctionName(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromParameterFunctionName, ptr);
        }

        fn releaseFromParameterFunctionName(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromParameterFunctionName, ptr);
        }

        fn addRefFromRemapParamID(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromRemapParamID, ptr);
        }

        fn releaseFromRemapParamID(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromRemapParamID, ptr);
        }

        fn addRefFromXmlRepresentation(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromXmlRepresentation, ptr);
        }

        fn releaseFromXmlRepresentation(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromXmlRepresentation, ptr);
        }

        fn initialize(ptr: *anyopaque, context: ?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const next_host_application = queryHostApplication(context);
            releaseHostApplication(&self.host_application);
            self.host_application = next_host_application;
            return types.kResultOk;
        }

        fn terminate(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            releaseConnectionPeer(&self.connected_peer);
            releaseComponentHandlers(self);
            releaseHostApplication(&self.host_application);
            return types.kResultOk;
        }

        fn setComponentState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return Self.readState(state);
        }

        fn setState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return Self.readState(state);
        }

        fn getState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return Self.writeState(state);
        }

        fn getParameterCount(_: *anyopaque) callconv(.c) types.int32 {
            return parameters.parameterCount();
        }

        fn getParameterInfo(_: *anyopaque, index: types.int32, out: *ivsteditcontroller.ParameterInfo) callconv(.c) types.tresult {
            return parameters.parameterInfo(index, out);
        }

        fn getParamStringByValue(_: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            return parameters.stringByValue(id, value, out);
        }

        fn getParamValueByString(_: *anyopaque, id: vsttypes.ParamID, text: [*]vsttypes.TChar, out: *vsttypes.ParamValue) callconv(.c) types.tresult {
            return parameters.valueByString(id, text, out);
        }

        fn normalizedParamToPlain(_: *anyopaque, id: vsttypes.ParamID, normalized: vsttypes.ParamValue) callconv(.c) vsttypes.ParamValue {
            return parameters.plainFromNormalized(id, normalized);
        }

        fn plainParamToNormalized(_: *anyopaque, id: vsttypes.ParamID, plain: vsttypes.ParamValue) callconv(.c) vsttypes.ParamValue {
            return parameters.normalizedFromPlain(id, plain);
        }

        fn getParamNormalized(_: *anyopaque, id: vsttypes.ParamID) callconv(.c) vsttypes.ParamValue {
            return parameters.getNormalized(id);
        }

        fn setParamNormalized(_: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            return parameters.setNormalized(id, value);
        }

        fn setComponentHandler(ptr: *anyopaque, handler: ?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const next_component_handler = retainComponentHandler(handler);
            const next_component_handler2 = queryComponentHandler2(handler);
            const next_component_handler3 = queryComponentHandler3(handler);
            const next_component_handler_bus_activation = queryComponentHandlerBusActivation(handler);
            const next_component_handler_system_time = queryComponentHandlerSystemTime(handler);
            const next_progress = queryProgress(handler);
            const next_unit_handler = queryUnitHandler(handler);
            const next_unit_handler2 = queryUnitHandler2(handler);

            releaseComponentHandlers(self);
            self.component_handler = next_component_handler;
            self.component_handler2 = next_component_handler2;
            self.component_handler3 = next_component_handler3;
            self.component_handler_bus_activation = next_component_handler_bus_activation;
            self.component_handler_system_time = next_component_handler_system_time;
            self.progress = next_progress;
            self.unit_handler = next_unit_handler;
            self.unit_handler2 = next_unit_handler2;
            return types.kResultOk;
        }

        fn createView(_: *anyopaque, name: types.FIDString) callconv(.c) ?*iplugview.IPlugView {
            if (@hasDecl(Config, "createView")) {
                return Config.createView(name);
            }
            return null;
        }

        const connection_point_vtable = ivstmessage.IConnectionPointVTable{
            .queryInterface = queryFromConnectionPoint,
            .addRef = addRefFromConnectionPoint,
            .release = releaseFromConnectionPoint,
            .connect = connect,
            .disconnect = disconnect,
            .notify = notify,
        };

        fn connect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromConnectionPoint(ptr);
            const connection_peer = peer orelse return types.kInvalidArgument;
            const next_peer = retainConnectionPeer(connection_peer);
            releaseConnectionPeer(&self.connected_peer);
            self.connected_peer = next_peer;
            return types.kResultOk;
        }

        fn disconnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromConnectionPoint(ptr);
            const connection_peer = peer orelse {
                releaseConnectionPeer(&self.connected_peer);
                return types.kResultOk;
            };
            const connected_peer = self.connected_peer orelse {
                releaseConnectionPeer(&self.connected_peer);
                return types.kResultOk;
            };
            if (connected_peer == connection_peer) {
                releaseConnectionPeer(&self.connected_peer);
                return types.kResultOk;
            }
            return types.kResultFalse;
        }

        fn notify(_: *anyopaque, _: ?*ivstmessage.IMessage) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const controller2_vtable = ivsteditcontroller.IEditController2VTable{
            .queryInterface = queryFromController2,
            .addRef = addRefFromController2,
            .release = releaseFromController2,
            .setKnobMode = setKnobMode,
            .openHelp = openHelp,
            .openAboutBox = openAboutBox,
        };

        fn setKnobMode(_: *anyopaque, _: ivsteditcontroller.KnobMode) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        fn openHelp(_: *anyopaque, _: types.TBool) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn openAboutBox(_: *anyopaque, _: types.TBool) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const host_editing_vtable = ivsteditcontroller.IEditControllerHostEditingVTable{
            .queryInterface = queryFromHostEditing,
            .addRef = addRefFromHostEditing,
            .release = releaseFromHostEditing,
            .beginEditFromHost = beginEditFromHost,
            .endEditFromHost = endEditFromHost,
        };

        fn beginEditFromHost(_: *anyopaque, _: vsttypes.ParamID) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        fn endEditFromHost(_: *anyopaque, _: vsttypes.ParamID) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        const unit_info_vtable = ivstunits.IUnitInfoVTable{
            .queryInterface = queryFromUnitInfo,
            .addRef = addRefFromUnitInfo,
            .release = releaseFromUnitInfo,
            .getUnitCount = getUnitCount,
            .getUnitInfo = getUnitInfo,
            .getProgramListCount = getProgramListCount,
            .getProgramListInfo = getProgramListInfo,
            .getProgramName = getProgramName,
            .getProgramInfo = getProgramInfo,
            .hasProgramPitchNames = hasProgramPitchNames,
            .getProgramPitchName = getProgramPitchName,
            .getSelectedUnit = getSelectedUnit,
            .selectUnit = selectUnit,
            .getUnitByBus = getUnitByBus,
            .setUnitProgramData = setUnitProgramData,
        };

        fn getUnitCount(_: *anyopaque) callconv(.c) types.int32 {
            return countToInt32(UnitSet.unit_count);
        }

        fn getUnitInfo(_: *anyopaque, index: types.int32, out: *ivstunits.UnitInfo) callconv(.c) types.tresult {
            const unit_index = vst_index.bounded(index, UnitSet.unit_count) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            const reflected = units.unit(unit_index) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            out.* = .{
                .id = reflected.id,
                .parentUnitId = reflected.parent_id,
                .programListId = reflected.program_list_id,
            };
            string128.copy(&out.name, reflected.name);
            return types.kResultOk;
        }

        fn getProgramListCount(_: *anyopaque) callconv(.c) types.int32 {
            return countToInt32(UnitSet.program_list_count);
        }

        fn getProgramListInfo(_: *anyopaque, index: types.int32, out: *ivstunits.ProgramListInfo) callconv(.c) types.tresult {
            const list_index = vst_index.bounded(index, UnitSet.program_list_count) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            const reflected = units.programList(list_index) orelse {
                out.* = .{};
                return types.kInvalidArgument;
            };
            out.* = .{
                .id = reflected.id,
                .programCount = countToInt32(reflected.programs.len),
            };
            string128.copy(&out.name, reflected.name);
            return types.kResultOk;
        }

        fn getProgramName(_: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.clearPtr(out);
            const count = units.programCount(list_id) orelse return types.kInvalidArgument;
            const index = vst_index.bounded(program_index, count) orelse return types.kInvalidArgument;
            const name = units.programName(list_id, index) orelse return types.kInvalidArgument;
            string128.copyPtr(out, name);
            return types.kResultOk;
        }

        fn getProgramInfo(_: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, attribute_id: vsttypes.CString, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.clearPtr(out);
            const count = units.programCount(list_id) orelse return types.kInvalidArgument;
            const index = vst_index.bounded(program_index, count) orelse return types.kInvalidArgument;
            const value = units.programInfo(list_id, index, std.mem.span(attribute_id)) orelse return types.kInvalidArgument;
            string128.copyPtr(out, value);
            return types.kResultOk;
        }

        fn hasProgramPitchNames(_: *anyopaque, _: vsttypes.ProgramListID, _: types.int32) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn getProgramPitchName(_: *anyopaque, _: vsttypes.ProgramListID, _: types.int32, _: types.int16, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.clearPtr(out);
            return types.kInvalidArgument;
        }

        fn getSelectedUnit(_: *anyopaque) callconv(.c) vsttypes.UnitID {
            return units.rootUnit().id;
        }

        fn selectUnit(_: *anyopaque, id: vsttypes.UnitID) callconv(.c) types.tresult {
            if (units.unitById(id) == null) return types.kInvalidArgument;
            return types.kResultOk;
        }

        fn getUnitByBus(_: *anyopaque, _: vsttypes.MediaType, _: vsttypes.BusDirection, _: types.int32, _: types.int32, out: *vsttypes.UnitID) callconv(.c) types.tresult {
            out.* = units.rootUnit().id;
            return types.kResultOk;
        }

        fn setUnitProgramData(_: *anyopaque, _: types.int32, _: types.int32, _: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const program_list_data_vtable = ivstunits.IProgramListDataVTable{
            .queryInterface = queryFromProgramListData,
            .addRef = addRefFromProgramListData,
            .release = releaseFromProgramListData,
            .programDataSupported = programDataSupported,
            .getProgramData = getProgramData,
            .setProgramData = setProgramData,
        };

        fn programDataSupported(_: *anyopaque, list_id: vsttypes.ProgramListID) callconv(.c) types.tresult {
            const count = units.programCount(list_id) orelse return types.kResultFalse;
            for (0..count) |program_index| {
                if ((units.programParameterCount(list_id, program_index) orelse 0) != 0) return types.kResultOk;
            }
            return types.kResultFalse;
        }

        fn getProgramData(_: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const count = units.programCount(list_id) orelse return types.kResultFalse;
            const index = vst_index.bounded(program_index, count) orelse return types.kInvalidArgument;
            const reflected = units.program(list_id, index) orelse return types.kInvalidArgument;
            if (reflected.parameters.len == 0) return types.kResultFalse;

            var values = plug_core.parameters.ParameterValues(Params).init(Config.parameter_set);
            for (reflected.parameters) |parameter| {
                if (!zig_vst3_plugin_bridge.isNormalizedValue(parameter.normalized)) {
                    return types.kResultFalse;
                }
                _ = values.storeById(Config.parameter_set, parameter.parameter_id, parameter.normalized);
            }
            return zig_vst3_plugin_bridge.writeParameterState(Params, stream, Config.parameter_set, &values);
        }

        fn setProgramData(_: *anyopaque, _: vsttypes.ProgramListID, _: types.int32, _: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const unit_data_vtable = ivstunits.IUnitDataVTable{
            .queryInterface = queryFromUnitData,
            .addRef = addRefFromUnitData,
            .release = releaseFromUnitData,
            .unitDataSupported = unitDataSupported,
            .getUnitData = getUnitData,
            .setUnitData = setUnitData,
        };

        fn unitDataSupported(_: *anyopaque, _: vsttypes.UnitID) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn getUnitData(_: *anyopaque, _: vsttypes.UnitID, _: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn setUnitData(_: *anyopaque, _: vsttypes.UnitID, _: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const midi_mapping_vtable = ivsteditcontroller.IMidiMappingVTable{
            .queryInterface = queryFromMidiMapping,
            .addRef = addRefFromMidiMapping,
            .release = releaseFromMidiMapping,
            .getMidiControllerAssignment = getMidiControllerAssignment,
        };

        fn getMidiControllerAssignment(_: *anyopaque, _: types.int32, _: types.int16, _: vsttypes.CtrlNumber, out: *vsttypes.ParamID) callconv(.c) types.tresult {
            out.* = vsttypes.kNoParamId;
            return types.kResultFalse;
        }

        const midi_learn_vtable = ivstmidilearn.IMidiLearnVTable{
            .queryInterface = queryFromMidiLearn,
            .addRef = addRefFromMidiLearn,
            .release = releaseFromMidiLearn,
            .onLiveMIDIControllerInput = onLiveMIDIControllerInput,
        };

        fn onLiveMIDIControllerInput(_: *anyopaque, _: types.int32, _: types.int16, _: vsttypes.CtrlNumber) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const midi_mapping2_vtable = ivstmidimapping2.IMidiMapping2VTable{
            .queryInterface = queryFromMidiMapping2,
            .addRef = addRefFromMidiMapping2,
            .release = releaseFromMidiMapping2,
            .getNumMidi2ControllerAssignments = getNumMidi2ControllerAssignments,
            .getMidi2ControllerAssignments = getMidi2ControllerAssignments,
            .getNumMidi1ControllerAssignments = getNumMidi1ControllerAssignments,
            .getMidi1ControllerAssignments = getMidi1ControllerAssignments,
        };

        fn getNumMidi2ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection) callconv(.c) types.uint32 {
            return 0;
        }

        fn getMidi2ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection, _: *const ivstmidimapping2.Midi2ControllerParamIDAssignmentList) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn getNumMidi1ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection) callconv(.c) types.uint32 {
            return 0;
        }

        fn getMidi1ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection, _: *const ivstmidimapping2.Midi1ControllerParamIDAssignmentList) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const midi_learn2_vtable = ivstmidimapping2.IMidiLearn2VTable{
            .queryInterface = queryFromMidiLearn2,
            .addRef = addRefFromMidiLearn2,
            .release = releaseFromMidiLearn2,
            .onLiveMidi2ControllerInput = onLiveMidi2ControllerInput,
            .onLiveMidi1ControllerInput = onLiveMidi1ControllerInput,
        };

        fn onLiveMidi2ControllerInput(_: *anyopaque, _: ivstmidimapping2.BusIndex, _: ivstmidimapping2.MidiChannel, _: ivstmidimapping2.Midi2Controller) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn onLiveMidi1ControllerInput(_: *anyopaque, _: ivstmidimapping2.BusIndex, _: ivstmidimapping2.MidiChannel, _: vsttypes.CtrlNumber) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const note_expression_vtable = ivstnoteexpression.INoteExpressionControllerVTable{
            .queryInterface = queryFromNoteExpression,
            .addRef = addRefFromNoteExpression,
            .release = releaseFromNoteExpression,
            .getNoteExpressionCount = getNoteExpressionCount,
            .getNoteExpressionInfo = getNoteExpressionInfo,
            .getNoteExpressionStringByValue = getNoteExpressionStringByValue,
            .getNoteExpressionValueByString = getNoteExpressionValueByString,
        };

        fn getNoteExpressionCount(_: *anyopaque, _: types.int32, _: types.int16) callconv(.c) types.int32 {
            return 0;
        }

        fn getNoteExpressionInfo(_: *anyopaque, _: types.int32, _: types.int16, _: types.int32, out: *ivstnoteexpression.NoteExpressionTypeInfo) callconv(.c) types.tresult {
            out.* = .{};
            return types.kInvalidArgument;
        }

        fn getNoteExpressionStringByValue(_: *anyopaque, _: types.int32, _: types.int16, _: ivstnoteexpression.NoteExpressionTypeID, _: ivstnoteexpression.NoteExpressionValue, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            string128.clearPtr(out);
            return types.kInvalidArgument;
        }

        fn getNoteExpressionValueByString(_: *anyopaque, _: types.int32, _: types.int16, _: ivstnoteexpression.NoteExpressionTypeID, _: [*:0]const vsttypes.TChar, out: *ivstnoteexpression.NoteExpressionValue) callconv(.c) types.tresult {
            out.* = 0;
            return types.kInvalidArgument;
        }

        const keyswitch_vtable = ivstnoteexpression.IKeyswitchControllerVTable{
            .queryInterface = queryFromKeyswitch,
            .addRef = addRefFromKeyswitch,
            .release = releaseFromKeyswitch,
            .getKeyswitchCount = getKeyswitchCount,
            .getKeyswitchInfo = getKeyswitchInfo,
        };

        fn getKeyswitchCount(_: *anyopaque, _: types.int32, _: types.int16) callconv(.c) types.int32 {
            return 0;
        }

        fn getKeyswitchInfo(_: *anyopaque, _: types.int32, _: types.int16, _: types.int32, out: *ivstnoteexpression.KeyswitchInfo) callconv(.c) types.tresult {
            out.* = .{};
            return types.kInvalidArgument;
        }

        const physical_ui_mapping_vtable = ivstphysicalui.INoteExpressionPhysicalUIMappingVTable{
            .queryInterface = queryFromPhysicalUIMapping,
            .addRef = addRefFromPhysicalUIMapping,
            .release = releaseFromPhysicalUIMapping,
            .getPhysicalUIMapping = getPhysicalUIMapping,
        };

        fn getPhysicalUIMapping(_: *anyopaque, _: types.int32, _: types.int16, out: *ivstphysicalui.PhysicalUIMapList) callconv(.c) types.tresult {
            out.* = .{};
            return types.kResultFalse;
        }

        const parameter_function_name_vtable = ivstparameterfunctionname.IParameterFunctionNameVTable{
            .queryInterface = queryFromParameterFunctionName,
            .addRef = addRefFromParameterFunctionName,
            .release = releaseFromParameterFunctionName,
            .getParameterIDFromFunctionName = getParameterIDFromFunctionName,
        };

        fn getParameterIDFromFunctionName(_: *anyopaque, _: vsttypes.UnitID, _: types.FIDString, out: *vsttypes.ParamID) callconv(.c) types.tresult {
            out.* = vsttypes.kNoParamId;
            return types.kResultFalse;
        }

        const remap_param_id_vtable = ivstremapparamid.IRemapParamIDVTable{
            .queryInterface = queryFromRemapParamID,
            .addRef = addRefFromRemapParamID,
            .release = releaseFromRemapParamID,
            .getCompatibleParamID = getCompatibleParamID,
        };

        fn getCompatibleParamID(_: *anyopaque, _: *const tuid.TUID, _: vsttypes.ParamID, out: *vsttypes.ParamID) callconv(.c) types.tresult {
            out.* = vsttypes.kNoParamId;
            return types.kResultFalse;
        }

        const xml_representation_vtable = ivstrepresentation.IXmlRepresentationControllerVTable{
            .queryInterface = queryFromXmlRepresentation,
            .addRef = addRefFromXmlRepresentation,
            .release = releaseFromXmlRepresentation,
            .getXmlRepresentationStream = getXmlRepresentationStream,
        };

        fn getXmlRepresentationStream(_: *anyopaque, info: *ivstrepresentation.RepresentationInfo, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            if (@hasDecl(Config, "getXmlRepresentationStream")) {
                return Config.getXmlRepresentationStream(info, stream);
            }
            return types.kResultFalse;
        }
    };
}

fn countToInt32(count: usize) types.int32 {
    return std.math.cast(types.int32, count) orelse std.math.maxInt(types.int32);
}

test "reflected edit controller clears unsupported query outputs" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "QueryController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var queried: ?*anyopaque = @ptrFromInt(0x10);
    try std.testing.expectEqual(types.kNoInterface, controller_iface.vtable.queryInterface(controller_iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstunits.iunit_info_iid, &queried));
    const unit_info: *ivstunits.IUnitInfo = @ptrCast(@alignCast(queried.?));

    queried = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, unit_info.vtable.queryInterface(unit_info, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expect(unit_info.vtable.release(unit_info) >= 1);
}

test "reflected edit controller exposes configured units and programs" {
    const programs = [_]plug_core.units.Program{
        .{ .name = "Clean", .info = &.{.{ .key = "category", .value = "Clean" }} },
        .{ .name = "Lead" },
    };
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "UnitController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub const unit_config = plug_core.units.Config{
            .units = &.{
                plug_core.units.Unit.root("Main"),
                .{ .id = 1, .name = "Voice", .parent_id = plug_core.units.root_unit_id, .program_list_id = 7 },
            },
            .program_lists = &.{
                .{ .id = 7, .name = "Voice Programs", .programs = &programs },
            },
        };
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var unit_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstunits.iunit_info_iid, &unit_out));
    try std.testing.expect(unit_out != null);
    const unit_info: *ivstunits.IUnitInfo = @ptrCast(@alignCast(unit_out.?));
    defer _ = unit_info.vtable.release(unit_info);

    try std.testing.expectEqual(@as(types.int32, 2), unit_info.vtable.getUnitCount(unit_info));
    var unit: ivstunits.UnitInfo = .{};
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getUnitInfo(unit_info, -1, &unit));
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.getUnitInfo(unit_info, 1, &unit));
    try std.testing.expectEqual(@as(vsttypes.UnitID, 1), unit.id);
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 7), unit.programListId);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'V'), unit.name[0]);

    try std.testing.expectEqual(@as(types.int32, 1), unit_info.vtable.getProgramListCount(unit_info));
    var list: ivstunits.ProgramListInfo = .{};
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramListInfo(unit_info, -1, &list));
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.getProgramListInfo(unit_info, 0, &list));
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 7), list.id);
    try std.testing.expectEqual(@as(types.int32, 2), list.programCount);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'V'), list.name[0]);

    var program_name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.getProgramName(unit_info, 7, 1, &program_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'L'), program_name[0]);
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramName(unit_info, 7, -1, &program_name));
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramName(unit_info, 7, 2, &program_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_name[0]);

    var program_info: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.getProgramInfo(unit_info, 7, 0, "category", &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'C'), program_info[0]);
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramInfo(unit_info, 7, -1, "category", &program_info));
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramInfo(unit_info, 7, 0, "missing", &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[0]);

    try std.testing.expectEqual(@as(vsttypes.UnitID, 0), unit_info.vtable.getSelectedUnit(unit_info));
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.selectUnit(unit_info, 1));
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.selectUnit(unit_info, 99));
}

test "reflected edit controller exposes program snapshot data" {
    const Fixture = struct {
        const Params = struct {
            gain: plug_core.parameters.FloatParam = plug_core.parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
        const ParameterSet = plug_core.parameters.ParameterSet(Params);
        const parameter_set = ParameterSet.init(.{});
        const programs = [_]plug_core.units.Program{
            .{
                .name = "Quiet",
                .parameters = &.{.{ .parameter_id = 1, .normalized = 0.25 }},
            },
            .{ .name = "Metadata Only" },
        };
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "ProgramDataController";
        pub const Params = Fixture.Params;
        pub const parameter_set = &Fixture.parameter_set;
        pub const unit_config = plug_core.units.Config{
            .program_lists = &.{
                .{ .id = 7, .name = "Gain Programs", .programs = &Fixture.programs },
            },
        };
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var program_data_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstunits.iprogram_list_data_iid, &program_data_out));
    try std.testing.expect(program_data_out != null);
    const program_data: *ivstunits.IProgramListData = @ptrCast(@alignCast(program_data_out.?));
    defer _ = program_data.vtable.release(program_data);

    const Stream = vst_stream.FixedBufferStream(plug_core.state.encodedSize(Fixture.Params));
    var stream = Stream{};
    var restored = plug_core.parameters.ParameterValues(Fixture.Params).init(&Fixture.parameter_set);
    var pos: types.int64 = -1;

    try std.testing.expectEqual(types.kResultOk, program_data.vtable.programDataSupported(program_data, 7));
    try std.testing.expectEqual(types.kResultOk, program_data.vtable.getProgramData(program_data, 7, 0, stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), &pos));
    try std.testing.expectEqual(types.kResultOk, zig_vst3_plugin_bridge.readParameterState(Fixture.Params, stream.asStream(), &Fixture.parameter_set, &restored));
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadById(&Fixture.parameter_set, 1).?);
    try std.testing.expectEqual(types.kResultFalse, program_data.vtable.getProgramData(program_data, 7, 1, stream.asStream()));
    try std.testing.expectEqual(types.kInvalidArgument, program_data.vtable.getProgramData(program_data, 7, -1, stream.asStream()));
    try std.testing.expectEqual(types.kInvalidArgument, program_data.vtable.getProgramData(program_data, 7, 2, stream.asStream()));
    try std.testing.expectEqual(types.kResultFalse, program_data.vtable.programDataSupported(program_data, 99));
    try std.testing.expectEqual(types.kResultFalse, program_data.vtable.setProgramData(program_data, 7, 0, stream.asStream()));
}

test "reflected edit controller round-trips parameter state through host callbacks" {
    const Fixture = struct {
        const Params = struct {
            gain: plug_core.parameters.FloatParam = plug_core.parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 0.25),
        };
        const ParameterSet = plug_core.parameters.ParameterSet(Params);
        const parameter_set = ParameterSet.init(.{});
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "StateController";
        pub const Params = Fixture.Params;
        pub const parameter_set = &Fixture.parameter_set;
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setParamNormalized(controller_iface, 1, 0.75));

    const Stream = vst_stream.FixedBufferStream(plug_core.state.encodedSize(Fixture.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.getState(controller_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_core.state.encodedSize(Fixture.Params)), stream.data().len);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setParamNormalized(controller_iface, 1, 0.0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.0), controller_iface.vtable.getParamNormalized(controller_iface, 1));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentState(controller_iface, stream.asStream()));
    try std.testing.expectApproxEqAbs(@as(vsttypes.ParamValue, 0.75), controller_iface.vtable.getParamNormalized(controller_iface, 1), 0.000001);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setParamNormalized(controller_iface, 1, 0.25));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setState(controller_iface, stream.asStream()));
    try std.testing.expectApproxEqAbs(@as(vsttypes.ParamValue, 0.75), controller_iface.vtable.getParamNormalized(controller_iface, 1), 0.000001);
}

fn queryInterfaceAs(comptime Base: type, comptime Interface: type, source: ?*anyopaque, iid: *const tuid.TUID) ?*Interface {
    const raw = source orelse return null;
    const base: *Base = @ptrCast(@alignCast(raw));
    var out: ?*anyopaque = null;
    if (base.vtable.queryInterface(base, iid, &out) != types.kResultOk) return null;
    return if (out) |value| @ptrCast(@alignCast(value)) else null;
}

fn queryHostApplication(context: ?*anyopaque) ?*ivsthostapplication.IHostApplication {
    return queryInterfaceAs(funknown.Header, ivsthostapplication.IHostApplication, context, &ivsthostapplication.ihost_application_iid);
}

fn releaseOptionalInterface(comptime Interface: type, slot: *?*Interface) void {
    if (slot.*) |value| {
        _ = value.vtable.release(value);
        slot.* = null;
    }
}

fn releaseHostApplication(host_application: *?*ivsthostapplication.IHostApplication) void {
    releaseOptionalInterface(ivsthostapplication.IHostApplication, host_application);
}

fn queryInfoListener(context: ?*anyopaque) ?*ivstchannelcontextinfo.IInfoListener {
    return queryInterfaceAs(funknown.Header, ivstchannelcontextinfo.IInfoListener, context, &ivstchannelcontextinfo.iinfo_listener_iid);
}

fn releaseInfoListener(info_listener: *?*ivstchannelcontextinfo.IInfoListener) void {
    releaseOptionalInterface(ivstchannelcontextinfo.IInfoListener, info_listener);
}

fn queryAutomationState(context: ?*anyopaque) ?*ivstautomationstate.IAutomationState {
    return queryInterfaceAs(funknown.Header, ivstautomationstate.IAutomationState, context, &ivstautomationstate.iautomation_state_iid);
}

fn releaseAutomationState(automation_state: *?*ivstautomationstate.IAutomationState) void {
    releaseOptionalInterface(ivstautomationstate.IAutomationState, automation_state);
}

fn queryDataExchangeHandler(context: ?*anyopaque) ?*ivstdataexchange.IDataExchangeHandler {
    return queryInterfaceAs(funknown.Header, ivstdataexchange.IDataExchangeHandler, context, &ivstdataexchange.idata_exchange_handler_iid);
}

fn releaseDataExchangeHandler(data_exchange_handler: *?*ivstdataexchange.IDataExchangeHandler) void {
    releaseOptionalInterface(ivstdataexchange.IDataExchangeHandler, data_exchange_handler);
}

fn queryComponentHandler2(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandler2 {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IComponentHandler2, handler, &ivsteditcontroller.icomponent_handler2_iid);
}

fn queryComponentHandler3(handler: ?*anyopaque) ?*ivstcontextmenu.IComponentHandler3 {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivstcontextmenu.IComponentHandler3, handler, &ivstcontextmenu.icomponent_handler3_iid);
}

fn queryComponentHandlerBusActivation(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandlerBusActivation {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IComponentHandlerBusActivation, handler, &ivsteditcontroller.icomponent_handler_bus_activation_iid);
}

fn queryComponentHandlerSystemTime(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandlerSystemTime {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IComponentHandlerSystemTime, handler, &ivsteditcontroller.icomponent_handler_system_time_iid);
}

fn queryProgress(handler: ?*anyopaque) ?*ivsteditcontroller.IProgress {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivsteditcontroller.IProgress, handler, &ivsteditcontroller.iprogress_iid);
}

fn queryUnitHandler(handler: ?*anyopaque) ?*ivstunits.IUnitHandler {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivstunits.IUnitHandler, handler, &ivstunits.iunit_handler_iid);
}

fn queryUnitHandler2(handler: ?*anyopaque) ?*ivstunits.IUnitHandler2 {
    return queryInterfaceAs(ivsteditcontroller.IComponentHandler, ivstunits.IUnitHandler2, handler, &ivstunits.iunit_handler2_iid);
}

fn retainComponentHandler(handler: ?*anyopaque) ?*ivsteditcontroller.IComponentHandler {
    const raw = handler orelse return null;
    const base: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(raw));
    _ = base.vtable.addRef(base);
    return base;
}

fn retainConnectionPeer(peer: *ivstmessage.IConnectionPoint) *ivstmessage.IConnectionPoint {
    _ = peer.vtable.addRef(peer);
    return peer;
}

fn releaseConnectionPeer(peer: *?*ivstmessage.IConnectionPoint) void {
    releaseOptionalInterface(ivstmessage.IConnectionPoint, peer);
}

fn releaseComponentHandlers(controller: anytype) void {
    releaseOptionalInterface(ivstunits.IUnitHandler2, &controller.unit_handler2);
    releaseOptionalInterface(ivstunits.IUnitHandler, &controller.unit_handler);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandlerSystemTime, &controller.component_handler_system_time);
    releaseOptionalInterface(ivsteditcontroller.IProgress, &controller.progress);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandlerBusActivation, &controller.component_handler_bus_activation);
    releaseOptionalInterface(ivstcontextmenu.IComponentHandler3, &controller.component_handler3);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandler2, &controller.component_handler2);
    releaseOptionalInterface(ivsteditcontroller.IComponentHandler, &controller.component_handler);
}

test "simple stereo effect clears unsupported query outputs" {
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "QueryComponent";
        pub const controller_cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    @memset(output, 0);
                }
            }
        };

        pub fn applyParameterChanges(_: plug_process.ParameterChanges) void {}

        pub fn readState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultFalse;
        }

        pub fn writeState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultFalse;
        }
    });

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var queried: ?*anyopaque = @ptrFromInt(0x10);
    try std.testing.expectEqual(types.kNoInterface, component_iface.vtable.queryInterface(component_iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &queried));
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(queried.?));

    queried = @ptrFromInt(0x20);
    try std.testing.expectEqual(types.kNoInterface, processor.vtable.queryInterface(processor, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
    try std.testing.expect(processor.vtable.release(processor) >= 1);
}

pub fn SimpleStereoEffect(comptime Config: type) type {
    return struct {
        const Self = @This();
        const event_output = @hasDecl(Config, "event_output") and Config.event_output;
        const event_input = !@hasDecl(Config, "event_input") or Config.event_input;
        const audio_input = !@hasDecl(Config, "audio_input") or Config.audio_input;
        const audio_output = !@hasDecl(Config, "audio_output") or Config.audio_output;
        const bus_config = zig_vst3_plugin_bridge.StereoAudioBuses.Config{
            .audio_input = audio_input,
            .audio_output = audio_output,
            .event_input = event_input,
            .event_output = event_output,
        };
        const process_context_requirements: types.uint32 = if (@hasDecl(Config, "process_context_requirements"))
            Config.process_context_requirements
        else
            0;

        const Component = extern struct {
            iface: ivstcomponent.IComponent = .{ .vtable = &component_vtable },
            connection_point: ivstmessage.IConnectionPoint = .{ .vtable = &component_connection_point_vtable },
            processor: ivstaudioprocessor.IAudioProcessor = .{ .vtable = &processor_vtable },
            process_context_requirements: ivstaudioprocessor.IProcessContextRequirements = .{ .vtable = &process_context_requirements_vtable },
            audio_presentation_latency: ivstaudioprocessor.IAudioPresentationLatency = .{ .vtable = &audio_presentation_latency_vtable },
            plug_interface_support: ivstpluginterfacesupport.IPlugInterfaceSupport = .{ .vtable = &plug_interface_support_vtable },
            prefetchable_support: ivstprefetchablesupport.IPrefetchableSupport = .{ .vtable = &prefetchable_support_vtable },
            data_exchange_receiver: ivstdataexchange.IDataExchangeReceiver = .{ .vtable = &data_exchange_receiver_vtable },
            connected_peer: ?*ivstmessage.IConnectionPoint = null,
            host_application: ?*ivsthostapplication.IHostApplication = null,
            info_listener: ?*ivstchannelcontextinfo.IInfoListener = null,
            automation_state: ?*ivstautomationstate.IAutomationState = null,
            data_exchange_handler: ?*ivstdataexchange.IDataExchangeHandler = null,
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        };

        var component = Component{};

        pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.c) types.tresult {
            return query(&component.iface, @ptrCast(requested_iid), out);
        }

        pub fn setChannelContextInfos(attributes: ?*ivstattributes.IAttributeList) types.tresult {
            const info_listener = component.info_listener orelse return types.kResultFalse;
            return info_listener.vtable.setChannelContextInfos(info_listener, attributes);
        }

        pub fn setAutomationState(state: types.int32) types.tresult {
            const automation_state = component.automation_state orelse return types.kResultFalse;
            return automation_state.vtable.setAutomationState(automation_state, state);
        }

        pub fn openDataExchangeQueue(block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            const handler = component.data_exchange_handler orelse {
                out.* = ivstdataexchange.InvalidDataExchangeQueueID;
                return types.kResultFalse;
            };
            return handler.vtable.openQueue(handler, &component.processor, block_size, num_blocks, alignment, user_context_id, out);
        }

        pub fn closeDataExchangeQueue(queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
            const handler = component.data_exchange_handler orelse return types.kResultFalse;
            return handler.vtable.closeQueue(handler, queue_id);
        }

        pub fn lockDataExchangeBlock(queue_id: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            const handler = component.data_exchange_handler orelse {
                block.* = .{ .blockID = ivstdataexchange.InvalidDataExchangeBlockID };
                return types.kResultFalse;
            };
            return handler.vtable.lockBlock(handler, queue_id, block);
        }

        pub fn freeDataExchangeBlock(queue_id: ivstdataexchange.DataExchangeQueueID, block_id: ivstdataexchange.DataExchangeBlockID, send_to_receiver: types.TBool) types.tresult {
            const handler = component.data_exchange_handler orelse return types.kResultFalse;
            return handler.vtable.freeBlock(handler, queue_id, block_id, send_to_receiver);
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

        fn ownerFromComponentConnectionPoint(ptr: *anyopaque) *Component {
            const iface: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("connection_point", iface);
        }

        fn ownerFromProcessContextRequirements(ptr: *anyopaque) *Component {
            const iface: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("process_context_requirements", iface);
        }

        fn ownerFromAudioPresentationLatency(ptr: *anyopaque) *Component {
            const iface: *ivstaudioprocessor.IAudioPresentationLatency = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("audio_presentation_latency", iface);
        }

        fn ownerFromPlugInterfaceSupport(ptr: *anyopaque) *Component {
            const iface: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("plug_interface_support", iface);
        }

        fn ownerFromPrefetchableSupport(ptr: *anyopaque) *Component {
            const iface: *ivstprefetchablesupport.IPrefetchableSupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("prefetchable_support", iface);
        }

        fn ownerFromDataExchangeReceiver(ptr: *anyopaque) *Component {
            const iface: *ivstdataexchange.IDataExchangeReceiver = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("data_exchange_receiver", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const entries = [_]interface_map.Entry{
                interface_map.fieldEntry("iface", self, &funknown.iid),
                interface_map.fieldEntry("iface", self, &ipluginbase.iplugin_base_iid),
                interface_map.fieldEntry("iface", self, &ivstcomponent.icomponent_iid),
                interface_map.fieldEntry("connection_point", self, &ivstmessage.iconnection_point_iid),
                interface_map.fieldEntry("processor", self, &ivstaudioprocessor.iaudio_processor_iid),
                interface_map.fieldEntry("process_context_requirements", self, &ivstaudioprocessor.iprocess_context_requirements_iid),
                interface_map.fieldEntry("audio_presentation_latency", self, &ivstaudioprocessor.iaudio_presentation_latency_iid),
                interface_map.fieldEntry("plug_interface_support", self, &ivstpluginterfacesupport.iplug_interface_support_iid),
                interface_map.fieldEntry("prefetchable_support", self, &ivstprefetchablesupport.iprefetchable_support_iid),
                interface_map.fieldEntry("data_exchange_receiver", self, &ivstdataexchange.idata_exchange_receiver_iid),
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn queryFromOwnedInterface(comptime ownerFn: fn (*anyopaque) *Component, ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            return query(&ownerFn(ptr).iface, requested_iid, out);
        }

        fn queryFromProcessor(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromProcessor, ptr, requested_iid, out);
        }

        fn queryFromComponentConnectionPoint(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromComponentConnectionPoint, ptr, requested_iid, out);
        }

        fn queryFromProcessContextRequirements(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromProcessContextRequirements, ptr, requested_iid, out);
        }

        fn queryFromAudioPresentationLatency(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromAudioPresentationLatency, ptr, requested_iid, out);
        }

        fn queryFromPlugInterfaceSupport(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromPlugInterfaceSupport, ptr, requested_iid, out);
        }

        fn queryFromPrefetchableSupport(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromPrefetchableSupport, ptr, requested_iid, out);
        }

        fn queryFromDataExchangeReceiver(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryFromOwnedInterface(ownerFromDataExchangeReceiver, ptr, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, Config.component_name);
        }

        fn initialize(ptr: *anyopaque, context: ?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const next_host_application = queryHostApplication(context);
            const next_info_listener = queryInfoListener(context);
            const next_automation_state = queryAutomationState(context);
            const next_data_exchange_handler = queryDataExchangeHandler(context);

            releaseDataExchangeHandler(&self.data_exchange_handler);
            releaseAutomationState(&self.automation_state);
            releaseInfoListener(&self.info_listener);
            releaseHostApplication(&self.host_application);
            self.host_application = next_host_application;
            self.info_listener = next_info_listener;
            self.automation_state = next_automation_state;
            self.data_exchange_handler = next_data_exchange_handler;
            return types.kResultOk;
        }

        fn terminate(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            releaseConnectionPeer(&self.connected_peer);
            releaseDataExchangeHandler(&self.data_exchange_handler);
            releaseAutomationState(&self.automation_state);
            releaseInfoListener(&self.info_listener);
            releaseHostApplication(&self.host_application);
            return types.kResultOk;
        }

        fn getControllerClassId(_: *anyopaque, out: *tuid.TUID) callconv(.c) types.tresult {
            out.* = Config.controller_cid;
            return types.kResultOk;
        }

        fn setIoMode(_: *anyopaque, _: vsttypes.IoMode) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        fn getBusCount(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) callconv(.c) types.int32 {
            return zig_vst3_plugin_bridge.StereoAudioBuses.busCountConfigured(media_type, direction, bus_config);
        }

        fn getBusInfo(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) callconv(.c) types.tresult {
            return zig_vst3_plugin_bridge.StereoAudioBuses.busInfoConfigured(media_type, direction, index, out, bus_config);
        }

        fn getRoutingInfo(_: *anyopaque, _: *ivstcomponent.RoutingInfo, _: *ivstcomponent.RoutingInfo) callconv(.c) types.tresult {
            return types.kNoInterface;
        }

        fn activateBus(_: *anyopaque, _: vsttypes.MediaType, _: vsttypes.BusDirection, _: types.int32, _: types.TBool) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        fn resetProcessState() void {
            if (@hasDecl(Config, "resetProcessState")) {
                Config.resetProcessState();
            }
        }

        fn setActive(_: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            if (state == 0) resetProcessState();
            return types.kResultOk;
        }

        fn setState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return Config.readState(state);
        }

        fn getState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
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

        fn addRefFromOwnedInterface(comptime ownerFn: fn (*anyopaque) *Component, ptr: *anyopaque) types.uint32 {
            return addRef(&ownerFn(ptr).iface);
        }

        fn releaseFromOwnedInterface(comptime ownerFn: fn (*anyopaque) *Component, ptr: *anyopaque) types.uint32 {
            return release(&ownerFn(ptr).iface);
        }

        fn addRefFromProcessor(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromProcessor, ptr);
        }

        fn releaseFromProcessor(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromProcessor, ptr);
        }

        fn addRefFromComponentConnectionPoint(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromComponentConnectionPoint, ptr);
        }

        fn releaseFromComponentConnectionPoint(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromComponentConnectionPoint, ptr);
        }

        fn addRefFromProcessContextRequirements(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromProcessContextRequirements, ptr);
        }

        fn releaseFromProcessContextRequirements(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromProcessContextRequirements, ptr);
        }

        fn addRefFromAudioPresentationLatency(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromAudioPresentationLatency, ptr);
        }

        fn releaseFromAudioPresentationLatency(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromAudioPresentationLatency, ptr);
        }

        fn addRefFromPlugInterfaceSupport(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromPlugInterfaceSupport, ptr);
        }

        fn releaseFromPlugInterfaceSupport(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromPlugInterfaceSupport, ptr);
        }

        fn addRefFromPrefetchableSupport(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromPrefetchableSupport, ptr);
        }

        fn releaseFromPrefetchableSupport(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromPrefetchableSupport, ptr);
        }

        fn addRefFromDataExchangeReceiver(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRefFromOwnedInterface(ownerFromDataExchangeReceiver, ptr);
        }

        fn releaseFromDataExchangeReceiver(ptr: *anyopaque) callconv(.c) types.uint32 {
            return releaseFromOwnedInterface(ownerFromDataExchangeReceiver, ptr);
        }

        const component_connection_point_vtable = ivstmessage.IConnectionPointVTable{
            .queryInterface = queryFromComponentConnectionPoint,
            .addRef = addRefFromComponentConnectionPoint,
            .release = releaseFromComponentConnectionPoint,
            .connect = componentConnect,
            .disconnect = componentDisconnect,
            .notify = componentNotify,
        };

        fn componentConnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromComponentConnectionPoint(ptr);
            const connection_peer = peer orelse return types.kInvalidArgument;
            const next_peer = retainConnectionPeer(connection_peer);
            releaseConnectionPeer(&self.connected_peer);
            self.connected_peer = next_peer;
            return types.kResultOk;
        }

        fn componentDisconnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromComponentConnectionPoint(ptr);
            const connection_peer = peer orelse {
                releaseConnectionPeer(&self.connected_peer);
                return types.kResultOk;
            };
            const connected_peer = self.connected_peer orelse {
                releaseConnectionPeer(&self.connected_peer);
                return types.kResultOk;
            };
            if (connected_peer == connection_peer) {
                releaseConnectionPeer(&self.connected_peer);
                return types.kResultOk;
            }
            return types.kResultFalse;
        }

        fn componentNotify(_: *anyopaque, _: ?*ivstmessage.IMessage) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const process_context_requirements_vtable = ivstaudioprocessor.IProcessContextRequirementsVTable{
            .queryInterface = queryFromProcessContextRequirements,
            .addRef = addRefFromProcessContextRequirements,
            .release = releaseFromProcessContextRequirements,
            .getProcessContextRequirements = getProcessContextRequirements,
        };

        fn getProcessContextRequirements(_: *anyopaque) callconv(.c) types.uint32 {
            return process_context_requirements;
        }

        const audio_presentation_latency_vtable = ivstaudioprocessor.IAudioPresentationLatencyVTable{
            .queryInterface = queryFromAudioPresentationLatency,
            .addRef = addRefFromAudioPresentationLatency,
            .release = releaseFromAudioPresentationLatency,
            .setAudioPresentationLatencySamples = setAudioPresentationLatencySamples,
        };

        fn setAudioPresentationLatencySamples(_: *anyopaque, _: vsttypes.BusDirection, _: types.int32, _: types.uint32) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        const plug_interface_support_vtable = ivstpluginterfacesupport.IPlugInterfaceSupportVTable{
            .queryInterface = queryFromPlugInterfaceSupport,
            .addRef = addRefFromPlugInterfaceSupport,
            .release = releaseFromPlugInterfaceSupport,
            .isPlugInterfaceSupported = isPlugInterfaceSupported,
        };

        fn isPlugInterfaceSupported(_: *anyopaque, iid: *const tuid.TUID) callconv(.c) types.tresult {
            const supported = [_]*const tuid.TUID{
                &ivstcomponent.icomponent_iid,
                &ivstmessage.iconnection_point_iid,
                &ivstaudioprocessor.iaudio_processor_iid,
                &ivstaudioprocessor.iprocess_context_requirements_iid,
                &ivstaudioprocessor.iaudio_presentation_latency_iid,
                &ivstpluginterfacesupport.iplug_interface_support_iid,
                &ivstprefetchablesupport.iprefetchable_support_iid,
                &ivstdataexchange.idata_exchange_receiver_iid,
            };
            for (supported) |supported_iid| {
                if (std.mem.eql(u8, iid, supported_iid)) return types.kResultOk;
            }
            return types.kResultFalse;
        }

        const prefetchable_support_vtable = ivstprefetchablesupport.IPrefetchableSupportVTable{
            .queryInterface = queryFromPrefetchableSupport,
            .addRef = addRefFromPrefetchableSupport,
            .release = releaseFromPrefetchableSupport,
            .getPrefetchableSupport = getPrefetchableSupport,
        };

        fn getPrefetchableSupport(_: *anyopaque, out: *ivstprefetchablesupport.PrefetchableSupport) callconv(.c) types.tresult {
            out.* = @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNeverPrefetchable);
            return types.kResultOk;
        }

        const data_exchange_receiver_vtable = ivstdataexchange.IDataExchangeReceiverVTable{
            .queryInterface = queryFromDataExchangeReceiver,
            .addRef = addRefFromDataExchangeReceiver,
            .release = releaseFromDataExchangeReceiver,
            .queueOpened = dataExchangeQueueOpened,
            .queueClosed = dataExchangeQueueClosed,
            .onDataExchangeBlocksReceived = onDataExchangeBlocksReceived,
        };

        fn dataExchangeQueueOpened(_: *anyopaque, user_context_id: ivstdataexchange.DataExchangeUserContextID, block_size: types.uint32, out: *types.TBool) callconv(.c) void {
            if (@hasDecl(Config, "dataExchangeQueueOpened")) {
                out.* = Config.dataExchangeQueueOpened(user_context_id, block_size);
            } else {
                out.* = 0;
            }
        }

        fn dataExchangeQueueClosed(_: *anyopaque, user_context_id: ivstdataexchange.DataExchangeUserContextID) callconv(.c) void {
            if (@hasDecl(Config, "dataExchangeQueueClosed")) {
                Config.dataExchangeQueueClosed(user_context_id);
            }
        }

        fn onDataExchangeBlocksReceived(_: *anyopaque, user_context_id: ivstdataexchange.DataExchangeUserContextID, num_blocks: types.uint32, blocks: ?[*]ivstdataexchange.DataExchangeBlock, on_background_thread: types.TBool) callconv(.c) void {
            if (@hasDecl(Config, "onDataExchangeBlocksReceived")) {
                Config.onDataExchangeBlocksReceived(user_context_id, num_blocks, blocks, on_background_thread);
            }
        }

        fn setBusArrangements(_: *anyopaque, inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32) callconv(.c) types.tresult {
            return zig_vst3_plugin_bridge.StereoAudioBuses.setArrangementsConfigured(inputs, num_inputs, outputs, num_outputs, bus_config);
        }

        fn getBusArrangement(_: *anyopaque, direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement) callconv(.c) types.tresult {
            return zig_vst3_plugin_bridge.StereoAudioBuses.arrangementConfigured(direction, index, out, bus_config);
        }

        fn canProcessSampleSize(_: *anyopaque, symbolic_sample_size: types.int32) callconv(.c) types.tresult {
            return zig_vst3_plugin_bridge.RealtimeProcessorDefaults.canProcessSampleSize(symbolic_sample_size);
        }

        fn getLatencySamples(_: *anyopaque) callconv(.c) types.uint32 {
            return zig_vst3_plugin_bridge.RealtimeProcessorDefaults.latencySamples();
        }

        fn setupProcessing(_: *anyopaque, setup: *ivstaudioprocessor.ProcessSetup) callconv(.c) types.tresult {
            const setup_result = zig_vst3_plugin_bridge.RealtimeProcessorDefaults.validateProcessSetup(setup);
            if (setup_result != types.kResultOk) return setup_result;

            resetProcessState();
            return types.kResultOk;
        }

        fn setProcessing(_: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            if (state == 0) resetProcessState();
            return types.kResultOk;
        }

        fn process(_: *anyopaque, data: *ivstaudioprocessor.ProcessData) callconv(.c) types.tresult {
            var parameter_change_storage: [process_parameter_change_capacity]plug_process.ParameterChange = undefined;
            var event_storage: [process_event_capacity]plug_process.Event = undefined;
            var output_event_storage: [process_output_event_capacity]plug_process.Event = undefined;
            const parameter_changes = zig_vst3_plugin_bridge.collectInputParameterChanges(data, &parameter_change_storage);
            const events = zig_vst3_plugin_bridge.collectInputEvents(data, &event_storage);
            var output_events = plug_process.EventWriter.init(&output_event_storage, zig_vst3_plugin_bridge.frameCountOrZero(data));
            Config.applyParameterChanges(parameter_changes);
            const result = zig_vst3_plugin_bridge.processMainAudioConfigured(data, parameter_changes, events, &output_events, Config.Processor{}, bus_config);
            if (result != types.kResultOk) return result;
            return zig_vst3_plugin_bridge.writeOutputEvents(data, output_events.events());
        }

        fn getTailSamples(_: *anyopaque) callconv(.c) types.uint32 {
            return zig_vst3_plugin_bridge.RealtimeProcessorDefaults.tailSamples();
        }
    };
}
