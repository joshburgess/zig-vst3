const editor_smoke_spec = @import("editor_smoke_spec.zig");
const builtin = @import("builtin");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const plug_core = @import("zig-vst3-plugin-core");
const plug_process = plug_core.process;
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const parameter_editor = @import("vstgui.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const vst_component_handler = @import("vst_component_handler.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_bridge = @import("zig_vst3_plugin_bridge.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xE14D2D24, 0x9BC84C72, 0x8A522122, 0x121C781D);
pub const gain_param_id: vsttypes.ParamID = editor_smoke_spec.gain_param_id;
pub const voices_param_id: vsttypes.ParamID = editor_smoke_spec.voices_param_id;
pub const bypass_param_id: vsttypes.ParamID = editor_smoke_spec.bypass_param_id;
pub const mode_param_id: vsttypes.ParamID = editor_smoke_spec.mode_param_id;
pub const tone_param_id: vsttypes.ParamID = editor_smoke_spec.tone_param_id;
pub const output_param_id: vsttypes.ParamID = editor_smoke_spec.output_param_id;

pub const panel_expanded_state_id: u32 = 1;
pub const analyzer_mode_state_id: u32 = 2;
pub const selected_tab_state_id: u32 = 3;
pub const envelope_selection_state_id: u32 = 4;
pub const envelope_state_id: u32 = 5;
pub const preset_search_state_id: u32 = 6;
pub const preset_selection_state_id: u32 = 7;
pub const show_analyzer_state_id: u32 = 8;
pub const step_selection_state_id: u32 = 9;
pub const imported_file_count_state_id: u32 = 10;
pub const gallery_label_state_id: u32 = 11;
pub const waveform_zoom_state_id: u32 = 12;
pub const waveform_x_offset_state_id: u32 = 13;
pub const waveform_selection_start_state_id: u32 = 14;
pub const waveform_selection_end_state_id: u32 = 15;
pub const gallery_live_label_state_id: u32 = 16;
pub const linked_response_selection_state_id: u32 = 17;
const gallery_spectrum_overlay_source_id: u32 = 1;
const gallery_spectrum_overlay_points: usize = 64;
const gallery_linked_response_source_id: u32 = 2;
const gallery_linked_response_points: usize = 64;
const gallery_import_id: u32 = 1;
const gallery_import_waveform_source_id: u32 = 3;
const gallery_import_action_group_id: u32 = 3;
const gallery_import_action_id: u32 = 1;
const gallery_decoded_frame_capacity: usize = 4_096;

const gallery_envelope = plug_core.editor_state.Envelope.init(&.{
    .{ .id = 1, .x = 0.0, .y = 0.0 },
    .{ .id = 2, .x = 0.5, .y = 0.5 },
    .{ .id = 3, .x = 1.0, .y = 0.0 },
}) catch unreachable;
const cleared_gallery_envelope = plug_core.editor_state.Envelope.init(&.{
    .{ .id = 1, .x = 0.0, .y = 0.0 },
    .{ .id = 3, .x = 1.0, .y = 0.0 },
}) catch unreachable;
const empty_preset_search = plug_core.editor_state.Text.init("") catch unreachable;
const gallery_label = plug_core.editor_state.Text.init("Studio Plate") catch unreachable;
const gallery_live_label = plug_core.editor_state.Text.init("48 kHz, stereo") catch unreachable;

const GalleryAudioImporter = parameter_editor.DecodedAudioFileImporter(gallery_decoded_frame_capacity);

const GalleryControllerState = struct {
    importer: GalleryAudioImporter,

    pub fn init() GalleryControllerState {
        return .{ .importer = .init() };
    }

    pub fn deinit(self: *GalleryControllerState) void {
        self.importer.deinit();
    }
};

const gallery_parameters = [_]parameter_editor.Parameter{
    .{ .id = gain_param_id, .title = "Bipolar", .units = "±", .step_count = 0, .default_normalized = 0.5, .control_kind = .bipolar_slider, .tooltip = "Drag around the center line; the outlined marker shows modulation.", .modulation_normalized = 0.75 },
    .{ .id = tone_param_id, .title = "Rotary", .units = "%", .step_count = 0, .default_normalized = 0.5, .control_kind = .rotary_knob, .tooltip = "Drag vertically. Hold Shift for fine adjustment; Command-click resets.", .modulation_normalized = 0.72 },
    .{ .id = output_param_id, .title = "Output", .units = "dB", .step_count = 0, .default_normalized = 0.5, .control_kind = .decibel_slider, .tooltip = "Adjust output level. Command-click resets to 0 dB." },
    .{ .id = voices_param_id, .title = "Voices", .units = "voices", .step_count = 3, .default_normalized = 0.0, .control_kind = .segmented_enum },
    .{ .id = bypass_param_id, .title = "Bypass", .step_count = 1, .default_normalized = 0.0, .control_kind = .toggle },
    .{ .id = mode_param_id, .title = "Mode", .step_count = 2, .default_normalized = 0.0, .control_kind = .enum_dropdown },
};

pub const GalleryEditorState = plug_core.editor_state.Store(1, &.{
    .{ .id = panel_expanded_state_id, .default = .{ .boolean = true } },
    .{ .id = analyzer_mode_state_id, .default = .{ .index = 0 } },
    .{ .id = selected_tab_state_id, .default = .{ .index = 0 } },
    .{ .id = envelope_selection_state_id, .default = .{ .point_id = 2 } },
    .{ .id = envelope_state_id, .default = .{ .envelope = gallery_envelope } },
    .{ .id = preset_search_state_id, .default = .{ .text = empty_preset_search } },
    .{ .id = preset_selection_state_id, .default = .{ .index = 1 } },
    .{ .id = show_analyzer_state_id, .default = .{ .boolean = true } },
    .{ .id = step_selection_state_id, .default = .{ .index = 1 } },
    .{ .id = imported_file_count_state_id, .default = .{ .index = 0 } },
    .{ .id = gallery_label_state_id, .default = .{ .text = gallery_label } },
    .{ .id = waveform_zoom_state_id, .default = .{ .scalar = 1.0 } },
    .{ .id = waveform_x_offset_state_id, .default = .{ .scalar = 0.0 } },
    .{ .id = waveform_selection_start_state_id, .default = .{ .scalar = 0.2 } },
    .{ .id = waveform_selection_end_state_id, .default = .{ .scalar = 0.8 } },
    .{ .id = gallery_live_label_state_id, .default = .{ .text = gallery_live_label } },
    .{ .id = linked_response_selection_state_id, .default = .{ .point_id = 1 } },
});

fn applyPreset(
    comptime ControllerType: type,
    iface: *ivsteditcontroller.IEditController,
    ids: []const vsttypes.ParamID,
    values: []const f64,
) types.tresult {
    if (ids.len == 0 or ids.len != values.len or ids.len > 64) return types.kInvalidArgument;
    var previous: [64]f64 = undefined;
    for (ids, 0..) |id, index| previous[index] = ControllerType.getNormalized(iface, id);
    const grouped = ControllerType.startGroupEdit(iface) == types.kResultOk;
    var begun: usize = 0;
    while (begun < ids.len) : (begun += 1) {
        if (ControllerType.beginEdit(iface, ids[begun]) != types.kResultOk) {
            for (ids[0..begun]) |id| _ = ControllerType.endEdit(iface, id);
            if (grouped) _ = ControllerType.finishGroupEdit(iface);
            return types.kResultFalse;
        }
    }
    var applied: usize = 0;
    while (applied < ids.len) : (applied += 1) {
        if (ControllerType.performEdit(iface, ids[applied], values[applied]) != types.kResultOk) {
            for (ids[0..applied], previous[0..applied]) |id, value| _ = ControllerType.performEdit(iface, id, value);
            for (ids) |id| _ = ControllerType.endEdit(iface, id);
            if (grouped) _ = ControllerType.finishGroupEdit(iface);
            return types.kResultFalse;
        }
    }
    for (ids) |id| _ = ControllerType.endEdit(iface, id);
    if (grouped and ControllerType.finishGroupEdit(iface) != types.kResultOk) return types.kResultFalse;
    return types.kResultOk;
}

fn loadGalleryPreset(controller: *ivsteditcontroller.IEditController, preset_id: u32) types.tresult {
    const ids = [_]vsttypes.ParamID{ gain_param_id, tone_param_id, output_param_id, voices_param_id, bypass_param_id, mode_param_id };
    const values = switch (preset_id) {
        1 => [_]f64{ 0.5, 0.5, 0.5, 0.0, 0.0, 0.0 },
        2 => [_]f64{ 0.75, 0.8, 0.625, 2.0 / 3.0, 0.0, 0.5 },
        3 => [_]f64{ 0.5, 0.5, 0.5, 0.0, 1.0, 0.0 },
        else => return types.kInvalidArgument,
    };
    return applyPreset(Controller, controller, &ids, &values);
}

const checkmark_asset_id: types.uint32 = 1;
const pixel_asset_id: types.uint32 = 2;
const checkmark_svg =
    "<svg viewBox=\"0 0 24 24\">" ++
    "<path d=\"M2 12 L9 19 L22 4\" fill=\"none\" stroke=\"#7ce8c5\" stroke-width=\"3\"/>" ++
    "</svg>";
const accent_pixel = [_]u8{
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
    0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
    0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99,
    0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
};

fn drawGalleryParameter(
    _: ?*anyopaque,
    request: *const parameter_editor.DrawRequest,
    canvas: *parameter_editor.Canvas,
) callconv(.c) types.int32 {
    switch (request.component) {
        .dropdown => {
            _ = parameter_editor.drawAsset(
                canvas,
                pixel_asset_id,
                request.width - 10.0,
                4.0,
                request.width - 4.0,
                10.0,
                1.0,
            );
        },
        else => {},
    }
    return 0;
}

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "EditorSmokeController";
    pub const Params = editor_smoke_spec.Spec.Params;
    pub const parameter_set = &editor_smoke_spec.parameter_set;
    pub const EditorState = GalleryEditorState;
    pub const ControllerState = GalleryControllerState;

    pub fn loadGuiGraph(
        controller: *ivsteditcontroller.IEditController,
        source_id: u32,
        output: []parameter_editor.GraphPoint,
    ) usize {
        const tone = Controller.getNormalized(controller, tone_param_id);
        const gain_value = Controller.getNormalized(controller, gain_param_id);
        switch (source_id) {
            gallery_spectrum_overlay_source_id => {
                if (output.len < gallery_spectrum_overlay_points) return 0;
                for (output[0..gallery_spectrum_overlay_points], 0..) |*point, index| {
                    const normalized = @as(f64, @floatFromInt(index)) /
                        @as(f64, @floatFromInt(gallery_spectrum_overlay_points - 1));
                    const frequency = 20.0 * std.math.pow(f64, 1_200.0, normalized);
                    const center = 0.2 + tone * 0.6;
                    const level = -54.0 + gain_value * 18.0 + 12.0 *
                        std.math.exp(-std.math.pow(f64, (normalized - center) / 0.18, 2.0));
                    point.* = .{ .x = frequency, .y = level };
                }
                return gallery_spectrum_overlay_points;
            },
            gallery_linked_response_source_id => {
                if (output.len < gallery_linked_response_points) return 0;
                const amount = gain_value * 2.0 - 1.0;
                const output_offset = (Controller.getNormalized(controller, output_param_id) * 2.0 - 1.0) * 0.25;
                for (output[0..gallery_linked_response_points], 0..) |*point, index| {
                    const normalized = @as(f64, @floatFromInt(index)) /
                        @as(f64, @floatFromInt(gallery_linked_response_points - 1));
                    const bell = std.math.exp(-std.math.pow(f64, (normalized - tone) / 0.16, 2.0));
                    point.* = .{
                        .x = normalized * 100.0,
                        .y = std.math.clamp(output_offset + amount * bell, -1.0, 1.0),
                    };
                }
                return gallery_linked_response_points;
            },
            gallery_import_waveform_source_id => {
                var preview: [parameter_editor.audio_file_preview_capacity]parameter_editor.AudioFilePreviewPoint = undefined;
                const count = Controller.controllerState(controller).importer.copyPreview(&preview);
                const copied = @min(count, output.len);
                for (preview[0..copied], output[0..copied]) |point, *destination| {
                    destination.* = .{ .x = point.x, .y = point.y };
                }
                return copied;
            },
            else => return 0,
        }
    }

    pub const loadPreset = loadGalleryPreset;

    pub fn performMenuAction(
        controller: *ivsteditcontroller.IEditController,
        menu_id: u32,
        item_id: u32,
        _: bool,
    ) types.tresult {
        if (menu_id != 1) return types.kInvalidArgument;
        switch (item_id) {
            1 => {
                if (loadPreset(controller, 1) != types.kResultOk) return types.kResultFalse;
                const state = Controller.editorState(controller);
                state.set(panel_expanded_state_id, .{ .boolean = true }) catch return types.kResultFalse;
                state.set(analyzer_mode_state_id, .{ .index = 0 }) catch return types.kResultFalse;
                state.set(selected_tab_state_id, .{ .index = 0 }) catch return types.kResultFalse;
                return types.kResultOk;
            },
            2 => return types.kResultOk,
            4 => {
                const state = Controller.editorState(controller);
                state.set(envelope_state_id, .{ .envelope = cleared_gallery_envelope }) catch return types.kResultFalse;
                state.set(envelope_selection_state_id, .{ .point_id = 1 }) catch return types.kResultFalse;
                return types.kResultOk;
            },
            else => return types.kInvalidArgument,
        }
    }

    pub fn performAction(
        controller: *ivsteditcontroller.IEditController,
        group_id: u32,
        action_id: u32,
    ) types.tresult {
        if (group_id == 1 and action_id == 1) {
            return performMenuAction(controller, 1, 1, false);
        }
        if (group_id == 1 and action_id == 2) {
            return loadPreset(controller, 2);
        }
        if (group_id == 2 and action_id == 4) {
            return performMenuAction(controller, 1, action_id, false);
        }
        if (group_id == gallery_import_action_group_id and action_id == gallery_import_action_id) {
            const snapshot = Controller.controllerState(controller).importer.snapshot();
            if (snapshot.import.status != .ready) return types.kResultFalse;
            var buffer: [48]u8 = undefined;
            const text = std.fmt.bufPrint(
                &buffer,
                "{d} Hz, {d} ch, {d} frames",
                .{ snapshot.sample_rate, snapshot.channels, snapshot.sample_frames },
            ) catch return types.kResultFalse;
            const value = plug_core.editor_state.Text.init(text) catch return types.kResultFalse;
            Controller.editorState(controller).set(gallery_live_label_state_id, .{ .text = value }) catch return types.kResultFalse;
            return types.kResultOk;
        }
        return types.kInvalidArgument;
    }

    pub fn validateEditorText(
        _: *ivsteditcontroller.IEditController,
        field_id: u32,
        text: []const u8,
    ) types.tresult {
        if (field_id != gallery_label_state_id) return types.kInvalidArgument;
        return if (std.mem.trim(u8, text, " \t\r\n").len == 0) types.kResultFalse else types.kResultOk;
    }

    pub fn loadGuiProgress(
        controller: *ivsteditcontroller.IEditController,
        source_id: u32,
    ) ?plug_core.gui_progress.Snapshot {
        if (source_id != gallery_import_id) return null;
        const snapshot = Controller.controllerState(controller).importer.snapshot().import;
        return switch (snapshot.status) {
            .idle => .{ .generation = snapshot.generation },
            .validating => .{ .mode = .indeterminate, .state = .running, .generation = snapshot.generation },
            .importing => .{ .state = .running, .value = snapshot.progress(), .generation = snapshot.generation },
            .ready => .{ .state = .complete, .value = 1.0, .generation = snapshot.generation },
            else => .{ .state = .failed, .value = snapshot.progress(), .generation = snapshot.generation },
        };
    }

    pub fn handleFileImport(
        controller: *ivsteditcontroller.IEditController,
        import_id: u32,
        entry_point: parameter_editor.FileImportEntryPoint,
        paths: []const []const u8,
    ) types.tresult {
        if (import_id != gallery_import_id or paths.len != 1) return types.kInvalidArgument;
        if (!Controller.controllerState(controller).importer.begin(entry_point, paths)) return types.kResultFalse;
        Controller.editorState(controller).set(imported_file_count_state_id, .{ .index = 0 }) catch return types.kResultFalse;
        return types.kResultOk;
    }

    pub fn loadFileImport(
        controller: *ivsteditcontroller.IEditController,
        import_id: u32,
    ) ?parameter_editor.AudioFileImportSnapshot {
        if (import_id != gallery_import_id) return null;
        const snapshot = Controller.controllerState(controller).importer.snapshot();
        if (snapshot.import.status == .ready) {
            Controller.editorState(controller).set(imported_file_count_state_id, .{ .index = 1 }) catch {};
        }
        return snapshot;
    }

    pub fn performFileImportCommand(
        controller: *ivsteditcontroller.IEditController,
        import_id: u32,
        command: parameter_editor.FileImportCommand,
    ) types.tresult {
        if (import_id != gallery_import_id) return types.kInvalidArgument;
        const importer = &Controller.controllerState(controller).importer;
        const handled = switch (command) {
            .cancel => importer.requestCancel(),
            .retry => importer.retry(),
            .reset => importer.reset(),
        };
        if (!handled) return types.kResultFalse;
        if (command == .reset) {
            Controller.editorState(controller).set(imported_file_count_state_id, .{ .index = 0 }) catch return types.kResultFalse;
            Controller.editorState(controller).set(gallery_live_label_state_id, .{ .text = gallery_live_label }) catch return types.kResultFalse;
        }
        return types.kResultOk;
    }

    pub fn createView(controller: *ivsteditcontroller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        return parameter_editor.createEditor(Controller, controller, name, .{
            .parameters = &gallery_parameters,
            .meters = &.{
                .{ .title = "Peak", .kind = .peak, .first_source_id = 0 },
                .{ .title = "Stereo", .kind = .stereo, .first_source_id = 1, .second_source_id = 2 },
                .{ .title = "Reduction", .kind = .gain_reduction, .first_source_id = 3 },
            },
            .graphs = &.{
                .{
                    .title = "Waveform",
                    .kind = .waveform,
                    .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Frame" },
                    .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
                    .source_id = gallery_import_waveform_source_id,
                    .source = .controller,
                    .dynamic = true,
                    .maximum_refresh_hz = 30,
                    .viewport = .{
                        .maximum_zoom = 64.0,
                        .zoom_state_id = waveform_zoom_state_id,
                        .x_offset_state_id = waveform_x_offset_state_id,
                    },
                    .range_selection = .{
                        .initial_start = 0.2,
                        .initial_end = 0.8,
                        .minimum_span = 0.01,
                        .step = 0.01,
                        .start_state_id = waveform_selection_start_state_id,
                        .end_state_id = waveform_selection_end_state_id,
                    },
                },
                .{
                    .title = "Spectrum",
                    .kind = .spectrum,
                    .x_axis = .{ .minimum = 20.0, .maximum = 24_000.0, .scale = .logarithmic, .label = "Hz" },
                    .y_axis = .{ .minimum = -96.0, .maximum = 0.0, .scale = .decibels, .label = "dB" },
                    .source_id = 1,
                    .dynamic = true,
                    .maximum_refresh_hz = 30,
                    .layers = &.{.{
                        .style = .modulation,
                        .source_id = gallery_spectrum_overlay_source_id,
                        .source = .controller,
                        .parameter_driven = true,
                    }},
                },
                .{
                    .title = "Linked Response",
                    .kind = .transfer_function,
                    .x_axis = .{ .minimum = 0.0, .maximum = 100.0, .label = "Tone %" },
                    .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Amount" },
                    .source_id = gallery_linked_response_source_id,
                    .source = .controller,
                    .parameter_driven = true,
                    .selection_state_id = linked_response_selection_state_id,
                    .handles = &.{.{
                        .id = 1,
                        .name = "Tone and Amount",
                        .x_parameter_id = tone_param_id,
                        .y_parameter_id = gain_param_id,
                        .adjustment_parameter_id = output_param_id,
                        .adjustment_label = "Output",
                        .highlight_group_index = 0,
                    }},
                },
                .{
                    .title = "Envelope",
                    .kind = .envelope,
                    .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
                    .y_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Level" },
                    .editable_points = &.{
                        .{ .point_id = 1, .x = 0.0, .y = 0.0 },
                        .{
                            .point_id = 2,
                            .x = 0.5,
                            .y = 0.0,
                            .x_parameter_id = gain_param_id,
                            .y_parameter_id = voices_param_id,
                            .parameter_mask = 3,
                        },
                        .{ .point_id = 3, .x = 1.0, .y = 0.0 },
                    },
                    .point_capacity = 8,
                    .minimum_point_count = 2,
                    .snap_x = 0.05,
                    .snap_y = 0.05,
                    .selection_state_id = envelope_selection_state_id,
                    .envelope_state_id = envelope_state_id,
                },
            },
            .xy_pads = &.{.{
                .title = "Bipolar and Voices",
                .x_parameter_id = gain_param_id,
                .y_parameter_id = voices_param_id,
                .x_label = "Bipolar",
                .y_label = "Voices",
            }},
            .preset_browsers = &.{.{
                .title = "Gallery Presets",
                .presets = &.{
                    .{ .id = 1, .name = "Neutral" },
                    .{ .id = 2, .name = "Wide Motion" },
                    .{ .id = 3, .name = "Safe Bypass" },
                },
                .search_state_id = preset_search_state_id,
                .selection_state_id = preset_selection_state_id,
            }},
            .action_menus = &.{.{
                .id = 1,
                .title = "Actions",
                .items = &.{
                    .{ .id = 1, .label = "Reset Controls" },
                    .{ .id = 2, .label = "Show Analyzer", .kind = .toggle, .checked_state_id = show_analyzer_state_id },
                    .{ .id = 3, .label = "Export Snapshot", .enabled = false },
                    .{ .kind = .separator },
                    .{ .id = 4, .label = "Clear Envelope", .destructive = true },
                },
            }},
            .action_buttons = &.{
                .{
                    .group_id = 1,
                    .id = 1,
                    .label = "Reset Controls",
                    .accessible_label = "Reset gallery controls",
                    .tooltip = "Restore the neutral preset and default gallery state.",
                    .role = .primary,
                },
                .{
                    .group_id = 1,
                    .id = 2,
                    .label = "Apply Wide Motion",
                    .accessible_label = "Apply Wide Motion preset",
                    .tooltip = "Load the Wide Motion preset.",
                    .role = .secondary,
                },
                .{
                    .group_id = 2,
                    .id = 4,
                    .icon = .clear,
                    .accessible_label = "Clear envelope",
                    .tooltip = "Remove the editable envelope points.",
                    .confirmation_label = "Confirm Clear",
                    .failure_label = "Clear failed. Try again",
                    .role = .destructive,
                },
                .{
                    .group_id = gallery_import_action_group_id,
                    .id = gallery_import_action_id,
                    .label = "Show Import Details",
                    .accessible_label = "Show imported audio details",
                    .tooltip = "Show the decoded sample rate, channel count, and frame count.",
                    .role = .secondary,
                    .ready_importer_id = gallery_import_id,
                    .success_focus_importer_id = gallery_import_id,
                },
            },
            .editable_labels = &.{
                .{
                    .field_id = gallery_label_state_id,
                    .label = "Editable Label",
                    .accessible_label = "Effect name",
                    .placeholder = "Name this effect",
                    .error_text = "Enter a name",
                    .maximum_bytes = 48,
                },
                .{
                    .field_id = gallery_live_label_state_id,
                    .label = "Live Value",
                    .accessible_label = "Example live value",
                    .read_only = true,
                },
            },
            .progress_indicators = &.{.{
                .source_id = gallery_import_id,
                .label = "Audio Import",
                .accessible_label = "Gallery audio import progress",
                .idle_text = "Choose audio to inspect",
                .running_text = "Decoding audio",
                .complete_text = "Audio ready",
                .failure_text = "Import failed. Retry or choose another file",
            }},
            .pianos = &.{.{
                .title = "Piano Keyboard",
                .first_note = 48,
                .note_count = 24,
                .computer_base_pitch = 60,
            }},
            .step_sequencers = &.{.{
                .title = "Step Sequencer",
                .step_parameter_ids = &editor_smoke_spec.step_param_ids,
                .selection_state_id = step_selection_state_id,
                .playhead_source_id = 4,
            }},
            .file_importers = &.{.{
                .id = gallery_import_id,
                .title = "Audio Import",
                .prompt = "Drop WAV or AIFF files here",
                .extensions = &.{ ".wav", ".aiff", ".aif" },
                .maximum_files = 1,
            }},
            .skin = .{
                .assets = &.{
                    .{ .id = checkmark_asset_id, .data = checkmark_svg, .format = .svg, .scale = .contain },
                    .{ .id = pixel_asset_id, .data = &accent_pixel, .format = .png, .scale = .stretch },
                },
                .fonts = .{
                    .title_family = "zig-vst3 Gallery Sans",
                    .body_family = "zig-vst3 Gallery Sans",
                    .value_family = "zig-vst3 Gallery Mono",
                    .fallback_family = "Arial",
                },
                .drawing = .{ .draw_parameter = drawGalleryParameter },
            },
            .composition = .{
                .title = "Component Gallery",
                .groups = &.{
                    .{ .title = "Continuous", .parameter_count = 3, .style = .{ .accent = 0x7ce8c5ff }, .xy_pad_count = 1 },
                    .{ .title = "Discrete", .first_parameter = 3, .parameter_count = 3, .first_xy_pad = 1, .style = .{ .accent = 0xe8c77cff } },
                    .{ .title = "Telemetry", .first_parameter = 6, .meter_count = 3, .first_xy_pad = 1, .style = .{ .accent = 0x7caee8ff }, .graph_count = 4 },
                },
            },
        });
    }
});

