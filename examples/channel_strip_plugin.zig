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
pub const drive_param_id: u32 = 3;
pub const audio_import_id: u32 = 1;
pub const imported_waveform_source_id: u32 = 100;

pub const input_panel_expanded_state_id: u32 = 1;
pub const analyzer_mode_state_id: u32 = 2;
pub const selected_tab_state_id: u32 = 3;
pub const envelope_selection_state_id: u32 = 4;
pub const envelope_state_id: u32 = 5;
pub const preset_search_state_id: u32 = 6;
pub const preset_selection_state_id: u32 = 7;
pub const show_analyzer_state_id: u32 = 8;

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
        drive: core.parameters.FloatParam = .{
            .id = drive_param_id,
            .name = "Drive",
            .units = "dB",
            .min = -12.0,
            .max = 12.0,
            .default = 0.0,
        },
    };
};

pub const Spec = core.plugin.PluginSpec(ChannelStripDefinition);
pub const channel_parameter_set = Spec.ParameterSet.init(.{});

const transfer_points = blk: {
    @setEvalBranchQuota(4_000);
    var points: [33]vst3.vstgui.GraphPoint = undefined;
    for (&points, 0..) |*point, index| {
        const x = -2.0 + 4.0 * @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(points.len - 1));
        point.* = .{ .x = x, .y = std.math.tanh(x * 1.5) / std.math.tanh(@as(f64, 1.5)) };
    }
    break :blk points;
};

const envelope_points = [_]vst3.vstgui.EnvelopePoint{
    .{ .point_id = 1, .x = 0.0, .y = 0.0 },
    .{
        .point_id = 2,
        .x = 0.5,
        .y = 0.5,
        .x_parameter_id = gain_param_id,
        .y_parameter_id = drive_param_id,
        .parameter_mask = 3,
    },
    .{ .point_id = 3, .x = 1.0, .y = 0.0 },
};

const persisted_envelope = core.editor_state.Envelope.init(&.{
    .{ .id = 1, .x = 0.0, .y = 0.0 },
    .{ .id = 2, .x = 0.5, .y = 0.5 },
    .{ .id = 3, .x = 1.0, .y = 0.0 },
}) catch @compileError("invalid persisted envelope declaration");
const empty_preset_search = core.editor_state.Text.init("") catch
    @compileError("invalid empty preset search declaration");

const ChannelStripControllerState = struct {
    importer: vst3.vstgui.AudioFileImporter,

    pub fn init() ChannelStripControllerState {
        return .{ .importer = .init() };
    }

    pub fn deinit(self: *ChannelStripControllerState) void {
        self.importer.deinit();
    }
};

