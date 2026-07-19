const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const gui = vst3.pluginterfaces.gui;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const bypass_param_id: u32 = 0;
pub const output_param_id: u32 = 1;
pub const low_enabled_param_id: u32 = 10;
pub const low_type_param_id: u32 = 11;
pub const low_frequency_param_id: u32 = 12;
pub const low_gain_param_id: u32 = 13;
pub const low_q_param_id: u32 = 14;
pub const mid_enabled_param_id: u32 = 20;
pub const mid_type_param_id: u32 = 21;
pub const mid_frequency_param_id: u32 = 22;
pub const mid_gain_param_id: u32 = 23;
pub const mid_q_param_id: u32 = 24;
pub const high_enabled_param_id: u32 = 30;
pub const high_type_param_id: u32 = 31;
pub const high_frequency_param_id: u32 = 32;
pub const high_gain_param_id: u32 = 33;
pub const high_q_param_id: u32 = 34;
const response_graph_source_id: u32 = 1;
const low_response_source_id: u32 = 2;
const mid_response_source_id: u32 = 3;
const high_response_source_id: u32 = 4;
const response_point_count: usize = 97;
const spectrum_source_id: u32 = 0;
const eq_asset_id: u32 = 1;
const eq_curve_svg =
    "<svg viewBox=\"0 0 24 24\">" ++
    "<path d=\"M2 17 C6 17 7 7 12 7 C17 7 18 15 22 15\" fill=\"none\" stroke=\"#d7f5ed\" stroke-width=\"2\"/>" ++
    "</svg>";

fn bandAccent(parameter_id: u32) u32 {
    return if (parameter_id >= high_enabled_param_id)
        0xf0ad65ff
    else if (parameter_id >= mid_enabled_param_id)
        0xb58ce8ff
    else if (parameter_id >= low_enabled_param_id)
        0x4ed9b4ff
    else
        0x75b9f0ff;
}

fn drawEqParameter(
    _: ?*anyopaque,
    request: *const vst3.vstgui.DrawRequest,
    canvas: *vst3.vstgui.Canvas,
) callconv(.c) types.int32 {
    if (request.component == .knob) {
        const diameter = @min(8.0, @min(request.width, request.height) * 0.12);
        vst3.vstgui.fillEllipse(
            canvas,
            request.width - diameter - 5.0,
            5.0,
            request.width - 5.0,
            5.0 + diameter,
            bandAccent(request.parameter_id),
        );
        return 0;
    }
    if (request.parameter_id != bypass_param_id or request.component != .toggle) return 0;
    const side = @min(request.height - 10.0, 22.0);
    const top = (request.height - side) * 0.5;
    const drawn = vst3.vstgui.drawAsset(
        canvas,
        eq_asset_id,
        8.0,
        top,
        8.0 + side,
        top + side,
        if (request.state == .disabled) 0.45 else 1.0,
    );
    return if (drawn) 0 else -1;
}

const eq_skin: vst3.vstgui.Skin = .{
    .assets = &.{.{ .id = eq_asset_id, .data = eq_curve_svg, .format = .svg }},
    .fonts = .{
        .title_family = "Avenir Next",
        .body_family = "Avenir Next",
        .value_family = "Menlo",
        .fallback_family = "Arial",
    },
    .drawing = .{ .draw_parameter = drawEqParameter },
    .theme = .default,
    .layout = .adaptive,
};

pub const FilterType = enum { low_shelf, bell, high_shelf };
pub const FilterTypeParam = core.parameters.EnumParam(FilterType);

