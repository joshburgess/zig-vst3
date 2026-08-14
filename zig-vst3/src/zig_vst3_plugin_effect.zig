const std = @import("std");
const ara_vst3 = @import("ara_vst3.zig");
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
const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
const ivstremapparamid = @import("pluginterfaces/vst/ivstremapparamid.zig");
const ivstrepresentation = @import("pluginterfaces/vst/ivstrepresentation.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const plug_core = @import("zig-vst3-plugin-core");
const plug_process = plug_core.process;
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");
const vst_component_handler = @import("vst_component_handler.zig");
const vst_host_context = @import("vst_host_context.zig");
const vst_index = @import("vst_index.zig");
const vst_message = @import("vst_message.zig");
const vst_parameter_changes = @import("vst_parameter_changes.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_bridge = @import("zig_vst3_plugin_bridge.zig");
const zig_vst3_plugin_runtime_adapter =
    @import("zig_vst3_plugin_runtime_adapter.zig");

fn optionalChildOrSelf(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |info| info.child,
        else => T,
    };
}

const process_parameter_change_capacity = 64;
const process_event_capacity = 64;
const process_output_event_capacity = 64;
const parameter_observer_capacity = 8;

pub const ParameterObserver = struct {
    userdata: *anyopaque,
    changed: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue) callconv(.c) void,
};

pub const HostRequestSink = plug_core.plugin.HostRequestSink;

var test_data_exchange_queue_opened_count: usize = 0;
var test_data_exchange_queue_closed_count: usize = 0;
var test_data_exchange_blocks_received_count: usize = 0;
var test_data_exchange_last_user_context_id: ivstdataexchange.DataExchangeUserContextID = 0;
var test_data_exchange_last_block_size: types.uint32 = 0;
var test_data_exchange_last_num_blocks: types.uint32 = 0;
var test_data_exchange_last_block_id: ivstdataexchange.DataExchangeBlockID = 0;
var test_data_exchange_last_background_flag: types.TBool = 0;
var test_controller_state_init_count: usize = 0;
var test_controller_state_deinit_count: usize = 0;
var test_effect_processor_init_count: usize = 0;
var test_effect_processor_deinit_count: usize = 0;
var test_effect_prepare_sample_rate: f64 = 0;
var test_effect_prepare_block_size: u32 = 0;
var test_effect_prepare_mode: plug_process.ProcessMode = .realtime;
var test_effect_reset_count: usize = 0;

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

test "reflected edit controller owns isolated optional controller state" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const State = struct {
        value: usize = 7,

        pub fn init() @This() {
            test_controller_state_init_count += 1;
            return .{};
        }

        pub fn deinit(_: *@This()) void {
            test_controller_state_deinit_count += 1;
        }
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "StatefulController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub const ControllerState = State;
    });

    test_controller_state_init_count = 0;
    test_controller_state_deinit_count = 0;
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &second_out));
    const first: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(first_out orelse return error.MissingController));
    const second: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(second_out orelse return error.MissingController));

    try std.testing.expect(TestController.hasControllerState);
    try std.testing.expectEqual(@as(usize, 2), test_controller_state_init_count);
    try std.testing.expectEqual(@as(usize, 7), TestController.controllerState(first).value);
    TestController.controllerState(first).value = 19;
    try std.testing.expectEqual(@as(usize, 7), TestController.controllerState(second).value);

    _ = first.vtable.release(first);
    try std.testing.expectEqual(@as(usize, 1), test_controller_state_deinit_count);
    _ = second.vtable.release(second);
    try std.testing.expectEqual(@as(usize, 2), test_controller_state_deinit_count);
}

test "reflected edit controller initializes large state in place" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const State = struct {
        storage: [1024 * 1024]u8,
        marker: usize,

        pub fn initInto(self: *@This()) void {
            test_controller_state_init_count += 1;
            self.marker = 41;
        }
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "InPlaceStateController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub const ControllerState = State;
    });

    test_controller_state_init_count = 0;
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        TestController.create(
            @ptrCast(&ivsteditcontroller.iedit_controller_iid),
            &controller_out,
        ),
    );
    const controller: *ivsteditcontroller.IEditController =
        @ptrCast(@alignCast(
            controller_out orelse return error.MissingController,
        ));
    defer _ = controller.vtable.release(controller);

    try std.testing.expectEqual(
        @as(usize, 1),
        test_controller_state_init_count,
    );
    try std.testing.expectEqual(
        @as(usize, 41),
        TestController.controllerState(controller).marker,
    );
}

test "reflected edit controller rejects malformed host requests" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "HostRequestValidationController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);

    try std.testing.expectEqual(types.kInvalidArgument, controller.vtable.getParameterInfo(controller, 0, null));
    try std.testing.expectEqual(types.kInvalidArgument, controller.vtable.getParamStringByValue(controller, 0, 0, null));
    var text = [_]vsttypes.TChar{0};
    var value: vsttypes.ParamValue = 0.5;
    try std.testing.expectEqual(types.kInvalidArgument, controller.vtable.getParamValueByString(controller, 0, null, &value));
    try std.testing.expectEqual(types.kInvalidArgument, controller.vtable.getParamValueByString(controller, 0, &text, null));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    try std.testing.expectEqual(types.kInvalidArgument, TestController.setDirty(controller, 2));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.requestBusActivation(controller, 99, @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.requestBusActivation(controller, @intFromEnum(ivstcomponent.MediaTypes.kAudio), 99, 0, 1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.requestBusActivation(controller, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), -1, 1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.requestBusActivation(controller, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 2));
    var progress_id: ivsteditcontroller.ProgressID = 99;
    try std.testing.expectEqual(types.kInvalidArgument, TestController.startProgress(controller, 99, null, &progress_id));
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 0), progress_id);
    try std.testing.expectEqual(types.kInvalidArgument, TestController.updateProgress(controller, 1, -0.1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.updateProgress(controller, 1, 1.1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.updateProgress(controller, 1, std.math.nan(vsttypes.ParamValue)));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.updateProgress(controller, 1, std.math.inf(vsttypes.ParamValue)));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.performEdit(controller, 0, -0.1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.performEdit(controller, 0, 1.1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.performEdit(controller, 0, std.math.nan(vsttypes.ParamValue)));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.performEdit(controller, 0, std.math.inf(vsttypes.ParamValue)));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.beginEdit(controller, vsttypes.kNoParamId));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.performEdit(controller, vsttypes.kNoParamId, 0.5));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.endEdit(controller, vsttypes.kNoParamId));
    var invalid_param_id = vsttypes.kNoParamId;
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenu, null), TestController.createContextMenu(controller, null, &invalid_param_id));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.restartComponent(controller, -1));
    try std.testing.expectEqual(types.kInvalidArgument, TestController.restartComponent(controller, 1 << 12));
    try std.testing.expectEqual(types.kResultFalse, TestController.setDirty(controller, 1));
    try std.testing.expectEqual(types.kResultFalse, TestController.requestBusActivation(controller, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 1));
    try std.testing.expectEqual(types.kResultFalse, TestController.startProgress(controller, @intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), null, &progress_id));
    try std.testing.expectEqual(types.kResultFalse, TestController.updateProgress(controller, 1, 0.5));
    try std.testing.expectEqual(types.kResultFalse, TestController.restartComponent(controller, ivsteditcontroller.RestartFlags.kParamValuesChanged));
}

test "reflected edit controller releases replaced component handlers" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "HandlerLifecycleController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });
    const Handler = vst_component_handler.ComponentHandler(struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var first = Handler{};
    var second = Handler{};

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, first.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), first.release_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, second.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), second.release_count);

    try std.testing.expectEqual(types.kResultOk, TestController.beginEdit(controller_iface, 7));
    try std.testing.expectEqual(@as(types.uint32, 1), second.begin_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), second.last_param_id);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), second.release_count);
    try std.testing.expectEqual(types.kResultFalse, TestController.beginEdit(controller_iface, 7));
}

test "reflected edit controller releases replaced unit handler extensions" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "UnitHandlerLifecycleController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });
    const Handler = vst_component_handler.ComponentHandlerUnits(struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var first = Handler{};
    var second = Handler{};

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, first.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.unit_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), first.unit2_add_ref_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, second.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.unit_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), first.unit2_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.unit_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.unit2_add_ref_count);

    try std.testing.expectEqual(types.kResultOk, TestController.notifyUnitSelection(controller_iface, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultOk, TestController.notifyUnitByBusChange(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), second.unit_selection_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.unit_by_bus_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), second.unit_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.unit2_release_count);
    try std.testing.expectEqual(types.kResultFalse, TestController.notifyUnitSelection(controller_iface, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultFalse, TestController.notifyUnitByBusChange(controller_iface));
}

test "reflected edit controller releases replaced connection peers" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "ConnectionLifecycleController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });
    const Peer = vst_message.ConnectionPoint(struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstmessage.iconnection_point_iid, &connection_out));
    try std.testing.expect(connection_out != null);
    const connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(connection_out.?));
    defer _ = connection.vtable.release(connection);

    var first = Peer{};
    var second = Peer{};

    try std.testing.expectEqual(types.kResultOk, connection.vtable.connect(connection, first.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), first.release_count);

    try std.testing.expectEqual(types.kResultOk, connection.vtable.connect(connection, second.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), second.release_count);

    try std.testing.expectEqual(types.kResultOk, connection.vtable.disconnect(connection, null));
    try std.testing.expectEqual(@as(types.uint32, 1), second.release_count);
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
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramInfo(unit_info, 7, 0, null, &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[0]);
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

test "reflected edit controller notifies and removes parameter observers" {
    const Fixture = struct {
        const Params = struct {
            gain: plug_core.parameters.FloatParam = plug_core.parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 0.25),
        };
        const ParameterSet = plug_core.parameters.ParameterSet(Params);
        const parameter_set = ParameterSet.init(.{});
        const Tracker = struct {
            count: usize = 0,
            id: vsttypes.ParamID = vsttypes.kNoParamId,
            value: vsttypes.ParamValue = 0.0,

            fn changed(userdata: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) void {
                const self: *@This() = @ptrCast(@alignCast(userdata));
                self.count += 1;
                self.id = id;
                self.value = value;
            }
        };
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "ObserverController";
        pub const Params = Fixture.Params;
        pub const parameter_set = &Fixture.parameter_set;
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var tracker = Fixture.Tracker{};
    try std.testing.expect(TestController.addParameterObserver(controller_iface, .{ .userdata = &tracker, .changed = Fixture.Tracker.changed }));
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setParamNormalized(controller_iface, 1, 0.75));
    try std.testing.expectEqual(@as(usize, 1), tracker.count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 1), tracker.id);
    try std.testing.expectApproxEqAbs(@as(vsttypes.ParamValue, 0.75), tracker.value, 0.000001);

    const Stream = vst_stream.FixedBufferStream(plug_core.state.encodedSize(Fixture.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.getState(controller_iface, stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setParamNormalized(controller_iface, 1, 0.5));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setState(controller_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, 3), tracker.count);
    try std.testing.expectApproxEqAbs(@as(vsttypes.ParamValue, 0.75), tracker.value, 0.000001);

    TestController.removeParameterObserver(controller_iface, &tracker);
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setParamNormalized(controller_iface, 1, 0.5));
    try std.testing.expectEqual(@as(usize, 3), tracker.count);
}

test "reflected edit controller rejects a null view name" {
    const Fixture = struct {
        const Params = struct {};
        const ParameterSet = plug_core.parameters.ParameterSet(Params);
        const parameter_set = ParameterSet.init(.{});
        var create_view_calls: usize = 0;
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "NullViewNameController";
        pub const Params = Fixture.Params;
        pub const parameter_set = &Fixture.parameter_set;

        pub fn createView(_: types.FIDString) ?*iplugview.IPlugView {
            Fixture.create_view_calls += 1;
            return null;
        }
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    try std.testing.expect(controller_iface.vtable.createView(controller_iface, null) == null);
    try std.testing.expectEqual(@as(usize, 0), Fixture.create_view_calls);
    try std.testing.expect(controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) == null);
    try std.testing.expectEqual(@as(usize, 1), Fixture.create_view_calls);
}

test "reflected edit controller delegates host instance creation" {
    const Fixture = struct {
        const Params = struct {};
        const ParameterSet = plug_core.parameters.ParameterSet(Params);
        const parameter_set = ParameterSet.init(.{});
    };
    const TestController = ReflectedEditController(struct {
        pub const controller_name = "HostInstanceController";
        pub const Params = Fixture.Params;
        pub const parameter_set = &Fixture.parameter_set;
    });
    const Host = vst_host_context.ChannelContextHost("Host Instance Test", struct {
        pub fn createInstance(self: anytype, cid: *const tuid.TUID, iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            if (!std.mem.eql(u8, cid, &ivstchannelcontextinfo.iinfo_listener_iid) or
                !std.mem.eql(u8, iid, &ivstchannelcontextinfo.iinfo_listener_iid)) return types.kNoInterface;
            out.* = self.asInfoListener();
            _ = self.asInfoListener().vtable.addRef(self.asInfoListener());
            return types.kResultOk;
        }
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var unavailable: ?*anyopaque = @ptrFromInt(1);
    try std.testing.expectEqual(types.kResultFalse, TestController.createHostInstance(
        controller_iface,
        &ivstchannelcontextinfo.iinfo_listener_iid,
        &ivstchannelcontextinfo.iinfo_listener_iid,
        &unavailable,
    ));
    try std.testing.expectEqual(@as(?*anyopaque, null), unavailable);

    var host = Host{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.initialize(controller_iface, host.asHostApplication()));
    defer _ = controller_iface.vtable.terminate(controller_iface);

    var created: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestController.createHostInstance(
        controller_iface,
        &ivstchannelcontextinfo.iinfo_listener_iid,
        &ivstchannelcontextinfo.iinfo_listener_iid,
        &created,
    ));
    const info: *ivstchannelcontextinfo.IInfoListener = @ptrCast(@alignCast(created.?));
    try std.testing.expectEqual(@as(types.uint32, 1), info.vtable.release(info));
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

fn releaseTelemetrySource(source: *?gui_telemetry_source.RetainedSource) void {
    const retained = source.* orelse return;
    source.* = null;
    retained.release();
}

fn replaceConnectionPeer(slot: *?*ivstmessage.IConnectionPoint, peer: ?*ivstmessage.IConnectionPoint) types.tresult {
    const connection_peer = peer orelse return types.kInvalidArgument;
    const next_peer = retainConnectionPeer(connection_peer);
    releaseConnectionPeer(slot);
    slot.* = next_peer;
    return types.kResultOk;
}

fn disconnectConnectionPeer(slot: *?*ivstmessage.IConnectionPoint, peer: ?*ivstmessage.IConnectionPoint) types.tresult {
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

fn failOpenedDataExchangeQueue(out: *ivstdataexchange.DataExchangeQueueID, result: types.tresult) types.tresult {
    out.* = ivstdataexchange.InvalidDataExchangeQueueID;
    return result;
}

fn failLockedDataExchangeBlock(block: *ivstdataexchange.DataExchangeBlock, result: types.tresult) types.tresult {
    block.* = .{ .blockID = ivstdataexchange.InvalidDataExchangeBlockID };
    return result;
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

test "simple stereo effect aggregates ARA entry point identity" {
    const TestAraExtension = struct {
        var initialize_calls: usize = 0;
        var deinit_calls: usize = 0;
        var bind_calls: usize = 0;
        var unbind_calls: usize = 0;

        pub fn initializeInPlace(_: *@This()) void {
            initialize_calls += 1;
        }

        pub fn deinit(_: *@This()) void {
            deinit_calls += 1;
        }
    };
    TestAraExtension.initialize_calls = 0;
    TestAraExtension.deinit_calls = 0;
    TestAraExtension.bind_calls = 0;
    TestAraExtension.unbind_calls = 0;
    const TestAraEntryPoint = ara_vst3.PlugInEntryPoint(struct {
        pub fn bind(
            _: anytype,
            _: *ara_vst3.DocumentController,
            _: ara_vst3.RoleFlags,
            _: ara_vst3.RoleFlags,
        ) ?*const ara_vst3.PlugInExtensionInstance {
            return @ptrFromInt(0x3000);
        }
    });
    const ara_factory_ptr: *const ara_vst3.Factory =
        @ptrFromInt(0x1000);
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "ARA Component";
        pub const controller_cid = tuid.inlineUid(
            0x11111111,
            0x22222222,
            0x33333333,
            0x44444444,
        );
        pub const AraExtension = TestAraExtension;
        pub const AraEntryPoint = TestAraEntryPoint;
        pub const ara_factory = ara_factory_ptr;
        pub const Processor = struct {
            pub fn process(
                _: @This(),
                comptime Sample: type,
                context: *plug_process.ProcessContext(Sample),
            ) void {
                context.outputs.clear();
            }
        };

        pub fn initAraExtension(
            _: *Processor,
        ) AraExtension {
            return .{};
        }

        pub fn bindAraExtension(
            _: *Processor,
            _: *AraExtension,
        ) void {
            AraExtension.bind_calls += 1;
        }

        pub fn unbindAraExtension(
            _: *Processor,
            _: *AraExtension,
        ) void {
            AraExtension.unbind_calls += 1;
        }

        pub fn applyParameterChanges(
            _: plug_process.ParameterChanges,
        ) void {}

        pub fn readState(
            _: ?*ibstream.IBStream,
        ) types.tresult {
            return types.kResultFalse;
        }

        pub fn writeState(
            _: ?*ibstream.IBStream,
        ) types.tresult {
            return types.kResultFalse;
        }
    });

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        TestEffect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(component_out orelse
            return error.TestUnexpectedResult));
    try std.testing.expectEqual(
        @as(usize, 1),
        TestAraExtension.initialize_calls,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        TestAraExtension.bind_calls,
    );

    var entry_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &ara_vst3.plug_in_entry_point_iid,
            &entry_out,
        ),
    );
    const entry: *ara_vst3.IPlugInEntryPoint =
        @ptrCast(@alignCast(entry_out orelse
            return error.TestUnexpectedResult));
    try std.testing.expect(
        entry.vtable.getFactory(entry) == ara_factory_ptr,
    );

    var unknown_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        entry.vtable.queryInterface(
            entry,
            &funknown.iid,
            &unknown_out,
        ),
    );
    try std.testing.expect(
        unknown_out == @as(?*anyopaque, component),
    );
    const unknown: *funknown.Header =
        @ptrCast(@alignCast(unknown_out orelse
            return error.TestUnexpectedResult));
    _ = unknown.vtable.release(unknown);

    const extension =
        entry.vtable.bindToDocumentController(
            entry,
            @ptrFromInt(0x2000),
        ) orelse return error.TestUnexpectedResult;
    try std.testing.expect(
        extension ==
            @as(
                *const ara_vst3.PlugInExtensionInstance,
                @ptrFromInt(0x3000),
            ),
    );
    _ = entry.vtable.release(entry);
    try std.testing.expectEqual(
        @as(types.uint32, 0),
        component.vtable.release(component),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        TestAraExtension.deinit_calls,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        TestAraExtension.unbind_calls,
    );
}