pub const ChannelStripEditorState = core.editor_state.Store(1, &.{
    .{ .id = input_panel_expanded_state_id, .default = .{ .boolean = true } },
    .{ .id = analyzer_mode_state_id, .default = .{ .index = 0 } },
    .{ .id = selected_tab_state_id, .default = .{ .index = 0 } },
    .{ .id = envelope_selection_state_id, .default = .{ .point_id = 2 } },
    .{ .id = envelope_state_id, .default = .{ .envelope = persisted_envelope } },
    .{ .id = preset_search_state_id, .default = .{ .text = empty_preset_search } },
    .{ .id = preset_selection_state_id, .default = .{ .index = 1 } },
    .{ .id = show_analyzer_state_id, .default = .{ .boolean = true } },
});

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
    pub const controller_name = "ChannelStripController";
    pub const Params = Spec.Params;
    pub const parameter_set = &channel_parameter_set;
    pub const EditorState = ChannelStripEditorState;
    pub const ControllerState = ChannelStripControllerState;

    pub fn handleFileImport(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
        entry_point: vst3.vstgui.FileImportEntryPoint,
        paths: []const []const u8,
    ) types.tresult {
        if (import_id != audio_import_id) return types.kInvalidArgument;
        return if (Controller.controllerState(controller).importer.begin(entry_point, paths))
            types.kResultOk
        else
            types.kResultFalse;
    }

    pub fn loadFileImport(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
    ) ?vst3.vstgui.AudioFileImportSnapshot {
        if (import_id != audio_import_id) return null;
        return Controller.controllerState(controller).importer.snapshot();
    }

    pub fn performFileImportCommand(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
        command: vst3.vstgui.FileImportCommand,
    ) types.tresult {
        if (import_id != audio_import_id) return types.kInvalidArgument;
        const importer = &Controller.controllerState(controller).importer;
        const handled = switch (command) {
            .cancel => importer.requestCancel(),
            .retry => importer.retry(),
            .reset => importer.reset(),
        };
        return if (handled) types.kResultOk else types.kResultFalse;
    }

    pub fn loadGuiGraph(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
        output: []vst3.vstgui.GraphPoint,
    ) usize {
        if (source_id != imported_waveform_source_id) return 0;
        var preview: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.AudioFilePreviewPoint = undefined;
        const count = Controller.controllerState(controller).importer.copyPreview(&preview);
        const copied = @min(count, output.len);
        for (preview[0..copied], output[0..copied]) |point, *destination| {
            destination.* = .{ .x = point.x, .y = point.y };
        }
        return copied;
    }

    pub fn loadPreset(controller: *vst.ivsteditcontroller.IEditController, preset_id: u32) types.tresult {
        const ids = [_]u32{ gain_param_id, drive_param_id, bypass_param_id, mode_param_id };
        const values = switch (preset_id) {
            1 => [_]f64{ 0.5, 0.5, 0.0, 0.0 },
            2 => [_]f64{ 0.58, 0.72, 0.0, 0.5 },
            3 => [_]f64{ 0.45, 0.85, 0.0, 1.0 },
            else => return types.kInvalidArgument,
        };
        return applyPreset(Controller, controller, &ids, &values);
    }

    pub fn performMenuAction(
        controller: *vst.ivsteditcontroller.IEditController,
        menu_id: u32,
        item_id: u32,
        _: bool,
    ) types.tresult {
        if (menu_id != 1) return types.kInvalidArgument;
        switch (item_id) {
            1 => return loadPreset(controller, 1),
            2 => return types.kResultOk,
            4 => {
                const state = Controller.editorState(controller);
                state.set(input_panel_expanded_state_id, .{ .boolean = true }) catch return types.kResultFalse;
                state.set(analyzer_mode_state_id, .{ .index = 0 }) catch return types.kResultFalse;
                state.set(selected_tab_state_id, .{ .index = 0 }) catch return types.kResultFalse;
                return types.kResultOk;
            },
            else => return types.kInvalidArgument,
        }
    }

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
                    .id = drive_param_id,
                    .title = "Drive",
                    .units = "dB",
                    .step_count = 0,
                    .default_normalized = 0.5,
                    .control_kind = .bipolar_slider,
                    .tooltip = "Drive into or pull back from the selected character stage. Command-click resets to zero.",
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
            .xy_pads = &.{.{
                .title = "Gain and Drive",
                .x_parameter_id = gain_param_id,
                .y_parameter_id = drive_param_id,
                .x_label = "Gain",
                .y_label = "Drive",
            }},
            .meters = &.{
                .{ .title = "Stereo", .kind = .stereo, .first_source_id = 0, .second_source_id = 1 },
                .{ .title = "Reduction", .kind = .gain_reduction, .first_source_id = 2 },
            },
            .graphs = &.{
                .{
                    .title = "Console Transfer",
                    .kind = .transfer_function,
                    .x_axis = .{ .minimum = -2.0, .maximum = 2.0, .label = "Input" },
                    .y_axis = .{ .minimum = -1.2, .maximum = 1.2, .label = "Output" },
                    .points = &transfer_points,
                },
                .{
                    .title = "Dynamics Envelope",
                    .kind = .envelope,
                    .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
                    .y_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Level" },
                    .editable_points = &envelope_points,
                    .point_capacity = 8,
                    .minimum_point_count = 2,
                    .snap_x = 0.05,
                    .snap_y = 0.05,
                    .selection_state_id = envelope_selection_state_id,
                    .envelope_state_id = envelope_state_id,
                },
                .{
                    .title = "Output Waveform",
                    .kind = .waveform,
                    .style = .modulation,
                    .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Frame" },
                    .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
                    .source_id = 0,
                    .dynamic = true,
                    .maximum_refresh_hz = 30,
                },
                .{
                    .title = "Output Spectrum",
                    .kind = .spectrum,
                    .x_axis = .{ .minimum = 20.0, .maximum = 24_000.0, .scale = .logarithmic, .label = "Hz" },
                    .y_axis = .{ .minimum = -96.0, .maximum = 0.0, .scale = .decibels, .label = "dB" },
                    .source_id = 1,
                    .dynamic = true,
                    .maximum_refresh_hz = 30,
                },
                .{
                    .title = "Imported Waveform",
                    .kind = .waveform,
                    .style = .secondary,
                    .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "File" },
                    .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
                    .source_id = imported_waveform_source_id,
                    .source = .controller,
                    .dynamic = true,
                    .maximum_refresh_hz = 20,
                },
            },
            .file_importers = &.{.{
                .id = audio_import_id,
                .title = "Audio Reference",
                .prompt = "Drop a PCM WAV file here",
                .picker_label = "Choose Audio File",
                .picker_title = "Choose a PCM WAV File",
                .extensions = &.{".wav"},
                .maximum_files = 1,
            }},
            .preset_browsers = &.{.{
                .title = "Channel Presets",
                .presets = &.{
                    .{ .id = 1, .name = "Clean Start" },
                    .{ .id = 2, .name = "Console Push" },
                    .{ .id = 3, .name = "Peak Limit" },
                },
                .search_state_id = preset_search_state_id,
                .selection_state_id = preset_selection_state_id,
            }},
            .action_menus = &.{.{
                .id = 1,
                .title = "Options",
                .items = &.{
                    .{ .id = 1, .label = "Reset Channel" },
                    .{ .id = 2, .label = "Show Analyzer", .kind = .toggle, .checked_state_id = show_analyzer_state_id },
                    .{ .id = 3, .label = "Export Preset", .enabled = false },
                    .{ .kind = .separator },
                    .{ .id = 4, .label = "Reset UI", .destructive = true },
                },
            }},
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
                        .parameter_count = 2,
                        .style = .{ .accent = 0x3578baff, .border = 0x7994aaff },
                        .xy_pad_count = 1,
                    },
                    .{
                        .title = "Character",
                        .first_parameter = 2,
                        .parameter_count = 2,
                        .first_xy_pad = 1,
                        .style = .{ .accent = 0xb96b32ff, .border = 0xac8b73ff },
                    },
                    .{
                        .title = "Output",
                        .first_parameter = 4,
                        .first_meter = 0,
                        .meter_count = 2,
                        .first_xy_pad = 1,
                        .style = .{ .accent = 0x35866aff, .border = 0x719789ff },
                        .graph_count = 5,
                    },
                },
            },
        });
    }
});

