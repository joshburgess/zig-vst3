const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const gui = vst3.pluginterfaces.gui;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const bypass_param_id: u32 = 0;
pub const mode_param_id: u32 = 1;
pub const cutoff_param_id: u32 = 2;
pub const resonance_param_id: u32 = 3;
pub const drive_param_id: u32 = 4;
pub const mix_param_id: u32 = 5;
pub const output_param_id: u32 = 6;

pub const FilterMode = enum { low_pass, high_pass, band_pass, notch };
pub const FilterModeParam = core.parameters.EnumParam(FilterMode);

const Definition = struct {
    pub const name = "zig-vst3 Resonant Filter";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        bypass: core.parameters.BoolParam = .{ .id = bypass_param_id, .name = "Bypass", .is_bypass = true },
        mode: FilterModeParam = .{ .id = mode_param_id, .name = "Mode", .default = .low_pass },
        cutoff: core.parameters.LogFloatParam = .{ .id = cutoff_param_id, .name = "Cutoff", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 1_000.0 },
        resonance: core.parameters.LogFloatParam = .{ .id = resonance_param_id, .name = "Resonance", .min = 0.1, .max = 18.0, .default = 0.707 },
        drive: core.parameters.FloatParam = .{ .id = drive_param_id, .name = "Drive", .units = "dB", .min = 0.0, .max = 24.0, .default = 0.0 },
        mix: core.parameters.FloatParam = .{ .id = mix_param_id, .name = "Mix", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
        output: core.parameters.FloatParam = .{ .id = output_param_id, .name = "Output", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
    };
};

pub const Spec = core.plugin.PluginSpec(Definition);
pub const filter_parameter_set = Spec.ParameterSet.init(.{});

const filter_skin: vst3.vstgui.Skin = .{
    .theme = .alternate,
    .layout = .adaptive,
};

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ResonantFilterController";
    pub const Params = Spec.Params;
    pub const parameter_set = &filter_parameter_set;

    pub fn createView(
        controller: *vst.ivsteditcontroller.IEditController,
        name: types.FIDString,
    ) ?*gui.iplugview.IPlugView {
        return vst3.vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{
                parameterControl(bypass_param_id, "Bypass", "", 1, 0.0, .toggle),
                parameterControl(mode_param_id, "Mode", "", 3, 0.0, .enum_dropdown),
                parameterControl(cutoff_param_id, "Cutoff", "Hz", 0, normalizedCutoff(1_000.0), .rotary_knob),
                parameterControl(resonance_param_id, "Resonance", "", 0, normalizedResonance(0.707), .rotary_knob),
                parameterControl(drive_param_id, "Drive", "dB", 0, 0.0, .rotary_knob),
                parameterControl(mix_param_id, "Mix", "%", 0, 1.0, .linear_slider),
                parameterControl(output_param_id, "Output", "dB", 0, 0.5, .decibel_slider),
            },
            .skin = filter_skin,
            .composition = .{
                .title = "Resonant Filter",
                .style = .{ .background = 0x111922ff, .foreground = 0xeaf3f6ff, .accent = 0x52d5b0ff },
                .groups = &.{
                    .{ .title = "Filter", .first_parameter = 0, .parameter_count = 4, .style = .{ .accent = 0x52d5b0ff } },
                    .{ .title = "Color and Output", .first_parameter = 4, .parameter_count = 3, .style = .{ .accent = 0x79baf2ff } },
                },
            },
        });
    }
});

fn parameterControl(
    id: u32,
    title: [*:0]const u8,
    units: [*:0]const u8,
    step_count: i32,
    default_normalized: f64,
    control_kind: @TypeOf(@as(vst3.vstgui.Parameter, undefined).control_kind),
) vst3.vstgui.Parameter {
    return .{
        .id = id,
        .title = title,
        .units = units,
        .step_count = step_count,
        .default_normalized = default_normalized,
        .control_kind = control_kind,
        .tooltip = parameterTooltip(id),
        .modulation_normalized = if (id == cutoff_param_id) 0.62 else null,
    };
}