test "simple stereo effect requests followed host transport fields" {
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "TransportFollower";
        pub const controller_cid =
            tuid.inlineUid(0x618AD0C3, 0x3D1B48E4, 0xA74C1D3B, 0x96A05C22);
        pub const follow_host_transport = true;
        pub const Processor = struct {
            pub fn process(
                _: @This(),
                comptime Sample: type,
                context: *plug_process.ProcessContext(Sample),
            ) void {
                context.outputs.clear();
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
    try std.testing.expectEqual(
        types.kResultOk,
        TestEffect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    var requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &ivstaudioprocessor.iprocess_context_requirements_iid,
            &requirements_out,
        ),
    );
    const requirements: *ivstaudioprocessor.IProcessContextRequirements =
        @ptrCast(@alignCast(requirements_out.?));
    defer _ = requirements.vtable.release(requirements);
    const requested =
        requirements.vtable.getProcessContextRequirements(requirements);
    try std.testing.expect(
        requested &
            ivstaudioprocessor.ProcessContextRequirementFlags.kNeedTempo !=
            0,
    );
    try std.testing.expect(
        requested &
            ivstaudioprocessor.ProcessContextRequirementFlags.kNeedProjectTimeMusic !=
            0,
    );
    try std.testing.expect(
        requested &
            ivstaudioprocessor.ProcessContextRequirementFlags.kNeedTransportState !=
            0,
    );
}

test "simple stereo effect exposes bounded graph and text telemetry" {
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "GraphTelemetryComponent";
        pub const controller_cid = tuid.inlineUid(0x5A14B7C2, 0x98E4430D, 0xB9512E6F, 0x7C83A109);
        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    @memset(output, 0);
                }
            }

            pub fn guiGraphLoad(_: *@This(), source_id: u32, output: []plug_core.gui_graph.Point) usize {
                if (output.len == 0) return 0;
                if (source_id == 7) {
                    output[0] = .{ .x = 42.0, .y = -6.0 };
                    return 1;
                }
                if (source_id == 8) {
                    output[0] = .{ .x = @floatFromInt(output.len), .y = 0.0 };
                    return output.len + 1;
                }
                return 0;
            }

            pub fn guiTelemetryLoadText(_: *@This(), source_id: u32, output: []u8) usize {
                if (source_id != 9 or output.len == 0) return 0;
                output[0] = @intCast(output.len);
                return output.len + 1;
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
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.TestUnexpectedResult));
    defer _ = component.vtable.release(component);

    var telemetry_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &gui_telemetry_source.iid, &telemetry_out));
    const telemetry: *gui_telemetry_source.Interface = @ptrCast(@alignCast(telemetry_out orelse return error.TestUnexpectedResult));
    defer _ = telemetry.vtable.release(telemetry);

    var points: [1]plug_core.gui_graph.Point = undefined;
    try std.testing.expectEqual(@as(types.uint32, 1), telemetry.vtable.loadGraph(telemetry, 7, &points, points.len));
    try std.testing.expectEqual(@as(f32, 42.0), points[0].x);
    try std.testing.expectEqual(@as(f32, -6.0), points[0].y);

    var oversized_points: [gui_telemetry_source.maximum_graph_points + 1]plug_core.gui_graph.Point = undefined;
    try std.testing.expectEqual(
        @as(types.uint32, gui_telemetry_source.maximum_graph_points),
        telemetry.vtable.loadGraph(telemetry, 8, &oversized_points, oversized_points.len),
    );
    try std.testing.expectEqual(@as(f32, @floatFromInt(gui_telemetry_source.maximum_graph_points)), oversized_points[0].x);

    var oversized_text: [gui_telemetry_source.maximum_text_bytes + 1]u8 = undefined;
    try std.testing.expectEqual(
        @as(types.uint32, gui_telemetry_source.maximum_text_bytes),
        telemetry.vtable.loadText(telemetry, 9, &oversized_text, oversized_text.len),
    );
    try std.testing.expectEqual(@as(u8, gui_telemetry_source.maximum_text_bytes), oversized_text[0]);
}

test "simple stereo effect processes with setup sample rate when process context is absent" {
    const Config = struct {
        pub const component_name = "SampleRateFallback";
        pub const controller_cid = tuid.inlineUid(0x22222222, 0x33333333, 0x44444444, 0x55555555);

        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    @memset(output, @floatCast(context.sampleRate()));
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
    };
    const TestEffect = SimpleStereoEffect(Config);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var setup = ivstaudioprocessor.ProcessSetup{
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .sampleRate = 44_100.0,
        .maxSamplesPerBlock = 2,
    };
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setupProcessing(processor, &setup));

    var input_samples = [_]f32{ 1.0, 2.0 };
    var output_samples = [_]f32{ 9.0, 9.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqual(@as(f32, 44_100.0), output_samples[0]);
    try std.testing.expectEqual(@as(f32, 44_100.0), output_samples[1]);
}

test "simple stereo effect exposes offset zero state and persists the final queue value" {
    const Fixture = struct {
        const Params = struct {
            gain: plug_core.parameters.FloatParam = .{ .id = 7, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.25 },
        };
        const ParameterSet = plug_core.parameters.ParameterSet(Params);
        const parameter_set = ParameterSet.init(.{});
    };
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "BlockParameterState";
        pub const controller_cid = tuid.inlineUid(0x70707070, 0x71717171, 0x72727272, 0x73737373);
        pub const Params = Fixture.Params;
        pub const parameter_set = &Fixture.parameter_set;

        pub const Processor = struct {
            pub fn process(_: *@This(), parameters: anytype, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                const value: Sample = @floatCast(parameters.getNormalizedById(7));
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    @memset(output, value);
                }
            }
        };
    });

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.TestUnexpectedResult));
    defer _ = component.vtable.release(component);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out orelse return error.TestUnexpectedResult));
    defer _ = processor.vtable.release(processor);

    var setup = ivstaudioprocessor.ProcessSetup{
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .sampleRate = 48_000.0,
        .maxSamplesPerBlock = 2,
    };
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setupProcessing(processor, &setup));

    var input_samples = [_]f32{ 0.0, 0.0 };
    var output_samples = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
    };

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var later_changes = Changes{};
    const later_queue = later_changes.addQueue(7) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(types.kResultOk, later_queue.appendPoint(1, 0.75));
    data.inputParameterChanges = later_changes.asInterface();
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.25 }, &output_samples);

    data.inputParameterChanges = null;
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.75, 0.75 }, &output_samples);

    var boundary_changes = Changes{};
    const boundary_queue = boundary_changes.addQueue(7) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(types.kResultOk, boundary_queue.appendPoint(0, 0.5));
    data.inputParameterChanges = boundary_changes.asInterface();
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 0.5 }, &output_samples);

    var flush_changes = Changes{};
    const flush_queue = flush_changes.addQueue(7) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(types.kResultOk, flush_queue.appendPoint(0, 0.9));
    data.numInputs = 0;
    data.numOutputs = 0;
    data.inputs = null;
    data.outputs = null;
    data.numSamples = 0;
    data.inputParameterChanges = flush_changes.asInterface();
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));

    data.numInputs = 1;
    data.numOutputs = 1;
    data.inputs = &inputs;
    data.outputs = &outputs;
    data.numSamples = input_samples.len;
    data.inputParameterChanges = null;
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.9, 0.9 }, &output_samples);

    var rejected_flush_changes = Changes{};
    const rejected_flush_queue = rejected_flush_changes.addQueue(7) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(types.kResultOk, rejected_flush_queue.appendPoint(0, 0.1));
    data.numInputs = 1;
    data.numOutputs = 0;
    data.inputs = null;
    data.outputs = null;
    data.numSamples = 0;
    data.inputParameterChanges = rejected_flush_changes.asInterface();
    try std.testing.expectEqual(types.kInvalidArgument, processor.vtable.process(processor, &data));

    data.numInputs = 1;
    data.numOutputs = 1;
    data.inputs = &inputs;
    data.outputs = &outputs;
    data.numSamples = input_samples.len;
    data.inputParameterChanges = null;
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.9, 0.9 }, &output_samples);
}

var malformed_process_apply_count: usize = 0;
var malformed_process_last_change_count: usize = 0;

test "simple stereo effect ignores parameter changes when process data is malformed" {
    const Config = struct {
        pub const component_name = "MalformedProcess";
        pub const controller_cid = tuid.inlineUid(0x33333333, 0x44444444, 0x55555555, 0x66666666);

        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    @memset(output, 0);
                }
            }
        };

        pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
            malformed_process_apply_count += 1;
            malformed_process_last_change_count = changes.changeCount();
        }

        pub fn readState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultFalse;
        }

        pub fn writeState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultFalse;
        }
    };
    const TestEffect = SimpleStereoEffect(Config);

    malformed_process_apply_count = 0;
    malformed_process_last_change_count = 0;

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const queue = changes.addQueue(7).?;
    try std.testing.expectEqual(types.kResultOk, queue.appendPoint(0, 0.5));

    var input_samples = [_]f32{ 1.0, 2.0 };
    var output_samples = [_]f32{ 9.0, 9.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = -1,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kInvalidArgument, processor.vtable.process(processor, &data));
    try std.testing.expectEqual(@as(usize, 0), malformed_process_apply_count);
    try std.testing.expectEqual(@as(usize, 0), malformed_process_last_change_count);
    try std.testing.expectEqualSlices(f32, &.{ 9.0, 9.0 }, &output_samples);
}

test "simple stereo effect delegates data exchange receiver callbacks" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "DataExchangeReceiverComponent";
        pub const controller_cid = tuid.inlineUid(0xC0D66B7A, 0x56F24E07, 0x9B5A20B5, 0xE775D460);
        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                _ = context;
            }
        };
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub fn readState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultOk;
        }
        pub fn writeState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultOk;
        }
        pub fn applyParameterChanges(_: plug_process.ParameterChanges) void {}

        pub fn dataExchangeQueueOpened(user_context_id: ivstdataexchange.DataExchangeUserContextID, block_size: types.uint32) types.TBool {
            test_data_exchange_queue_opened_count += 1;
            test_data_exchange_last_user_context_id = user_context_id;
            test_data_exchange_last_block_size = block_size;
            return 2;
        }

        pub fn dataExchangeQueueClosed(user_context_id: ivstdataexchange.DataExchangeUserContextID) void {
            test_data_exchange_queue_closed_count += 1;
            test_data_exchange_last_user_context_id = user_context_id;
        }

        pub fn onDataExchangeBlocksReceived(user_context_id: ivstdataexchange.DataExchangeUserContextID, num_blocks: types.uint32, blocks: ?[*]ivstdataexchange.DataExchangeBlock, on_background_thread: types.TBool) void {
            test_data_exchange_blocks_received_count += 1;
            test_data_exchange_last_user_context_id = user_context_id;
            test_data_exchange_last_num_blocks = num_blocks;
            test_data_exchange_last_background_flag = on_background_thread;
            if (blocks) |items| test_data_exchange_last_block_id = items[0].blockID;
        }
    });

    test_data_exchange_queue_opened_count = 0;
    test_data_exchange_queue_closed_count = 0;
    test_data_exchange_blocks_received_count = 0;
    test_data_exchange_last_user_context_id = 0;
    test_data_exchange_last_block_size = 0;
    test_data_exchange_last_num_blocks = 0;
    test_data_exchange_last_block_id = 0;
    test_data_exchange_last_background_flag = 0;

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var receiver_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.queryInterface(component_iface, &ivstdataexchange.idata_exchange_receiver_iid, &receiver_out));
    try std.testing.expect(receiver_out != null);
    const receiver: *ivstdataexchange.IDataExchangeReceiver = @ptrCast(@alignCast(receiver_out.?));
    defer _ = receiver.vtable.release(receiver);

    var dispatch_on_background_thread: types.TBool = 1;
    receiver.vtable.queueOpened(receiver, 77, 0, &dispatch_on_background_thread);
    try std.testing.expectEqual(@as(types.TBool, 0), dispatch_on_background_thread);
    try std.testing.expectEqual(@as(usize, 0), test_data_exchange_queue_opened_count);

    receiver.vtable.queueOpened(receiver, 77, 512, &dispatch_on_background_thread);
    try std.testing.expectEqual(@as(types.TBool, 1), dispatch_on_background_thread);
    try std.testing.expectEqual(@as(usize, 1), test_data_exchange_queue_opened_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 77), test_data_exchange_last_user_context_id);
    try std.testing.expectEqual(@as(types.uint32, 512), test_data_exchange_last_block_size);

    var blocks = [_]ivstdataexchange.DataExchangeBlock{.{
        .data = @ptrFromInt(0x1000),
        .size = 64,
        .blockID = 22,
    }};
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, blocks.len, &blocks, 2);
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, 0, &blocks, 1);
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, 1, null, 1);
    blocks[0].data = null;
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, blocks.len, &blocks, 1);
    blocks[0].data = @ptrFromInt(0x1000);
    blocks[0].size = 0;
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, blocks.len, &blocks, 1);
    blocks[0].size = 64;
    blocks[0].blockID = ivstdataexchange.InvalidDataExchangeBlockID;
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, blocks.len, &blocks, 1);
    try std.testing.expectEqual(@as(usize, 0), test_data_exchange_blocks_received_count);
    blocks[0].blockID = 22;
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 77, blocks.len, &blocks, 1);
    try std.testing.expectEqual(@as(usize, 1), test_data_exchange_blocks_received_count);
    try std.testing.expectEqual(@as(types.uint32, blocks.len), test_data_exchange_last_num_blocks);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeBlockID, 22), test_data_exchange_last_block_id);
    try std.testing.expectEqual(@as(types.TBool, 1), test_data_exchange_last_background_flag);

    receiver.vtable.queueClosed(receiver, 77);
    try std.testing.expectEqual(@as(usize, 1), test_data_exchange_queue_closed_count);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 77), test_data_exchange_last_user_context_id);
}

test "simple stereo effect rejects invalid data exchange outputs" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "FailedDataExchangeOutputs";
        pub const controller_cid = tuid.inlineUid(0x87654321, 0x87654321, 0x87654321, 0x87654321);
        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                _ = context;
            }
        };
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub fn readState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultOk;
        }
        pub fn writeState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultOk;
        }
        pub fn applyParameterChanges(_: plug_process.ParameterChanges) void {}
    });
    const Host = vst_host_context.DataExchangeHost("Invalid Data Exchange Host", struct {
        pub fn openQueue(_: anytype, _: ?*ivstaudioprocessor.IAudioProcessor, _: types.uint32, _: types.uint32, _: types.uint32, _: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            out.* = ivstdataexchange.InvalidDataExchangeQueueID;
            return types.kResultOk;
        }

        pub fn lockBlock(_: anytype, _: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            block.* = .{
                .blockID = 12,
                .size = 128,
                .data = null,
            };
            return types.kResultOk;
        }
    });
    var host = Host{};

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component_iface.vtable.release(component_iface);
    defer _ = component_iface.vtable.terminate(component_iface);
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));

    var queue_id: ivstdataexchange.DataExchangeQueueID = 88;
    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.openDataExchangeQueue(component_iface, 0, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);
    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.openDataExchangeQueue(component_iface, 128, 0, 8, 77, &queue_id));
    try std.testing.expectEqual(@as(types.uint32, 0), host.open_count);
    try std.testing.expectEqual(types.kResultFalse, TestEffect.openDataExchangeQueue(component_iface, 128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);

    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.closeDataExchangeQueue(component_iface, ivstdataexchange.InvalidDataExchangeQueueID));

    var block = ivstdataexchange.DataExchangeBlock{
        .blockID = 1,
        .size = 64,
        .data = @ptrFromInt(0x2000),
    };
    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.lockDataExchangeBlock(component_iface, ivstdataexchange.InvalidDataExchangeQueueID, &block));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeBlockID, block.blockID);
    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.freeDataExchangeBlock(component_iface, ivstdataexchange.InvalidDataExchangeQueueID, 12, 1));
    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.freeDataExchangeBlock(component_iface, 44, ivstdataexchange.InvalidDataExchangeBlockID, 1));
    try std.testing.expectEqual(types.kInvalidArgument, TestEffect.freeDataExchangeBlock(component_iface, 44, 12, 2));
    try std.testing.expectEqual(types.kResultFalse, TestEffect.lockDataExchangeBlock(component_iface, 44, &block));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeBlockID, block.blockID);
    try std.testing.expectEqual(@as(types.uint32, 0), block.size);
    try std.testing.expectEqual(@as(?*anyopaque, null), block.data);
}