const ChannelStripProcessor = struct {
    const MeterBank = core.gui_telemetry.MeterBank(f64, 3);
    const Waveform = core.gui_graph.WaveformCapture(128);
    const Spectrum = core.gui_graph.SpectrumAnalyzer(128);

    meters: MeterBank = MeterBank.init(0.0),
    waveform: Waveform = Waveform.init(),
    spectrum: Spectrum = Spectrum.init(),

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
        const drive_parameter = core.parameters.FloatParam{
            .id = drive_param_id,
            .name = "Drive",
            .units = "dB",
            .min = -12.0,
            .max = 12.0,
            .default = 0.0,
        };
        const gain_db = gain_parameter.denormalize(parameters.getNormalizedById(gain_param_id));
        const gain = std.math.pow(f64, 10.0, gain_db / 20.0);
        const bypassed = parameters.getNormalizedById(bypass_param_id) >= 0.5;
        const mode = mode_parameter.denormalize(parameters.getNormalizedById(mode_param_id));
        const drive_db = drive_parameter.denormalize(parameters.getNormalizedById(drive_param_id));
        const drive = std.math.pow(f64, 10.0, drive_db / 20.0);

        const telemetry_active = self.meters.producing();
        var peaks = [_]f64{ 0.0, 0.0 };
        var maximum_unshaped: f64 = 0.0;
        var maximum_shaped: f64 = 0.0;
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample_index| {
                const input_sample = input[sample_index];
                const output_sample = processSample(Sample, input_sample, gain, drive, bypassed, mode);
                output[sample_index] = output_sample;
                if (telemetry_active) {
                    const output_magnitude = @abs(@as(f64, @floatCast(output_sample)));
                    if (channel < peaks.len) peaks[channel] = @max(peaks[channel], output_magnitude);
                    maximum_unshaped = @max(maximum_unshaped, @abs(@as(f64, @floatCast(input_sample))) * drive * gain);
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
        if (context.outputChannel(0)) |output| {
            _ = self.waveform.capture(output);
            _ = self.spectrum.push(output, context.sampleRate());
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
        self.waveform.editorOpened();
        self.spectrum.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *ChannelStripProcessor) void {
        self.meters.editorClosed();
        self.waveform.editorClosed();
        self.spectrum.editorClosed();
    }

    pub fn guiGraphLoad(self: *ChannelStripProcessor, source_id: types.uint32, output: []core.gui_graph.Point) usize {
        return switch (source_id) {
            0 => self.waveform.read(output) orelse 0,
            1 => self.spectrum.read(output) orelse 0,
            else => 0,
        };
    }
};

const RuntimeProcessor = struct {
    pub const name = ChannelStripDefinition.name;
    pub const vendor = ChannelStripDefinition.vendor;
    pub const url = ChannelStripDefinition.url;
    pub const Params = ChannelStripDefinition.Params;

    const ParameterAdapter = struct {
        view: core.parameters.ParameterView(Params),

        pub fn getNormalizedById(
            self: ParameterAdapter,
            id: u32,
        ) f64 {
            return self.view.loadById(id) orelse 0.0;
        }
    };

    engine: ChannelStripProcessor = .{},

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

    pub fn guiTelemetryLoad(
        self: *RuntimeProcessor,
        source_id: u32,
    ) f64 {
        return self.engine.guiTelemetryLoad(source_id);
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

    pub fn publishTelemetry(
        self: *RuntimeProcessor,
        left: f64,
        right: f64,
        reduction: f64,
    ) void {
        self.engine.publishTelemetry(
            left,
            right,
            reduction,
        );
    }
};

const Vst3ChannelStripProcessor =
    vst3.zig_vst3_plugin_runtime_adapter.Processor(
        RuntimeProcessor,
    );

fn processSample(comptime Sample: type, input: Sample, gain: f64, drive: f64, bypassed: bool, mode: Mode) Sample {
    if (bypassed) return input;
    const driven = @as(f64, @floatCast(input)) * drive;
    const shaped = switch (mode) {
        .clean => driven,
        .console => std.math.tanh(driven * 1.5) / std.math.tanh(@as(f64, 1.5)),
        .limit => std.math.clamp(driven, -1.0, 1.0),
    };
    return @floatCast(shaped * gain);
}

const Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect(
        RuntimeProcessor,
        struct {
            pub const component_name = "ChannelStripComponent";
            pub const controller_cid = channel_controller_cid;
        },
    );

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
    try std.testing.expect(
        Vst3ChannelStripProcessor.hasGuiTelemetryLoad,
    );
    try std.testing.expect(
        Vst3ChannelStripProcessor.hasGuiGraphLoad,
    );
    try std.testing.expect(
        Vst3ChannelStripProcessor.hasGuiTelemetryEditorOpened,
    );
    try std.testing.expect(
        Vst3ChannelStripProcessor.hasGuiTelemetryEditorClosed,
    );

    const plugin_factory = ChannelStripFactory.getPluginFactory().?;
    var class_info: base.ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Channel Strip", std.mem.sliceTo(&class_info.name, 0));
}

test "channel strip processing modes preserve their contracts" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), processSample(f32, 0.5, 1.0, 1.0, false, .clean), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), processSample(f32, 0.5, 4.0, 2.0, true, .limit), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), processSample(f32, 0.75, 2.0, 1.0, false, .limit), 0.0001);
    try std.testing.expect(processSample(f64, 0.75, 2.0, 1.0, false, .console) < 2.0);
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
    try std.testing.expectEqual(@as(types.int32, 720), second_size.right);
    try std.testing.expectEqual(@as(types.int32, 600), second_size.bottom);
}