fn parameterTooltip(id: u32) [*:0]const u8 {
    return switch (id) {
        bypass_param_id => "Bypass all filter processing.",
        mode_param_id => "Choose low-pass, high-pass, band-pass, or notch filtering.",
        cutoff_param_id => "Set the filter cutoff. Hold Shift for fine adjustment; Command-click resets.",
        resonance_param_id => "Set resonance at the cutoff. Hold Shift for fine adjustment; Command-click resets.",
        drive_param_id => "Add level-dependent color before the wet and dry blend.",
        mix_param_id => "Blend the filtered and dry signals.",
        output_param_id => "Adjust the final output level.",
        else => "Adjust this parameter.",
    };
}

fn normalizedCutoff(frequency: f64) f64 {
    return @log(frequency / 20.0) / @log(1_000.0);
}

fn normalizedResonance(q: f64) f64 {
    return @log(q / 0.1) / @log(180.0);
}

fn filterKind(mode: FilterMode) core.dsp.BiquadKind {
    return switch (mode) {
        .low_pass => .low_pass,
        .high_pass => .high_pass,
        .band_pass => .band_pass,
        .notch => .notch,
    };
}

const ResonantFilterProcessor = struct {
    const Filter32 = core.dsp.SmoothedBiquad(f32);
    const Filter64 = core.dsp.SmoothedBiquad(f64);

    filters32: [2]Filter32 = .{ .{}, .{} },
    filters64: [2]Filter64 = .{ .{}, .{} },
    drive32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    drive64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    mix32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    mix64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    output32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    output64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),

    pub fn process(
        self: *ResonantFilterProcessor,
        parameters: anytype,
        comptime Sample: type,
        context: *core.process.ProcessContext(Sample),
    ) void {
        const bypassed = parameters.getNormalizedById(bypass_param_id) >= 0.5;
        const mode = (FilterModeParam{ .id = mode_param_id, .name = "Mode", .default = .low_pass }).denormalize(parameters.getNormalizedById(mode_param_id));
        const cutoff = plain(parameters, cutoff_param_id, 1_000.0);
        const resonance = plain(parameters, resonance_param_id, 0.707);
        const coefficients = (core.dsp.BiquadConfig{
            .kind = filterKind(mode),
            .sample_rate = context.sampleRate(),
            .frequency_hz = cutoff,
            .gain_db = 0.0,
            .q = resonance,
        }).coefficients() catch core.dsp.BiquadCoefficients.identity();
        const filters = if (Sample == f32) &self.filters32 else &self.filters64;
        for (filters) |*filter| filter.setTarget(coefficients, 64);

        const drive_smoother = if (Sample == f32) &self.drive32 else &self.drive64;
        const mix_smoother = if (Sample == f32) &self.mix32 else &self.mix64;
        const output_smoother = if (Sample == f32) &self.output32 else &self.output64;
        drive_smoother.setTarget(std.math.pow(f64, 10.0, plain(parameters, drive_param_id, 0.0) / 20.0), 64);
        mix_smoother.setTarget(plain(parameters, mix_param_id, 100.0) / 100.0, 64);
        output_smoother.setTarget(std.math.pow(f64, 10.0, plain(parameters, output_param_id, 0.0) / 20.0), 64);

        for (0..context.frameCount()) |sample_index| {
            const drive: Sample = @floatCast(drive_smoother.next());
            const wet_mix: Sample = @floatCast(mix_smoother.next());
            const output_gain: Sample = @floatCast(output_smoother.next());
            for (0..@min(context.outputChannelCount(), filters.len)) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                const dry = input[sample_index];
                if (bypassed) {
                    output[sample_index] = dry;
                    continue;
                }
                const filtered = filters[channel].process(dry);
                const colored = filtered / (1.0 + @abs(filtered) * (drive - 1.0));
                output[sample_index] = (dry + (colored - dry) * wet_mix) * output_gain;
            }
        }
    }

    fn plain(parameters: anytype, id: u32, fallback: f64) f64 {
        return filter_parameter_set.plainFromNormalizedById(id, parameters.getNormalizedById(id)) orelse fallback;
    }
};

pub const component_cid = vst3.tuid.inlineUid(0x4C17E9A2, 0x865B43D1, 0xA92F6710, 0x3DE8B5C4);
pub const resonant_filter_controller_cid = vst3.tuid.inlineUid(0xB8035D71, 0x2AF64CE9, 0x9174E20B, 0x6C3D8FA5);