const Definition = struct {
    pub const name = "zig-vst3 Parametric EQ";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        bypass: core.parameters.BoolParam = .{ .id = bypass_param_id, .name = "Bypass", .is_bypass = true },
        output: core.parameters.FloatParam = .{ .id = output_param_id, .name = "Output", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        low_enabled: core.parameters.BoolParam = .{ .id = low_enabled_param_id, .name = "Low Enable", .default = true },
        low_type: FilterTypeParam = .{ .id = low_type_param_id, .name = "Low Type", .default = .low_shelf },
        low_frequency: core.parameters.LogFloatParam = .{ .id = low_frequency_param_id, .name = "Low Frequency", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 120.0 },
        low_gain: core.parameters.FloatParam = .{ .id = low_gain_param_id, .name = "Low Gain", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        low_q: core.parameters.LogFloatParam = .{ .id = low_q_param_id, .name = "Low Q", .min = 0.1, .max = 18.0, .default = 0.707 },
        mid_enabled: core.parameters.BoolParam = .{ .id = mid_enabled_param_id, .name = "Mid Enable", .default = true },
        mid_type: FilterTypeParam = .{ .id = mid_type_param_id, .name = "Mid Type", .default = .bell },
        mid_frequency: core.parameters.LogFloatParam = .{ .id = mid_frequency_param_id, .name = "Mid Frequency", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 1_000.0 },
        mid_gain: core.parameters.FloatParam = .{ .id = mid_gain_param_id, .name = "Mid Gain", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        mid_q: core.parameters.LogFloatParam = .{ .id = mid_q_param_id, .name = "Mid Q", .min = 0.1, .max = 18.0, .default = 1.0 },
        high_enabled: core.parameters.BoolParam = .{ .id = high_enabled_param_id, .name = "High Enable", .default = true },
        high_type: FilterTypeParam = .{ .id = high_type_param_id, .name = "High Type", .default = .high_shelf },
        high_frequency: core.parameters.LogFloatParam = .{ .id = high_frequency_param_id, .name = "High Frequency", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 8_000.0 },
        high_gain: core.parameters.FloatParam = .{ .id = high_gain_param_id, .name = "High Gain", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        high_q: core.parameters.LogFloatParam = .{ .id = high_q_param_id, .name = "High Q", .min = 0.1, .max = 18.0, .default = 0.707 },
    };
};

pub const Spec = core.plugin.PluginSpec(Definition);
pub const eq_parameter_set = Spec.ParameterSet.init(.{});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ParametricEqController";
    pub const Params = Spec.Params;
    pub const parameter_set = &eq_parameter_set;

    pub fn createView(
        controller: *vst.ivsteditcontroller.IEditController,
        name: types.FIDString,
    ) ?*gui.iplugview.IPlugView {
        return vst3.vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{
                parameterControl(bypass_param_id, "Bypass", "", 1, 0.0, .toggle),
                parameterControl(output_param_id, "Output", "dB", 0, 0.5, .decibel_slider),
                parameterControl(low_enabled_param_id, "Enable", "", 1, 1.0, .toggle),
                parameterControl(low_type_param_id, "Type", "", 2, 0.0, .enum_dropdown),
                parameterControl(low_frequency_param_id, "Frequency", "Hz", 0, normalizedFrequency(120.0), .rotary_knob),
                parameterControl(low_gain_param_id, "Gain", "dB", 0, 0.5, .rotary_knob),
                parameterControl(low_q_param_id, "Q", "", 0, normalizedQ(0.707), .rotary_knob),
                parameterControl(mid_enabled_param_id, "Enable", "", 1, 1.0, .toggle),
                parameterControl(mid_type_param_id, "Type", "", 2, 0.5, .enum_dropdown),
                parameterControl(mid_frequency_param_id, "Frequency", "Hz", 0, normalizedFrequency(1_000.0), .rotary_knob),
                parameterControl(mid_gain_param_id, "Gain", "dB", 0, 0.5, .rotary_knob),
                parameterControl(mid_q_param_id, "Q", "", 0, normalizedQ(1.0), .rotary_knob),
                parameterControl(high_enabled_param_id, "Enable", "", 1, 1.0, .toggle),
                parameterControl(high_type_param_id, "Type", "", 2, 1.0, .enum_dropdown),
                parameterControl(high_frequency_param_id, "Frequency", "Hz", 0, normalizedFrequency(8_000.0), .rotary_knob),
                parameterControl(high_gain_param_id, "Gain", "dB", 0, 0.5, .rotary_knob),
                parameterControl(high_q_param_id, "Q", "", 0, normalizedQ(0.707), .rotary_knob),
            },
            .graphs = &.{
                .{
                    .title = "EQ Response",
                    .kind = .transfer_function,
                    .x_axis = .{ .minimum = 20.0, .maximum = 20_000.0, .scale = .logarithmic, .label = "Hz" },
                    .y_axis = .{ .minimum = -24.0, .maximum = 24.0, .scale = .decibels, .label = "dB" },
                    .source_id = response_graph_source_id,
                    .source = .controller,
                    .parameter_driven = true,
                    .maximum_refresh_hz = 30,
                    .handles = &.{
                        .{ .id = 1, .name = "Low", .x_parameter_id = low_frequency_param_id, .y_parameter_id = low_gain_param_id, .adjustment_parameter_id = low_q_param_id, .adjustment_label = "Q", .enabled_parameter_id = low_enabled_param_id, .highlight_group_index = 1 },
                        .{ .id = 2, .name = "Mid", .x_parameter_id = mid_frequency_param_id, .y_parameter_id = mid_gain_param_id, .adjustment_parameter_id = mid_q_param_id, .adjustment_label = "Q", .enabled_parameter_id = mid_enabled_param_id, .highlight_group_index = 2 },
                        .{ .id = 3, .name = "High", .x_parameter_id = high_frequency_param_id, .y_parameter_id = high_gain_param_id, .adjustment_parameter_id = high_q_param_id, .adjustment_label = "Q", .enabled_parameter_id = high_enabled_param_id, .highlight_group_index = 3 },
                    },
                    .layers = &.{
                        .{ .style = .secondary, .source_id = low_response_source_id, .source = .controller, .parameter_driven = true },
                        .{ .style = .modulation, .source_id = mid_response_source_id, .source = .controller, .parameter_driven = true },
                        .{ .style = .secondary, .source_id = high_response_source_id, .source = .controller, .parameter_driven = true },
                        .{
                            .style = .secondary,
                            .kind = .spectrum,
                            .source_id = spectrum_source_id,
                            .dynamic = true,
                            .y_axis = .{ .minimum = -96.0, .maximum = 0.0, .scale = .decibels, .label = "dB" },
                        },
                    },
                },
            },
            .skin = eq_skin,
            .composition = .{
                .title = "Parametric EQ",
                .style = .{ .background = 0x101720ff, .foreground = 0xe9f1f5ff },
                .groups = &.{
                    .{ .title = "Master", .parameter_count = 2, .graph_count = 1, .style = .{ .accent = 0x75b9f0ff } },
                    .{ .title = "Low", .first_parameter = 2, .parameter_count = 5, .first_graph = 1, .style = .{ .accent = 0x4ed9b4ff } },
                    .{ .title = "Mid", .first_parameter = 7, .parameter_count = 5, .first_graph = 1, .style = .{ .accent = 0xb58ce8ff } },
                    .{ .title = "High", .first_parameter = 12, .parameter_count = 5, .first_graph = 1, .style = .{ .accent = 0xf0ad65ff } },
                },
            },
        });
    }

    pub fn loadGuiGraph(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
        output: []vst3.vstgui.GraphPoint,
    ) usize {
        if (source_id < response_graph_source_id or source_id > high_response_source_id or
            output.len < response_point_count) return 0;
        const bypassed = Controller.getNormalized(controller, bypass_param_id) >= 0.5;
        const output_db = eq_parameter_set.plainFromNormalizedById(
            output_param_id,
            Controller.getNormalized(controller, output_param_id),
        ) orelse 0.0;
        var coefficients: [band_parameter_ids.len]core.dsp.BiquadCoefficients = undefined;
        for (band_parameter_ids, 0..) |ids, index| {
            const enabled = !bypassed and Controller.getNormalized(controller, ids.enabled) >= 0.5;
            const filter_type = (FilterTypeParam{ .id = ids.filter_type, .name = "Type", .default = .bell }).denormalize(
                Controller.getNormalized(controller, ids.filter_type),
            );
            coefficients[index] = if (enabled)
                (core.dsp.BiquadConfig{
                    .kind = switch (filter_type) {
                        .low_shelf => .low_shelf,
                        .bell => .bell,
                        .high_shelf => .high_shelf,
                    },
                    .sample_rate = 48_000.0,
                    .frequency_hz = eq_parameter_set.plainFromNormalizedById(ids.frequency, Controller.getNormalized(controller, ids.frequency)) orelse 1_000.0,
                    .gain_db = eq_parameter_set.plainFromNormalizedById(ids.gain, Controller.getNormalized(controller, ids.gain)) orelse 0.0,
                    .q = eq_parameter_set.plainFromNormalizedById(ids.q, Controller.getNormalized(controller, ids.q)) orelse 1.0,
                }).coefficients() catch core.dsp.BiquadCoefficients.identity()
            else
                core.dsp.BiquadCoefficients.identity();
        }
        for (output[0..response_point_count], 0..) |*point, index| {
            const normalized = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(response_point_count - 1));
            const frequency = 20.0 * std.math.pow(f64, 1_000.0, normalized);
            var magnitude_db: f64 = 0.0;
            if (source_id == response_graph_source_id) {
                magnitude_db = if (bypassed) 0.0 else output_db;
                for (coefficients) |filter| magnitude_db += filter.magnitudeDb(48_000.0, frequency);
            } else {
                magnitude_db = coefficients[source_id - low_response_source_id].magnitudeDb(48_000.0, frequency);
            }
            point.* = .{ .x = frequency, .y = magnitude_db };
        }
        return response_point_count;
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
        .modulation_normalized = if (id == mid_gain_param_id) 0.68 else null,
    };
}