pub const create = Controller.create;

pub fn gain(iface: *ivsteditcontroller.IEditController) vsttypes.ParamValue {
    return Controller.getNormalized(iface, gain_param_id);
}

pub fn editorState(iface: *ivsteditcontroller.IEditController) *GalleryEditorState {
    return Controller.editorState(iface);
}

pub fn applyParameterChanges(iface: *ivsteditcontroller.IEditController, changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(iface, changes);
}

pub fn readState(iface: *ivsteditcontroller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(iface, state);
}

pub fn writeState(iface: *ivsteditcontroller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(iface, state);
}

test "editor smoke controller creates an editor view" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    const view = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = view.vtable.release(view);

    const platform_type = switch (builtin.os.tag) {
        .macos => iplugview.PlatformType.kPlatformTypeNSView,
        .windows => iplugview.PlatformType.kPlatformTypeHWND,
        .linux => iplugview.PlatformType.kPlatformTypeX11EmbedWindowID,
        else => return error.UnsupportedTestPlatform,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        view.vtable.isPlatformTypeSupported(view, platform_type),
    );
    var rect = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, view.vtable.getSize(view, &rect));
    try std.testing.expectEqual(@as(types.int32, 720), rect.right);
    try std.testing.expectEqual(@as(types.int32, 600), rect.bottom);
}

