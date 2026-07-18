const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const gui = vst3.pluginterfaces.gui;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const gain_param_id: u32 = 0;
pub const bypass_param_id: u32 = 1;
pub const mode_param_id: u32 = 2;

pub const Mode = enum { clean, console, limit };
pub const ModeParam = core.parameters.EnumParam(Mode);

const ChannelStripDefinition = struct {
    pub const name = "zig-vst3 Channel Strip";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = gain_param_id,
            .name = "Gain",
            .units = "dB",
            .min = -24.0,
            .max = 24.0,
            .default = 0.0,
        },
        bypass: core.parameters.BoolParam = .{
            .id = bypass_param_id,
            .name = "Bypass",
            .default = false,
            .is_bypass = true,
        },
        mode: ModeParam = .{
            .id = mode_param_id,
            .name = "Mode",
            .default = .clean,
        },
    };
};

pub const Spec = core.plugin.PluginSpec(ChannelStripDefinition);
pub const channel_parameter_set = Spec.ParameterSet.init(.{});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ChannelStripController";
    pub const Params = Spec.Params;
    pub const parameter_set = &channel_parameter_set;

    pub fn createView(
        controller: *vst.ivsteditcontroller.IEditController,
        name: types.FIDString,
    ) ?*gui.iplugview.IPlugView {
        return vst3.vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{
                .{
                    .id = gain_param_id,
                    .title = "Gain",
                    .units = "dB",
                    .step_count = 0,
                    .default_normalized = 0.5,
                    .control_kind = .decibel_slider,
                    .tooltip = "Equal dB steps change gain by equal ratios. Command-click resets to unity.",
                    .modulation_normalized = 0.64,
                },
                .{
                    .id = bypass_param_id,
                    .title = "Bypass",
                    .step_count = 1,
                    .default_normalized = 0.0,
                    .control_kind = .toggle,
                },
                .{
                    .id = mode_param_id,
                    .title = "Mode",
                    .step_count = 2,
                    .default_normalized = 0.0,
                    .control_kind = .enum_dropdown,
                },
            },
            .meters = &.{
                .{ .title = "Stereo", .kind = .stereo, .first_source_id = 0, .second_source_id = 1 },
                .{ .title = "Reduction", .kind = .gain_reduction, .first_source_id = 2 },
            },
            .skin = .{
                .theme = .alternate,
                .layout = .compact_strip,
            },
            .composition = .{
                .title = "Channel Strip",
                .style = .{ .background = 0xeeeae0ff, .foreground = 0x25231fff },
                .groups = &.{
                    .{
                        .title = "Input",
                        .parameter_count = 1,
                        .style = .{ .accent = 0x3578baff, .border = 0x7994aaff },
                    },
                    .{
                        .title = "Character",
                        .first_parameter = 1,
                        .parameter_count = 2,
                        .style = .{ .accent = 0xb96b32ff, .border = 0xac8b73ff },
                    },
                    .{
                        .title = "Output",
                        .first_parameter = 3,
                        .first_meter = 0,
                        .meter_count = 2,
                        .style = .{ .accent = 0x35866aff, .border = 0x719789ff },
                    },
                },
            },
        });
    }
});

