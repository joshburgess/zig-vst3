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
const response_graph_source_id: u32 = 1;
const spectrum_source_id: u32 = 0;
const response_point_count: usize = 97;
const preset_search_state_id: u32 = 1;
const preset_selection_state_id: u32 = 2;
const selected_handle_state_id: u32 = 3;
const empty_preset_search = core.editor_state.Text.init("") catch
    @compileError("invalid empty preset search declaration");

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

const FilterEditorState = core.editor_state.Store(1, &.{
    .{ .id = preset_search_state_id, .default = .{ .text = empty_preset_search } },
    .{ .id = preset_selection_state_id, .default = .{ .index = 1 } },
    .{ .id = selected_handle_state_id, .default = .{ .point_id = 1 } },
});

const filter_skin: vst3.vstgui.Skin = .{
    .theme = .default,
    .layout = .parameter_workspace,
};

fn applyPreset(
    comptime ControllerType: type,
    iface: *vst.ivsteditcontroller.IEditController,
    ids: []const u32,
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

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ResonantFilterController";
    pub const Params = Spec.Params;
    pub const parameter_set = &filter_parameter_set;
    pub const EditorState = FilterEditorState;

    pub fn loadGuiGraph(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
        output: []vst3.vstgui.GraphPoint,
    ) usize {
        if (source_id != response_graph_source_id or output.len < response_point_count) return 0;
        const bypassed = Controller.getNormalized(controller, bypass_param_id) >= 0.5;
        const mode = (FilterModeParam{ .id = mode_param_id, .name = "Mode", .default = .low_pass }).denormalize(Controller.getNormalized(controller, mode_param_id));
        const coefficients = (core.dsp.BiquadConfig{
            .kind = filterKind(mode),
            .sample_rate = 48_000.0,
            .frequency_hz = controllerPlain(controller, cutoff_param_id, 1_000.0),
            .gain_db = 0.0,
            .q = controllerPlain(controller, resonance_param_id, 0.707),
        }).coefficients() catch core.dsp.BiquadCoefficients.identity();
        const wet = controllerPlain(controller, mix_param_id, 100.0) / 100.0;
        const output_db = controllerPlain(controller, output_param_id, 0.0);
        for (output[0..response_point_count], 0..) |*point, index| {
            const normalized = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(response_point_count - 1));
            const frequency = 20.0 * std.math.pow(f64, 1_000.0, normalized);
            const response = coefficients.response(48_000.0, frequency);
            const real = (1.0 - wet) + wet * response.real;
            const imaginary = wet * response.imaginary;
            const magnitude = @sqrt(real * real + imaginary * imaginary);
            const response_db = if (magnitude <= std.math.floatEps(f64)) -160.0 else 20.0 * std.math.log10(magnitude);
            point.* = .{ .x = frequency, .y = if (bypassed) 0.0 else output_db + response_db };
        }
        return response_point_count;
    }

    pub fn loadPreset(controller: *vst.ivsteditcontroller.IEditController, preset_id: u32) types.tresult {
        const ids = [_]u32{ bypass_param_id, output_param_id, mode_param_id, cutoff_param_id, resonance_param_id, drive_param_id, mix_param_id };
        const values = switch (preset_id) {
            1 => [_]f64{ 0.0, 0.5, 0.0, normalizedCutoff(1_000.0), normalizedResonance(0.707), 0.0, 1.0 },
            2 => [_]f64{ 0.0, 0.5, 1.0 / 3.0, normalizedCutoff(250.0), normalizedResonance(4.0), 0.25, 1.0 },
            3 => [_]f64{ 0.0, 0.5, 2.0 / 3.0, normalizedCutoff(2_000.0), normalizedResonance(3.0), 0.33, 0.85 },
            4 => [_]f64{ 0.0, 0.5, 1.0, normalizedCutoff(60.0), normalizedResonance(8.0), 0.0, 1.0 },
            else => return types.kInvalidArgument,
        };
        return applyPreset(Controller, controller, &ids, &values);
    }

    pub fn createView(
        controller: *vst.ivsteditcontroller.IEditController,
        name: types.FIDString,
    ) ?*gui.iplugview.IPlugView {
        return vst3.vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{
                parameterControl(bypass_param_id, "Bypass", "", 1, 0.0, .toggle),
                parameterControl(output_param_id, "Output", "dB", 0, 0.5, .decibel_slider),
                parameterControl(mode_param_id, "Mode", "", 3, 0.0, .segmented_enum),
                parameterControl(cutoff_param_id, "Cutoff", "Hz", 0, normalizedCutoff(1_000.0), .rotary_knob),
                parameterControl(resonance_param_id, "Resonance", "", 0, normalizedResonance(0.707), .rotary_knob),
                parameterControl(drive_param_id, "Drive", "dB", 0, 0.0, .rotary_knob),
                parameterControl(mix_param_id, "Mix", "%", 0, 1.0, .linear_slider),
            },
            .graphs = &.{.{
                .title = "Filter Response",
                .kind = .transfer_function,
                .x_axis = .{ .minimum = 20.0, .maximum = 20_000.0, .scale = .logarithmic, .label = "Hz" },
                .y_axis = .{ .minimum = -20.0, .maximum = 25.105450102, .scale = .decibels, .label = "dB" },
                .source_id = response_graph_source_id,
                .source = .controller,
                .parameter_driven = true,
                .maximum_refresh_hz = 30,
                .selection_state_id = selected_handle_state_id,
                .handles = &.{.{
                    .id = 1,
                    .name = "Cutoff and resonance",
                    .x_parameter_id = cutoff_param_id,
                    .y_parameter_id = resonance_param_id,
                    .highlight_group_index = 1,
                }},
                .layers = &.{.{
                    .style = .secondary,
                    .kind = .spectrum,
                    .source_id = spectrum_source_id,
                    .dynamic = true,
                    .y_axis = .{ .minimum = -96.0, .maximum = 0.0, .scale = .decibels, .label = "dB" },
                }},
            }},
            .preset_browsers = &.{.{
                .title = "Filter Presets",
                .presets = &.{
                    .{ .id = 1, .name = "Smooth Low Pass" },
                    .{ .id = 2, .name = "Resonant High Pass" },
                    .{ .id = 3, .name = "Band Focus" },
                    .{ .id = 4, .name = "Notch Cleanup" },
                },
                .search_state_id = preset_search_state_id,
                .selection_state_id = preset_selection_state_id,
            }},
            .skin = filter_skin,
            .composition = .{
                .title = "Resonant Filter",
                .style = .{ .background = 0x111922ff, .foreground = 0xeaf3f6ff, .accent = 0x52d5b0ff },
                .groups = &.{
                    .{ .title = "Response", .parameter_count = 2, .graph_count = 1, .style = .{ .accent = 0x79baf2ff } },
                    .{ .title = "Filter", .first_parameter = 2, .parameter_count = 3, .first_graph = 1, .style = .{ .accent = 0x52d5b0ff } },
                    .{ .title = "Color", .first_parameter = 5, .parameter_count = 2, .first_graph = 1, .style = .{ .accent = 0xf0ad65ff } },
                },
            },
        });
    }
});