test "editor smoke gallery uses the production decibel control contract" {
    try std.testing.expectEqual(@as(usize, 6), gallery_parameters.len);
    const output = gallery_parameters[2];
    try std.testing.expectEqual(output_param_id, output.id);
    try std.testing.expectEqual(@TypeOf(output.control_kind).decibel_slider, output.control_kind);
    try std.testing.expectEqualStrings("Output", std.mem.span(output.title));
    try std.testing.expectEqualStrings("dB", std.mem.span(output.units));
    try std.testing.expectEqual(@as(f64, 0.5), output.default_normalized);
    try std.testing.expectEqual(@as(?f64, 0.0), editor_smoke_spec.parameter_set.plainFromNormalizedById(output_param_id, 0.5));
}

test "editor smoke presets include output gain" {
    const HostHandler = vst_component_handler.ComponentHandler2(struct {});
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller_iface.vtable.release(controller_iface);
    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    defer _ = controller_iface.vtable.setComponentHandler(controller_iface, null);

    try std.testing.expectEqual(types.kResultOk, loadGalleryPreset(controller_iface, 2));
    try std.testing.expectEqual(@as(f64, 0.625), Controller.getNormalized(controller_iface, output_param_id));
    try std.testing.expectEqual(types.kResultOk, loadGalleryPreset(controller_iface, 1));
    try std.testing.expectEqual(@as(f64, 0.5), Controller.getNormalized(controller_iface, output_param_id));
    try std.testing.expectEqual(@as(types.uint32, 12), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 12), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 12), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 2), handler.start_group_count);
    try std.testing.expectEqual(@as(types.uint32, 2), handler.finish_group_count);
}