const ChannelStripProcessor = struct {
    const MeterBank = core.gui_telemetry.MeterBank(f64, 3);

    meters: MeterBank = MeterBank.init(0.0),

    pub fn process(
        self: *ChannelStripProcessor,
        parameters: anytype,
        comptime Sample: type,
        context: *core.process.ProcessContext(Sample),
    ) void {
        const gain_parameter = core.parameters.FloatParam{
            .id = gain_param_id,
            .name = "Gain",
            .units = "dB",
            .min = -24.0,
            .max = 24.0,
            .default = 0.0,
        };
        const mode_parameter = ModeParam{ .id = mode_param_id, .name = "Mode", .default = .clean };
        const gain_db = gain_parameter.denormalize(parameters.getNormalizedById(gain_param_id));
        const gain = std.math.pow(f64, 10.0, gain_db / 20.0);
        const bypassed = parameters.getNormalizedById(bypass_param_id) >= 0.5;
        const mode = mode_parameter.denormalize(parameters.getNormalizedById(mode_param_id));

        const telemetry_active = self.meters.producing();
        var peaks = [_]f64{ 0.0, 0.0 };
        var maximum_unshaped: f64 = 0.0;
        var maximum_shaped: f64 = 0.0;
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample_index| {
                const input_sample = input[sample_index];
                const output_sample = processSample(Sample, input_sample, gain, bypassed, mode);
                output[sample_index] = output_sample;
                if (telemetry_active) {
                    const output_magnitude = @abs(@as(f64, @floatCast(output_sample)));
                    if (channel < peaks.len) peaks[channel] = @max(peaks[channel], output_magnitude);
                    maximum_unshaped = @max(maximum_unshaped, @abs(@as(f64, @floatCast(input_sample))) * gain);
                    maximum_shaped = @max(maximum_shaped, output_magnitude);
                }
            }
        }
        if (telemetry_active) {
            const reduction_db = if (bypassed or maximum_unshaped <= maximum_shaped or maximum_shaped <= 0.0)
                0.0
            else
                20.0 * std.math.log10(maximum_unshaped / maximum_shaped);
            self.publishTelemetry(peaks[0], peaks[1], reduction_db / 24.0);
        }
    }

    fn publishTelemetry(self: *ChannelStripProcessor, left: f64, right: f64, reduction: f64) void {
        _ = self.meters.publish(0, std.math.clamp(left, 0.0, 1.0));
        _ = self.meters.publish(1, std.math.clamp(right, 0.0, 1.0));
        _ = self.meters.publish(2, std.math.clamp(reduction, 0.0, 1.0));
    }

    pub fn guiTelemetryLoad(self: *ChannelStripProcessor, source_id: types.uint32) f64 {
        return self.meters.load(source_id) orelse 0.0;
    }

    pub fn guiTelemetryEditorOpened(self: *ChannelStripProcessor) void {
        self.meters.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *ChannelStripProcessor) void {
        self.meters.editorClosed();
    }
};

fn processSample(comptime Sample: type, input: Sample, gain: f64, bypassed: bool, mode: Mode) Sample {
    if (bypassed) return input;
    const amplified = @as(f64, @floatCast(input)) * gain;
    const shaped = switch (mode) {
        .clean => amplified,
        .console => std.math.tanh(amplified * 1.5) / std.math.tanh(@as(f64, 1.5)),
        .limit => std.math.clamp(amplified, -1.0, 1.0),
    };
    return @floatCast(shaped);
}

const Effect = vst3.zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "ChannelStripComponent";
    pub const controller_cid = channel_controller_cid;
    pub const Params = Spec.Params;
    pub const parameter_set = &channel_parameter_set;
    pub const Processor = ChannelStripProcessor;
});

pub const component_cid = vst3.tuid.inlineUid(0x760719F3, 0x4E144C91, 0xB09BF160, 0xC667AD90);
pub const channel_controller_cid = vst3.tuid.inlineUid(0x54E01F82, 0x900A4D49, 0x9F6B8C42, 0x5E4E5164);

const ChannelStripFactory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{
        .cid = component_cid,
        .category = Spec.component_category,
        .name = Spec.component_class_name,
        .create = Effect.create,
    },
    .{
        .cid = channel_controller_cid,
        .category = Spec.controller_category,
        .name = Spec.controller_class_name,
        .create = Controller.create,
    },
});

comptime {
    vst3.entry.exportPlugin(ChannelStripFactory);
}

test "channel strip exports component and controller classes" {
    const plugin_factory = ChannelStripFactory.getPluginFactory().?;
    var class_info: base.ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Channel Strip", std.mem.sliceTo(&class_info.name, 0));
}