test "simple stereo effect releases replaced connection peers" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const TestEffect = SimpleStereoEffect(struct {
        pub const component_name = "ConnectionLifecycleComponent";
        pub const controller_cid = tuid.inlineUid(0x12345678, 0x12345678, 0x12345678, 0x12345678);
        pub const Processor = struct {
            pub fn process(_: @This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
                _ = context;
            }
        };
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub fn readState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultOk;
        }
        pub fn writeState(_: ?*ibstream.IBStream) types.tresult {
            return types.kResultOk;
        }
        pub fn applyParameterChanges(_: plug_process.ParameterChanges) void {}
    });
    const Peer = vst_message.ConnectionPoint(struct {});

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, TestEffect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.queryInterface(component_iface, &ivstmessage.iconnection_point_iid, &connection_out));
    try std.testing.expect(connection_out != null);
    const connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(connection_out.?));
    defer _ = connection.vtable.release(connection);

    var first = Peer{};
    var second = Peer{};

    try std.testing.expectEqual(types.kResultOk, connection.vtable.connect(connection, first.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), first.release_count);

    try std.testing.expectEqual(types.kResultOk, connection.vtable.connect(connection, second.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), second.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), second.release_count);

    try std.testing.expectEqual(types.kResultOk, connection.vtable.disconnect(connection, null));
    try std.testing.expectEqual(@as(types.uint32, 1), second.release_count);
}

test "simple stereo effect exposes processor lifecycle and decoded audio transport hooks" {
    const EmptyParams = struct {};
    const ParameterSet = plug_core.parameters.ParameterSet(EmptyParams);
    const Convolver = plug_core.gui_ir_convolution.PartitionedConvolver(16, 8);
    const TestProcessor = struct {
        convolver: Convolver,

        pub fn init() @This() {
            test_effect_processor_init_count += 1;
            return .{ .convolver = Convolver.init(48_000) };
        }

        pub fn deinit(_: *@This()) void {
            test_effect_processor_deinit_count += 1;
        }

        pub fn prepare(_: *@This(), config: plug_core.plugin.PrepareConfig) void {
            test_effect_prepare_sample_rate = config.sample_rate;
            test_effect_prepare_block_size = config.max_block_size;
            test_effect_prepare_mode = config.process_mode;
        }

        pub fn reset(_: *@This()) void {
            test_effect_reset_count += 1;
        }

        pub fn latencySamples(_: *const @This()) u32 {
            return 8;
        }

        pub fn tailSamples(_: *const @This()) u32 {
            return 16;
        }

        pub fn audioImportReceiver(self: *@This()) *Convolver {
            return &self.convolver;
        }

        pub fn process(_: *@This(), comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
            _ = context;
        }
    };
    const Effect = SimpleStereoEffect(struct {
        pub const component_name = "LifecycleAudioImportComponent";
        pub const controller_cid = tuid.inlineUid(0x12340001, 0x12340002, 0x12340003, 0x12340004);
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
        pub const audio_import_target_id: u32 = 12;
        pub const Processor = TestProcessor;
    });
    const Controller = ReflectedEditController(struct {
        pub const controller_name = "LifecycleAudioImportController";
        pub const Params = EmptyParams;
        pub const parameter_set = &ParameterSet.init(.{});
    });
    const Importer = struct {
        pub fn snapshot(_: *@This()) plug_core.gui_audio_file_importer.Snapshot {
            return .{
                .import = .{
                    .status = .ready,
                    .entry_point = .picker,
                    .path_count = 1,
                    .completed_units = 2,
                    .total_units = 2,
                    .generation = 7,
                    .cancellation_pending = false,
                },
                .failure = .none,
                .sample_rate = 48_000,
                .channels = 1,
                .sample_frames = 2,
                .preview_points = 2,
                .decoded_frames = 2,
            };
        }

        pub fn copyDecoded(_: *@This(), offset: usize, output: []f32) usize {
            const samples = [_]f32{ 1.0, 0.5 };
            if (offset >= samples.len) return 0;
            const count = @min(output.len, samples.len - offset);
            @memcpy(output[0..count], samples[offset .. offset + count]);
            return count;
        }
    };

    test_effect_processor_init_count = 0;
    test_effect_processor_deinit_count = 0;
    test_effect_prepare_sample_rate = 0;
    test_effect_prepare_block_size = 0;
    test_effect_prepare_mode = .realtime;
    test_effect_reset_count = 0;

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out));
    try std.testing.expect(component_out != null);
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    try std.testing.expectEqual(@as(u32, 8), processor.vtable.getLatencySamples(processor));
    try std.testing.expectEqual(@as(u32, 16), processor.vtable.getTailSamples(processor));
    var setup = ivstaudioprocessor.ProcessSetup{
        .processMode = @intFromEnum(ivstaudioprocessor.ProcessModes.kOffline),
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .sampleRate = 96_000,
        .maxSamplesPerBlock = 256,
    };
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setupProcessing(processor, &setup));
    try std.testing.expectEqual(@as(f64, 96_000), test_effect_prepare_sample_rate);
    try std.testing.expectEqual(@as(u32, 256), test_effect_prepare_block_size);
    try std.testing.expectEqual(plug_process.ProcessMode.offline, test_effect_prepare_mode);
    try std.testing.expectEqual(@as(usize, 1), test_effect_reset_count);

    try std.testing.expectEqual(types.kInvalidArgument, component.vtable.activateBus(component, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 2));
    try std.testing.expectEqual(types.kInvalidArgument, component.vtable.activateBus(component, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 1, 1));
    try std.testing.expectEqual(types.kInvalidArgument, component.vtable.setActive(component, 2));
    try std.testing.expectEqual(types.kInvalidArgument, processor.vtable.setProcessing(processor, 2));
    try std.testing.expectEqual(@as(usize, 1), test_effect_reset_count);

    try std.testing.expectEqual(types.kResultOk, component.vtable.activateBus(component, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 1));
    try std.testing.expectEqual(types.kResultOk, component.vtable.setActive(component, 1));
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setProcessing(processor, 1));
    try std.testing.expectEqual(@as(usize, 1), test_effect_reset_count);
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setProcessing(processor, 0));
    try std.testing.expectEqual(types.kResultOk, component.vtable.setActive(component, 0));
    try std.testing.expectEqual(@as(usize, 3), test_effect_reset_count);

    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &ivstmessage.iconnection_point_iid, &component_connection_out));
    const component_connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out.?));

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller.vtable.queryInterface(controller, &ivstmessage.iconnection_point_iid, &controller_connection_out));
    const controller_connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out.?));
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));

    var importer = Importer{};
    try std.testing.expectEqual(types.kResultOk, Controller.sendDecodedAudio(controller, 12, &importer));
    const effect_processor = Effect.processorInstance(component);
    try std.testing.expect(effect_processor.convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 7), effect_processor.convolver.activeMetadata().?.generation);

    try std.testing.expectEqual(@as(types.uint32, 1), controller_connection.vtable.release(controller_connection));
    try std.testing.expectEqual(@as(types.uint32, 0), controller.vtable.release(controller));
    try std.testing.expectEqual(@as(types.uint32, 2), component_connection.vtable.release(component_connection));
    try std.testing.expectEqual(@as(types.uint32, 1), processor.vtable.release(processor));
    try std.testing.expectEqual(@as(types.uint32, 0), component.vtable.release(component));
    try std.testing.expectEqual(@as(usize, 1), test_effect_processor_init_count);
    try std.testing.expectEqual(@as(usize, 1), test_effect_processor_deinit_count);
}

test "simple effect reports fallible processor construction failure" {
    const EmptyParams = struct {};
    const Set = plug_core.parameters.ParameterSet(EmptyParams);
    const Effect = SimpleEffect(struct {
        pub const component_name = "FallibleProcessorComponent";
        pub const controller_cid =
            tuid.inlineUid(
                0x61A88001,
                0x61A88002,
                0x61A88003,
                0x61A88004,
            );
        pub const Params = EmptyParams;
        pub const parameter_set = &Set.init(.{});
        pub const Processor = struct {
            pub fn initWithAllocator(
                _: std.mem.Allocator,
            ) !@This() {
                return error.InitializationFailed;
            }

            pub fn process(
                _: *@This(),
                comptime Sample: type,
                _: *plug_process.ProcessContext(Sample),
            ) void {}
        };
    });

    var out: ?*anyopaque = @ptrFromInt(1);
    try std.testing.expectEqual(
        types.kResultFalse,
        Effect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &out,
        ),
    );
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
}