test "editor smoke restores legacy state with unity output gain" {
    const LegacyParams = struct {
        gain: plug_core.parameters.FloatParam = .{ .id = gain_param_id, .name = "Gain", .short_name = "Gain", .units = "x", .min = 0.0, .max = 1.0, .default = 1.0 },
        voices: plug_core.parameters.IntParam = plug_core.parameters.IntParam.init(voices_param_id, "Voices", 1, 4, 1),
        bypass: plug_core.parameters.BoolParam = .{ .id = bypass_param_id, .name = "Bypass", .default = false, .is_bypass = true },
        mode: editor_smoke_spec.ModeParam = .{ .id = mode_param_id, .name = "Mode", .default = .clean },
        tone: plug_core.parameters.FloatParam = .{ .id = tone_param_id, .name = "Tone", .short_name = "Tone", .units = "%", .min = 0.0, .max = 100.0, .default = 50.0 },
    };
    const LegacySet = plug_core.parameters.ParameterSet(LegacyParams);
    const LegacyValues = plug_core.parameters.ParameterValues(LegacyParams);
    const legacy_set = LegacySet.init(.{});
    var legacy_values = LegacyValues.init(&legacy_set);
    try std.testing.expect(legacy_values.storeField(&legacy_set, "gain", 0.25));
    const Stream = vst_stream.FixedBufferStream(1024);
    var stream = Stream{};
    try std.testing.expectEqual(
        types.kResultOk,
        zig_vst3_plugin_bridge.writeParameterState(LegacyParams, stream.asStream(), &legacy_set, &legacy_values),
    );

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller_iface.vtable.release(controller_iface);
    try std.testing.expectEqual(
        types.kResultOk,
        stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null),
    );
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentState(controller_iface, stream.asStream()));
    try std.testing.expectEqual(@as(f64, 0.25), Controller.getNormalized(controller_iface, gain_param_id));
    try std.testing.expectEqual(@as(f64, 0.5), Controller.getNormalized(controller_iface, output_param_id));
}