fn parameterTooltip(id: u32) [*:0]const u8 {
    return switch (id) {
        low_frequency_param_id, mid_frequency_param_id, high_frequency_param_id => "Set the band frequency. Hold Shift for fine adjustment; Command-click resets.",
        low_gain_param_id, mid_gain_param_id, high_gain_param_id => "Set the band gain. Hold Shift for fine adjustment; Command-click resets.",
        low_q_param_id, mid_q_param_id, high_q_param_id => "Set the band width. Hold Shift for fine adjustment; Command-click resets.",
        bypass_param_id => "Bypass all EQ processing.",
        output_param_id => "Adjust the EQ output level.",
        low_enabled_param_id, mid_enabled_param_id, high_enabled_param_id => "Enable or disable this band.",
        low_type_param_id, mid_type_param_id, high_type_param_id => "Choose the band filter type.",
        else => "Adjust this parameter.",
    };
}

fn normalizedFrequency(frequency: f64) f64 {
    return @log(frequency / 20.0) / @log(1_000.0);
}

fn normalizedQ(q: f64) f64 {
    return @log(q / 0.1) / @log(180.0);
}

const BandParameterIds = struct {
    enabled: u32,
    filter_type: u32,
    frequency: u32,
    gain: u32,
    q: u32,
};

const band_parameter_ids = [_]BandParameterIds{
    .{ .enabled = low_enabled_param_id, .filter_type = low_type_param_id, .frequency = low_frequency_param_id, .gain = low_gain_param_id, .q = low_q_param_id },
    .{ .enabled = mid_enabled_param_id, .filter_type = mid_type_param_id, .frequency = mid_frequency_param_id, .gain = mid_gain_param_id, .q = mid_q_param_id },
    .{ .enabled = high_enabled_param_id, .filter_type = high_type_param_id, .frequency = high_frequency_param_id, .gain = high_gain_param_id, .q = high_q_param_id },
};

