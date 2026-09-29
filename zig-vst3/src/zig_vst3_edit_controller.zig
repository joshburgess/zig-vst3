const std = @import("std");
const support = @import("effect_support.zig");
const funknown = @import("funknown.zig");
const gui_ir_transport = @import("gui_ir_transport.zig");
const resource_path_transport = @import("resource_path_transport.zig");
const gui_note_transport = @import("gui_note_transport.zig");
const gui_telemetry_source = @import("gui_telemetry_source.zig");
const latency_transport = @import("latency_transport.zig");
const host_restart_transport = @import("host_restart_transport.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const types = @import("pluginterfaces/base/types.zig");
const interface_map = @import("interface_map.zig");
const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const ivstmidilearn = @import("pluginterfaces/vst/ivstmidilearn.zig");
const ivstmidimapping2 = @import("pluginterfaces/vst/ivstmidimapping2.zig");
const ivstnoteexpression = @import("pluginterfaces/vst/ivstnoteexpression.zig");
const ivstparameterfunctionname = @import("pluginterfaces/vst/ivstparameterfunctionname.zig");
const ivstphysicalui = @import("pluginterfaces/vst/ivstphysicalui.zig");
const ivstremapparamid = @import("pluginterfaces/vst/ivstremapparamid.zig");
const ivstrepresentation = @import("pluginterfaces/vst/ivstrepresentation.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const plug_core = @import("zig-vst3-plugin-core");
const plug_process = plug_core.process;
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");
const vst_component_handler = @import("vst_component_handler.zig");
const vst_index = @import("vst_index.zig");
const zig_vst3_plugin_bridge = @import("zig_vst3_plugin_bridge.zig");

const disconnectConnectionPeer = support.disconnectConnectionPeer;
const queryComponentHandler2 = support.queryComponentHandler2;
const queryComponentHandler3 = support.queryComponentHandler3;
const queryComponentHandlerBusActivation = support.queryComponentHandlerBusActivation;
const queryComponentHandlerSystemTime = support.queryComponentHandlerSystemTime;
const queryHostApplication = support.queryHostApplication;
const queryProgress = support.queryProgress;
const queryUnitHandler = support.queryUnitHandler;
const queryUnitHandler2 = support.queryUnitHandler2;
const releaseComponentHandlers = support.releaseComponentHandlers;
const releaseConnectionPeer = support.releaseConnectionPeer;
const releaseHostApplication = support.releaseHostApplication;
const releaseTelemetrySource = support.releaseTelemetrySource;
const replaceConnectionPeer = support.replaceConnectionPeer;
const retainComponentHandler = support.retainComponentHandler;

const parameter_observer_capacity = 8;

pub const ParameterObserver = struct {
    userdata: *anyopaque,
    changed: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue) callconv(.c) void,
};

fn failInfo(out: anytype) types.tresult {
    out.* = .{};
    return types.kInvalidArgument;
}

pub fn ReflectedEditController(comptime Config: type) type {
    return struct {
        const Self = @This();
        const Params = Config.Params;
        const unit_config = if (@hasDecl(Config, "unit_config")) Config.unit_config else plug_core.units.Config{};
        const UnitSet = plug_core.units.UnitSet(unit_config);
        const units = UnitSet{};
        const physical_ui_maps: []const ivstphysicalui.PhysicalUIMap = if (@hasDecl(Config, "physical_ui_maps"))
            Config.physical_ui_maps
        else
            &.{};

        const ParameterState = zig_vst3_plugin_bridge.ParameterState(Params);
        const ParameterController = zig_vst3_plugin_bridge.ParameterController(Params);
        const has_editor_state = @hasDecl(Config, "EditorState");
        const EditorState = if (has_editor_state) Config.EditorState else struct {};
        const has_controller_state = @hasDecl(Config, "ControllerState");
        const ControllerState = if (has_controller_state) Config.ControllerState else struct {};
        pub const hasEditorState = has_editor_state;
        pub const hasControllerState = has_controller_state;
        pub const hasPresetLoader = @hasDecl(Config, "loadPreset");
        pub const hasMenuActionHandler = @hasDecl(Config, "performMenuAction");
        pub const hasActionHandler = @hasDecl(Config, "performAction") or hasMenuActionHandler;
        pub const hasFileDropHandler = @hasDecl(Config, "handleFileImport") or @hasDecl(Config, "handleFileDrop");
        pub const hasFileImportStatus = @hasDecl(Config, "loadFileImport");
        pub const hasFileImportCommandHandler = @hasDecl(Config, "performFileImportCommand");
        pub const hasGuiGraphSource = @hasDecl(Config, "loadGuiGraph");
        pub const hasGuiProgressSource = @hasDecl(Config, "loadGuiProgress");
        pub const EditorStateType = EditorState;
        pub const ControllerStateType = ControllerState;
        const editor_state_migrations: []const plug_core.editor_state.Migration = if (@hasDecl(Config, "editor_state_migrations"))
            Config.editor_state_migrations
        else
            &.{};

        const Controller = struct {
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
            telemetry_source: ?gui_telemetry_source.RetainedSource = null,
            component_handler: ?*ivsteditcontroller.IComponentHandler = null,
            component_handler2: ?*ivsteditcontroller.IComponentHandler2 = null,
            component_handler3: ?*ivstcontextmenu.IComponentHandler3 = null,
            component_handler_bus_activation: ?*ivsteditcontroller.IComponentHandlerBusActivation = null,
            component_handler_system_time: ?*ivsteditcontroller.IComponentHandlerSystemTime = null,
            progress: ?*ivsteditcontroller.IProgress = null,
            unit_handler: ?*ivstunits.IUnitHandler = null,
            unit_handler2: ?*ivstunits.IUnitHandler2 = null,
            host_application: ?*ivsthostapplication.IHostApplication = null,
            parameter_state: ParameterState,
            parameters: ParameterController,
            editor_state: EditorState,
            controller_state: ControllerState,
            parameter_observers: [parameter_observer_capacity]?ParameterObserver = @splat(null),
            allocator: std.mem.Allocator,
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

            fn init(self: *Controller, allocator: std.mem.Allocator) void {
                const initializes_controller_state_in_place =
                    has_controller_state and
                    @hasDecl(ControllerState, "initInto");
                self.* = .{
                    .parameter_state = ParameterState.init(Config.parameter_set),
                    .parameters = undefined,
                    .editor_state = if (has_editor_state) EditorState.init() else .{},
                    .controller_state = if (initializes_controller_state_in_place)
                        undefined
                    else if (has_controller_state and @hasDecl(ControllerState, "init"))
                        ControllerState.init()
                    else
                        .{},
                    .allocator = allocator,
                };
                if (comptime initializes_controller_state_in_place) {
                    self.controller_state.initInto();
                }
                self.parameters = .{
                    .set = Config.parameter_set,
                    .state = &self.parameter_state,
                };
            }
        };

        pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.c) types.tresult {
            return createWithAllocator(
                std.heap.page_allocator,
                requested_iid,
                out,
            );
        }

        fn createWithAllocator(
            allocator: std.mem.Allocator,
            requested_iid: types.FIDString,
            out: *?*anyopaque,
        ) types.tresult {
            out.* = null;
            const controller = allocator.create(Controller) catch
                return types.kResultFalse;
            controller.init(allocator);
            const result = query(&controller.iface, @ptrCast(requested_iid), out);
            _ = release(&controller.iface);
            return result;
        }

        pub fn retainGuiTelemetry(iface: *ivsteditcontroller.IEditController) ?gui_telemetry_source.RetainedSource {
            const source = owner(iface).telemetry_source orelse return null;
            return source.clone();
        }

        fn instance(iface: *ivsteditcontroller.IEditController) *Controller {
            return owner(iface);
        }

        pub fn getNormalized(iface: *ivsteditcontroller.IEditController, id: vsttypes.ParamID) vsttypes.ParamValue {
            return instance(iface).parameters.getNormalized(id);
        }

        pub fn editorState(iface: *ivsteditcontroller.IEditController) *EditorState {
            return &instance(iface).editor_state;
        }

        pub fn controllerState(iface: *ivsteditcontroller.IEditController) *ControllerState {
            return &instance(iface).controller_state;
        }

        pub fn loadPreset(iface: *ivsteditcontroller.IEditController, preset_id: u32) types.tresult {
            if (comptime @hasDecl(Config, "loadPreset")) return Config.loadPreset(iface, preset_id);
            return types.kResultFalse;
        }

        pub fn performMenuAction(
            iface: *ivsteditcontroller.IEditController,
            menu_id: u32,
            item_id: u32,
            checked: bool,
        ) types.tresult {
            if (comptime @hasDecl(Config, "performMenuAction")) {
                return Config.performMenuAction(iface, menu_id, item_id, checked);
            }
            return types.kResultFalse;
        }

        pub fn performAction(
            iface: *ivsteditcontroller.IEditController,
            group_id: u32,
            action_id: u32,
        ) types.tresult {
            if (comptime @hasDecl(Config, "performAction")) {
                return Config.performAction(iface, group_id, action_id);
            }
            if (comptime @hasDecl(Config, "performMenuAction")) {
                return Config.performMenuAction(iface, group_id, action_id, false);
            }
            return types.kResultFalse;
        }

        pub fn handleFileDrop(
            iface: *ivsteditcontroller.IEditController,
            drop_id: u32,
            paths: []const []const u8,
        ) types.tresult {
            if (comptime @hasDecl(Config, "handleFileDrop")) {
                return Config.handleFileDrop(iface, drop_id, paths);
            }
            return types.kResultFalse;
        }

        pub fn handleFileImport(
            iface: *ivsteditcontroller.IEditController,
            drop_id: u32,
            entry_point: plug_core.gui_file_importer.EntryPoint,
            paths: []const []const u8,
        ) types.tresult {
            if (comptime @hasDecl(Config, "handleFileImport")) {
                return Config.handleFileImport(iface, drop_id, entry_point, paths);
            }
            return handleFileDrop(iface, drop_id, paths);
        }

        pub fn loadFileImport(
            iface: *ivsteditcontroller.IEditController,
            drop_id: u32,
        ) ?plug_core.gui_audio_file_importer.Snapshot {
            if (comptime @hasDecl(Config, "loadFileImport")) return Config.loadFileImport(iface, drop_id);
            return null;
        }

        pub fn performFileImportCommand(
            iface: *ivsteditcontroller.IEditController,
            drop_id: u32,
            command: plug_core.gui_file_importer.Command,
        ) types.tresult {
            if (comptime @hasDecl(Config, "performFileImportCommand")) {
                return Config.performFileImportCommand(iface, drop_id, command);
            }
            return types.kResultFalse;
        }

        pub fn loadGuiGraph(
            iface: *ivsteditcontroller.IEditController,
            source_id: u32,
            output: []plug_core.gui_graph.Point,
        ) usize {
            if (comptime @hasDecl(Config, "loadGuiGraph")) return Config.loadGuiGraph(iface, source_id, output);
            return 0;
        }

        pub fn validateEditorText(
            iface: *ivsteditcontroller.IEditController,
            field_id: u32,
            text: []const u8,
        ) types.tresult {
            if (comptime @hasDecl(Config, "validateEditorText")) {
                return Config.validateEditorText(iface, field_id, text);
            }
            return types.kResultOk;
        }

        pub fn loadGuiProgress(
            iface: *ivsteditcontroller.IEditController,
            source_id: u32,
        ) ?plug_core.gui_progress.Snapshot {
            if (comptime @hasDecl(Config, "loadGuiProgress")) return Config.loadGuiProgress(iface, source_id);
            return null;
        }

        pub fn sendGuiNote(
            iface: *ivsteditcontroller.IEditController,
            command: gui_note_transport.Command,
        ) types.tresult {
            return gui_note_transport.send(instance(iface).connected_peer, command);
        }

        pub fn sendDecodedAudio(
            iface: *ivsteditcontroller.IEditController,
            target_id: u32,
            importer: anytype,
        ) types.tresult {
            return gui_ir_transport.sendDecoded(instance(iface).connected_peer, target_id, importer);
        }

        pub fn sendDecodedAudioGeneration(
            iface: *ivsteditcontroller.IEditController,
            target_id: u32,
            generation: u64,
            importer: anytype,
        ) types.tresult {
            return gui_ir_transport.sendDecodedGeneration(instance(iface).connected_peer, target_id, generation, importer);
        }

        pub fn clearDecodedAudio(
            iface: *ivsteditcontroller.IEditController,
            target_id: u32,
            generation: u64,
        ) types.tresult {
            return gui_ir_transport.sendClear(instance(iface).connected_peer, target_id, generation);
        }

        pub fn importResourcePath(
            iface: *ivsteditcontroller.IEditController,
            target_id: u32,
            path: []const u8,
        ) types.tresult {
            return resource_path_transport.sendImport(instance(iface).connected_peer, target_id, path);
        }

        pub fn relinkResourcePath(
            iface: *ivsteditcontroller.IEditController,
            target_id: u32,
            path: []const u8,
        ) types.tresult {
            return resource_path_transport.sendRelink(instance(iface).connected_peer, target_id, path);
        }

        pub fn cancelResourceImport(iface: *ivsteditcontroller.IEditController, target_id: u32) types.tresult {
            return resource_path_transport.sendCancel(instance(iface).connected_peer, target_id);
        }

        pub fn retryResourceImport(iface: *ivsteditcontroller.IEditController, target_id: u32) types.tresult {
            return resource_path_transport.sendRetry(instance(iface).connected_peer, target_id);
        }

        pub fn setNormalized(iface: *ivsteditcontroller.IEditController, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            return setNormalizedAndNotify(instance(iface), id, value);
        }

        pub fn addParameterObserver(iface: *ivsteditcontroller.IEditController, observer: ParameterObserver) bool {
            const self = instance(iface);
            for (&self.parameter_observers) |*slot| {
                if (slot.* == null) {
                    slot.* = observer;
                    return true;
                }
            }
            return false;
        }

        pub fn removeParameterObserver(iface: *ivsteditcontroller.IEditController, userdata: *anyopaque) void {
            const self = instance(iface);
            for (&self.parameter_observers) |*slot| {
                if (slot.*) |observer| {
                    if (observer.userdata == userdata) slot.* = null;
                }
            }
        }

        pub fn createHostInstance(iface: *ivsteditcontroller.IEditController, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            out.* = null;
            const host = instance(iface).host_application orelse return types.kResultFalse;
            return host.vtable.createInstance(host, cid, iid, out);
        }

        pub fn beginEdit(iface: *ivsteditcontroller.IEditController, id: vsttypes.ParamID) types.tresult {
            if (!vst_component_handler.parameterIdIsValid(id)) return types.kInvalidArgument;
            const handler = instance(iface).component_handler orelse return types.kResultFalse;
            return handler.vtable.beginEdit(handler, id);
        }

        pub fn performEdit(iface: *ivsteditcontroller.IEditController, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            if (!vst_component_handler.parameterIdIsValid(id)) return types.kInvalidArgument;
            if (!vst_component_handler.automationValueIsValid(value)) return types.kInvalidArgument;
            const self = instance(iface);
            const handler = self.component_handler orelse return types.kResultFalse;
            const previous = self.parameters.getNormalized(id);
            const result = self.parameters.setNormalized(id, value);
            if (result != types.kResultOk) return result;
            const edit_result = handler.vtable.performEdit(handler, id, value);
            if (edit_result != types.kResultOk) {
                _ = self.parameters.setNormalized(id, previous);
                return edit_result;
            }
            notifyParameterObservers(self, id, value);
            return types.kResultOk;
        }

        pub fn endEdit(iface: *ivsteditcontroller.IEditController, id: vsttypes.ParamID) types.tresult {
            if (!vst_component_handler.parameterIdIsValid(id)) return types.kInvalidArgument;
            const handler = instance(iface).component_handler orelse return types.kResultFalse;
            return handler.vtable.endEdit(handler, id);
        }

        pub fn restartComponent(iface: *ivsteditcontroller.IEditController, flags: types.int32) types.tresult {
            if (!vst_component_handler.restartFlagsAreValid(flags)) return types.kInvalidArgument;
            const handler = instance(iface).component_handler orelse return types.kResultFalse;
            return handler.vtable.restartComponent(handler, flags);
        }

        pub fn setDirty(iface: *ivsteditcontroller.IEditController, state: types.TBool) types.tresult {
            if (state > 1) return types.kInvalidArgument;
            const handler = instance(iface).component_handler2 orelse return types.kResultFalse;
            return handler.vtable.setDirty(handler, state);
        }

        pub fn requestOpenEditor(iface: *ivsteditcontroller.IEditController, name: types.FIDString) types.tresult {
            const handler = instance(iface).component_handler2 orelse return types.kResultFalse;
            return handler.vtable.requestOpenEditor(handler, name);
        }

        pub fn startGroupEdit(iface: *ivsteditcontroller.IEditController) types.tresult {
            const handler = instance(iface).component_handler2 orelse return types.kResultFalse;
            return handler.vtable.startGroupEdit(handler);
        }

        pub fn finishGroupEdit(iface: *ivsteditcontroller.IEditController) types.tresult {
            const handler = instance(iface).component_handler2 orelse return types.kResultFalse;
            return handler.vtable.finishGroupEdit(handler);
        }

        pub fn createContextMenu(iface: *ivsteditcontroller.IEditController, view: ?*iplugview.IPlugView, param_id: ?*const vsttypes.ParamID) ?*ivstcontextmenu.IContextMenu {
            if (!vst_component_handler.contextMenuParameterIsValid(param_id)) return null;
            const handler = instance(iface).component_handler3 orelse return null;
            return handler.vtable.createContextMenu(handler, view, param_id);
        }

        pub fn requestBusActivation(iface: *ivsteditcontroller.IEditController, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, state: types.TBool) types.tresult {
            if (!vst_component_handler.busActivationIsValid(media_type, direction, index, state)) return types.kInvalidArgument;
            const handler = instance(iface).component_handler_bus_activation orelse return types.kResultFalse;
            return handler.vtable.requestBusActivation(handler, media_type, direction, index, state);
        }

        pub fn getSystemTime(iface: *ivsteditcontroller.IEditController, out: *types.int64) types.tresult {
            const handler = instance(iface).component_handler_system_time orelse {
                out.* = 0;
                return types.kResultFalse;
            };
            return handler.vtable.getSystemTime(handler, out);
        }

        pub fn startProgress(iface: *ivsteditcontroller.IEditController, progress_type: types.uint32, title: ?[*]const types.char16, out: *ivsteditcontroller.ProgressID) types.tresult {
            if (!vst_component_handler.progressTypeIsValid(progress_type)) {
                out.* = 0;
                return types.kInvalidArgument;
            }
            const progress = instance(iface).progress orelse {
                out.* = 0;
                return types.kResultFalse;
            };
            return progress.vtable.start(progress, progress_type, title, out);
        }

        pub fn updateProgress(iface: *ivsteditcontroller.IEditController, id: ivsteditcontroller.ProgressID, value: vsttypes.ParamValue) types.tresult {
            if (!vst_component_handler.progressValueIsValid(value)) return types.kInvalidArgument;
            const progress = instance(iface).progress orelse return types.kResultFalse;
            return progress.vtable.update(progress, id, value);
        }

        pub fn finishProgress(iface: *ivsteditcontroller.IEditController, id: ivsteditcontroller.ProgressID) types.tresult {
            const progress = instance(iface).progress orelse return types.kResultFalse;
            return progress.vtable.finish(progress, id);
        }

        pub fn notifyUnitSelection(iface: *ivsteditcontroller.IEditController, unit_id: vsttypes.UnitID) types.tresult {
            const handler = instance(iface).unit_handler orelse return types.kResultFalse;
            return handler.vtable.notifyUnitSelection(handler, unit_id);
        }

        pub fn notifyProgramListChange(iface: *ivsteditcontroller.IEditController, list_id: vsttypes.ProgramListID, program_index: types.int32) types.tresult {
            const handler = instance(iface).unit_handler orelse return types.kResultFalse;
            return handler.vtable.notifyProgramListChange(handler, list_id, program_index);
        }

        pub fn notifyUnitByBusChange(iface: *ivsteditcontroller.IEditController) types.tresult {
            const handler = instance(iface).unit_handler2 orelse return types.kResultFalse;
            return handler.vtable.notifyUnitByBusChange(handler);
        }

        pub fn openView(iface: *ivsteditcontroller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
            return createView(iface, name);
        }

        pub fn applyParameterChanges(iface: *ivsteditcontroller.IEditController, changes: plug_process.ParameterChanges) void {
            instance(iface).parameters.applyChanges(changes);
        }

        pub fn readState(iface: *ivsteditcontroller.IEditController, state: ?*ibstream.IBStream) types.tresult {
            return readStateAndNotify(instance(iface), state);
        }

        pub fn writeState(iface: *ivsteditcontroller.IEditController, state: ?*ibstream.IBStream) types.tresult {
            return instance(iface).parameters.writeState(state);
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

        const owner = interface_map.ownerFromField(Controller, ivsteditcontroller.IEditController, "iface");
        const ownerFromController2 = interface_map.ownerFromField(Controller, ivsteditcontroller.IEditController2, "controller2");
        const ownerFromConnectionPoint = interface_map.ownerFromField(Controller, ivstmessage.IConnectionPoint, "connection_point");
        const ownerFromHostEditing = interface_map.ownerFromField(Controller, ivsteditcontroller.IEditControllerHostEditing, "host_editing");
        const ownerFromUnitInfo = interface_map.ownerFromField(Controller, ivstunits.IUnitInfo, "unit_info");
        const ownerFromProgramListData = interface_map.ownerFromField(Controller, ivstunits.IProgramListData, "program_list_data");
        const ownerFromUnitData = interface_map.ownerFromField(Controller, ivstunits.IUnitData, "unit_data");
        const ownerFromMidiMapping = interface_map.ownerFromField(Controller, ivsteditcontroller.IMidiMapping, "midi_mapping");
        const ownerFromMidiLearn = interface_map.ownerFromField(Controller, ivstmidilearn.IMidiLearn, "midi_learn");
        const ownerFromMidiMapping2 = interface_map.ownerFromField(Controller, ivstmidimapping2.IMidiMapping2, "midi_mapping2");
        const ownerFromMidiLearn2 = interface_map.ownerFromField(Controller, ivstmidimapping2.IMidiLearn2, "midi_learn2");
        const ownerFromNoteExpression = interface_map.ownerFromField(Controller, ivstnoteexpression.INoteExpressionController, "note_expression");
        const ownerFromKeyswitch = interface_map.ownerFromField(Controller, ivstnoteexpression.IKeyswitchController, "keyswitch");
        const ownerFromPhysicalUIMapping = interface_map.ownerFromField(Controller, ivstphysicalui.INoteExpressionPhysicalUIMapping, "physical_ui_mapping");
        const ownerFromParameterFunctionName = interface_map.ownerFromField(Controller, ivstparameterfunctionname.IParameterFunctionName, "parameter_function_name");
        const ownerFromRemapParamID = interface_map.ownerFromField(Controller, ivstremapparamid.IRemapParamID, "remap_param_id");
        const ownerFromXmlRepresentation = interface_map.ownerFromField(Controller, ivstrepresentation.IXmlRepresentationController, "xml_representation");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            const next = funknown.decrementRefCount(&self.ref_count, Config.controller_name);
            if (next == 0) {
                _ = self.ref_count.load(.acquire);
                if (comptime has_controller_state and @hasDecl(ControllerState, "deinit")) {
                    self.controller_state.deinit();
                }
                releaseConnectionPeer(&self.connected_peer);
                releaseTelemetrySource(&self.telemetry_source);
                releaseComponentHandlers(self);
                releaseHostApplication(&self.host_application);
                self.allocator.destroy(self);
            }
            return next;
        }

        const UnitInfoDelegate = interface_map.DelegatedInterface(Controller, ownerFromUnitInfo, "iface", query, addRef, release);
        const ProgramListDataDelegate = interface_map.DelegatedInterface(Controller, ownerFromProgramListData, "iface", query, addRef, release);
        const UnitDataDelegate = interface_map.DelegatedInterface(Controller, ownerFromUnitData, "iface", query, addRef, release);
        const Controller2Delegate = interface_map.DelegatedInterface(Controller, ownerFromController2, "iface", query, addRef, release);
        const ConnectionPointDelegate = interface_map.DelegatedInterface(Controller, ownerFromConnectionPoint, "iface", query, addRef, release);
        const HostEditingDelegate = interface_map.DelegatedInterface(Controller, ownerFromHostEditing, "iface", query, addRef, release);
        const MidiMappingDelegate = interface_map.DelegatedInterface(Controller, ownerFromMidiMapping, "iface", query, addRef, release);
        const MidiLearnDelegate = interface_map.DelegatedInterface(Controller, ownerFromMidiLearn, "iface", query, addRef, release);
        const MidiMapping2Delegate = interface_map.DelegatedInterface(Controller, ownerFromMidiMapping2, "iface", query, addRef, release);
        const MidiLearn2Delegate = interface_map.DelegatedInterface(Controller, ownerFromMidiLearn2, "iface", query, addRef, release);
        const NoteExpressionDelegate = interface_map.DelegatedInterface(Controller, ownerFromNoteExpression, "iface", query, addRef, release);
        const KeyswitchDelegate = interface_map.DelegatedInterface(Controller, ownerFromKeyswitch, "iface", query, addRef, release);
        const PhysicalUIMappingDelegate = interface_map.DelegatedInterface(Controller, ownerFromPhysicalUIMapping, "iface", query, addRef, release);
        const ParameterFunctionNameDelegate = interface_map.DelegatedInterface(Controller, ownerFromParameterFunctionName, "iface", query, addRef, release);
        const RemapParamIDDelegate = interface_map.DelegatedInterface(Controller, ownerFromRemapParamID, "iface", query, addRef, release);
        const XmlRepresentationDelegate = interface_map.DelegatedInterface(Controller, ownerFromXmlRepresentation, "iface", query, addRef, release);

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
            releaseTelemetrySource(&self.telemetry_source);
            releaseComponentHandlers(self);
            releaseHostApplication(&self.host_application);
            return types.kResultOk;
        }

        fn setComponentState(ptr: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return readStateAndNotify(owner(ptr), state);
        }

        fn setState(ptr: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            if (comptime has_editor_state) {
                const self = owner(ptr);
                const result = zig_vst3_plugin_bridge.readControllerState(
                    Params,
                    EditorState,
                    state,
                    Config.parameter_set,
                    &self.parameter_state.values,
                    &self.editor_state,
                    editor_state_migrations,
                );
                if (result == types.kResultOk) {
                    notifyAllParameterObservers(self);
                    if (comptime @hasDecl(Config, "afterStateRestore")) {
                        Config.afterStateRestore(&self.iface);
                    }
                }
                return result;
            }
            return readStateAndNotify(owner(ptr), state);
        }

        fn getState(ptr: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            if (comptime has_editor_state) {
                const self = owner(ptr);
                return zig_vst3_plugin_bridge.writeControllerState(
                    Params,
                    EditorState,
                    state,
                    Config.parameter_set,
                    &self.parameter_state.values,
                    &self.editor_state,
                );
            }
            return owner(ptr).parameters.writeState(state);
        }

        fn getParameterCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return owner(ptr).parameters.parameterCount();
        }

        fn getParameterInfo(ptr: *anyopaque, index: types.int32, out: [*c]ivsteditcontroller.ParameterInfo) callconv(.c) types.tresult {
            return owner(ptr).parameters.parameterInfo(index, out);
        }

        fn getParamStringByValue(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue, out: [*c]vsttypes.TChar) callconv(.c) types.tresult {
            return owner(ptr).parameters.stringByValue(id, value, out);
        }

        fn getParamValueByString(ptr: *anyopaque, id: vsttypes.ParamID, text: [*c]vsttypes.TChar, out: [*c]vsttypes.ParamValue) callconv(.c) types.tresult {
            return owner(ptr).parameters.valueByString(id, text, out);
        }

        fn normalizedParamToPlain(ptr: *anyopaque, id: vsttypes.ParamID, normalized: vsttypes.ParamValue) callconv(.c) vsttypes.ParamValue {
            return owner(ptr).parameters.plainFromNormalized(id, normalized);
        }

        fn plainParamToNormalized(ptr: *anyopaque, id: vsttypes.ParamID, plain: vsttypes.ParamValue) callconv(.c) vsttypes.ParamValue {
            return owner(ptr).parameters.normalizedFromPlain(id, plain);
        }

        fn getParamNormalized(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) vsttypes.ParamValue {
            return owner(ptr).parameters.getNormalized(id);
        }

        fn setParamNormalized(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            return setNormalizedAndNotify(owner(ptr), id, value);
        }

        fn setNormalizedAndNotify(self: *Controller, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            const result = self.parameters.setNormalized(id, value);
            if (result == types.kResultOk) notifyParameterObservers(self, id, self.parameters.getNormalized(id));
            return result;
        }

        fn readStateAndNotify(self: *Controller, state: ?*ibstream.IBStream) types.tresult {
            const result = zig_vst3_plugin_bridge.readComponentParameterState(
                Params,
                state,
                Config.parameter_set,
                &self.parameter_state.values,
            );
            if (result != types.kResultOk) return result;
            notifyAllParameterObservers(self);
            return result;
        }

        fn notifyAllParameterObservers(self: *Controller) void {
            var index: types.int32 = 0;
            while (index < self.parameters.parameterCount()) : (index += 1) {
                var info: ivsteditcontroller.ParameterInfo = undefined;
                if (self.parameters.parameterInfo(index, &info) == types.kResultOk) {
                    notifyParameterObservers(self, info.id, self.parameters.getNormalized(info.id));
                }
            }
        }

        fn notifyParameterObservers(self: *Controller, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            for (self.parameter_observers) |slot| {
                if (slot) |observer| observer.changed(observer.userdata, id, value);
            }
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

        fn createView(ptr: *anyopaque, name: ?types.FIDString) callconv(.c) ?*iplugview.IPlugView {
            const view_name = name orelse return null;
            if (@hasDecl(Config, "createView")) {
                const parameter_count = @typeInfo(@TypeOf(Config.createView)).@"fn".params.len;
                if (comptime parameter_count == 1) return Config.createView(view_name);
                return Config.createView(&owner(ptr).iface, view_name);
            }
            return null;
        }

        const connection_point_vtable = ivstmessage.IConnectionPointVTable{
            .queryInterface = ConnectionPointDelegate.query,
            .addRef = ConnectionPointDelegate.addRef,
            .release = ConnectionPointDelegate.release,
            .connect = connect,
            .disconnect = disconnect,
            .notify = notify,
        };

        fn connect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const connection_peer = peer orelse
                return types.kInvalidArgument;
            const self = ownerFromConnectionPoint(ptr);
            const result = replaceConnectionPeer(
                &self.connected_peer,
                connection_peer,
            );
            if (result != types.kResultOk) return result;
            releaseTelemetrySource(&self.telemetry_source);
            self.telemetry_source = gui_telemetry_source.query(connection_peer);
            return types.kResultOk;
        }

        fn disconnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromConnectionPoint(ptr);
            const result = disconnectConnectionPeer(&self.connected_peer, peer);
            if (result == types.kResultOk) releaseTelemetrySource(&self.telemetry_source);
            return result;
        }

        fn notify(ptr: *anyopaque, message: ?*ivstmessage.IMessage) callconv(.c) types.tresult {
            if (message == null) return types.kResultFalse;
            var restart_flags: types.int32 = 0;
            const restart_result =
                host_restart_transport.receive(message, &restart_flags);
            if (restart_result == types.kResultOk) {
                return restartComponent(
                    &ownerFromConnectionPoint(ptr).iface,
                    restart_flags,
                );
            }
            if (restart_result == types.kInvalidArgument)
                return restart_result;
            const latency_result = latency_transport.receive(message);
            if (latency_result == types.kResultOk) {
                return restartComponent(&ownerFromConnectionPoint(ptr).iface, ivsteditcontroller.RestartFlags.kLatencyChanged);
            }
            return latency_result;
        }

        const controller2_vtable = ivsteditcontroller.IEditController2VTable{
            .queryInterface = Controller2Delegate.query,
            .addRef = Controller2Delegate.addRef,
            .release = Controller2Delegate.release,
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
            .queryInterface = HostEditingDelegate.query,
            .addRef = HostEditingDelegate.addRef,
            .release = HostEditingDelegate.release,
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
            .queryInterface = UnitInfoDelegate.query,
            .addRef = UnitInfoDelegate.addRef,
            .release = UnitInfoDelegate.release,
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
            return vst_index.int32Count(UnitSet.unit_count);
        }

        fn getUnitInfo(_: *anyopaque, index: types.int32, out_raw: [*c]ivstunits.UnitInfo) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *ivstunits.UnitInfo = @ptrCast(out_raw);
            const unit_index = vst_index.bounded(index, UnitSet.unit_count) orelse return failInfo(out);
            const reflected = units.unit(unit_index) orelse return failInfo(out);
            out.* = .{
                .id = reflected.id,
                .parentUnitId = reflected.parent_id,
                .programListId = reflected.program_list_id,
            };
            string128.copy(&out.name, reflected.name);
            return types.kResultOk;
        }

        fn getProgramListCount(_: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(UnitSet.program_list_count);
        }

        fn getProgramListInfo(_: *anyopaque, index: types.int32, out_raw: [*c]ivstunits.ProgramListInfo) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *ivstunits.ProgramListInfo = @ptrCast(out_raw);
            const list_index = vst_index.bounded(index, UnitSet.program_list_count) orelse return failInfo(out);
            const reflected = units.programList(list_index) orelse return failInfo(out);
            out.* = .{
                .id = reflected.id,
                .programCount = vst_index.int32Count(reflected.programs.len),
            };
            string128.copy(&out.name, reflected.name);
            return types.kResultOk;
        }

        fn getProgramName(_: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, out: [*c]vsttypes.TChar) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: [*]vsttypes.TChar = @ptrCast(out);
            string128.clearPtr(output);
            const count = units.programCount(list_id) orelse return types.kInvalidArgument;
            const index = vst_index.bounded(program_index, count) orelse return types.kInvalidArgument;
            const name = units.programName(list_id, index) orelse return types.kInvalidArgument;
            string128.copyPtr(output, name);
            return types.kResultOk;
        }

        fn getProgramInfo(_: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, attribute_id: ?vsttypes.CString, out: [*c]vsttypes.TChar) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: [*]vsttypes.TChar = @ptrCast(out);
            string128.clearPtr(output);
            const id = attribute_id orelse return types.kInvalidArgument;
            const count = units.programCount(list_id) orelse return types.kInvalidArgument;
            const index = vst_index.bounded(program_index, count) orelse return types.kInvalidArgument;
            const value = units.programInfo(list_id, index, std.mem.span(id)) orelse return types.kInvalidArgument;
            string128.copyPtr(output, value);
            return types.kResultOk;
        }

        fn hasProgramPitchNames(_: *anyopaque, _: vsttypes.ProgramListID, _: types.int32) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        fn getProgramPitchName(_: *anyopaque, _: vsttypes.ProgramListID, _: types.int32, _: types.int16, out: [*c]vsttypes.TChar) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: [*]vsttypes.TChar = @ptrCast(out);
            string128.clearPtr(output);
            return types.kInvalidArgument;
        }

        fn getSelectedUnit(_: *anyopaque) callconv(.c) vsttypes.UnitID {
            return units.rootUnit().id;
        }

        fn selectUnit(_: *anyopaque, id: vsttypes.UnitID) callconv(.c) types.tresult {
            if (!units.hasUnit(id)) return types.kInvalidArgument;
            return types.kResultOk;
        }

        fn getUnitByBus(_: *anyopaque, _: vsttypes.MediaType, _: vsttypes.BusDirection, _: types.int32, _: types.int32, out_raw: [*c]vsttypes.UnitID) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *vsttypes.UnitID = @ptrCast(out_raw);
            out.* = units.rootUnit().id;
            return types.kResultOk;
        }

        fn setUnitProgramData(_: *anyopaque, _: types.int32, _: types.int32, _: ?*ibstream.IBStream) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const program_list_data_vtable = ivstunits.IProgramListDataVTable{
            .queryInterface = ProgramListDataDelegate.query,
            .addRef = ProgramListDataDelegate.addRef,
            .release = ProgramListDataDelegate.release,
            .programDataSupported = programDataSupported,
            .getProgramData = getProgramData,
            .setProgramData = setProgramData,
        };

        fn programDataSupported(_: *anyopaque, list_id: vsttypes.ProgramListID) callconv(.c) types.tresult {
            const count = units.programCount(list_id) orelse return types.kResultFalse;
            for (0..count) |program_index| {
                if (units.programHasParameters(list_id, program_index)) return types.kResultOk;
            }
            return types.kResultFalse;
        }

        fn getProgramData(_: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const count = units.programCount(list_id) orelse return types.kResultFalse;
            const index = vst_index.bounded(program_index, count) orelse return types.kInvalidArgument;
            const reflected = units.program(list_id, index) orelse return types.kInvalidArgument;
            if (reflected.parametersEmpty()) return types.kResultFalse;

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
            .queryInterface = UnitDataDelegate.query,
            .addRef = UnitDataDelegate.addRef,
            .release = UnitDataDelegate.release,
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
            .queryInterface = MidiMappingDelegate.query,
            .addRef = MidiMappingDelegate.addRef,
            .release = MidiMappingDelegate.release,
            .getMidiControllerAssignment = getMidiControllerAssignment,
        };

        fn getMidiControllerAssignment(_: *anyopaque, _: types.int32, _: types.int16, _: vsttypes.CtrlNumber, out: [*c]vsttypes.ParamID) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            out[0] = vsttypes.kNoParamId;
            return types.kResultFalse;
        }

        const midi_learn_vtable = ivstmidilearn.IMidiLearnVTable{
            .queryInterface = MidiLearnDelegate.query,
            .addRef = MidiLearnDelegate.addRef,
            .release = MidiLearnDelegate.release,
            .onLiveMIDIControllerInput = onLiveMIDIControllerInput,
        };

        fn onLiveMIDIControllerInput(_: *anyopaque, _: types.int32, _: types.int16, _: vsttypes.CtrlNumber) callconv(.c) types.tresult {
            return types.kResultFalse;
        }

        const midi_mapping2_vtable = ivstmidimapping2.IMidiMapping2VTable{
            .queryInterface = MidiMapping2Delegate.query,
            .addRef = MidiMapping2Delegate.addRef,
            .release = MidiMapping2Delegate.release,
            .getNumMidi2ControllerAssignments = getNumMidi2ControllerAssignments,
            .getMidi2ControllerAssignments = getMidi2ControllerAssignments,
            .getNumMidi1ControllerAssignments = getNumMidi1ControllerAssignments,
            .getMidi1ControllerAssignments = getMidi1ControllerAssignments,
        };

        fn getNumMidi2ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection) callconv(.c) types.uint32 {
            return 0;
        }

        fn getMidi2ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection, list: [*c]const ivstmidimapping2.Midi2ControllerParamIDAssignmentList) callconv(.c) types.tresult {
            if (list == null) return types.kInvalidArgument;
            return types.kResultFalse;
        }

        fn getNumMidi1ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection) callconv(.c) types.uint32 {
            return 0;
        }

        fn getMidi1ControllerAssignments(_: *anyopaque, _: vsttypes.BusDirection, list: [*c]const ivstmidimapping2.Midi1ControllerParamIDAssignmentList) callconv(.c) types.tresult {
            if (list == null) return types.kInvalidArgument;
            return types.kResultFalse;
        }

        const midi_learn2_vtable = ivstmidimapping2.IMidiLearn2VTable{
            .queryInterface = MidiLearn2Delegate.query,
            .addRef = MidiLearn2Delegate.addRef,
            .release = MidiLearn2Delegate.release,
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
            .queryInterface = NoteExpressionDelegate.query,
            .addRef = NoteExpressionDelegate.addRef,
            .release = NoteExpressionDelegate.release,
            .getNoteExpressionCount = getNoteExpressionCount,
            .getNoteExpressionInfo = getNoteExpressionInfo,
            .getNoteExpressionStringByValue = getNoteExpressionStringByValue,
            .getNoteExpressionValueByString = getNoteExpressionValueByString,
        };

        fn getNoteExpressionCount(_: *anyopaque, _: types.int32, _: types.int16) callconv(.c) types.int32 {
            return 0;
        }

        fn getNoteExpressionInfo(_: *anyopaque, _: types.int32, _: types.int16, _: types.int32, out_raw: [*c]ivstnoteexpression.NoteExpressionTypeInfo) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *ivstnoteexpression.NoteExpressionTypeInfo =
                @ptrCast(out_raw);
            out.* = .{};
            return types.kInvalidArgument;
        }

        fn getNoteExpressionStringByValue(_: *anyopaque, _: types.int32, _: types.int16, _: ivstnoteexpression.NoteExpressionTypeID, _: ivstnoteexpression.NoteExpressionValue, out_raw: [*c]vsttypes.TChar) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: [*]vsttypes.TChar = @ptrCast(out_raw);
            string128.clearPtr(out);
            return types.kInvalidArgument;
        }

        fn getNoteExpressionValueByString(_: *anyopaque, _: types.int32, _: types.int16, _: ivstnoteexpression.NoteExpressionTypeID, value_raw: [*c]const vsttypes.TChar, out_raw: [*c]ivstnoteexpression.NoteExpressionValue) callconv(.c) types.tresult {
            if (value_raw == null or out_raw == null)
                return types.kInvalidArgument;
            const out: *ivstnoteexpression.NoteExpressionValue =
                @ptrCast(out_raw);
            out.* = 0;
            return types.kInvalidArgument;
        }

        const keyswitch_vtable = ivstnoteexpression.IKeyswitchControllerVTable{
            .queryInterface = KeyswitchDelegate.query,
            .addRef = KeyswitchDelegate.addRef,
            .release = KeyswitchDelegate.release,
            .getKeyswitchCount = getKeyswitchCount,
            .getKeyswitchInfo = getKeyswitchInfo,
        };

        fn getKeyswitchCount(_: *anyopaque, _: types.int32, _: types.int16) callconv(.c) types.int32 {
            return 0;
        }

        fn getKeyswitchInfo(_: *anyopaque, _: types.int32, _: types.int16, _: types.int32, out_raw: [*c]ivstnoteexpression.KeyswitchInfo) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *ivstnoteexpression.KeyswitchInfo = @ptrCast(out_raw);
            out.* = .{};
            return types.kInvalidArgument;
        }

        const physical_ui_mapping_vtable = ivstphysicalui.INoteExpressionPhysicalUIMappingVTable{
            .queryInterface = PhysicalUIMappingDelegate.query,
            .addRef = PhysicalUIMappingDelegate.addRef,
            .release = PhysicalUIMappingDelegate.release,
            .getPhysicalUIMapping = getPhysicalUIMapping,
        };

        fn getPhysicalUIMapping(_: *anyopaque, _: types.int32, _: types.int16, out_raw: [*c]ivstphysicalui.PhysicalUIMapList) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out = &out_raw[0];
            const requested_maps = out.map orelse return types.kInvalidArgument;
            if (physical_ui_maps.len == 0 or out.count == 0) return types.kResultFalse;
            for (requested_maps[0..out.count]) |*requested| {
                requested.noteExpressionTypeID = @intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kInvalidTypeID);
                for (physical_ui_maps) |mapping| {
                    if (mapping.physicalUITypeID == requested.physicalUITypeID) {
                        requested.noteExpressionTypeID = mapping.noteExpressionTypeID;
                        break;
                    }
                }
            }
            return types.kResultOk;
        }

        const parameter_function_name_vtable = ivstparameterfunctionname.IParameterFunctionNameVTable{
            .queryInterface = ParameterFunctionNameDelegate.query,
            .addRef = ParameterFunctionNameDelegate.addRef,
            .release = ParameterFunctionNameDelegate.release,
            .getParameterIDFromFunctionName = getParameterIDFromFunctionName,
        };

        fn getParameterIDFromFunctionName(_: *anyopaque, _: vsttypes.UnitID, function_name: ?types.FIDString, out_raw: [*c]vsttypes.ParamID) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *vsttypes.ParamID = @ptrCast(out_raw);
            out.* = vsttypes.kNoParamId;
            if (function_name == null) return types.kInvalidArgument;
            return types.kResultFalse;
        }

        const remap_param_id_vtable = ivstremapparamid.IRemapParamIDVTable{
            .queryInterface = RemapParamIDDelegate.query,
            .addRef = RemapParamIDDelegate.addRef,
            .release = RemapParamIDDelegate.release,
            .getCompatibleParamID = getCompatibleParamID,
        };

        fn getCompatibleParamID(_: *anyopaque, cid: [*c]const tuid.TUID, _: vsttypes.ParamID, out_raw: [*c]vsttypes.ParamID) callconv(.c) types.tresult {
            if (cid == null or out_raw == null)
                return types.kInvalidArgument;
            const out: *vsttypes.ParamID = @ptrCast(out_raw);
            out.* = vsttypes.kNoParamId;
            return types.kResultFalse;
        }

        const xml_representation_vtable = ivstrepresentation.IXmlRepresentationControllerVTable{
            .queryInterface = XmlRepresentationDelegate.query,
            .addRef = XmlRepresentationDelegate.addRef,
            .release = XmlRepresentationDelegate.release,
            .getXmlRepresentationStream = getXmlRepresentationStream,
        };

        fn getXmlRepresentationStream(_: *anyopaque, info_raw: [*c]ivstrepresentation.RepresentationInfo, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            if (info_raw == null) return types.kInvalidArgument;
            const info = &info_raw[0];
            if (@hasDecl(Config, "getXmlRepresentationStream")) {
                return Config.getXmlRepresentationStream(info, stream);
            }
            return types.kResultFalse;
        }
    };
}

test "reflected edit controller reports outer allocation failure" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "AllocationFailureController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    var out: ?*anyopaque = @ptrFromInt(1);
    try std.testing.expectEqual(
        types.kResultFalse,
        TestController.createWithAllocator(
            failing.allocator(),
            @ptrCast(&ivsteditcontroller.iedit_controller_iid),
            &out,
        ),
    );
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
}