test "editor smoke controller creates independent views" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    const first = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = first.vtable.release(first);
    const second = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = second.vtable.release(second);
    try std.testing.expect(first != second);

    var changed = iplugview.ViewRect{ .left = 0, .top = 0, .right = 640, .bottom = 520 };
    try std.testing.expectEqual(types.kResultOk, first.vtable.onSize(first, &changed));
    var second_size = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, second.vtable.getSize(second, &second_size));
    try std.testing.expectEqual(@as(types.int32, 720), second_size.right);
    try std.testing.expectEqual(@as(types.int32, 600), second_size.bottom);
}

test "editor smoke controller provides the parameter-driven spectrum layer" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller_iface.vtable.release(controller_iface);
    var points: [gallery_spectrum_overlay_points]parameter_editor.GraphPoint = undefined;

    try std.testing.expectEqual(
        points.len,
        Controller.loadGuiGraph(controller_iface, gallery_spectrum_overlay_source_id, &points),
    );
    for (points) |point| {
        try std.testing.expect(std.math.isFinite(point.x));
        try std.testing.expect(std.math.isFinite(point.y));
        try std.testing.expect(point.x >= 20.0 and point.x <= 24_000.0);
        try std.testing.expect(point.y >= -96.0 and point.y <= 0.0);
    }
}