const EqProcessor = struct {
    const Filter32 = core.dsp.SmoothedBiquad(f32);
    const Filter64 = core.dsp.SmoothedBiquad(f64);
    const Spectrum = core.gui_graph.SpectrumAnalyzer(128);

    filters32: [2][3]Filter32 = .{ .{ .{}, .{}, .{} }, .{ .{}, .{}, .{} } },
    filters64: [2][3]Filter64 = .{ .{ .{}, .{}, .{} }, .{ .{}, .{}, .{} } },
    output32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    output64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    spectrum: Spectrum = Spectrum.init(),

    pub fn process(
        self: *EqProcessor,
        parameters: anytype,
        comptime Sample: type,
        context: *core.process.ProcessContext(Sample),
    ) void {
        const bypassed = parameters.getNormalizedById(bypass_param_id) >= 0.5;
        const output_db = eq_parameter_set.plainFromNormalizedById(output_param_id, parameters.getNormalizedById(output_param_id)) orelse 0.0;
        const output_gain = std.math.pow(f64, 10.0, output_db / 20.0);
        const smoother = if (Sample == f32) &self.output32 else &self.output64;
        smoother.setTarget(output_gain, 64);
        const filters = if (Sample == f32) &self.filters32 else &self.filters64;
        configureFilters(filters, parameters, context.sampleRate());

        for (0..context.frameCount()) |sample_index| {
            const gain: Sample = @floatCast(smoother.next());
            for (0..@min(context.outputChannelCount(), filters.len)) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                if (bypassed) {
                    output[sample_index] = input[sample_index];
                    continue;
                }
                var sample = input[sample_index];
                for (&filters[channel]) |*filter| sample = filter.process(sample);
                output[sample_index] = sample * gain;
            }
        }
        if (context.outputChannel(0)) |output| _ = self.spectrum.push(output, context.sampleRate());
    }

    fn configureFilters(filters: anytype, parameters: anytype, sample_rate: f64) void {
        for (band_parameter_ids, 0..) |ids, band| {
            const enabled = parameters.getNormalizedById(ids.enabled) >= 0.5;
            const filter_type = (FilterTypeParam{ .id = ids.filter_type, .name = "Type", .default = .bell }).denormalize(parameters.getNormalizedById(ids.filter_type));
            const frequency = eq_parameter_set.plainFromNormalizedById(ids.frequency, parameters.getNormalizedById(ids.frequency)) orelse 1_000.0;
            const gain_db = eq_parameter_set.plainFromNormalizedById(ids.gain, parameters.getNormalizedById(ids.gain)) orelse 0.0;
            const q = eq_parameter_set.plainFromNormalizedById(ids.q, parameters.getNormalizedById(ids.q)) orelse 1.0;
            const coefficients = if (enabled)
                (core.dsp.BiquadConfig{
                    .kind = switch (filter_type) {
                        .low_shelf => .low_shelf,
                        .bell => .bell,
                        .high_shelf => .high_shelf,
                    },
                    .sample_rate = sample_rate,
                    .frequency_hz = frequency,
                    .gain_db = gain_db,
                    .q = q,
                }).coefficients() catch core.dsp.BiquadCoefficients.identity()
            else
                core.dsp.BiquadCoefficients.identity();
            for (filters) |*channel| channel[band].setTarget(coefficients, 64);
        }
    }

    pub fn guiTelemetryEditorOpened(self: *EqProcessor) void {
        self.spectrum.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *EqProcessor) void {
        self.spectrum.editorClosed();
    }

    pub fn guiGraphLoad(self: *EqProcessor, source_id: types.uint32, output: []core.gui_graph.Point) usize {
        if (source_id != 0) return 0;
        return self.spectrum.read(output) orelse 0;
    }
};