const Effect = vst3.zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "ResonantFilterComponent";
    pub const controller_cid = resonant_filter_controller_cid;
    pub const Params = Spec.Params;
    pub const parameter_set = &filter_parameter_set;
    pub const Processor = ResonantFilterProcessor;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = resonant_filter_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "resonant filter exports component and controller classes" {
    const plugin_factory = Factory.getPluginFactory().?;
    var class_info: base.ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Resonant Filter", std.mem.sliceTo(&class_info.name, 0));
    try filter_parameter_set.validate();
}

test "resonant filter editor is available through the public authoring API" {
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    const view = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = view.vtable.release(view);

    var size = gui.iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, view.vtable.getSize(view, &size));
    try std.testing.expect(size.right > 0);
    try std.testing.expect(size.bottom > 0);
}

const TestParameters = struct {
    values: Spec.ParameterValues = Spec.ParameterValues.init(&filter_parameter_set),

    fn getNormalizedById(self: *const TestParameters, id: u32) f64 {
        return self.values.loadById(&filter_parameter_set, id) orelse 0.0;
    }

    fn store(self: *TestParameters, id: u32, normalized: f64) void {
        _ = self.values.storeById(&filter_parameter_set, id, normalized);
    }
};

test "resonant filter bypass is sample identical for f32 and f64" {
    inline for (.{ f32, f64 }) |Sample| {
        var processor = ResonantFilterProcessor{};
        var parameters = TestParameters{};
        parameters.store(bypass_param_id, 1.0);
        parameters.store(drive_param_id, 1.0);
        parameters.store(output_param_id, 1.0);
        const input = [_]Sample{ -0.75, -0.25, 0.0, 0.125, 0.875 };
        var output = [_]Sample{0.0} ** input.len;
        const input_channels = [_][]const Sample{&input};
        const output_channels = [_][]Sample{&output};
        var context = try core.process.ProcessContext(Sample).init(48_000.0, &input_channels, &output_channels);

        processor.process(&parameters, Sample, &context);
        try std.testing.expectEqualSlices(Sample, &input, &output);
    }
}

test "resonant filter dry mix converges to the input" {
    var processor = ResonantFilterProcessor{};
    var parameters = TestParameters{};
    parameters.store(mix_param_id, 0.0);
    parameters.store(drive_param_id, 1.0);
    var input: [192]f64 = undefined;
    var output = [_]f64{0.0} ** input.len;
    for (&input, 0..) |*sample, index| sample.* = std.math.sin(std.math.tau * 997.0 * @as(f64, @floatFromInt(index)) / 48_000.0);
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    var context = try core.process.ProcessContext(f64).init(48_000.0, &input_channels, &output_channels);

    processor.process(&parameters, f64, &context);
    for (input[64..], output[64..]) |expected, actual| try std.testing.expectApproxEqAbs(expected, actual, 0.0000001);
}

test "resonant filter processor instances keep independent modes" {
    var low_processor = ResonantFilterProcessor{};
    var high_processor = ResonantFilterProcessor{};
    var low_parameters = TestParameters{};
    var high_parameters = TestParameters{};
    high_parameters.store(mode_param_id, 1.0 / 3.0);
    var input: [256]f64 = undefined;
    var low_output = [_]f64{0.0} ** input.len;
    var high_output = [_]f64{0.0} ** input.len;
    for (&input, 0..) |*sample, index| sample.* = std.math.sin(std.math.tau * 100.0 * @as(f64, @floatFromInt(index)) / 48_000.0);
    const input_channels = [_][]const f64{&input};
    const low_channels = [_][]f64{&low_output};
    const high_channels = [_][]f64{&high_output};
    var low_context = try core.process.ProcessContext(f64).init(48_000.0, &input_channels, &low_channels);
    var high_context = try core.process.ProcessContext(f64).init(48_000.0, &input_channels, &high_channels);

    low_processor.process(&low_parameters, f64, &low_context);
    high_processor.process(&high_parameters, f64, &high_context);
    try std.testing.expect(@abs(low_output[255]) > @abs(high_output[255]) * 8.0);
    try std.testing.expectEqual(FilterMode.low_pass, (FilterModeParam{ .id = mode_param_id, .name = "Mode", .default = .low_pass }).denormalize(low_parameters.getNormalizedById(mode_param_id)));
}