test "editor smoke controller provides the linked response graph" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller_iface.vtable.release(controller_iface);
    var neutral: [gallery_linked_response_points]parameter_editor.GraphPoint = undefined;
    var shaped: [gallery_linked_response_points]parameter_editor.GraphPoint = undefined;
    var moved: [gallery_linked_response_points]parameter_editor.GraphPoint = undefined;
    var adjusted: [gallery_linked_response_points]parameter_editor.GraphPoint = undefined;

    try std.testing.expectEqual(
        neutral.len,
        Controller.loadGuiGraph(controller_iface, gallery_linked_response_source_id, &neutral),
    );
    for (neutral) |point| {
        try std.testing.expect(std.math.isFinite(point.x));
        try std.testing.expect(std.math.isFinite(point.y));
        try std.testing.expect(point.x >= 0.0 and point.x <= 100.0);
        try std.testing.expect(point.y >= -1.0 and point.y <= 1.0);
    }

    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(controller_iface, gain_param_id, 0.8));
    try std.testing.expectEqual(
        shaped.len,
        Controller.loadGuiGraph(controller_iface, gallery_linked_response_source_id, &shaped),
    );
    try std.testing.expect(shaped[31].y > shaped[47].y);

    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(controller_iface, tone_param_id, 0.75));
    try std.testing.expectEqual(
        moved.len,
        Controller.loadGuiGraph(controller_iface, gallery_linked_response_source_id, &moved),
    );
    try std.testing.expect(moved[47].y > moved[31].y);

    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(controller_iface, output_param_id, 0.625));
    try std.testing.expectEqual(
        adjusted.len,
        Controller.loadGuiGraph(controller_iface, gallery_linked_response_source_id, &adjusted),
    );
    for (moved, adjusted) |before, after| {
        try std.testing.expect(after.y > before.y);
    }
    try std.testing.expect(adjusted[47].y > adjusted[16].y);
    try std.testing.expectEqual(
        @as(usize, 0),
        Controller.loadGuiGraph(controller_iface, gallery_linked_response_source_id, adjusted[0 .. adjusted.len - 1]),
    );
}