test "simple effect cleans up allocation failures with owning allocator" {
    const EmptyParams = struct {};
    const Set = plug_core.parameters.ParameterSet(EmptyParams);
    const Effect = SimpleEffect(struct {
        pub const component_name = "AllocationFailureComponent";
        pub const controller_cid =
            tuid.inlineUid(
                0x71A88001,
                0x71A88002,
                0x71A88003,
                0x71A88004,
            );
        pub const Params = EmptyParams;
        pub const parameter_set = &Set.init(.{});
        pub const Processor = struct {
            allocator: std.mem.Allocator,
            storage: []u8,

            pub fn initWithAllocator(
                allocator: std.mem.Allocator,
            ) !@This() {
                return .{
                    .allocator = allocator,
                    .storage = try allocator.alloc(u8, 32),
                };
            }

            pub fn deinit(self: *@This()) void {
                self.allocator.free(self.storage);
            }

            pub fn process(
                _: *@This(),
                comptime Sample: type,
                _: *plug_process.ProcessContext(Sample),
            ) void {}
        };
    });

    inline for (0..2) |fail_index| {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        var out: ?*anyopaque = @ptrFromInt(1);
        try std.testing.expectEqual(
            types.kResultFalse,
            Effect.createWithAllocator(
                failing.allocator(),
                @ptrCast(&ivstcomponent.icomponent_iid),
                &out,
            ),
        );
        try std.testing.expectEqual(@as(?*anyopaque, null), out);
    }

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.createWithAllocator(
            std.testing.allocator,
            @ptrCast(&ivstcomponent.icomponent_iid),
            &out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(
        @as(types.uint32, 0),
        component.vtable.release(component),
    );
}

test "simple effect binds dynamic topology across host metadata negotiation activation and flush validation" {
    const vstspeaker = @import("pluginterfaces/vst/vstspeaker.zig");
    const Config = struct {
        pub const component_name = "DynamicTopologyComponent";
        pub const controller_cid =
            tuid.inlineUid(
                0xD7A64B21,
                0x0C62477E,
                0xB8A44E18,
                0xF06B8D93,
            );
        pub const dynamic_audio_bus_topology: ?plug_core.plugin.DynamicAudioBusTopology = makeTopology();

        fn makeTopology() plug_core.plugin.DynamicAudioBusTopology {
            const main_layouts =
                plug_core.plugin.AudioBusLayoutSet.init(
                    &.{ .mono, .stereo },
                ) catch unreachable;
            var topology =
                plug_core.plugin.DynamicAudioBusTopology.init(
                    plug_core.plugin.DynamicAudioBus.init(
                        .stereo,
                        main_layouts,
                        true,
                    ) catch unreachable,
                    plug_core.plugin.DynamicAudioBus.init(
                        .stereo,
                        main_layouts,
                        true,
                    ) catch unreachable,
                ) catch unreachable;
            _ = topology.addAuxiliary(
                .input,
                plug_core.plugin.DynamicAudioBus.fixed(
                    .mono,
                    false,
                ) catch unreachable,
            ) catch unreachable;
            return topology;
        }

        pub const Processor = struct {
            host_requests: ?*HostRequestSink = null,
            last_auxiliary_input_count: usize = 0,
            last_auxiliary_output_count: usize = 0,

            pub fn bindHostRequests(
                self: *@This(),
                requests: *HostRequestSink,
            ) void {
                self.host_requests = requests;
            }

            pub fn process(
                self: *@This(),
                comptime Sample: type,
                context: *plug_process.ProcessContext(Sample),
            ) void {
                self.last_auxiliary_input_count =
                    context.auxiliaryInputBusCount();
                self.last_auxiliary_output_count =
                    context.auxiliaryOutputBusCount();
                context.outputs.clear();
                context.clearAuxiliaryOutputs();
            }
        };
    };
    const Effect = SimpleEffect(Config);
    const ControllerParams = struct {};
    const controller_parameter_set =
        plug_core.parameters.ParameterSet(ControllerParams).init(.{});
    const Controller = ReflectedEditController(struct {
        pub const controller_name = "DynamicTopologyController";
        pub const Params = ControllerParams;
        pub const parameter_set = &controller_parameter_set;
    });
    const HandlerConfig = struct {
        var reject_restart = false;

        pub fn restartComponent(
            _: anytype,
            _: types.int32,
        ) types.tresult {
            if (!reject_restart) return types.kResultOk;
            reject_restart = false;
            return types.kResultFalse;
        }
    };
    const Handler = vst_component_handler.ComponentHandler(HandlerConfig);
    var handler = Handler{};
    HandlerConfig.reject_restart = false;

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(
            component_out orelse return error.MissingComponent,
        ));
    defer _ = component.vtable.release(component);
    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &ivstmessage.iconnection_point_iid,
            &component_connection_out,
        ),
    );
    const component_connection: *ivstmessage.IConnectionPoint =
        @ptrCast(@alignCast(
            component_connection_out orelse return error.MissingConnection,
        ));
    defer _ = component_connection.vtable.release(component_connection);
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Controller.create(
            @ptrCast(&ivsteditcontroller.iedit_controller_iid),
            &controller_out,
        ),
    );
    const controller: *ivsteditcontroller.IEditController =
        @ptrCast(@alignCast(
            controller_out orelse return error.MissingController,
        ));
    defer _ = controller.vtable.release(controller);
    try std.testing.expectEqual(
        types.kResultOk,
        controller.vtable.setComponentHandler(
            controller,
            handler.asHandler(),
        ),
    );
    defer _ = controller.vtable.setComponentHandler(controller, null);
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller.vtable.queryInterface(
            controller,
            &ivstmessage.iconnection_point_iid,
            &controller_connection_out,
        ),
    );
    const controller_connection: *ivstmessage.IConnectionPoint =
        @ptrCast(@alignCast(
            controller_connection_out orelse return error.MissingConnection,
        ));
    defer _ = controller_connection.vtable.release(controller_connection);
    try std.testing.expectEqual(
        types.kResultOk,
        controller_connection.vtable.connect(
            controller_connection,
            component_connection,
        ),
    );
    defer _ = controller_connection.vtable.disconnect(
        controller_connection,
        component_connection,
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component_connection.vtable.connect(
            component_connection,
            controller_connection,
        ),
    );
    defer _ = component_connection.vtable.disconnect(
        component_connection,
        controller_connection,
    );
    const audio = @intFromEnum(ivstcomponent.MediaTypes.kAudio);
    const input = @intFromEnum(ivstcomponent.BusDirections.kInput);
    const output = @intFromEnum(ivstcomponent.BusDirections.kOutput);
    try std.testing.expectEqual(
        @as(types.int32, 2),
        component.vtable.getBusCount(component, audio, input),
    );
    try std.testing.expectEqual(
        @as(types.int32, 1),
        component.vtable.getBusCount(component, audio, output),
    );
    var info = ivstcomponent.BusInfo{};
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.getBusInfo(component, audio, input, 1, &info),
    );
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);
    try std.testing.expectEqual(@as(types.uint32, 0), info.flags);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &ivstaudioprocessor.iaudio_processor_iid,
            &processor_out,
        ),
    );
    const processor: *ivstaudioprocessor.IAudioProcessor =
        @ptrCast(@alignCast(
            processor_out orelse return error.MissingProcessor,
        ));
    defer _ = processor.vtable.release(processor);

    try std.testing.expectEqual(
        types.kInvalidArgument,
        processor.vtable.getBusArrangement(processor, input, 0, null),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        processor.vtable.setupProcessing(processor, null),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        processor.vtable.process(processor, null),
    );
    var input_arrangements = [_]vsttypes.SpeakerArrangement{
        vstspeaker.SpeakerArr.kMono,
        vstspeaker.SpeakerArr.kMono,
    };
    var output_arrangements = [_]vsttypes.SpeakerArrangement{
        vstspeaker.SpeakerArr.kMono,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.setBusArrangements(
            processor,
            &input_arrangements,
            input_arrangements.len,
            &output_arrangements,
            output_arrangements.len,
        ),
    );
    var arrangement: vsttypes.SpeakerArrangement = 0;
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.getBusArrangement(
            processor,
            input,
            0,
            &arrangement,
        ),
    );
    try std.testing.expectEqual(
        vstspeaker.SpeakerArr.kMono,
        arrangement,
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.activateBus(
            component,
            audio,
            input,
            1,
            1,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.getBusInfo(component, audio, input, 1, &info),
    );
    try std.testing.expectEqual(@as(types.uint32, 0), info.flags);

    const processor_instance = Effect.processorInstance(component);
    const host_requests =
        processor_instance.host_requests orelse
        return error.MissingHostRequests;
    const denied_bus =
        try plug_core.plugin.DynamicAudioBus.fixed(.mono, false);
    var denied_snapshot: plug_core.plugin.DynamicAudioBusSnapshot = .{};
    const realtime_topology_scope =
        plug_core.realtime_audit.Scope.enter();
    try std.testing.expect(
        !Effect.audioBusTopologySnapshot(component, &denied_snapshot),
    );
    try std.testing.expect(
        !Effect.setAudioBusLayout(component, .input, 0, .mono),
    );
    try std.testing.expect(
        !Effect.addAuxiliaryAudioBus(component, .output, denied_bus),
    );
    try std.testing.expect(
        !Effect.removeAuxiliaryAudioBus(component, .input, 0),
    );
    const realtime_topology_report = realtime_topology_scope.leave();
    try std.testing.expectEqual(
        @as(u32, 4),
        realtime_topology_report.count(.lock),
    );
    try std.testing.expect(
        host_requests.addAuxiliaryAudioBus(
            .output,
            try plug_core.plugin.DynamicAudioBus.fixed(.mono, false),
        ),
    );
    try std.testing.expectEqual(
        @as(types.int32, 2),
        component.vtable.getBusCount(component, audio, output),
    );
    var snapshot: plug_core.plugin.DynamicAudioBusSnapshot = .{};
    try std.testing.expect(
        Effect.audioBusTopologySnapshot(component, &snapshot),
    );
    try std.testing.expect(snapshot.bus(.input, 1).?.active);
    try std.testing.expectEqual(
        plug_core.plugin.AudioBusLayout.mono,
        snapshot.bus(.output, 1).?.layout,
    );

    var input_buses = [_]ivstaudioprocessor.AudioBusBuffers{
        .{ .numChannels = 1 },
        .{ .numChannels = 1 },
    };
    var output_buses = [_]ivstaudioprocessor.AudioBusBuffers{
        .{ .numChannels = 1 },
        .{ .numChannels = 1 },
    };
    var flush = ivstaudioprocessor.ProcessData{
        .numInputs = input_buses.len,
        .numOutputs = output_buses.len,
        .inputs = &input_buses,
        .outputs = &output_buses,
        .numSamples = 0,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.process(processor, &flush),
    );
    flush.numOutputs = output_buses.len + 1;
    try std.testing.expectEqual(
        types.kInvalidArgument,
        processor.vtable.process(processor, &flush),
    );
    var setup = ivstaudioprocessor.ProcessSetup{
        .symbolicSampleSize = @intFromEnum(
            ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .sampleRate = 48_000,
        .maxSamplesPerBlock = 1,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.setupProcessing(processor, &setup),
    );
    var main_input_sample = [_]f32{1};
    var auxiliary_input_sample = [_]f32{2};
    var main_output_sample = [_]f32{3};
    var auxiliary_output_sample = [_]f32{4};
    var main_input_channels = [_][*]f32{&main_input_sample};
    var auxiliary_input_channels =
        [_][*]f32{&auxiliary_input_sample};
    var main_output_channels = [_][*]f32{&main_output_sample};
    var auxiliary_output_channels =
        [_][*]f32{&auxiliary_output_sample};
    input_buses[0].channelBuffers = .{
        .channelBuffers32 = &main_input_channels,
    };
    input_buses[1].channelBuffers = .{
        .channelBuffers32 = &auxiliary_input_channels,
    };
    output_buses[0].channelBuffers = .{
        .channelBuffers32 = &main_output_channels,
    };
    output_buses[1].channelBuffers = .{
        .channelBuffers32 = &auxiliary_output_channels,
    };
    flush.numOutputs = output_buses.len;
    flush.numSamples = 1;
    flush.symbolicSampleSize =
        @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32);
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.process(processor, &flush),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        processor_instance.last_auxiliary_input_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        processor_instance.last_auxiliary_output_count,
    );
    try std.testing.expectEqual(@as(f32, 0), main_output_sample[0]);
    try std.testing.expectEqual(@as(f32, 0), auxiliary_output_sample[0]);

    const before_rejection = snapshot;
    try std.testing.expect(
        !host_requests.setAudioBusLayout(
            .input,
            0,
            .surround_5_1,
        ),
    );
    try std.testing.expect(
        Effect.audioBusTopologySnapshot(component, &snapshot),
    );
    try std.testing.expectEqualDeep(before_rejection, snapshot);

    const StateStream = vst_stream.FixedBufferStream(256);
    var state_stream = StateStream{};
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.getState(component, state_stream.asStream()),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        state_stream.asStream().vtable.seek(
            state_stream.asStream(),
            0,
            @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet),
            null,
        ),
    );
    var restored_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &restored_out,
        ),
    );
    const restored_component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(
            restored_out orelse return error.MissingComponent,
        ));
    defer _ = restored_component.vtable.release(restored_component);
    try std.testing.expectEqual(
        types.kResultOk,
        restored_component.vtable.setState(
            restored_component,
            state_stream.asStream(),
        ),
    );
    var restored_snapshot: plug_core.plugin.DynamicAudioBusSnapshot = .{};
    try std.testing.expect(
        Effect.audioBusTopologySnapshot(
            restored_component,
            &restored_snapshot,
        ),
    );
    snapshot.generation = 0;
    restored_snapshot.generation = 0;
    try std.testing.expectEqualDeep(snapshot, restored_snapshot);
    try std.testing.expectEqual(
        @as(types.int32, 2),
        restored_component.vtable.getBusCount(
            restored_component,
            audio,
            output,
        ),
    );
    try std.testing.expectEqual(
        types.kResultFalse,
        Effect.dispatchHostRequests(restored_component),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.dispatchHostRequests(component),
    );
    try std.testing.expectEqual(@as(u32, 1), handler.restart_count);
    try std.testing.expectEqual(
        ivsteditcontroller.RestartFlags.kIoChanged,
        handler.last_restart_flags,
    );

    host_requests.markChanges(&.{
        .component_reload,
        .audio_io,
        .parameter_values,
        .latency,
        .parameter_titles,
        .midi_cc_assignments,
        .note_expression,
        .io_titles,
        .prefetchable_support,
        .routing_info,
        .keyswitches,
        .parameter_id_mapping,
        .latency,
    });
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.dispatchHostRequests(component),
    );
    try std.testing.expectEqual(@as(u32, 2), handler.restart_count);
    try std.testing.expectEqual(
        ivsteditcontroller.RestartFlags.kReloadComponent |
            ivsteditcontroller.RestartFlags.kIoChanged |
            ivsteditcontroller.RestartFlags.kParamValuesChanged |
            ivsteditcontroller.RestartFlags.kLatencyChanged |
            ivsteditcontroller.RestartFlags.kParamTitlesChanged |
            ivsteditcontroller.RestartFlags.kMidiCCAssignmentChanged |
            ivsteditcontroller.RestartFlags.kNoteExpressionChanged |
            ivsteditcontroller.RestartFlags.kIoTitlesChanged |
            ivsteditcontroller.RestartFlags
                .kPrefetchableSupportChanged |
            ivsteditcontroller.RestartFlags.kRoutingInfoChanged |
            ivsteditcontroller.RestartFlags.kKeyswitchChanged |
            ivsteditcontroller.RestartFlags.kParamIDMappingChanged,
        handler.last_restart_flags,
    );

    host_requests.markChanges(&.{ .parameter_values, .routing_info });
    HandlerConfig.reject_restart = true;
    try std.testing.expectEqual(
        types.kResultFalse,
        Effect.dispatchHostRequests(component),
    );
    try std.testing.expectEqual(@as(u32, 3), handler.restart_count);
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.dispatchHostRequests(component),
    );
    try std.testing.expectEqual(@as(u32, 4), handler.restart_count);
    try std.testing.expectEqual(
        ivsteditcontroller.RestartFlags.kParamValuesChanged |
            ivsteditcontroller.RestartFlags.kRoutingInfoChanged,
        handler.last_restart_flags,
    );

    try std.testing.expectEqual(
        types.kResultOk,
        component_connection.vtable.disconnect(
            component_connection,
            controller_connection,
        ),
    );
    host_requests.markChanges(&.{ .parameter_values, .routing_info });
    try std.testing.expectEqual(
        types.kResultFalse,
        Effect.dispatchHostRequests(component),
    );
    try std.testing.expectEqual(@as(u32, 4), handler.restart_count);
    try std.testing.expectEqual(
        types.kResultOk,
        component_connection.vtable.connect(
            component_connection,
            controller_connection,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.dispatchHostRequests(component),
    );
    try std.testing.expectEqual(@as(u32, 5), handler.restart_count);
    try std.testing.expectEqual(
        ivsteditcontroller.RestartFlags.kParamValuesChanged |
            ivsteditcontroller.RestartFlags.kRoutingInfoChanged,
        handler.last_restart_flags,
    );
}

test "simple effect carries selected bus capacity through VST3 processing and state" {
    const Topology =
        plug_core.plugin.BoundedDynamicAudioBusTopology(12);
    const Snapshot = Topology.SnapshotType;
    const Config = struct {
        pub const component_name = "LargeDynamicTopologyComponent";
        pub const controller_cid =
            tuid.inlineUid(
                0x659E43B1,
                0x7D4C4F28,
                0xA7320B69,
                0x1CE745D0,
            );
        pub const dynamic_audio_bus_topology: ?Topology =
            makeTopology();

        fn makeTopology() Topology {
            var topology = Topology.init(
                plug_core.plugin.DynamicAudioBus.fixed(
                    .mono,
                    true,
                ) catch unreachable,
                null,
            ) catch unreachable;
            for (0..Topology.auxiliary_capacity) |_|
                _ = topology.addAuxiliary(
                    .input,
                    plug_core.plugin.DynamicAudioBus.fixed(
                        .mono,
                        false,
                    ) catch unreachable,
                ) catch unreachable;
            return topology;
        }

        pub const Processor = struct {
            auxiliary_input_count: usize = 0,

            pub fn process(
                self: *@This(),
                comptime Sample: type,
                context: *plug_process.BoundedProcessContext(
                    Sample,
                    Topology.auxiliary_capacity,
                ),
            ) void {
                self.auxiliary_input_count =
                    context.auxiliaryInputBusCount();
            }
        };
    };
    const Effect = SimpleEffect(Config);
    const audio =
        @intFromEnum(ivstcomponent.MediaTypes.kAudio);
    const input =
        @intFromEnum(ivstcomponent.BusDirections.kInput);
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(
            component_out orelse return error.MissingComponent,
        ));
    defer _ = component.vtable.release(component);
    try std.testing.expectEqual(
        @as(types.int32, 13),
        component.vtable.getBusCount(component, audio, input),
    );

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &ivstaudioprocessor.iaudio_processor_iid,
            &processor_out,
        ),
    );
    const processor: *ivstaudioprocessor.IAudioProcessor =
        @ptrCast(@alignCast(
            processor_out orelse return error.MissingProcessor,
        ));
    defer _ = processor.vtable.release(processor);
    var setup = ivstaudioprocessor.ProcessSetup{
        .symbolicSampleSize = @intFromEnum(
            ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .sampleRate = 48_000,
        .maxSamplesPerBlock = 1,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.setupProcessing(processor, &setup),
    );
    var samples: [Topology.bus_capacity][1]f32 =
        @splat(.{1.0});
    var channel_pointers: [Topology.bus_capacity][1][*]f32 = undefined;
    var input_buses: [Topology.bus_capacity]ivstaudioprocessor.AudioBusBuffers =
        @splat(.{ .numChannels = 1 });
    for (
        &samples,
        &channel_pointers,
        &input_buses,
    ) |*bus_samples, *bus_channel_pointers, *bus| {
        bus_channel_pointers[0] = bus_samples;
        bus.channelBuffers = .{
            .channelBuffers32 = bus_channel_pointers,
        };
    }
    var process_data = ivstaudioprocessor.ProcessData{
        .symbolicSampleSize = @intFromEnum(
            ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .numSamples = 1,
        .numInputs = Topology.bus_capacity,
        .inputs = &input_buses,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.process(processor, &process_data),
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        Effect.processorInstance(component)
            .auxiliary_input_count,
    );

    var snapshot: Snapshot = .{};
    try std.testing.expect(
        Effect.audioBusTopologySnapshot(component, &snapshot),
    );
    try std.testing.expectEqual(
        @as(usize, 13),
        snapshot.busCount(.input),
    );
    const StateStream = vst_stream.FixedBufferStream(512);
    var state_stream = StateStream{};
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.getState(
            component,
            state_stream.asStream(),
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        state_stream.asStream().vtable.seek(
            state_stream.asStream(),
            0,
            @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet),
            null,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.setState(
            component,
            state_stream.asStream(),
        ),
    );
}

test "VST3 runtime adapter forwards resource audio and telemetry payloads" {
    const ResourceReceiver = struct {
        imported: [16]u8 = @splat(0),
        imported_length: usize = 0,

        pub fn importPath(
            self: *@This(),
            path: []const u8,
        ) bool {
            if (path.len > self.imported.len) return false;
            @memcpy(self.imported[0..path.len], path);
            self.imported_length = path.len;
            return true;
        }

        pub fn relink(_: *@This(), _: []const u8) bool {
            return true;
        }

        pub fn requestCancel(_: *@This()) bool {
            return true;
        }

        pub fn retry(_: *@This()) bool {
            return true;
        }
    };
    const AudioReceiver = struct {
        cleared_generation: u64 = 0,

        pub fn begin(_: *@This(), _: anytype) !void {}

        pub fn write(
            _: *@This(),
            _: u64,
            _: usize,
            _: []const f32,
        ) !void {}

        pub fn commit(_: *@This(), _: u64) !void {}

        pub fn cancel(_: *@This(), _: u64) bool {
            return true;
        }

        pub fn clear(self: *@This(), generation: u64) !void {
            self.cleared_generation = generation;
        }
    };
    const Plugin = struct {
        resource_receiver: ResourceReceiver = .{},
        audio_receiver: AudioReceiver = .{},
        editor_open_count: usize = 0,
        editor_close_count: usize = 0,

        pub const name = "Payload Adapter";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn resourcePathReceiver(
            self: *@This(),
        ) *ResourceReceiver {
            return &self.resource_receiver;
        }

        pub fn audioImportReceiver(
            self: *@This(),
        ) *AudioReceiver {
            return &self.audio_receiver;
        }

        pub fn guiTelemetryLoad(
            _: *@This(),
            source_id: u32,
        ) f64 {
            return @floatFromInt(source_id);
        }

        pub fn guiGraphLoad(
            _: *@This(),
            source_id: u32,
            output: []plug_core.gui_graph.Point,
        ) usize {
            if (output.len == 0) return 0;
            output[0] = .{
                .x = @floatFromInt(source_id),
                .y = 0.25,
            };
            return 1;
        }

        pub fn guiTelemetryLoadText(
            _: *@This(),
            _: u32,
            output: []u8,
        ) usize {
            if (output.len < 7) return 0;
            @memcpy(output[0..7], "payload");
            return 7;
        }

        pub fn guiTelemetryEditorOpened(self: *@This()) void {
            self.editor_open_count += 1;
        }

        pub fn guiTelemetryEditorClosed(self: *@This()) void {
            self.editor_close_count += 1;
        }
    };
    const Configuration = struct {
        pub const component_name = "PayloadAdapterComponent";
        pub const controller_cid = tuid.inlineUid(
            0x66421F3A,
            0x95D14B31,
            0xAF243D5A,
            0xD6FB56A1,
        );
        pub const resource_path_target_id: u32 = 17;
        pub const audio_import_target_id: u32 = 19;
    };
    const Effect = HighLevelEffect(Plugin, Configuration);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(
            component_out orelse return error.MissingComponent,
        ));
    defer _ = component.vtable.release(component);
    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &ivstmessage.iconnection_point_iid,
            &connection_out,
        ),
    );
    const connection: *ivstmessage.IConnectionPoint =
        @ptrCast(@alignCast(
            connection_out orelse return error.MissingConnection,
        ));
    defer _ = connection.vtable.release(connection);

    try std.testing.expectEqual(
        types.kResultOk,
        resource_path_transport.sendImport(
            connection,
            17,
            "model.fixture",
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        gui_ir_transport.sendClear(connection, 19, 23),
    );
    const plugin = &Effect.processorInstance(component)
        .runtime.instance.plugin;
    try std.testing.expectEqualStrings(
        "model.fixture",
        plugin.resource_receiver
            .imported[0..plugin.resource_receiver.imported_length],
    );
    try std.testing.expectEqual(
        @as(u64, 23),
        plugin.audio_receiver.cleared_generation,
    );

    const telemetry =
        gui_telemetry_source.query(component) orelse
        return error.MissingTelemetry;
    defer telemetry.release();
    try std.testing.expectEqual(@as(f64, 5), telemetry.load(5));
    var graph: [1]plug_core.gui_graph.Point = undefined;
    try std.testing.expectEqual(
        @as(usize, 1),
        telemetry.loadGraph(7, &graph),
    );
    try std.testing.expectEqual(
        plug_core.gui_graph.Point{ .x = 7, .y = 0.25 },
        graph[0],
    );
    var text: [7]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 7),
        telemetry.loadText(3, &text),
    );
    try std.testing.expectEqualStrings("payload", &text);
    telemetry.editorOpened();
    telemetry.editorClosed();
    try std.testing.expectEqual(
        @as(usize, 1),
        plugin.editor_open_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        plugin.editor_close_count,
    );
}