test "channel strip survives concurrent headless host lifecycle stress" {
    const report = try vst3.testing.vstgui_headless_host.run(struct {
        pub const component_create = Effect.create;
        pub const controller_create = Controller.create;
    }, .{});
    try std.testing.expectEqual(@as(usize, 12), report.editor_lifecycles);
    try std.testing.expect(report.process_blocks >= 128);
}

test "channel strip importer survives editor reopen and publishes its controller graph" {
    const frame_count = 1024;
    var wav_bytes: [44 + frame_count * 2]u8 = undefined;
    var writer = std.Io.Writer.fixed(&wav_bytes);
    try writer.writeAll("RIFF");
    try writer.writeInt(u32, wav_bytes.len - 8, .little);
    try writer.writeAll("WAVEfmt ");
    try writer.writeInt(u32, 16, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 48_000, .little);
    try writer.writeInt(u32, 96_000, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u16, 16, .little);
    try writer.writeAll("data");
    try writer.writeInt(u32, frame_count * 2, .little);
    for (0..frame_count) |index| {
        const sample: i16 = if (index % 2 == 0) 12_000 else -12_000;
        try writer.writeInt(i16, sample, .little);
    }
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "reference.wav", .data = writer.buffered() });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "reference.wav", &path);

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    const first_view = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        controller,
        audio_import_id,
        .picker,
        &.{path[0..path_length]},
    ));
    _ = first_view.vtable.release(first_view);
    const second_view = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = second_view.vtable.release(second_view);

    var attempts: usize = 0;
    while (attempts < 1_000_000) : (attempts += 1) {
        const snapshot = Controller.loadFileImport(controller, audio_import_id) orelse return error.MissingImportState;
        if (snapshot.import.status == .ready) break;
        if (snapshot.import.status != .validating and snapshot.import.status != .importing) return error.ImportFailed;
        std.Thread.yield() catch {};
    }
    try std.testing.expect(attempts < 1_000_000);
    const snapshot = Controller.loadFileImport(controller, audio_import_id) orelse return error.MissingImportState;
    try std.testing.expectEqual(core.gui_file_importer.Status.ready, snapshot.import.status);
    try std.testing.expectEqual(core.gui_file_importer.EntryPoint.picker, snapshot.import.entry_point);
    var graph: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.GraphPoint = undefined;
    try std.testing.expectEqual(
        @as(usize, vst3.vstgui.audio_file_preview_capacity),
        Controller.loadGuiGraph(controller, imported_waveform_source_id, &graph),
    );
    try std.testing.expectEqual(@as(f64, 0.0), graph[0].x);
    try std.testing.expectEqual(@as(f64, 1.0), graph[graph.len - 1].x);
}