fn controllerPlain(controller: *vst.ivsteditcontroller.IEditController, id: u32, fallback: f64) f64 {
    return filter_parameter_set.plainFromNormalizedById(id, Controller.getNormalized(controller, id)) orelse fallback;
}

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
    const Spectrum = core.gui_graph.SpectrumAnalyzer(128);

    filters32: [2]Filter32 = .{ .{}, .{} },
    filters64: [2]Filter64 = .{ .{}, .{} },
    drive32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    drive64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    mix32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    mix64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    output32: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    output64: core.parameters.LinearSmoother = core.parameters.LinearSmoother.init(1.0),
    spectrum: Spectrum = Spectrum.init(),

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
        if (context.outputChannel(0)) |output| _ = self.spectrum.push(output, context.sampleRate());
    }

    pub fn guiTelemetryEditorOpened(self: *ResonantFilterProcessor) void {
        self.spectrum.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *ResonantFilterProcessor) void {
        self.spectrum.editorClosed();
    }

    pub fn guiGraphLoad(self: *ResonantFilterProcessor, source_id: types.uint32, output: []core.gui_graph.Point) usize {
        if (source_id != spectrum_source_id) return 0;
        return self.spectrum.read(output) orelse 0;
    }

    fn plain(parameters: anytype, id: u32, fallback: f64) f64 {
        return filter_parameter_set.plainFromNormalizedById(id, parameters.getNormalizedById(id)) orelse fallback;
    }
};