test "high-level effect derives metadata and configured parameters" {
    const Plugin = struct {
        pub const name = "Configured High-Level Effect";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plug_core.plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: plug_core.plugin.AudioBusLayout = .surround_5_1;
        pub const event_input = false;
        pub const Params = struct {
            enabled: plug_core.parameters.BoolParam = .{
                .id = 0,
                .name = "Enabled",
                .default = false,
            },
        };
    };
    const Configuration = struct {
        pub const component_name =
            "ConfiguredHighLevelComponent";
        pub const controller_cid = tuid.inlineUid(
            0xD71371CE,
            0x357D49A6,
            0xA6CCB501,
            0x588D88E7,
        );
        pub const params = Plugin.Params{
            .enabled = .{
                .id = 0,
                .name = "Enabled",
                .default = true,
            },
        };
    };
    const Effect = HighLevelEffectWithParameters(
        Plugin,
        Configuration.params,
        Configuration,
    );

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *ivstcomponent.IComponent =
        @ptrCast(@alignCast(
            component_out orelse return error.MissingComponent,
        ));
    defer _ = component.vtable.release(component);

    try std.testing.expectEqual(
        types.kInvalidArgument,
        component.vtable.getControllerClassId(component, null),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        component.vtable.getBusInfo(
            component,
            @intFromEnum(ivstcomponent.MediaTypes.kAudio),
            @intFromEnum(ivstcomponent.BusDirections.kInput),
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        types.kNoInterface,
        component.vtable.getRoutingInfo(component, null, null),
    );
    try std.testing.expectEqual(
        @as(types.int32, 1),
        component.vtable.getBusCount(
            component,
            @intFromEnum(ivstcomponent.MediaTypes.kAudio),
            @intFromEnum(ivstcomponent.BusDirections.kInput),
        ),
    );
    var output_info: ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.getBusInfo(
            component,
            @intFromEnum(ivstcomponent.MediaTypes.kAudio),
            @intFromEnum(ivstcomponent.BusDirections.kOutput),
            0,
            &output_info,
        ),
    );
    try std.testing.expectEqual(
        @as(types.int32, 6),
        output_info.channelCount,
    );
    try std.testing.expectEqual(
        @as(f64, 1.0),
        Effect.processorInstance(component)
            .runtime.instance.parameterView()
            .loadNormalized("enabled"),
    );
}

pub fn HighLevelEditController(
    comptime Plugin: type,
    comptime declared_controller_name: []const u8,
) type {
    return HighLevelEditControllerWithParameters(
        Plugin,
        .{},
        declared_controller_name,
    );
}

pub fn HighLevelEditControllerWithParameters(
    comptime Plugin: type,
    comptime params: Plugin.Params,
    comptime declared_controller_name: []const u8,
) type {
    const Spec = plug_core.plugin.PluginSpec(Plugin);

    return ReflectedEditController(struct {
        pub const controller_name = declared_controller_name;
        pub const Params = Spec.Params;
        pub const owned_parameter_set =
            Spec.ParameterSet.init(params);
        pub const parameter_set = &owned_parameter_set;
    });
}

pub fn SimpleStereoEffect(comptime Config: type) type {
    return SimpleEffect(Config);
}

pub fn HighLevelEffect(
    comptime Plugin: type,
    comptime Config: type,
) type {
    return HighLevelEffectWithParameters(Plugin, .{}, Config);
}

pub fn HighLevelEffectWithParameters(
    comptime Plugin: type,
    comptime params: Plugin.Params,
    comptime Config: type,
) type {
    const Spec = plug_core.plugin.PluginSpec(Plugin);

    return SimpleEffect(struct {
        pub const component_name = Config.component_name;
        pub const controller_cid = Config.controller_cid;
        pub const dynamic_audio_bus_topology =
            Spec.dynamic_audio_bus_topology;
        pub const maximum_auxiliary_audio_buses =
            Spec.auxiliary_audio_bus_capacity;
        pub const audio_input_layout = Spec.audio_input_layout;
        pub const audio_output_layout = Spec.audio_output_layout;
        pub const audio_auxiliary_input_layouts =
            Spec.audio_auxiliary_input_layouts;
        pub const audio_auxiliary_output_layouts =
            Spec.audio_auxiliary_output_layouts;
        pub const event_input = Spec.event_input;
        pub const event_output = Spec.event_output;
        pub const follow_host_transport =
            Spec.follow_host_transport;
        pub const gui_note_input =
            @hasDecl(Config, "gui_note_input") and
            Config.gui_note_input;
        pub const process_context_requirements =
            if (@hasDecl(Config, "process_context_requirements"))
                Config.process_context_requirements
            else
                0;
        pub const Params = Spec.Params;
        pub const owned_parameter_set =
            Spec.ParameterSet.init(params);
        pub const parameter_set = &owned_parameter_set;
        pub const Processor =
            zig_vst3_plugin_runtime_adapter.ProcessorWithParameters(
                Plugin,
                params,
            );
        pub const ara_enabled = @hasDecl(Config, "AraExtension");
        pub const AraExtension = if (ara_enabled)
            Config.AraExtension
        else
            struct {};
        pub const AraEntryPoint = if (ara_enabled)
            Config.AraEntryPoint
        else
            struct {};
        pub const ara_factory: *const ara_vst3.Factory =
            if (ara_enabled)
                Config.ara_factory
            else
                @ptrFromInt(1);
        pub fn initAraExtension(
            processor: *Processor,
        ) AraExtension {
            if (comptime ara_enabled)
                return Config.initAraExtension(processor);
            return .{};
        }
        pub fn bindAraExtension(
            processor: *Processor,
            extension: *AraExtension,
        ) void {
            if (comptime ara_enabled and
                @hasDecl(Config, "bindAraExtension"))
                Config.bindAraExtension(processor, extension);
        }
        pub fn unbindAraExtension(
            processor: *Processor,
            extension: *AraExtension,
        ) void {
            if (comptime ara_enabled and
                @hasDecl(Config, "unbindAraExtension"))
                Config.unbindAraExtension(processor, extension);
        }
        pub const resource_path_target_id: ?u32 =
            if (@hasDecl(Config, "resource_path_target_id"))
                Config.resource_path_target_id
            else
                null;
        pub const audio_import_target_id: ?u32 =
            if (@hasDecl(Config, "audio_import_target_id"))
                Config.audio_import_target_id
            else
                null;
    });
}