test "editor smoke controller persists UI state without changing parameters" {
    var source_out: ?*anyopaque = null;
    var restored_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &source_out));
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &restored_out));
    const source: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(source_out.?));
    defer _ = source.vtable.release(source);
    const restored: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(restored_out.?));
    defer _ = restored.vtable.release(restored);

    const source_gain_before = Controller.getNormalized(source, gain_param_id);
    try editorState(source).set(selected_tab_state_id, .{ .index = 2 });
    try editorState(source).set(preset_search_state_id, .{
        .text = try plug_core.editor_state.Text.init("wide"),
    });
    try editorState(source).set(preset_selection_state_id, .{ .index = 2 });
    try editorState(source).set(show_analyzer_state_id, .{ .boolean = false });
    try editorState(source).set(linked_response_selection_state_id, .{ .point_id = 0 });
    try std.testing.expectEqual(source_gain_before, Controller.getNormalized(source, gain_param_id));
    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(source, gain_param_id, 0.75));
    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(source, tone_param_id, 0.8));
    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(source, output_param_id, 0.625));
    const Stream = vst_stream.FixedBufferStream(65536);
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, source.vtable.getState(source, stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, restored.vtable.setState(restored, stream.asStream()));

    try std.testing.expectEqual(@as(u32, 2), editorState(restored).get(selected_tab_state_id).?.index);
    try std.testing.expectEqualStrings("wide", editorState(restored).get(preset_search_state_id).?.text.slice());
    try std.testing.expectEqual(@as(u32, 2), editorState(restored).get(preset_selection_state_id).?.index);
    try std.testing.expect(!editorState(restored).get(show_analyzer_state_id).?.boolean);
    try std.testing.expectEqual(@as(u32, 0), editorState(restored).get(linked_response_selection_state_id).?.point_id);
    try std.testing.expectEqual(@as(f64, 0.75), Controller.getNormalized(restored, gain_param_id));
    try std.testing.expectEqual(@as(f64, 0.8), Controller.getNormalized(restored, tone_param_id));
    try std.testing.expectEqual(@as(f64, 0.625), Controller.getNormalized(restored, output_param_id));
    const first = restored.vtable.createView(restored, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    _ = first.vtable.release(first);
    const reopened = restored.vtable.createView(restored, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = reopened.vtable.release(reopened);
    try std.testing.expectEqual(@as(u32, 2), editorState(restored).get(selected_tab_state_id).?.index);
    try std.testing.expectEqualStrings("wide", editorState(restored).get(preset_search_state_id).?.text.slice());
    try std.testing.expectEqual(@as(u32, 0), editorState(restored).get(linked_response_selection_state_id).?.point_id);

    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(restored, gain_param_id, 0.25));
    try editorState(restored).set(selected_tab_state_id, .{ .index = 1 });
    stream.len -= 1;
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, restored.vtable.setState(restored, stream.asStream()));
    try std.testing.expectEqual(@as(f64, 0.25), Controller.getNormalized(restored, gain_param_id));
    try std.testing.expectEqual(@as(u32, 1), editorState(restored).get(selected_tab_state_id).?.index);
}