const RuntimeProcessor = struct {
    pub const name = Definition.name;
    pub const vendor = Definition.vendor;
    pub const url = Definition.url;
    pub const Params = Definition.Params;

    const ParameterAdapter = struct {
        view: core.parameters.ParameterView(Params),

        pub fn getNormalizedById(
            self: ParameterAdapter,
            id: u32,
        ) f64 {
            return self.view.loadById(id) orelse 0.0;
        }
    };

    engine: ResonantFilterProcessor = .{},

    pub fn processWithParameterView(
        self: *RuntimeProcessor,
        context: *core.process.ProcessContext(f32),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        self.engine.process(
            ParameterAdapter{ .view = parameters },
            f32,
            context,
        );
    }

    pub fn process64WithParameterView(
        self: *RuntimeProcessor,
        context: *core.process.ProcessContext(f64),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        self.engine.process(
            ParameterAdapter{ .view = parameters },
            f64,
            context,
        );
    }

    pub fn guiGraphLoad(
        self: *RuntimeProcessor,
        source_id: u32,
        output: []core.gui_graph.Point,
    ) usize {
        return self.engine.guiGraphLoad(source_id, output);
    }

    pub fn guiTelemetryEditorOpened(
        self: *RuntimeProcessor,
    ) void {
        self.engine.guiTelemetryEditorOpened();
    }

    pub fn guiTelemetryEditorClosed(
        self: *RuntimeProcessor,
    ) void {
        self.engine.guiTelemetryEditorClosed();
    }
};

const Vst3ResonantFilterProcessor =
    vst3.zig_vst3_plugin_runtime_adapter.Processor(
        RuntimeProcessor,
    );

pub const component_cid = vst3.tuid.inlineUid(0x4C17E9A2, 0x865B43D1, 0xA92F6710, 0x3DE8B5C4);
pub const resonant_filter_controller_cid = vst3.tuid.inlineUid(0xB8035D71, 0x2AF64CE9, 0x9174E20B, 0x6C3D8FA5);

const Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect(
        RuntimeProcessor,
        struct {
            pub const component_name = "ResonantFilterComponent";
            pub const controller_cid =
                resonant_filter_controller_cid;
        },
    );

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
    try std.testing.expect(
        Vst3ResonantFilterProcessor.hasGuiGraphLoad,
    );
    try std.testing.expect(
        Vst3ResonantFilterProcessor
            .hasGuiTelemetryEditorOpened,
    );
    try std.testing.expect(
        Vst3ResonantFilterProcessor
            .hasGuiTelemetryEditorClosed,
    );

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
    try std.testing.expectEqual(@as(types.int32, 720), size.right);
    try std.testing.expectEqual(@as(types.int32, 660), size.bottom);
    var constrained = gui.iplugview.ViewRect{ .left = 0, .top = 0, .right = 120, .bottom = 100 };
    try std.testing.expectEqual(types.kResultOk, view.vtable.checkSizeConstraint(view, &constrained));
    try std.testing.expectEqual(@as(types.int32, 400), constrained.right);
    try std.testing.expectEqual(@as(types.int32, 360), constrained.bottom);
}