test "channel strip controller state is serialized and instance isolated" {
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &second_out));
    const first: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(first_out orelse return error.MissingController));
    defer _ = first.vtable.release(first);
    const second: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(second_out orelse return error.MissingController));
    defer _ = second.vtable.release(second);

    try Controller.editorState(first).set(input_panel_expanded_state_id, .{ .boolean = false });
    try Controller.editorState(first).set(show_analyzer_state_id, .{ .boolean = false });
    try std.testing.expect(Controller.editorState(second).get(input_panel_expanded_state_id).?.boolean);
    try std.testing.expect(Controller.editorState(second).get(show_analyzer_state_id).?.boolean);
    const Stream = vst3.vst_stream.FixedBufferStream(65536);
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, first.vtable.getState(first, stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, second.vtable.setState(second, stream.asStream()));
    try std.testing.expect(!Controller.editorState(second).get(input_panel_expanded_state_id).?.boolean);
    try std.testing.expect(!Controller.editorState(second).get(show_analyzer_state_id).?.boolean);
    try std.testing.expectEqual(@as(f64, 0.5), Controller.getNormalized(second, gain_param_id));
    try std.testing.expectEqual(
        core.gui_file_importer.Status.idle,
        (Controller.loadFileImport(second, audio_import_id) orelse return error.MissingImportState).import.status,
    );
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
    var signal: [128]f64 = undefined;
    for (&signal, 0..) |*sample, index| {
        sample.* = std.math.sin(std.math.tau * 8.0 * @as(f64, @floatFromInt(index)) / 128.0);
    }
    try std.testing.expect(first.waveform.capture(&signal));
    try std.testing.expect(first.spectrum.push(&signal, 48_000.0));
    try std.testing.expectEqual(@as(f64, 0.75), first.guiTelemetryLoad(0));
    try std.testing.expectEqual(@as(f64, 0.5), first.guiTelemetryLoad(1));
    try std.testing.expectEqual(@as(f64, 0.25), first.guiTelemetryLoad(2));
    try std.testing.expectEqual(@as(f64, 0.0), second.guiTelemetryLoad(0));
    var waveform: [128]core.gui_graph.Point = undefined;
    var spectrum: [64]core.gui_graph.Point = undefined;
    try std.testing.expectEqual(@as(usize, 128), first.guiGraphLoad(0, &waveform));
    try std.testing.expectEqual(@as(usize, 64), first.guiGraphLoad(1, &spectrum));
    try std.testing.expectEqual(@as(usize, 0), second.guiGraphLoad(0, &waveform));
    try std.testing.expect(spectrum[7].y > -1.0);

    first.guiTelemetryEditorClosed();
    first.publishTelemetry(0.5, 0.5, 0.5);
    try std.testing.expectEqual(@as(f64, 0.5), first.guiTelemetryLoad(0));
    first.guiTelemetryEditorClosed();
    first.publishTelemetry(1.0, 1.0, 1.0);
    try std.testing.expect(!first.waveform.capture(&signal));
    try std.testing.expect(!first.spectrum.push(&signal, 48_000.0));
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

    Effect.processorInstance(component)
        .runtime.instance.plugin
        .publishTelemetry(0.8, 0.6, 0.4);
    try std.testing.expectEqual(@as(f64, 0.8), source.load(0));
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.disconnect(controller_connection, component_connection));
    try std.testing.expectEqual(@as(f64, 0.8), source.load(0));
}