pub const component_cid = vst3.tuid.inlineUid(0x5A58C6F1, 0x1D8947E2, 0xA19B3C7D, 0x8E2014F6);
pub const parametric_eq_controller_cid = vst3.tuid.inlineUid(0x9F624B30, 0x7C1542D8, 0xB503E91A, 0x6D84F2C7);

const Effect = vst3.zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "ParametricEqComponent";
    pub const controller_cid = parametric_eq_controller_cid;
    pub const Params = Spec.Params;
    pub const parameter_set = &eq_parameter_set;
    pub const Processor = EqProcessor;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = parametric_eq_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "parametric EQ exports component and controller classes" {
    const plugin_factory = Factory.getPluginFactory().?;
    var class_info: base.ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Parametric EQ", std.mem.sliceTo(&class_info.name, 0));
    try eq_parameter_set.validate();
}

test "parametric EQ component instances isolate parameter state" {
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &second_out));
    const first: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(first_out orelse return error.MissingComponent));
    defer _ = first.vtable.release(first);
    const second: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(second_out orelse return error.MissingComponent));
    defer _ = second.vtable.release(second);

    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(first, mid_gain_param_id, 0.75));
    try std.testing.expectEqual(@as(f64, 0.75), Effect.getParameterNormalized(first, mid_gain_param_id));
    try std.testing.expectEqual(@as(f64, 0.5), Effect.getParameterNormalized(second, mid_gain_param_id));
}

test "parametric EQ response is finite across its display range" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    var response_points: [response_point_count]vst3.vstgui.GraphPoint = undefined;
    try std.testing.expectEqual(response_points.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response_points));
    for (response_points) |point| {
        try std.testing.expect(std.math.isFinite(point.x));
        try std.testing.expect(std.math.isFinite(point.y));
        try std.testing.expect(point.x >= 20.0 and point.x <= 20_000.0);
    }
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setParamNormalized(controller, mid_gain_param_id, 0.75));
    try std.testing.expectEqual(response_points.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response_points));
    var maximum_gain: f64 = -std.math.inf(f64);
    for (response_points) |point| maximum_gain = @max(maximum_gain, point.y);
    try std.testing.expect(maximum_gain > 8.0);
    var mid_response: [response_point_count]vst3.vstgui.GraphPoint = undefined;
    try std.testing.expectEqual(mid_response.len, Controller.loadGuiGraph(controller, mid_response_source_id, &mid_response));
    var maximum_mid_gain: f64 = -std.math.inf(f64);
    for (mid_response) |point| maximum_mid_gain = @max(maximum_mid_gain, point.y);
    try std.testing.expect(maximum_mid_gain > 8.0);
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setParamNormalized(controller, bypass_param_id, 1.0));
    try std.testing.expectEqual(response_points.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response_points));
    for (response_points) |point| try std.testing.expectApproxEqAbs(@as(f64, 0.0), point.y, 0.0000001);
}

