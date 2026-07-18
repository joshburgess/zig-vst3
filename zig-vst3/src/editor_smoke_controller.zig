const editor_smoke_spec = @import("editor_smoke_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const parameter_editor = @import("vstgui.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xE14D2D24, 0x9BC84C72, 0x8A522122, 0x121C781D);
pub const gain_param_id: vsttypes.ParamID = editor_smoke_spec.gain_param_id;
pub const voices_param_id: vsttypes.ParamID = editor_smoke_spec.voices_param_id;
pub const bypass_param_id: vsttypes.ParamID = editor_smoke_spec.bypass_param_id;
pub const mode_param_id: vsttypes.ParamID = editor_smoke_spec.mode_param_id;

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
            .graphs = &.{.{
                .title = "Waveform",
                .kind = .waveform,
                .x_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Time" },
                .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
                .source_id = 0,
                .dynamic = true,
                .maximum_refresh_hz = 30,
            }},
            .xy_pads = &.{.{
                .title = "Bipolar and Voices",
                .x_parameter_id = gain_param_id,
                .y_parameter_id = voices_param_id,
                .x_label = "Bipolar",
                .y_label = "Voices",
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
                    .{ .title = "Telemetry", .first_parameter = 4, .meter_count = 3, .first_xy_pad = 1, .style = .{ .accent = 0x7caee8ff }, .graph_count = 1 },
                },
            },
        });
    }
});

pub const create = Controller.create;

pub fn gain(iface: *ivsteditcontroller.IEditController) vsttypes.ParamValue {
    return Controller.getNormalized(iface, gain_param_id);
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
    try std.testing.expectEqual(@as(types.int32, 400), rect.right);
    try std.testing.expectEqual(@as(types.int32, 300), rect.bottom);
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

    var changed = iplugview.ViewRect{ .left = 0, .top = 0, .right = 640, .bottom = 360 };
    try std.testing.expectEqual(types.kResultOk, first.vtable.onSize(first, &changed));
    var second_size = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, second.vtable.getSize(second, &second_size));
    try std.testing.expectEqual(@as(types.int32, 400), second_size.right);
    try std.testing.expectEqual(@as(types.int32, 300), second_size.bottom);
}