fn writeGalleryFixture(directory: *std.Io.Dir, sub_path: []const u8) !void {
    var bytes: [52]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try writer.writeAll("RIFF");
    try writer.writeInt(u32, 44, .little);
    try writer.writeAll("WAVEfmt ");
    try writer.writeInt(u32, 16, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 48_000, .little);
    try writer.writeInt(u32, 96_000, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u16, 16, .little);
    try writer.writeAll("data");
    try writer.writeInt(u32, 8, .little);
    try writer.writeInt(i16, -16_384, .little);
    try writer.writeInt(i16, 0, .little);
    try writer.writeInt(i16, 16_384, .little);
    try writer.writeInt(i16, 32_767, .little);
    try directory.writeFile(std.testing.io, .{ .sub_path = sub_path, .data = writer.buffered() });
}

fn waitForGalleryImport(
    controller: *ivsteditcontroller.IEditController,
) !parameter_editor.AudioFileImportSnapshot {
    for (0..1_000_000) |_| {
        const snapshot = Controller.loadFileImport(controller, gallery_import_id) orelse return error.MissingImportState;
        switch (snapshot.import.status) {
            .validating, .importing => std.Thread.yield() catch {},
            else => return snapshot,
        }
    }
    return error.ImportTimedOut;
}

fn waitForGalleryWorker(controller: *ivsteditcontroller.IEditController) !void {
    for (0..1_000_000) |_| {
        if (Controller.controllerState(controller).importer.canReset()) return;
        std.Thread.yield() catch {};
    }
    return error.ImportTimedOut;
}

test "component gallery exercises decoded import progress waveform dependency and recovery" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeGalleryFixture(&temporary.dir, "gallery.wav");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "broken.wav", .data = "not audio" });
    var valid_path: [1024]u8 = undefined;
    const valid_length = try temporary.dir.realPathFile(std.testing.io, "gallery.wav", &valid_path);
    var broken_path: [1024]u8 = undefined;
    const broken_length = try temporary.dir.realPathFile(std.testing.io, "broken.wav", &broken_path);

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);

    try std.testing.expectEqual(
        types.kResultFalse,
        Controller.performAction(controller, gallery_import_action_group_id, gallery_import_action_id),
    );
    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        controller,
        gallery_import_id,
        .picker,
        &.{valid_path[0..valid_length]},
    ));
    const ready = try waitForGalleryImport(controller);
    try std.testing.expectEqual(parameter_editor.FileImportStatus.ready, ready.import.status);
    try std.testing.expectEqual(@as(usize, 4), ready.decoded_frames);
    try std.testing.expectEqual(plug_core.gui_progress.State.complete, Controller.loadGuiProgress(controller, gallery_import_id).?.state);
    var waveform: [parameter_editor.audio_file_preview_capacity]parameter_editor.GraphPoint = undefined;
    try std.testing.expectEqual(@as(usize, 4), Controller.loadGuiGraph(controller, gallery_import_waveform_source_id, &waveform));
    try std.testing.expect(waveform[0].y < 0.0);
    try std.testing.expect(waveform[3].y > 0.9);
    try std.testing.expectEqual(types.kResultOk, Controller.performAction(
        controller,
        gallery_import_action_group_id,
        gallery_import_action_id,
    ));
    try std.testing.expectEqualStrings(
        "48000 Hz, 1 ch, 4 frames",
        Controller.editorState(controller).get(gallery_live_label_state_id).?.text.slice(),
    );

    try waitForGalleryWorker(controller);
    try std.testing.expectEqual(types.kResultOk, Controller.performFileImportCommand(controller, gallery_import_id, .reset));
    try std.testing.expectEqual(@as(usize, 0), Controller.loadGuiGraph(controller, gallery_import_waveform_source_id, &waveform));
    try std.testing.expectEqual(plug_core.gui_progress.State.idle, Controller.loadGuiProgress(controller, gallery_import_id).?.state);

    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        controller,
        gallery_import_id,
        .drop,
        &.{broken_path[0..broken_length]},
    ));
    const failed = try waitForGalleryImport(controller);
    try std.testing.expectEqual(parameter_editor.FileImportStatus.failed, failed.import.status);
    try std.testing.expectEqual(plug_core.gui_progress.State.failed, Controller.loadGuiProgress(controller, gallery_import_id).?.state);
    try waitForGalleryWorker(controller);
    try std.testing.expectEqual(types.kResultOk, Controller.performFileImportCommand(controller, gallery_import_id, .retry));
    const retried = try waitForGalleryImport(controller);
    try std.testing.expect(retried.import.generation > failed.import.generation);
    try std.testing.expectEqual(parameter_editor.FileImportStatus.failed, retried.import.status);
}