const TestParameters = struct {
    values: Spec.ParameterValues = Spec.ParameterValues.init(&eq_parameter_set),

    fn getNormalizedById(self: *const TestParameters, id: u32) f64 {
        return self.values.loadById(&eq_parameter_set, id) orelse 0.0;
    }

    fn store(self: *TestParameters, id: u32, normalized: f64) void {
        _ = self.values.storeById(&eq_parameter_set, id, normalized);
    }
};

test "parametric EQ bypass is sample identical for f32 and f64" {
    inline for (.{ f32, f64 }) |Sample| {
        var processor = EqProcessor{};
        var parameters = TestParameters{};
        parameters.store(bypass_param_id, 1.0);
        const input = [_]Sample{ -0.75, -0.25, 0.0, 0.125, 0.875 };
        var output = [_]Sample{0.0} ** input.len;
        const input_channels = [_][]const Sample{&input};
        const output_channels = [_][]Sample{&output};
        var context = try core.process.ProcessContext(Sample).init(48_000.0, &input_channels, &output_channels);

        processor.process(&parameters, Sample, &context);
        try std.testing.expectEqualSlices(Sample, &input, &output);
    }
}

test "parametric EQ unity settings preserve the input" {
    var processor = EqProcessor{};
    var parameters = TestParameters{};
    var input: [256]f64 = undefined;
    var output = [_]f64{0.0} ** input.len;
    for (&input, 0..) |*sample, index| sample.* = std.math.sin(std.math.tau * 997.0 * @as(f64, @floatFromInt(index)) / 48_000.0);
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    var context = try core.process.ProcessContext(f64).init(48_000.0, &input_channels, &output_channels);

    processor.process(&parameters, f64, &context);
    for (input, output) |expected, actual| try std.testing.expectApproxEqAbs(expected, actual, 0.0000001);
}

test "parametric EQ analyzer is bounded and editor activity gated" {
    var active = EqProcessor{};
    var inactive = EqProcessor{};
    var parameters = TestParameters{};
    var input: [128]f32 = undefined;
    var active_output = [_]f32{0.0} ** input.len;
    var inactive_output = [_]f32{0.0} ** input.len;
    for (&input, 0..) |*sample, index| {
        sample.* = @floatCast(std.math.sin(std.math.tau * 3_000.0 *
            @as(f64, @floatFromInt(index)) / 48_000.0));
    }
    const input_channels = [_][]const f32{&input};
    const active_channels = [_][]f32{&active_output};
    const inactive_channels = [_][]f32{&inactive_output};
    var active_context = try core.process.ProcessContext(f32).init(48_000.0, &input_channels, &active_channels);
    var inactive_context = try core.process.ProcessContext(f32).init(48_000.0, &input_channels, &inactive_channels);

    active.guiTelemetryEditorOpened();
    active.guiTelemetryEditorOpened();
    active.process(&parameters, f32, &active_context);
    inactive.process(&parameters, f32, &inactive_context);

    var points: [64]core.gui_graph.Point = undefined;
    try std.testing.expectEqual(@as(usize, 64), active.guiGraphLoad(spectrum_source_id, &points));
    try std.testing.expectEqual(@as(usize, 0), inactive.guiGraphLoad(spectrum_source_id, &points));
    try std.testing.expect(active.spectrum.producing());
    try std.testing.expect(!inactive.spectrum.producing());
    active.guiTelemetryEditorClosed();
    try std.testing.expect(active.spectrum.producing());
    active.guiTelemetryEditorClosed();
    try std.testing.expect(!active.spectrum.producing());
}

test "parametric EQ skin uses public assets fonts and custom drawing" {
    try std.testing.expectEqual(@as(usize, 1), eq_skin.assets.len);
    try std.testing.expectEqual(vst3.vstgui.AssetFormat.svg, eq_skin.assets[0].format);
    try std.testing.expect(eq_skin.fonts.fallback_family != null);
    try std.testing.expect(eq_skin.drawing.draw_parameter != null);
}