pub fn SimpleEffect(comptime Config: type) type {
    return struct {
        const ara_enabled =
            if (@hasDecl(Config, "ara_enabled"))
                Config.ara_enabled
            else
                @hasDecl(Config, "AraExtension");
        const AraExtension = if (ara_enabled)
            Config.AraExtension
        else
            struct {};
        const AraEntryPoint = if (ara_enabled)
            Config.AraEntryPoint
        else
            struct {};
        const Params = if (@hasDecl(Config, "Params")) Config.Params else struct {};
        const DefaultParameterSet = plug_core.parameters.ParameterSet(Params);
        const default_parameter_set = DefaultParameterSet.init(.{});
        const parameter_set = if (@hasDecl(Config, "parameter_set")) Config.parameter_set else &default_parameter_set;
        const ParameterState = zig_vst3_plugin_bridge.ParameterState(Params);
        const processor_component_state =
            @hasDecl(
                Config.Processor,
                "component_state_maximum_encoded_size",
            ) and
            Config.Processor.component_state_maximum_encoded_size != 0;
        const event_output = @hasDecl(Config, "event_output") and Config.event_output;
        const event_input = !@hasDecl(Config, "event_input") or Config.event_input;
        const gui_note_input = @hasDecl(Config, "gui_note_input") and Config.gui_note_input;
        const resource_path_target_id: ?u32 =
            if (@hasDecl(Config, "resource_path_target_id"))
                Config.resource_path_target_id
            else
                null;
        const audio_import_target_id: ?u32 =
            if (@hasDecl(Config, "audio_import_target_id"))
                Config.audio_import_target_id
            else
                null;
        const processor_resource_path_receiver =
            if (@hasDecl(
                Config.Processor,
                "hasResourcePathReceiver",
            ))
                Config.Processor.hasResourcePathReceiver
            else
                @hasDecl(Config.Processor, "resourcePathReceiver");
        const processor_audio_import_receiver =
            if (@hasDecl(
                Config.Processor,
                "hasAudioImportReceiver",
            ))
                Config.Processor.hasAudioImportReceiver
            else
                @hasDecl(Config.Processor, "audioImportReceiver");
        const processor_gui_telemetry_load =
            if (@hasDecl(Config.Processor, "hasGuiTelemetryLoad"))
                Config.Processor.hasGuiTelemetryLoad
            else
                @hasDecl(Config.Processor, "guiTelemetryLoad");
        const processor_gui_graph_load =
            if (@hasDecl(Config.Processor, "hasGuiGraphLoad"))
                Config.Processor.hasGuiGraphLoad
            else
                @hasDecl(Config.Processor, "guiGraphLoad");
        const processor_gui_telemetry_load_text =
            if (@hasDecl(
                Config.Processor,
                "hasGuiTelemetryLoadText",
            ))
                Config.Processor.hasGuiTelemetryLoadText
            else
                @hasDecl(Config.Processor, "guiTelemetryLoadText");
        const processor_gui_editor_opened =
            if (@hasDecl(
                Config.Processor,
                "hasGuiTelemetryEditorOpened",
            ))
                Config.Processor.hasGuiTelemetryEditorOpened
            else
                @hasDecl(
                    Config.Processor,
                    "guiTelemetryEditorOpened",
                );
        const processor_gui_editor_closed =
            if (@hasDecl(
                Config.Processor,
                "hasGuiTelemetryEditorClosed",
            ))
                Config.Processor.hasGuiTelemetryEditorClosed
            else
                @hasDecl(
                    Config.Processor,
                    "guiTelemetryEditorClosed",
                );
        const audio_input_layout: plug_core.plugin.AudioBusLayout = if (@hasDecl(Config, "audio_input_layout"))
            Config.audio_input_layout
        else if (!@hasDecl(Config, "audio_input") or Config.audio_input)
            .stereo
        else
            .none;
        const audio_output_layout: plug_core.plugin.AudioBusLayout = if (@hasDecl(Config, "audio_output_layout"))
            Config.audio_output_layout
        else if (!@hasDecl(Config, "audio_output") or Config.audio_output)
            .stereo
        else
            .none;
        const audio_input = audio_input_layout.hasBus();
        const audio_output = audio_output_layout.hasBus();
        const audio_sidechain_layout: plug_core.plugin.AudioBusLayout = if (@hasDecl(Config, "audio_sidechain_layout"))
            Config.audio_sidechain_layout
        else
            .none;
        const audio_auxiliary_input_layouts: []const plug_core.plugin.AudioBusLayout = if (@hasDecl(Config, "audio_auxiliary_input_layouts"))
            Config.audio_auxiliary_input_layouts
        else
            &.{};
        const audio_auxiliary_output_layout: plug_core.plugin.AudioBusLayout = if (@hasDecl(Config, "audio_auxiliary_output_layout"))
            Config.audio_auxiliary_output_layout
        else
            .none;
        const audio_auxiliary_output_layouts: []const plug_core.plugin.AudioBusLayout = if (@hasDecl(Config, "audio_auxiliary_output_layouts"))
            Config.audio_auxiliary_output_layouts
        else
            &.{};
        const bus_config = zig_vst3_plugin_bridge.StereoAudioBuses.Config{
            .audio_input = audio_input,
            .audio_output = audio_output,
            .audio_input_layout = audio_input_layout,
            .audio_output_layout = audio_output_layout,
            .audio_sidechain_layout = audio_sidechain_layout,
            .audio_auxiliary_input_layouts = audio_auxiliary_input_layouts,
            .audio_auxiliary_output_layout = audio_auxiliary_output_layout,
            .audio_auxiliary_output_layouts = audio_auxiliary_output_layouts,
            .event_input = event_input,
            .event_output = event_output,
        };
        const AudioBusTopology =
            if (@hasDecl(Config, "audio_bus_topology"))
                optionalChildOrSelf(
                    @TypeOf(Config.audio_bus_topology),
                )
            else if (@hasDecl(Config, "dynamic_audio_bus_topology"))
                optionalChildOrSelf(
                    @TypeOf(Config.dynamic_audio_bus_topology),
                )
            else if (@hasDecl(
                Config,
                "maximum_auxiliary_audio_buses",
            ))
                plug_core.plugin.BoundedDynamicAudioBusTopology(
                    Config.maximum_auxiliary_audio_buses,
                )
            else
                plug_core.plugin.DynamicAudioBusTopology;
        const AudioBusSnapshot = AudioBusTopology.SnapshotType;
        const auxiliary_audio_bus_capacity =
            AudioBusTopology.auxiliary_capacity;
        const declared_audio_bus_topology: ?AudioBusTopology =
            if (@hasDecl(Config, "audio_bus_topology"))
                Config.audio_bus_topology
            else if (@hasDecl(Config, "dynamic_audio_bus_topology"))
                Config.dynamic_audio_bus_topology
            else
                null;
        const dynamic_audio_buses =
            declared_audio_bus_topology != null;
        const initial_audio_bus_topology: AudioBusTopology =
            declared_audio_bus_topology orelse fixedAudioBusTopology();
        const initial_audio_bus_snapshot =
            initial_audio_bus_topology.snapshot() catch
                @compileError("invalid initial audio bus topology");
        const AudioBusSnapshotPublisher =
            plug_core.dsp.RealtimeSnapshotPublisher(
                AudioBusSnapshot,
            );
        const declared_process_context_requirements: types.uint32 =
            if (@hasDecl(Config, "process_context_requirements"))
                Config.process_context_requirements
            else
                0;
        const host_transport_requirements: types.uint32 =
            if (@hasDecl(Config, "follow_host_transport") and
            Config.follow_host_transport)
                ivstaudioprocessor.ProcessContextRequirementFlags.kNeedProjectTimeMusic |
                    ivstaudioprocessor.ProcessContextRequirementFlags.kNeedBarPositionMusic |
                    ivstaudioprocessor.ProcessContextRequirementFlags.kNeedCycleMusic |
                    ivstaudioprocessor.ProcessContextRequirementFlags.kNeedTempo |
                    ivstaudioprocessor.ProcessContextRequirementFlags.kNeedTimeSignature |
                    ivstaudioprocessor.ProcessContextRequirementFlags.kNeedTransportState
            else
                0;
        const process_context_requirements =
            declared_process_context_requirements |
            host_transport_requirements;

        comptime {
            if (ara_enabled and
                (!@hasDecl(Config, "AraExtension") or
                    !@hasDecl(Config, "AraEntryPoint") or
                    !@hasDecl(Config, "ara_factory") or
                    !@hasDecl(Config, "initAraExtension")))
                @compileError(
                    "ARA effects require AraExtension, AraEntryPoint, ara_factory, and initAraExtension",
                );
            if (@hasDecl(Config, "audio_input") and Config.audio_input != audio_input_layout.hasBus()) {
                @compileError("audio_input_layout conflicts with audio_input");
            }
            if (@hasDecl(Config, "audio_output") and Config.audio_output != audio_output_layout.hasBus()) {
                @compileError("audio_output_layout conflicts with audio_output");
            }
            if (audio_sidechain_layout.hasBus() and !audio_input_layout.hasBus()) {
                @compileError("audio_sidechain_layout requires a main audio input bus");
            }
            if (@hasDecl(Config, "audio_auxiliary_input_layouts") and @hasDecl(Config, "audio_sidechain_layout")) {
                @compileError("audio_auxiliary_input_layouts conflicts with audio_sidechain_layout");
            }
            if (audio_auxiliary_input_layouts.len > auxiliary_audio_bus_capacity) {
                @compileError("too many auxiliary audio input buses");
            }
            for (audio_auxiliary_input_layouts) |layout| {
                if (!layout.hasBus()) {
                    @compileError("auxiliary audio input bus layouts cannot be none");
                }
            }
            if (audio_auxiliary_input_layouts.len != 0 and !audio_input_layout.hasBus()) {
                @compileError("audio_auxiliary_input_layouts requires a main audio input bus");
            }
            if (audio_auxiliary_output_layout.hasBus() and !audio_output_layout.hasBus()) {
                @compileError("audio_auxiliary_output_layout requires a main audio output bus");
            }
            if (@hasDecl(Config, "audio_auxiliary_output_layouts") and @hasDecl(Config, "audio_auxiliary_output_layout")) {
                @compileError("audio_auxiliary_output_layouts conflicts with audio_auxiliary_output_layout");
            }
            if (audio_auxiliary_output_layouts.len > auxiliary_audio_bus_capacity) {
                @compileError("too many auxiliary audio output buses");
            }
            for (audio_auxiliary_output_layouts) |layout| {
                if (!layout.hasBus()) {
                    @compileError("auxiliary audio output bus layouts cannot be none");
                }
            }
            if (audio_auxiliary_output_layouts.len != 0 and !audio_output_layout.hasBus()) {
                @compileError("audio_auxiliary_output_layouts requires a main audio output bus");
            }
            if (gui_note_input and !event_input) {
                @compileError("gui_note_input requires an event input bus");
            }
            if (!initial_audio_bus_topology.valid()) {
                @compileError("audio_bus_topology must be valid");
            }
        }

        fn fixedAudioBusTopology() AudioBusTopology {
            var topology = AudioBusTopology{};
            if (audio_input_layout.hasBus()) {
                topology.input_buses[0] =
                    plug_core.plugin.DynamicAudioBus.fixed(
                        audio_input_layout,
                        true,
                    ) catch @compileError("invalid main audio input layout");
                topology.input_count = 1;
                for (0..bus_config.auxiliaryInputCount()) |index| {
                    const layout =
                        bus_config.auxiliaryInputLayout(index) orelse
                        @compileError("invalid auxiliary audio input index");
                    topology.input_buses[topology.input_count] =
                        plug_core.plugin.DynamicAudioBus.fixed(
                            layout,
                            false,
                        ) catch @compileError("invalid auxiliary audio input layout");
                    topology.input_count += 1;
                }
            }
            if (audio_output_layout.hasBus()) {
                topology.output_buses[0] =
                    plug_core.plugin.DynamicAudioBus.fixed(
                        audio_output_layout,
                        true,
                    ) catch @compileError("invalid main audio output layout");
                topology.output_count = 1;
                for (0..bus_config.auxiliaryOutputCount()) |index| {
                    const layout =
                        bus_config.auxiliaryOutputLayoutAt(index) orelse
                        @compileError("invalid auxiliary audio output index");
                    topology.output_buses[topology.output_count] =
                        plug_core.plugin.DynamicAudioBus.fixed(
                            layout,
                            false,
                        ) catch @compileError("invalid auxiliary audio output layout");
                    topology.output_count += 1;
                }
            }
            return topology;
        }

        const Component = struct {
            iface: ivstcomponent.IComponent = .{ .vtable = &component_vtable },
            connection_point: ivstmessage.IConnectionPoint = .{ .vtable = &component_connection_point_vtable },
            processor: ivstaudioprocessor.IAudioProcessor = .{ .vtable = &processor_vtable },
            process_context_requirements: ivstaudioprocessor.IProcessContextRequirements = .{ .vtable = &process_context_requirements_vtable },
            audio_presentation_latency: ivstaudioprocessor.IAudioPresentationLatency = .{ .vtable = &audio_presentation_latency_vtable },
            plug_interface_support: ivstpluginterfacesupport.IPlugInterfaceSupport = .{ .vtable = &plug_interface_support_vtable },
            prefetchable_support: ivstprefetchablesupport.IPrefetchableSupport = .{ .vtable = &prefetchable_support_vtable },
            data_exchange_receiver: ivstdataexchange.IDataExchangeReceiver = .{ .vtable = &data_exchange_receiver_vtable },
            telemetry_source: gui_telemetry_source.Interface = .{ .vtable = &telemetry_source_vtable },
            ara_extension: AraExtension = undefined,
            ara_entry_point: AraEntryPoint = undefined,
            connected_peer: ?*ivstmessage.IConnectionPoint = null,
            connected_peer_mutex: std.Io.Mutex = .init,
            audio_bus_topology_mutex: std.Io.Mutex = .init,
            audio_bus_topology: AudioBusTopology =
                initial_audio_bus_topology,
            audio_bus_snapshots: AudioBusSnapshotPublisher = undefined,
            pending_host_changes: std.atomic.Value(u16) =
                std.atomic.Value(u16).init(0),
            host_request_sink: HostRequestSink = undefined,
            host_application: ?*ivsthostapplication.IHostApplication = null,
            info_listener: ?*ivstchannelcontextinfo.IInfoListener = null,
            automation_state: ?*ivstautomationstate.IAutomationState = null,
            data_exchange_handler: ?*ivstdataexchange.IDataExchangeHandler = null,
            parameter_state: ParameterState,
            processor_impl: Config.Processor,
            gui_notes: gui_note_transport.Mailbox = .{},
            gui_note_seen: [128]u64 = @splat(0),
            sample_rate: f64 = 0,
            component_active: bool = false,
            allocator: std.mem.Allocator,
            ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

            fn init(
                self: *Component,
                allocator: std.mem.Allocator,
            ) !void {
                self.* = .{
                    .parameter_state = ParameterState.init(parameter_set),
                    .processor_impl = undefined,
                    .allocator = allocator,
                };
                self.audio_bus_snapshots =
                    AudioBusSnapshotPublisher.init(
                        initial_audio_bus_snapshot,
                    );
                if (@hasDecl(
                    Config.Processor,
                    "initInPlaceWithAllocator",
                )) {
                    try self.processor_impl.initInPlaceWithAllocator(
                        allocator,
                    );
                } else if (@hasDecl(Config.Processor, "initWithAllocator")) {
                    self.processor_impl = try Config.Processor.initWithAllocator(
                        allocator,
                    );
                } else if (@hasDecl(Config.Processor, "initInPlace")) {
                    self.processor_impl.initInPlace();
                } else if (@hasDecl(Config.Processor, "init")) {
                    self.processor_impl = Config.Processor.init();
                } else {
                    self.processor_impl = .{};
                }
                if (comptime ara_enabled) {
                    self.ara_extension =
                        Config.initAraExtension(
                            &self.processor_impl,
                        );
                    if (@hasDecl(
                        AraExtension,
                        "initializeInPlace",
                    )) {
                        self.ara_extension.initializeInPlace();
                    }
                    if (@hasDecl(Config, "bindAraExtension")) {
                        Config.bindAraExtension(
                            &self.processor_impl,
                            &self.ara_extension,
                        );
                    }
                    self.ara_entry_point =
                        AraEntryPoint.initDelegated(
                            &self.ara_extension,
                            Config.ara_factory,
                            .{
                                .context = self,
                                .query = araIdentityQuery,
                                .add_ref = araIdentityAddRef,
                                .release = araIdentityRelease,
                            },
                        );
                }
                self.host_request_sink = .{
                    .context = self,
                    .mark_change = markHostChangeRequest,
                    .set_audio_bus_layout = setAudioBusLayoutRequest,
                    .add_auxiliary_audio_bus = addAuxiliaryAudioBusRequest,
                    .remove_auxiliary_audio_bus = removeAuxiliaryAudioBusRequest,
                    .dispatch = dispatchHostRequestsRequest,
                };
                if (@hasDecl(Config.Processor, "bindHostRequests")) {
                    self.processor_impl.bindHostRequests(&self.host_request_sink);
                }
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
            const component = allocator.create(Component) catch
                return types.kResultFalse;
            component.init(allocator) catch {
                allocator.destroy(component);
                return types.kResultFalse;
            };
            const result = query(&component.iface, @ptrCast(requested_iid), out);
            _ = release(&component.iface);
            return result;
        }

        pub fn getParameterNormalized(iface: *ivstcomponent.IComponent, id: vsttypes.ParamID) vsttypes.ParamValue {
            return owner(iface).parameter_state.getNormalizedById(id);
        }

        pub fn setParameterNormalized(iface: *ivstcomponent.IComponent, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            return owner(iface).parameter_state.setNormalizedById(id, value);
        }

        pub fn processorInstance(iface: *ivstcomponent.IComponent) *Config.Processor {
            return &owner(iface).processor_impl;
        }

        pub fn markLatencyChanged(iface: *ivstcomponent.IComponent) void {
            markHostChange(owner(iface), .latency);
        }

        pub fn markIoChanged(iface: *ivstcomponent.IComponent) void {
            markHostChange(owner(iface), .audio_io);
        }

        pub fn markHostChanged(
            iface: *ivstcomponent.IComponent,
            change: plug_core.plugin.HostChange,
        ) void {
            markHostChange(owner(iface), change);
        }

        pub fn audioBusTopologySnapshot(
            iface: *ivstcomponent.IComponent,
            out: *AudioBusSnapshot,
        ) bool {
            if (!plug_core.realtime_audit.observe(.lock)) return false;
            const self = owner(iface);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            out.* = self.audio_bus_topology.snapshot() catch return false;
            return true;
        }

        pub fn setAudioBusLayout(
            iface: *ivstcomponent.IComponent,
            direction: plug_core.plugin.AudioBusDirection,
            index: usize,
            layout: plug_core.plugin.AudioBusLayout,
        ) bool {
            if (comptime !dynamic_audio_buses)
                return false;
            if (!plug_core.realtime_audit.observe(.lock)) return false;
            const self = owner(iface);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            var next = self.audio_bus_topology;
            const previous_generation = next.current_generation;
            _ = next.setLayout(direction, index, layout) catch return false;
            return publishPluginTopologyChange(
                self,
                next,
                previous_generation,
            );
        }

        pub fn addAuxiliaryAudioBus(
            iface: *ivstcomponent.IComponent,
            direction: plug_core.plugin.AudioBusDirection,
            bus_value: plug_core.plugin.DynamicAudioBus,
        ) bool {
            if (comptime !dynamic_audio_buses)
                return false;
            if (!plug_core.realtime_audit.observe(.lock)) return false;
            const self = owner(iface);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            var next = self.audio_bus_topology;
            const previous_generation = next.current_generation;
            _ = next.addAuxiliary(direction, bus_value) catch return false;
            return publishPluginTopologyChange(
                self,
                next,
                previous_generation,
            );
        }

        pub fn removeAuxiliaryAudioBus(
            iface: *ivstcomponent.IComponent,
            direction: plug_core.plugin.AudioBusDirection,
            auxiliary_index: usize,
        ) bool {
            if (comptime !dynamic_audio_buses)
                return false;
            if (!plug_core.realtime_audit.observe(.lock)) return false;
            const self = owner(iface);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            var next = self.audio_bus_topology;
            const previous_generation = next.current_generation;
            _ = next.removeAuxiliary(
                direction,
                auxiliary_index,
            ) catch return false;
            return publishPluginTopologyChange(
                self,
                next,
                previous_generation,
            );
        }

        pub fn dispatchHostRequests(iface: *ivstcomponent.IComponent) types.tresult {
            return dispatchPendingHostRequests(owner(iface));
        }

        pub fn setChannelContextInfos(iface: *ivstcomponent.IComponent, attributes: ?*ivstattributes.IAttributeList) types.tresult {
            const info_listener = owner(iface).info_listener orelse return types.kResultFalse;
            return info_listener.vtable.setChannelContextInfos(info_listener, attributes);
        }

        pub fn setAutomationState(iface: *ivstcomponent.IComponent, state: types.int32) types.tresult {
            const automation_state = owner(iface).automation_state orelse return types.kResultFalse;
            return automation_state.vtable.setAutomationState(automation_state, state);
        }

        pub fn openDataExchangeQueue(iface: *ivstcomponent.IComponent, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            if (block_size == 0 or num_blocks == 0) return failOpenedDataExchangeQueue(out, types.kInvalidArgument);
            const self = owner(iface);
            const handler = self.data_exchange_handler orelse {
                return failOpenedDataExchangeQueue(out, types.kResultFalse);
            };
            const result = handler.vtable.openQueue(handler, &self.processor, block_size, num_blocks, alignment, user_context_id, out);
            if (result != types.kResultOk) return failOpenedDataExchangeQueue(out, result);
            if (out.* == ivstdataexchange.InvalidDataExchangeQueueID) return failOpenedDataExchangeQueue(out, types.kResultFalse);
            return result;
        }

        pub fn closeDataExchangeQueue(iface: *ivstcomponent.IComponent, queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
            if (queue_id == ivstdataexchange.InvalidDataExchangeQueueID) return types.kInvalidArgument;
            const handler = owner(iface).data_exchange_handler orelse return types.kResultFalse;
            return handler.vtable.closeQueue(handler, queue_id);
        }

        pub fn lockDataExchangeBlock(iface: *ivstcomponent.IComponent, queue_id: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            if (queue_id == ivstdataexchange.InvalidDataExchangeQueueID) return failLockedDataExchangeBlock(block, types.kInvalidArgument);
            const handler = owner(iface).data_exchange_handler orelse {
                return failLockedDataExchangeBlock(block, types.kResultFalse);
            };
            const result = handler.vtable.lockBlock(handler, queue_id, block);
            if (result != types.kResultOk) return failLockedDataExchangeBlock(block, result);
            if (block.data == null or block.size == 0 or block.blockID == ivstdataexchange.InvalidDataExchangeBlockID) return failLockedDataExchangeBlock(block, types.kResultFalse);
            return result;
        }

        pub fn freeDataExchangeBlock(iface: *ivstcomponent.IComponent, queue_id: ivstdataexchange.DataExchangeQueueID, block_id: ivstdataexchange.DataExchangeBlockID, send_to_receiver: types.TBool) types.tresult {
            if (queue_id == ivstdataexchange.InvalidDataExchangeQueueID or block_id == ivstdataexchange.InvalidDataExchangeBlockID or send_to_receiver > 1) return types.kInvalidArgument;
            const handler = owner(iface).data_exchange_handler orelse return types.kResultFalse;
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

        const owner = interface_map.ownerFromField(Component, ivstcomponent.IComponent, "iface");
        const ownerFromProcessor = interface_map.ownerFromField(Component, ivstaudioprocessor.IAudioProcessor, "processor");
        const ownerFromComponentConnectionPoint = interface_map.ownerFromField(Component, ivstmessage.IConnectionPoint, "connection_point");
        const ownerFromProcessContextRequirements = interface_map.ownerFromField(Component, ivstaudioprocessor.IProcessContextRequirements, "process_context_requirements");
        const ownerFromAudioPresentationLatency = interface_map.ownerFromField(Component, ivstaudioprocessor.IAudioPresentationLatency, "audio_presentation_latency");
        const ownerFromPlugInterfaceSupport = interface_map.ownerFromField(Component, ivstpluginterfacesupport.IPlugInterfaceSupport, "plug_interface_support");
        const ownerFromPrefetchableSupport = interface_map.ownerFromField(Component, ivstprefetchablesupport.IPrefetchableSupport, "prefetchable_support");
        const ownerFromDataExchangeReceiver = interface_map.ownerFromField(Component, ivstdataexchange.IDataExchangeReceiver, "data_exchange_receiver");
        const ownerFromTelemetrySource = interface_map.ownerFromField(Component, gui_telemetry_source.Interface, "telemetry_source");

        fn markHostChangeRequest(
            context: *anyopaque,
            change: plug_core.plugin.HostChange,
        ) void {
            const self: *Component = @ptrCast(@alignCast(context));
            markHostChange(self, change);
        }

        fn setAudioBusLayoutRequest(
            context: *anyopaque,
            direction: plug_core.plugin.AudioBusDirection,
            index: usize,
            layout: plug_core.plugin.AudioBusLayout,
        ) bool {
            const self: *Component = @ptrCast(@alignCast(context));
            return setAudioBusLayout(
                &self.iface,
                direction,
                index,
                layout,
            );
        }

        fn addAuxiliaryAudioBusRequest(
            context: *anyopaque,
            direction: plug_core.plugin.AudioBusDirection,
            bus_value: plug_core.plugin.DynamicAudioBus,
        ) bool {
            const self: *Component = @ptrCast(@alignCast(context));
            return addAuxiliaryAudioBus(
                &self.iface,
                direction,
                bus_value,
            );
        }

        fn removeAuxiliaryAudioBusRequest(
            context: *anyopaque,
            direction: plug_core.plugin.AudioBusDirection,
            auxiliary_index: usize,
        ) bool {
            const self: *Component = @ptrCast(@alignCast(context));
            return removeAuxiliaryAudioBus(
                &self.iface,
                direction,
                auxiliary_index,
            );
        }

        fn publishPluginTopologyChange(
            self: *Component,
            next: AudioBusTopology,
            previous_generation: u64,
        ) bool {
            if (next.current_generation == previous_generation)
                return true;
            const snapshot = next.snapshot() catch return false;
            _ = self.audio_bus_snapshots.publish(snapshot) catch
                return false;
            self.audio_bus_topology = next;
            markHostChange(self, .audio_io);
            return true;
        }

        fn dispatchHostRequestsRequest(context: *anyopaque) bool {
            const self: *Component = @ptrCast(@alignCast(context));
            return dispatchPendingHostRequests(self) == types.kResultOk;
        }

        fn dispatchPendingHostRequests(self: *Component) types.tresult {
            const pending =
                self.pending_host_changes.swap(0, .acq_rel);
            if (pending == 0) return types.kResultOk;
            const peer = retainComponentConnectionPeer(self) orelse {
                _ = self.pending_host_changes.fetchOr(
                    pending,
                    .release,
                );
                return types.kResultFalse;
            };
            defer _ = peer.vtable.release(peer);
            const flags = hostRestartFlags(pending);
            const result = host_restart_transport.send(peer, flags);
            if (result != types.kResultOk)
                _ = self.pending_host_changes.fetchOr(
                    pending,
                    .release,
                );
            return result;
        }

        fn markHostChange(
            self: *Component,
            change: plug_core.plugin.HostChange,
        ) void {
            _ = self.pending_host_changes.fetchOr(
                hostChangeBit(change),
                .release,
            );
        }

        fn hostChangeBit(
            change: plug_core.plugin.HostChange,
        ) u16 {
            return @as(u16, 1) << @intFromEnum(change);
        }

        fn hostRestartFlags(pending: u16) types.int32 {
            var flags: types.int32 = 0;
            inline for (std.meta.fields(
                plug_core.plugin.HostChange,
            )) |field| {
                const change: plug_core.plugin.HostChange =
                    @enumFromInt(field.value);
                if (pending & hostChangeBit(change) != 0)
                    flags |= hostRestartFlag(change);
            }
            return flags;
        }

        fn hostRestartFlag(
            change: plug_core.plugin.HostChange,
        ) types.int32 {
            return switch (change) {
                .component_reload => ivsteditcontroller.RestartFlags.kReloadComponent,
                .audio_io => ivsteditcontroller.RestartFlags.kIoChanged,
                .parameter_values => ivsteditcontroller.RestartFlags.kParamValuesChanged,
                .latency => ivsteditcontroller.RestartFlags.kLatencyChanged,
                .parameter_titles => ivsteditcontroller.RestartFlags.kParamTitlesChanged,
                .midi_cc_assignments => ivsteditcontroller.RestartFlags
                    .kMidiCCAssignmentChanged,
                .note_expression => ivsteditcontroller.RestartFlags
                    .kNoteExpressionChanged,
                .io_titles => ivsteditcontroller.RestartFlags.kIoTitlesChanged,
                .prefetchable_support => ivsteditcontroller.RestartFlags
                    .kPrefetchableSupportChanged,
                .routing_info => ivsteditcontroller.RestartFlags.kRoutingInfoChanged,
                .keyswitches => ivsteditcontroller.RestartFlags.kKeyswitchChanged,
                .parameter_id_mapping => ivsteditcontroller.RestartFlags
                    .kParamIDMappingChanged,
            };
        }

        fn retainComponentConnectionPeer(self: *Component) ?*ivstmessage.IConnectionPoint {
            lockComponentPeer(self);
            defer unlockComponentPeer(self);
            return if (self.connected_peer) |peer| retainConnectionPeer(peer) else null;
        }

        fn releaseComponentConnectionPeer(self: *Component) void {
            lockComponentPeer(self);
            defer unlockComponentPeer(self);
            releaseConnectionPeer(&self.connected_peer);
        }

        fn lockComponentPeer(self: *Component) void {
            self.connected_peer_mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        }

        fn unlockComponentPeer(self: *Component) void {
            self.connected_peer_mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }

        fn lockAudioBusTopology(self: *Component) void {
            self.audio_bus_topology_mutex.lockUncancelable(
                std.Io.Threaded.global_single_threaded.io(),
            );
        }

        fn unlockAudioBusTopology(self: *Component) void {
            self.audio_bus_topology_mutex.unlock(
                std.Io.Threaded.global_single_threaded.io(),
            );
        }

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const base_entries = [_]interface_map.Entry{
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
            if (comptime processor_gui_telemetry_load or
                processor_gui_graph_load or
                processor_gui_telemetry_load_text)
            {
                if (comptime ara_enabled) {
                    const entries = base_entries ++
                        [_]interface_map.Entry{
                            .{
                                .iid = &gui_telemetry_source.iid,
                                .ptr = &self.telemetry_source,
                            },
                            .{
                                .iid = &ara_vst3.plug_in_entry_point_iid,
                                .ptr = self.ara_entry_point
                                    .asEntryPoint(),
                            },
                            .{
                                .iid = &ara_vst3.plug_in_entry_point_2_iid,
                                .ptr = self.ara_entry_point
                                    .asEntryPoint2(),
                            },
                        };
                    return interface_map.queryWithAddRef(
                        ptr,
                        addRef,
                        &entries,
                        requested_iid,
                        out,
                    );
                }
                const entries = base_entries ++ [_]interface_map.Entry{
                    interface_map.fieldEntry("telemetry_source", self, &gui_telemetry_source.iid),
                };
                return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
            }
            if (comptime ara_enabled) {
                const entries = base_entries ++
                    [_]interface_map.Entry{
                        .{
                            .iid = &ara_vst3.plug_in_entry_point_iid,
                            .ptr = self.ara_entry_point
                                .asEntryPoint(),
                        },
                        .{
                            .iid = &ara_vst3.plug_in_entry_point_2_iid,
                            .ptr = self.ara_entry_point
                                .asEntryPoint2(),
                        },
                    };
                return interface_map.queryWithAddRef(
                    ptr,
                    addRef,
                    &entries,
                    requested_iid,
                    out,
                );
            }
            return interface_map.queryWithAddRef(ptr, addRef, &base_entries, requested_iid, out);
        }

        fn araIdentityQuery(
            context: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            const self: *Component = @ptrCast(@alignCast(context));
            return query(
                &self.iface,
                requested_iid,
                out,
            );
        }

        fn araIdentityAddRef(
            context: *anyopaque,
        ) callconv(.c) types.uint32 {
            const self: *Component = @ptrCast(@alignCast(context));
            return addRef(&self.iface);
        }

        fn araIdentityRelease(
            context: *anyopaque,
        ) callconv(.c) types.uint32 {
            const self: *Component = @ptrCast(@alignCast(context));
            return release(&self.iface);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            const next = funknown.decrementRefCount(&self.ref_count, Config.component_name);
            if (next == 0) {
                _ = self.ref_count.load(.acquire);
                if (comptime ara_enabled and
                    @hasDecl(Config, "unbindAraExtension"))
                {
                    Config.unbindAraExtension(
                        &self.processor_impl,
                        &self.ara_extension,
                    );
                }
                if (comptime ara_enabled and
                    @hasDecl(AraExtension, "deinit"))
                {
                    self.ara_extension.deinit();
                }
                if (@hasDecl(Config.Processor, "deinit")) self.processor_impl.deinit();
                releaseComponentConnectionPeer(self);
                releaseDataExchangeHandler(&self.data_exchange_handler);
                releaseAutomationState(&self.automation_state);
                releaseInfoListener(&self.info_listener);
                releaseHostApplication(&self.host_application);
                self.allocator.destroy(self);
            }
            return next;
        }

        const ProcessorDelegate = interface_map.DelegatedInterface(Component, ownerFromProcessor, "iface", query, addRef, release);
        const ComponentConnectionPointDelegate = interface_map.DelegatedInterface(Component, ownerFromComponentConnectionPoint, "iface", query, addRef, release);
        const ProcessContextRequirementsDelegate = interface_map.DelegatedInterface(Component, ownerFromProcessContextRequirements, "iface", query, addRef, release);
        const AudioPresentationLatencyDelegate = interface_map.DelegatedInterface(Component, ownerFromAudioPresentationLatency, "iface", query, addRef, release);
        const PlugInterfaceSupportDelegate = interface_map.DelegatedInterface(Component, ownerFromPlugInterfaceSupport, "iface", query, addRef, release);
        const PrefetchableSupportDelegate = interface_map.DelegatedInterface(Component, ownerFromPrefetchableSupport, "iface", query, addRef, release);
        const DataExchangeReceiverDelegate = interface_map.DelegatedInterface(Component, ownerFromDataExchangeReceiver, "iface", query, addRef, release);
        const TelemetrySourceDelegate = interface_map.DelegatedInterface(Component, ownerFromTelemetrySource, "iface", query, addRef, release);

        const telemetry_source_vtable = gui_telemetry_source.VTable{
            .queryInterface = TelemetrySourceDelegate.query,
            .addRef = TelemetrySourceDelegate.addRef,
            .release = TelemetrySourceDelegate.release,
            .load = telemetryLoad,
            .editorOpened = telemetryEditorOpened,
            .editorClosed = telemetryEditorClosed,
            .loadGraph = telemetryLoadGraph,
            .loadText = telemetryLoadText,
        };

        fn telemetryLoad(ptr: *anyopaque, source_id: types.uint32) callconv(.c) f64 {
            const self = ownerFromTelemetrySource(ptr);
            if (comptime processor_gui_telemetry_load) {
                return self.processor_impl.guiTelemetryLoad(source_id);
            }
            return 0.0;
        }

        fn telemetryEditorOpened(ptr: *anyopaque) callconv(.c) void {
            if (comptime processor_gui_editor_opened) {
                ownerFromTelemetrySource(ptr).processor_impl.guiTelemetryEditorOpened();
            }
        }

        fn telemetryEditorClosed(ptr: *anyopaque) callconv(.c) void {
            if (comptime processor_gui_editor_closed) {
                ownerFromTelemetrySource(ptr).processor_impl.guiTelemetryEditorClosed();
            }
        }

        fn telemetryLoadGraph(
            ptr: *anyopaque,
            source_id: types.uint32,
            output_raw: [*c]plug_core.gui_graph.Point,
            capacity: types.uint32,
        ) callconv(.c) types.uint32 {
            if (output_raw == null) return 0;
            const output: [*]plug_core.gui_graph.Point = @ptrCast(output_raw);
            if (comptime processor_gui_graph_load) {
                const bounded_capacity = @min(capacity, gui_telemetry_source.maximum_graph_points);
                const count = ownerFromTelemetrySource(ptr).processor_impl.guiGraphLoad(source_id, output[0..bounded_capacity]);
                return @intCast(@min(count, bounded_capacity));
            }
            return 0;
        }

        fn telemetryLoadText(
            ptr: *anyopaque,
            source_id: types.uint32,
            output_raw: [*c]u8,
            capacity: types.uint32,
        ) callconv(.c) types.uint32 {
            if (output_raw == null) return 0;
            const output: [*]u8 = @ptrCast(output_raw);
            if (comptime processor_gui_telemetry_load_text) {
                const bounded_capacity = @min(capacity, gui_telemetry_source.maximum_text_bytes);
                const count = ownerFromTelemetrySource(ptr).processor_impl.guiTelemetryLoadText(source_id, output[0..bounded_capacity]);
                return @intCast(@min(count, bounded_capacity));
            }
            return 0;
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
            releaseComponentConnectionPeer(self);
            releaseDataExchangeHandler(&self.data_exchange_handler);
            releaseAutomationState(&self.automation_state);
            releaseInfoListener(&self.info_listener);
            releaseHostApplication(&self.host_application);
            return types.kResultOk;
        }

        fn getControllerClassId(_: *anyopaque, out: [*c]tuid.TUID) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            out[0] = Config.controller_cid;
            return types.kResultOk;
        }

        fn setIoMode(_: *anyopaque, _: vsttypes.IoMode) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        fn getBusCount(ptr: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) callconv(.c) types.int32 {
            const self = owner(ptr);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            const snapshot =
                self.audio_bus_topology.snapshot() catch return 0;
            const config =
                zig_vst3_plugin_bridge.StereoAudioBuses
                    .configFromSnapshot(
                    &snapshot,
                    event_input,
                    event_output,
                ) orelse return 0;
            return zig_vst3_plugin_bridge.StereoAudioBuses
                .busCountConfigured(media_type, direction, config);
        }

        fn getBusInfo(ptr: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: [*c]ivstcomponent.BusInfo) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            const output: *ivstcomponent.BusInfo = @ptrCast(out);
            const self = owner(ptr);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            const snapshot =
                self.audio_bus_topology.snapshot() catch {
                    output.* = .{};
                    return types.kInvalidArgument;
                };
            return zig_vst3_plugin_bridge.StereoAudioBuses
                .busInfoSnapshot(
                media_type,
                direction,
                index,
                output,
                &snapshot,
                event_input,
                event_output,
            );
        }

        fn getRoutingInfo(_: *anyopaque, _: [*c]ivstcomponent.RoutingInfo, _: [*c]ivstcomponent.RoutingInfo) callconv(.c) types.tresult {
            return types.kNoInterface;
        }

        fn activateBus(ptr: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, state: types.TBool) callconv(.c) types.tresult {
            if (state > 1) return types.kInvalidArgument;
            const self = owner(ptr);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            const snapshot =
                self.audio_bus_topology.snapshot() catch
                    return types.kInvalidArgument;
            const config =
                zig_vst3_plugin_bridge.StereoAudioBuses
                    .configFromSnapshot(
                    &snapshot,
                    event_input,
                    event_output,
                ) orelse return types.kInvalidArgument;
            if (media_type != @intFromEnum(ivstcomponent.MediaTypes.kAudio)) {
                return zig_vst3_plugin_bridge.StereoAudioBuses
                    .activateBusConfigured(
                    media_type,
                    direction,
                    index,
                    state,
                    config,
                );
            }
            const bus_direction: plug_core.plugin.AudioBusDirection =
                if (direction ==
                @intFromEnum(ivstcomponent.BusDirections.kInput))
                    .input
                else if (direction ==
                @intFromEnum(ivstcomponent.BusDirections.kOutput))
                    .output
                else
                    return types.kInvalidArgument;
            const bus_index =
                std.math.cast(usize, index) orelse
                return types.kInvalidArgument;
            var next = self.audio_bus_topology;
            const previous_generation = next.current_generation;
            _ = next.setActive(
                bus_direction,
                bus_index,
                state != 0,
            ) catch return types.kInvalidArgument;
            if (next.current_generation == previous_generation)
                return types.kResultOk;
            const next_snapshot =
                next.snapshot() catch return types.kInvalidArgument;
            _ = self.audio_bus_snapshots.publish(next_snapshot) catch
                return types.kResultFalse;
            self.audio_bus_topology = next;
            return types.kResultOk;
        }

        fn resetProcessState(self: *Component) void {
            if (@hasDecl(Config.Processor, "reset")) {
                self.processor_impl.reset();
            }
            self.gui_note_seen = @splat(0);
        }

        fn syncProcessorParameterValues(self: *Component) void {
            if (@hasDecl(Config.Processor, "syncParameterValues")) {
                self.processor_impl.syncParameterValues(
                    &self.parameter_state.values,
                );
            }
        }

        fn notifyProcessorStateRestore(self: *Component) void {
            syncProcessorParameterValues(self);
            if (@hasDecl(Config.Processor, "afterParameterStateRestore")) {
                self.processor_impl.afterParameterStateRestore();
            }
            if (@hasDecl(Config.Processor, "afterComponentStateRestore")) {
                self.processor_impl.afterComponentStateRestore();
            }
        }

        fn topologyContentEqual(
            left_value: AudioBusTopology,
            right_value: AudioBusTopology,
        ) bool {
            var left = left_value;
            var right = right_value;
            left.current_generation = 0;
            right.current_generation = 0;
            return std.meta.eql(left, right);
        }

        fn setActive(ptr: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            if (state > 1) return types.kInvalidArgument;
            const self = owner(ptr);
            const active = state != 0;
            if (active == self.component_active) {
                if (!active) resetProcessState(self);
                return types.kResultOk;
            }
            if (active) {
                if (comptime @hasDecl(Config.Processor, "activateChecked")) {
                    self.processor_impl.activateChecked() catch
                        return types.kResultFalse;
                } else if (comptime @hasDecl(Config.Processor, "activate")) {
                    self.processor_impl.activate();
                }
            } else {
                if (comptime @hasDecl(Config.Processor, "deactivateChecked")) {
                    self.processor_impl.deactivateChecked() catch
                        return types.kResultFalse;
                } else if (comptime @hasDecl(Config.Processor, "deactivate")) {
                    self.processor_impl.deactivate();
                } else {
                    resetProcessState(self);
                }
            }
            self.component_active = active;
            return types.kResultOk;
        }

        fn setState(ptr: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (comptime dynamic_audio_buses) {
                lockAudioBusTopology(self);
                defer unlockAudioBusTopology(self);
                var restored_topology = self.audio_bus_topology;
                const result = if (comptime processor_component_state)
                    zig_vst3_plugin_bridge
                        .readProcessorComponentStateWithTopology(
                        Params,
                        Config.Processor,
                        state,
                        parameter_set,
                        &self.parameter_state.values,
                        &self.processor_impl,
                        &restored_topology,
                    )
                else
                    zig_vst3_plugin_bridge
                        .readComponentParameterStateWithTopology(
                        Params,
                        state,
                        parameter_set,
                        &self.parameter_state.values,
                        &restored_topology,
                    );
                if (result != types.kResultOk) return result;
                if (!topologyContentEqual(
                    self.audio_bus_topology,
                    restored_topology,
                )) {
                    restored_topology.current_generation =
                        self.audio_bus_topology.current_generation;
                    restored_topology.current_generation +%= 1;
                    if (restored_topology.current_generation == 0)
                        restored_topology.current_generation = 1;
                    const snapshot =
                        restored_topology.snapshot() catch
                            return types.kResultFalse;
                    _ = self.audio_bus_snapshots.publish(snapshot) catch
                        return types.kResultFalse;
                    self.audio_bus_topology = restored_topology;
                    markHostChange(self, .audio_io);
                }
                notifyProcessorStateRestore(self);
                return types.kResultOk;
            }
            if (comptime processor_component_state) {
                const result = zig_vst3_plugin_bridge.readProcessorComponentState(
                    Params,
                    Config.Processor,
                    state,
                    parameter_set,
                    &self.parameter_state.values,
                    &self.processor_impl,
                );
                if (result == types.kResultOk)
                    notifyProcessorStateRestore(self);
                return result;
            }
            const result = self.parameter_state.readFromStream(state);
            if (result == types.kResultOk)
                notifyProcessorStateRestore(self);
            return result;
        }

        fn getState(ptr: *anyopaque, state: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (comptime dynamic_audio_buses) {
                lockAudioBusTopology(self);
                defer unlockAudioBusTopology(self);
                if (comptime processor_component_state) {
                    return zig_vst3_plugin_bridge
                        .writeProcessorComponentStateWithTopology(
                        Params,
                        Config.Processor,
                        state,
                        parameter_set,
                        &self.parameter_state.values,
                        &self.processor_impl,
                        &self.audio_bus_topology,
                    );
                }
                return zig_vst3_plugin_bridge
                    .writeComponentParameterStateWithTopology(
                    Params,
                    state,
                    parameter_set,
                    &self.parameter_state.values,
                    &self.audio_bus_topology,
                );
            }
            if (comptime processor_component_state) {
                return zig_vst3_plugin_bridge.writeProcessorComponentState(
                    Params,
                    Config.Processor,
                    state,
                    parameter_set,
                    &self.parameter_state.values,
                    &self.processor_impl,
                );
            }
            return self.parameter_state.writeToStream(state);
        }

        const processor_vtable = ivstaudioprocessor.IAudioProcessorVTable{
            .queryInterface = ProcessorDelegate.query,
            .addRef = ProcessorDelegate.addRef,
            .release = ProcessorDelegate.release,
            .setBusArrangements = setBusArrangements,
            .getBusArrangement = getBusArrangement,
            .canProcessSampleSize = canProcessSampleSize,
            .getLatencySamples = getLatencySamples,
            .setupProcessing = setupProcessing,
            .setProcessing = setProcessing,
            .process = process,
            .getTailSamples = getTailSamples,
        };

        const component_connection_point_vtable = ivstmessage.IConnectionPointVTable{
            .queryInterface = ComponentConnectionPointDelegate.query,
            .addRef = ComponentConnectionPointDelegate.addRef,
            .release = ComponentConnectionPointDelegate.release,
            .connect = componentConnect,
            .disconnect = componentDisconnect,
            .notify = componentNotify,
        };

        fn componentConnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromComponentConnectionPoint(ptr);
            lockComponentPeer(self);
            const result = replaceConnectionPeer(&self.connected_peer, peer);
            unlockComponentPeer(self);
            if (result == types.kResultOk and @hasDecl(Config.Processor, "componentConnectionReady")) {
                self.processor_impl.componentConnectionReady();
            }
            return result;
        }

        fn componentDisconnect(ptr: *anyopaque, peer: ?*ivstmessage.IConnectionPoint) callconv(.c) types.tresult {
            const self = ownerFromComponentConnectionPoint(ptr);
            lockComponentPeer(self);
            defer unlockComponentPeer(self);
            return disconnectConnectionPeer(&self.connected_peer, peer);
        }

        fn componentNotify(ptr: *anyopaque, message: ?*ivstmessage.IMessage) callconv(.c) types.tresult {
            const self = ownerFromComponentConnectionPoint(ptr);
            if (comptime resource_path_target_id != null and
                processor_resource_path_receiver)
            {
                const result = resource_path_transport.receive(
                    self.processor_impl.resourcePathReceiver(),
                    resource_path_target_id.?,
                    message,
                );
                if (result != types.kResultFalse) return result;
            }
            if (comptime audio_import_target_id != null and
                processor_audio_import_receiver)
            {
                const result = gui_ir_transport.receive(
                    self.processor_impl.audioImportReceiver(),
                    audio_import_target_id.?,
                    message,
                );
                if (result != types.kResultFalse) return result;
            }
            if (comptime gui_note_input) {
                return gui_note_transport.receive(&self.gui_notes, message);
            }
            return types.kResultFalse;
        }

        const process_context_requirements_vtable = ivstaudioprocessor.IProcessContextRequirementsVTable{
            .queryInterface = ProcessContextRequirementsDelegate.query,
            .addRef = ProcessContextRequirementsDelegate.addRef,
            .release = ProcessContextRequirementsDelegate.release,
            .getProcessContextRequirements = getProcessContextRequirements,
        };

        fn getProcessContextRequirements(_: *anyopaque) callconv(.c) types.uint32 {
            return process_context_requirements;
        }

        const audio_presentation_latency_vtable = ivstaudioprocessor.IAudioPresentationLatencyVTable{
            .queryInterface = AudioPresentationLatencyDelegate.query,
            .addRef = AudioPresentationLatencyDelegate.addRef,
            .release = AudioPresentationLatencyDelegate.release,
            .setAudioPresentationLatencySamples = setAudioPresentationLatencySamples,
        };

        fn setAudioPresentationLatencySamples(_: *anyopaque, _: vsttypes.BusDirection, _: types.int32, _: types.uint32) callconv(.c) types.tresult {
            return types.kResultOk;
        }

        const plug_interface_support_vtable = ivstpluginterfacesupport.IPlugInterfaceSupportVTable{
            .queryInterface = PlugInterfaceSupportDelegate.query,
            .addRef = PlugInterfaceSupportDelegate.addRef,
            .release = PlugInterfaceSupportDelegate.release,
            .isPlugInterfaceSupported = isPlugInterfaceSupported,
        };

        fn isPlugInterfaceSupported(_: *anyopaque, iid_raw: [*c]const tuid.TUID) callconv(.c) types.tresult {
            if (iid_raw == null) return types.kInvalidArgument;
            const iid = &iid_raw[0];
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
            .queryInterface = PrefetchableSupportDelegate.query,
            .addRef = PrefetchableSupportDelegate.addRef,
            .release = PrefetchableSupportDelegate.release,
            .getPrefetchableSupport = getPrefetchableSupport,
        };

        fn getPrefetchableSupport(_: *anyopaque, out: [*c]ivstprefetchablesupport.PrefetchableSupport) callconv(.c) types.tresult {
            if (out == null) return types.kInvalidArgument;
            out[0] = @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNeverPrefetchable);
            return types.kResultOk;
        }

        const data_exchange_receiver_vtable = ivstdataexchange.IDataExchangeReceiverVTable{
            .queryInterface = DataExchangeReceiverDelegate.query,
            .addRef = DataExchangeReceiverDelegate.addRef,
            .release = DataExchangeReceiverDelegate.release,
            .queueOpened = dataExchangeQueueOpened,
            .queueClosed = dataExchangeQueueClosed,
            .onDataExchangeBlocksReceived = onDataExchangeBlocksReceived,
        };

        fn dataExchangeQueueOpened(_: *anyopaque, user_context_id: ivstdataexchange.DataExchangeUserContextID, block_size: types.uint32, out_raw: [*c]types.TBool) callconv(.c) void {
            if (out_raw == null) return;
            const out: *types.TBool = @ptrCast(out_raw);
            out.* = 0;
            if (block_size == 0) return;
            if (@hasDecl(Config, "dataExchangeQueueOpened")) {
                out.* = @intFromBool(Config.dataExchangeQueueOpened(user_context_id, block_size) != 0);
            }
        }

        fn dataExchangeQueueClosed(_: *anyopaque, user_context_id: ivstdataexchange.DataExchangeUserContextID) callconv(.c) void {
            if (@hasDecl(Config, "dataExchangeQueueClosed")) {
                Config.dataExchangeQueueClosed(user_context_id);
            }
        }

        fn onDataExchangeBlocksReceived(_: *anyopaque, user_context_id: ivstdataexchange.DataExchangeUserContextID, num_blocks: types.uint32, blocks: ?[*]ivstdataexchange.DataExchangeBlock, on_background_thread: types.TBool) callconv(.c) void {
            if (@hasDecl(Config, "onDataExchangeBlocksReceived")) {
                if (on_background_thread > 1) return;
                if (num_blocks == 0) return;
                const received = blocks orelse return;
                for (received[0..@intCast(num_blocks)]) |block| {
                    if (block.data == null or block.size == 0 or block.blockID == ivstdataexchange.InvalidDataExchangeBlockID) return;
                }
                Config.onDataExchangeBlocksReceived(user_context_id, num_blocks, received, on_background_thread);
            }
        }

        fn setBusArrangements(ptr: *anyopaque, inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32) callconv(.c) types.tresult {
            const input_count =
                std.math.cast(usize, num_inputs) orelse
                return types.kResultFalse;
            const output_count =
                std.math.cast(usize, num_outputs) orelse
                return types.kResultFalse;
            const self = ownerFromProcessor(ptr);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            if (input_count != self.audio_bus_topology.input_count or
                output_count != self.audio_bus_topology.output_count)
                return types.kResultFalse;
            var input_layouts: [AudioBusTopology.bus_capacity]plug_core.plugin.AudioBusLayout = @splat(.none);
            var output_layouts: [AudioBusTopology.bus_capacity]plug_core.plugin.AudioBusLayout = @splat(.none);
            if (input_count != 0) {
                const values = inputs orelse return types.kResultFalse;
                for (values[0..input_count], 0..) |arrangement_value, index| {
                    input_layouts[index] =
                        zig_vst3_plugin_bridge.StereoAudioBuses
                            .layoutForSpeakerArrangement(
                            arrangement_value,
                        ) orelse return types.kResultFalse;
                }
            }
            if (output_count != 0) {
                const values = outputs orelse return types.kResultFalse;
                for (values[0..output_count], 0..) |arrangement_value, index| {
                    output_layouts[index] =
                        zig_vst3_plugin_bridge.StereoAudioBuses
                            .layoutForSpeakerArrangement(
                            arrangement_value,
                        ) orelse return types.kResultFalse;
                }
            }
            var next = self.audio_bus_topology;
            const previous_generation = next.current_generation;
            _ = next.setLayouts(
                input_layouts[0..input_count],
                output_layouts[0..output_count],
            ) catch return types.kResultFalse;
            if (next.current_generation == previous_generation)
                return types.kResultOk;
            const snapshot =
                next.snapshot() catch return types.kResultFalse;
            _ = self.audio_bus_snapshots.publish(snapshot) catch
                return types.kResultFalse;
            self.audio_bus_topology = next;
            return types.kResultOk;
        }

        fn getBusArrangement(ptr: *anyopaque, direction: vsttypes.BusDirection, index: types.int32, out_raw: [*c]vsttypes.SpeakerArrangement) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *vsttypes.SpeakerArrangement = @ptrCast(out_raw);
            const self = ownerFromProcessor(ptr);
            lockAudioBusTopology(self);
            defer unlockAudioBusTopology(self);
            const snapshot =
                self.audio_bus_topology.snapshot() catch {
                    out.* = 0;
                    return types.kInvalidArgument;
                };
            const config =
                zig_vst3_plugin_bridge.StereoAudioBuses
                    .configFromSnapshot(
                    &snapshot,
                    event_input,
                    event_output,
                ) orelse {
                    out.* = 0;
                    return types.kInvalidArgument;
                };
            return zig_vst3_plugin_bridge.StereoAudioBuses
                .arrangementConfigured(
                direction,
                index,
                out,
                config,
            );
        }

        fn canProcessSampleSize(ptr: *anyopaque, symbolic_sample_size: types.int32) callconv(.c) types.tresult {
            if (comptime @hasDecl(Config.Processor, "supportsSampleType")) {
                const supported =
                    if (symbolic_sample_size == @intFromEnum(
                        ivstaudioprocessor.SymbolicSampleSizes.kSample32,
                    ))
                        ownerFromProcessor(ptr)
                            .processor_impl.supportsSampleType(f32)
                    else if (symbolic_sample_size == @intFromEnum(
                        ivstaudioprocessor.SymbolicSampleSizes.kSample64,
                    ))
                        ownerFromProcessor(ptr)
                            .processor_impl.supportsSampleType(f64)
                    else
                        false;
                return if (supported)
                    types.kResultOk
                else
                    types.kResultFalse;
            }
            return zig_vst3_plugin_bridge.RealtimeProcessorDefaults.canProcessSampleSize(symbolic_sample_size);
        }

        fn getLatencySamples(ptr: *anyopaque) callconv(.c) types.uint32 {
            if (comptime @hasDecl(Config.Processor, "latencySamples")) {
                return ownerFromProcessor(ptr).processor_impl.latencySamples();
            }
            return zig_vst3_plugin_bridge.RealtimeProcessorDefaults.latencySamples();
        }

        fn setupProcessing(ptr: *anyopaque, setup_raw: [*c]ivstaudioprocessor.ProcessSetup) callconv(.c) types.tresult {
            if (setup_raw == null) return types.kInvalidArgument;
            const setup: *const ivstaudioprocessor.ProcessSetup =
                @ptrCast(setup_raw);
            const self = ownerFromProcessor(ptr);
            const setup_result = zig_vst3_plugin_bridge.RealtimeProcessorDefaults.validateProcessSetup(setup);
            if (setup_result != types.kResultOk) return setup_result;
            const sample_size_result =
                canProcessSampleSize(ptr, setup.symbolicSampleSize);
            if (sample_size_result != types.kResultOk)
                return sample_size_result;
            const process_mode = zig_vst3_plugin_bridge.RealtimeProcessorDefaults.processMode(setup.processMode) orelse {
                return types.kInvalidArgument;
            };

            self.sample_rate = setup.sampleRate;
            if (comptime @hasDecl(Config.Processor, "prepareChecked")) {
                self.processor_impl.prepareChecked(.{
                    .sample_rate = setup.sampleRate,
                    .max_block_size = @intCast(setup.maxSamplesPerBlock),
                    .process_mode = process_mode,
                }) catch return types.kResultFalse;
            } else if (comptime @hasDecl(Config.Processor, "prepare")) {
                self.processor_impl.prepare(.{
                    .sample_rate = setup.sampleRate,
                    .max_block_size = @intCast(setup.maxSamplesPerBlock),
                    .process_mode = process_mode,
                });
            }
            resetProcessState(self);
            return types.kResultOk;
        }

        fn setProcessing(ptr: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            if (state > 1) return types.kInvalidArgument;
            if (state == 0) resetProcessState(ownerFromProcessor(ptr));
            return types.kResultOk;
        }

        fn process(ptr: *anyopaque, data_raw: [*c]ivstaudioprocessor.ProcessData) callconv(.c) types.tresult {
            if (data_raw == null) return types.kInvalidArgument;
            const data: *ivstaudioprocessor.ProcessData =
                @ptrCast(data_raw);
            const self = ownerFromProcessor(ptr);
            const Processor = struct {
                component: *Component,
                parameter_changes: plug_process.ParameterChanges,

                pub fn process(
                    processor: @This(),
                    comptime Sample: type,
                    context: *plug_process.BoundedProcessContext(
                        Sample,
                        auxiliary_audio_bus_capacity,
                    ),
                ) void {
                    const process_parameter_count = @typeInfo(@TypeOf(Config.Processor.process)).@"fn".params.len;
                    if (comptime process_parameter_count == 3) {
                        processor.component.parameter_state.applyChanges(processor.parameter_changes);
                        processor.component.processor_impl.process(Sample, context);
                    } else {
                        var block_parameter_state = processor.component.parameter_state.snapshotAtOffset(processor.parameter_changes, 0);
                        processor.component.parameter_state.applyChanges(processor.parameter_changes);
                        processor.component.processor_impl.process(&block_parameter_state, Sample, context);
                    }
                }
            };
            var parameter_change_storage: [process_parameter_change_capacity]plug_process.ParameterChange = undefined;
            var event_storage: [process_event_capacity]plug_process.Event = undefined;
            var output_event_storage: [process_output_event_capacity]plug_process.Event = undefined;
            const parameter_changes = zig_vst3_plugin_bridge.collectInputParameterChanges(data, &parameter_change_storage);
            if (data.numSamples == 0) {
                const audio_bus_snapshot =
                    self.audio_bus_snapshots.tryRead() orelse
                    return types.kResultFalse;
                const flush_result =
                    zig_vst3_plugin_bridge
                        .validateParameterFlushSnapshot(
                        data,
                        &audio_bus_snapshot.value,
                        event_input,
                        event_output,
                    );
                if (flush_result != types.kResultOk) return flush_result;
                self.parameter_state.applyChanges(parameter_changes);
                syncProcessorParameterValues(self);
                return types.kResultOk;
            }
            const host_events = zig_vst3_plugin_bridge.collectInputEvents(data, &event_storage);
            var event_count = host_events.items.len;
            const frame_count = zig_vst3_plugin_bridge.frameCountOrZero(data);
            if (comptime gui_note_input) {
                if (frame_count != 0 and event_count < event_storage.len) {
                    var commands: [process_event_capacity]gui_note_transport.Command = undefined;
                    const command_count = self.gui_notes.collect(
                        &self.gui_note_seen,
                        commands[0 .. event_storage.len - event_count],
                    );
                    for (commands[0..command_count]) |command| {
                        event_storage[event_count] = if (command.pressed)
                            plug_process.Event.noteOn(0, command.channel, command.pitch, @floatCast(command.velocity))
                        else
                            plug_process.Event.noteOff(0, command.channel, command.pitch, 0.0);
                        event_count += 1;
                    }
                    for (host_events.items.len..event_count) |index| {
                        const item = event_storage[index];
                        var cursor = index;
                        while (cursor > 0 and event_storage[cursor - 1].sample_offset > item.sample_offset) {
                            event_storage[cursor] = event_storage[cursor - 1];
                            cursor -= 1;
                        }
                        event_storage[cursor] = item;
                    }
                }
            }
            const events = plug_process.Events.init(event_storage[0..event_count], frame_count) catch {
                return types.kInvalidArgument;
            };
            var output_events = plug_process.EventWriter.init(&output_event_storage, zig_vst3_plugin_bridge.frameCountOrZero(data));
            const audio_bus_snapshot =
                self.audio_bus_snapshots.tryRead() orelse
                return types.kResultFalse;
            const realtime_scope = plug_core.realtime_audit.Scope.enter();
            const result =
                zig_vst3_plugin_bridge
                    .processMainAudioSnapshotWithSampleRate(
                    data,
                    parameter_changes,
                    events,
                    &output_events,
                    Processor{
                        .component = self,
                        .parameter_changes = parameter_changes,
                    },
                    &audio_bus_snapshot.value,
                    event_input,
                    event_output,
                    self.sample_rate,
                );
            const audit_report = realtime_scope.leave();
            if (!audit_report.clean()) return types.kResultFalse;
            if (result != types.kResultOk) return result;
            if (comptime @hasDecl(Config.Processor, "processSucceeded")) {
                if (!self.processor_impl.processSucceeded())
                    return types.kResultFalse;
            }
            return zig_vst3_plugin_bridge.writeOutputEvents(data, output_events.events());
        }

        fn getTailSamples(ptr: *anyopaque) callconv(.c) types.uint32 {
            if (comptime @hasDecl(Config.Processor, "tailSamples")) {
                return ownerFromProcessor(ptr).processor_impl.tailSamples();
            }
            return zig_vst3_plugin_bridge.RealtimeProcessorDefaults.tailSamples();
        }
    };
}