test "resonant filter survives concurrent headless host lifecycle stress" {
    const report = try vst3.testing.vstgui_headless_host.run(struct {
        pub const component_create = Effect.create;
        pub const controller_create = Controller.create;
    }, .{});
    try std.testing.expectEqual(@as(usize, 12), report.editor_lifecycles);
    try std.testing.expect(report.process_blocks >= 128);
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

test "resonant filter response follows mode mix output and bypass" {
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);

    var response: [response_point_count]vst3.vstgui.GraphPoint = undefined;
    try std.testing.expectEqual(response.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response));
    try std.testing.expect(response[0].y > -0.1);
    try std.testing.expect(response[response.len - 1].y < -30.0);

    try std.testing.expectEqual(types.kResultOk, controller.vtable.setParamNormalized(controller, mode_param_id, 1.0 / 3.0));
    try std.testing.expectEqual(response.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response));
    try std.testing.expect(response[0].y < -30.0);
    try std.testing.expect(response[response.len - 1].y > -0.1);

    try std.testing.expectEqual(types.kResultOk, controller.vtable.setParamNormalized(controller, mix_param_id, 0.0));
    try std.testing.expectEqual(response.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response));
    for (response) |point| try std.testing.expectApproxEqAbs(@as(f64, 0.0), point.y, 0.0000001);

    try std.testing.expectEqual(types.kResultOk, controller.vtable.setParamNormalized(controller, output_param_id, 2.0 / 3.0));
    try std.testing.expectEqual(response.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response));
    for (response) |point| try std.testing.expectApproxEqAbs(@as(f64, 6.0), point.y, 0.0000001);

    try std.testing.expectEqual(types.kResultOk, controller.vtable.setParamNormalized(controller, bypass_param_id, 1.0));
    try std.testing.expectEqual(response.len, Controller.loadGuiGraph(controller, response_graph_source_id, &response));
    for (response) |point| try std.testing.expectApproxEqAbs(@as(f64, 0.0), point.y, 0.0000001);
}

test "resonant filter presets update the complete accepted state" {
    const HostHandler = vst3.vst_component_handler.ComponentHandler2(struct {});
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setComponentHandler(controller, handler.asHandler()));
    defer _ = controller.vtable.setComponentHandler(controller, null);

    try std.testing.expectEqual(types.kResultOk, Controller.loadPreset(controller, 3));
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), Controller.getNormalized(controller, mode_param_id), 0.0000001);
    try std.testing.expectApproxEqAbs(normalizedCutoff(2_000.0), Controller.getNormalized(controller, cutoff_param_id), 0.0000001);
    try std.testing.expectApproxEqAbs(normalizedResonance(3.0), Controller.getNormalized(controller, resonance_param_id), 0.0000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.85), Controller.getNormalized(controller, mix_param_id), 0.0000001);
    try std.testing.expectEqual(@as(types.uint32, 7), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 7), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 7), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.start_group_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.finish_group_count);
    try std.testing.expectEqual(types.kInvalidArgument, Controller.loadPreset(controller, 0));
}

test "resonant filter analyzer is bounded and editor activity gated" {
    var active = ResonantFilterProcessor{};
    var inactive = ResonantFilterProcessor{};
    var parameters = TestParameters{};
    var input: [128]f32 = undefined;
    var active_output = [_]f32{0.0} ** input.len;
    var inactive_output = [_]f32{0.0} ** input.len;
    for (&input, 0..) |*sample, index| sample.* = @floatCast(std.math.sin(std.math.tau * 3_000.0 * @as(f64, @floatFromInt(index)) / 48_000.0));
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

test "resonant filter editor state is instance local" {
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &second_out));
    const first: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(first_out orelse return error.MissingController));
    defer _ = first.vtable.release(first);
    const second: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(second_out orelse return error.MissingController));
    defer _ = second.vtable.release(second);

    try Controller.editorState(first).set(preset_selection_state_id, .{ .index = 4 });
    try std.testing.expectEqual(@as(u32, 4), Controller.editorState(first).get(preset_selection_state_id).?.index);
    try std.testing.expectEqual(@as(u32, 1), Controller.editorState(second).get(preset_selection_state_id).?.index);
    try std.testing.expectEqual(@as(u32, 1), Controller.editorState(second).get(selected_handle_state_id).?.point_id);
}