test "channel strip processing modes preserve their contracts" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), processSample(f32, 0.5, 1.0, false, .clean), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), processSample(f32, 0.5, 4.0, true, .limit), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), processSample(f32, 0.75, 2.0, false, .limit), 0.0001);
    try std.testing.expect(processSample(f64, 0.75, 2.0, false, .console) < 1.1);
}

test "channel strip controller creates independent public API views" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out),
    );
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);

    const first = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = first.vtable.release(first);
    const second = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = second.vtable.release(second);
    try std.testing.expect(first != second);
    var expanded = gui.iplugview.ViewRect{ .left = 0, .top = 0, .right = 720, .bottom = 480 };
    try std.testing.expectEqual(types.kResultOk, first.vtable.onSize(first, &expanded));
    var second_size = gui.iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, second.vtable.getSize(second, &second_size));
    try std.testing.expectEqual(@as(types.int32, 400), second_size.right);
    try std.testing.expectEqual(@as(types.int32, 300), second_size.bottom);
}

test "channel strip component instances keep independent parameter state" {
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &first_out),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &second_out),
    );
    const first: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(first_out orelse return error.MissingComponent));
    defer _ = first.vtable.release(first);
    const second: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(second_out orelse return error.MissingComponent));
    defer _ = second.vtable.release(second);

    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(first, gain_param_id, 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), Effect.getParameterNormalized(first, gain_param_id));
    try std.testing.expectEqual(@as(f64, 0.5), Effect.getParameterNormalized(second, gain_param_id));
}

test "channel strip telemetry is activity gated and instance isolated" {
    var first = ChannelStripProcessor{};
    var second = ChannelStripProcessor{};

    first.publishTelemetry(0.75, 0.5, 0.25);
    try std.testing.expectEqual(@as(f64, 0.0), first.guiTelemetryLoad(0));

    first.guiTelemetryEditorOpened();
    first.guiTelemetryEditorOpened();
    first.publishTelemetry(0.75, 0.5, 0.25);
    try std.testing.expectEqual(@as(f64, 0.75), first.guiTelemetryLoad(0));
    try std.testing.expectEqual(@as(f64, 0.5), first.guiTelemetryLoad(1));
    try std.testing.expectEqual(@as(f64, 0.25), first.guiTelemetryLoad(2));
    try std.testing.expectEqual(@as(f64, 0.0), second.guiTelemetryLoad(0));

    first.guiTelemetryEditorClosed();
    first.publishTelemetry(0.5, 0.5, 0.5);
    try std.testing.expectEqual(@as(f64, 0.5), first.guiTelemetryLoad(0));
    first.guiTelemetryEditorClosed();
    first.publishTelemetry(1.0, 1.0, 1.0);
    try std.testing.expectEqual(@as(f64, 0.5), first.guiTelemetryLoad(0));
}

test "controller retains its connected component telemetry through editor teardown" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out),
    );
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);

    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(component, &vst.ivstmessage.iconnection_point_iid, &component_connection_out),
    );
    const component_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out orelse return error.MissingConnection));
    defer _ = component_connection.vtable.release(component_connection);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out),
    );
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);

    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller.vtable.queryInterface(controller, &vst.ivstmessage.iconnection_point_iid, &controller_connection_out),
    );
    const controller_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingConnection));
    defer _ = controller_connection.vtable.release(controller_connection);

    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));
    const source = Controller.retainGuiTelemetry(controller) orelse return error.MissingTelemetry;
    defer source.release();
    source.editorOpened();
    defer source.editorClosed();

    Effect.processorInstance(component).publishTelemetry(0.8, 0.6, 0.4);
    try std.testing.expectEqual(@as(f64, 0.8), source.load(0));
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.disconnect(controller_connection, component_connection));
    try std.testing.expectEqual(@as(f64, 0.8), source.load(0));
}
