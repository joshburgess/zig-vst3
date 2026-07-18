const editor_smoke_spec = @import("editor_smoke_spec.zig");
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
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xE14D2D24, 0x9BC84C72, 0x8A522122, 0x121C781D);
pub const gain_param_id: vsttypes.ParamID = editor_smoke_spec.gain_param_id;
pub const voices_param_id: vsttypes.ParamID = editor_smoke_spec.voices_param_id;
pub const bypass_param_id: vsttypes.ParamID = editor_smoke_spec.bypass_param_id;
pub const mode_param_id: vsttypes.ParamID = editor_smoke_spec.mode_param_id;

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
        .knob => {
            const side = @min(request.width, request.height);
            parameter_editor.fillEllipse(canvas, 2.0, 2.0, side - 2.0, side - 2.0, 0x192029ff);
            _ = parameter_editor.drawAsset(canvas, checkmark_asset_id, side * 0.25, side * 0.25, side * 0.75, side * 0.75, 1.0);
        },
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

    pub fn loadPreset(controller: *ivsteditcontroller.IEditController, preset_id: u32) types.tresult {
        const ids = [_]vsttypes.ParamID{ gain_param_id, voices_param_id, bypass_param_id, mode_param_id };
        const values = switch (preset_id) {
            1 => [_]f64{ 0.5, 0.0, 0.0, 0.0 },
            2 => [_]f64{ 0.75, 2.0 / 3.0, 0.0, 0.5 },
            3 => [_]f64{ 0.5, 0.0, 1.0, 0.0 },
            else => return types.kInvalidArgument,
        };
        return applyPreset(Controller, controller, &ids, &values);
    }

    pub fn performMenuAction(
        controller: *ivsteditcontroller.IEditController,
        menu_id: u32,
        item_id: u32,
        _: bool,
    ) types.tresult {
        if (menu_id != 1) return types.kInvalidArgument;
        switch (item_id) {
            1 => {
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
        return performMenuAction(controller, group_id, action_id, false);
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
        _: *ivsteditcontroller.IEditController,
        source_id: u32,
    ) ?plug_core.gui_progress.Snapshot {
        if (source_id != 1) return null;
        return .{ .state = .running, .value = 0.42, .generation = 1 };
    }

    pub fn handleFileDrop(
        controller: *ivsteditcontroller.IEditController,
        drop_id: u32,
        paths: []const []const u8,
    ) types.tresult {
        if (drop_id != 1 or paths.len == 0 or paths.len > 2) return types.kInvalidArgument;
        Controller.editorState(controller).set(
            imported_file_count_state_id,
            .{ .index = @intCast(paths.len) },
        ) catch return types.kResultFalse;
        return types.kResultOk;
    }

    pub fn createView(controller: *ivsteditcontroller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        return parameter_editor.createEditor(Controller, controller, name, .{
            .parameters = &.{
                .{ .id = gain_param_id, .title = "Bipolar", .units = "±", .step_count = 0, .default_normalized = 0.5, .control_kind = .bipolar_slider, .tooltip = "Drag around the center line; the outlined marker shows modulation.", .modulation_normalized = 0.75 },
                .{ .id = voices_param_id, .title = "Voices", .units = "voices", .step_count = 3, .default_normalized = 0.0, .control_kind = .segmented_enum },
                .{ .id = bypass_param_id, .title = "Bypass", .step_count = 1, .default_normalized = 0.0, .control_kind = .toggle },
                .{ .id = mode_param_id, .title = "Mode", .step_count = 2, .default_normalized = 0.0, .control_kind = .enum_dropdown },
            },
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
                    .source_id = 0,
                    .dynamic = true,
                    .maximum_refresh_hz = 30,
                },
                .{
                    .title = "Spectrum",
                    .kind = .spectrum,
                    .x_axis = .{ .minimum = 20.0, .maximum = 24_000.0, .scale = .logarithmic, .label = "Hz" },
                    .y_axis = .{ .minimum = -96.0, .maximum = 0.0, .scale = .decibels, .label = "dB" },
                    .source_id = 1,
                    .dynamic = true,
                    .maximum_refresh_hz = 30,
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
                    .{ .id = 1, .label = "Reset UI" },
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
                    .label = "Reset Layout",
                    .accessible_label = "Reset gallery layout",
                    .role = .primary,
                },
                .{
                    .group_id = 1,
                    .id = 2,
                    .label = "Audition",
                    .accessible_label = "Audition current settings",
                    .role = .secondary,
                },
                .{
                    .group_id = 2,
                    .id = 4,
                    .icon = .clear,
                    .accessible_label = "Clear envelope",
                    .tooltip = "Remove the editable envelope points.",
                    .confirmation_label = "Confirm Clear",
                    .role = .destructive,
                },
            },
            .editable_labels = &.{.{
                .field_id = gallery_label_state_id,
                .label = "Editable Label",
                .accessible_label = "Effect name",
                .placeholder = "Name this effect",
                .error_text = "Enter a name",
                .maximum_bytes = 48,
            }},
            .progress_indicators = &.{.{
                .source_id = 1,
                .label = "Progress",
                .accessible_label = "Example render progress",
                .running_text = "Rendering preview",
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
                .id = 1,
                .title = "Audio Import",
                .prompt = "Drop WAV or AIFF files here",
                .extensions = &.{ ".wav", ".aiff", ".aif" },
                .maximum_files = 2,
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
                    .{ .title = "Continuous", .parameter_count = 1, .style = .{ .accent = 0x7ce8c5ff }, .xy_pad_count = 1 },
                    .{ .title = "Discrete", .first_parameter = 1, .parameter_count = 3, .first_xy_pad = 1, .style = .{ .accent = 0xe8c77cff } },
                    .{ .title = "Telemetry", .first_parameter = 4, .meter_count = 3, .first_xy_pad = 1, .style = .{ .accent = 0x7caee8ff }, .graph_count = 3 },
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

    try std.testing.expectEqual(types.kResultOk, view.vtable.isPlatformTypeSupported(view, iplugview.PlatformType.kPlatformTypeNSView));
    var rect = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, view.vtable.getSize(view, &rect));
    try std.testing.expectEqual(@as(types.int32, 720), rect.right);
    try std.testing.expectEqual(@as(types.int32, 600), rect.bottom);
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
    try std.testing.expectEqual(source_gain_before, Controller.getNormalized(source, gain_param_id));
    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(source, gain_param_id, 0.75));
    const Stream = vst_stream.FixedBufferStream(65536);
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, source.vtable.getState(source, stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, restored.vtable.setState(restored, stream.asStream()));

    try std.testing.expectEqual(@as(u32, 2), editorState(restored).get(selected_tab_state_id).?.index);
    try std.testing.expectEqualStrings("wide", editorState(restored).get(preset_search_state_id).?.text.slice());
    try std.testing.expectEqual(@as(u32, 2), editorState(restored).get(preset_selection_state_id).?.index);
    try std.testing.expect(!editorState(restored).get(show_analyzer_state_id).?.boolean);
    try std.testing.expectEqual(@as(f64, 0.75), Controller.getNormalized(restored, gain_param_id));
    const first = restored.vtable.createView(restored, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    _ = first.vtable.release(first);
    const reopened = restored.vtable.createView(restored, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = reopened.vtable.release(reopened);
    try std.testing.expectEqual(@as(u32, 2), editorState(restored).get(selected_tab_state_id).?.index);
    try std.testing.expectEqualStrings("wide", editorState(restored).get(preset_search_state_id).?.text.slice());

    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(restored, gain_param_id, 0.25));
    try editorState(restored).set(selected_tab_state_id, .{ .index = 1 });
    stream.len -= 1;
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, restored.vtable.setState(restored, stream.asStream()));
    try std.testing.expectEqual(@as(f64, 0.25), Controller.getNormalized(restored, gain_param_id));
    try std.testing.expectEqual(@as(u32, 1), editorState(restored).get(selected_tab_state_id).?.index);
}
