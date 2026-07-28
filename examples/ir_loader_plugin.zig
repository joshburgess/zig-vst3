const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const gui = vst3.pluginterfaces.gui;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const wet_param_id: u32 = 0;
pub const output_param_id: u32 = 1;
pub const bypass_param_id: u32 = 2;
pub const ir_import_id: u32 = 1;
pub const ir_waveform_source_id: u32 = 100;
pub const ir_edit_action_group_id: u32 = 1;
pub const trim_action_id: u32 = 1;
pub const normalize_action_id: u32 = 2;
pub const reverse_action_id: u32 = 3;
pub const fade_in_action_id: u32 = 4;
pub const fade_out_action_id: u32 = 5;
pub const reset_action_id: u32 = 6;
pub const ir_destructive_action_group_id: u32 = 2;
pub const clear_ir_action_id: u32 = 1;
pub const ir_name_state_id: u32 = 1;
pub const ir_zoom_state_id: u32 = 2;
pub const ir_x_offset_state_id: u32 = 3;
pub const ir_selection_start_state_id: u32 = 4;
pub const ir_selection_end_state_id: u32 = 5;
pub const ir_format_state_id: u32 = 6;
pub const ir_original_duration_state_id: u32 = 7;
pub const ir_edited_duration_state_id: u32 = 8;
pub const ir_peak_state_id: u32 = 9;
pub const ir_publish_state_id: u32 = 10;
pub const maximum_ir_frames: usize = 131_072;
pub const convolution_partition_size: usize = 512;

const impulse_asset_id: u32 = 1;
const impulse_svg =
    "<svg viewBox=\"0 0 24 24\">" ++
    "<path d=\"M2 12 L7 12 L9 4 L12 20 L15 8 L17 12 L22 12\" fill=\"none\" stroke=\"#f2f4f7\" stroke-width=\"2\"/>" ++
    "</svg>";

fn drawIRParameter(
    _: ?*anyopaque,
    request: *const vst3.vstgui.DrawRequest,
    canvas: *vst3.vstgui.Canvas,
) callconv(.c) types.int32 {
    if (request.parameter_id != bypass_param_id or request.component != .toggle) return 0;
    const side = @min(request.height - 8.0, 24.0);
    const top = (request.height - side) * 0.5;
    const background: u32 = if (request.normalized >= 0.5) 0xb9472fff else 0x263140ff;
    vst3.vstgui.fillEllipse(canvas, 8.0, top, 8.0 + side, top + side, background);
    const drawn = vst3.vstgui.drawAsset(
        canvas,
        impulse_asset_id,
        10.0,
        top + 2.0,
        6.0 + side,
        top + side - 2.0,
        if (request.state == .disabled) 0.45 else 1.0,
    );
    return if (drawn) 0 else -1;
}

const ir_skin: vst3.vstgui.Skin = .{
    .assets = &.{.{ .id = impulse_asset_id, .data = impulse_svg, .format = .svg }},
    .fonts = .{
        .title_family = "Avenir Next",
        .body_family = "Avenir Next",
        .value_family = "Menlo",
        .fallback_family = "Arial",
    },
    .drawing = .{ .draw_parameter = drawIRParameter },
    .theme = .alternate,
    .layout = .adaptive,
};

const Definition = struct {
    pub const name = "zig-vst3 IR Loader";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        wet: core.parameters.FloatParam = .{
            .id = wet_param_id,
            .name = "Wet",
            .units = "%",
            .min = 0.0,
            .max = 100.0,
            .default = 100.0,
        },
        output: core.parameters.FloatParam = .{
            .id = output_param_id,
            .name = "Output",
            .units = "dB",
            .min = -24.0,
            .max = 12.0,
            .default = 0.0,
        },
        bypass: core.parameters.BoolParam = .{
            .id = bypass_param_id,
            .name = "Bypass",
            .default = false,
            .is_bypass = true,
        },
    };
};

pub const Spec = core.plugin.PluginSpec(Definition);
pub const ir_parameter_set = Spec.ParameterSet.init(.{});
const Convolver = core.gui_ir_convolution.PartitionedConvolver(maximum_ir_frames, convolution_partition_size);
const IREditor = core.gui_ir_editor.Editor(maximum_ir_frames);
const AudioImporter = vst3.vstgui.DecodedAudioFileImporter(maximum_ir_frames);
const default_ir_name = core.editor_state.Text.init("Untitled IR") catch unreachable;
const empty_ir_format = core.editor_state.Text.init("No IR loaded") catch unreachable;
const zero_ir_duration = core.editor_state.Text.init("0.000 s") catch unreachable;
const zero_ir_peak = core.editor_state.Text.init("0.000") catch unreachable;
const empty_ir_state = core.editor_state.Text.init("Empty") catch unreachable;
const IREditorState = core.editor_state.Store(1, &.{
    .{ .id = ir_name_state_id, .default = .{ .text = default_ir_name } },
    .{ .id = ir_zoom_state_id, .default = .{ .scalar = 1.0 } },
    .{ .id = ir_x_offset_state_id, .default = .{ .scalar = 0.0 } },
    .{ .id = ir_selection_start_state_id, .default = .{ .scalar = 0.0 } },
    .{ .id = ir_selection_end_state_id, .default = .{ .scalar = 1.0 } },
    .{ .id = ir_format_state_id, .default = .{ .text = empty_ir_format } },
    .{ .id = ir_original_duration_state_id, .default = .{ .text = zero_ir_duration } },
    .{ .id = ir_edited_duration_state_id, .default = .{ .text = zero_ir_duration } },
    .{ .id = ir_peak_state_id, .default = .{ .text = zero_ir_peak } },
    .{ .id = ir_publish_state_id, .default = .{ .text = empty_ir_state } },
});

const IRControllerState = struct {
    importer: AudioImporter,
    editor: IREditor = .{},
    published_import_generation: u64 = 0,
    transfer_generation: u64 = 0,

    pub fn init() IRControllerState {
        return .{ .importer = .init() };
    }

    pub fn deinit(self: *IRControllerState) void {
        self.importer.deinit();
    }
};

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "IRLoaderController";
    pub const Params = Spec.Params;
    pub const parameter_set = &ir_parameter_set;
    pub const ControllerState = IRControllerState;
    pub const EditorState = IREditorState;

    pub fn handleFileImport(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
        entry_point: vst3.vstgui.FileImportEntryPoint,
        paths: []const []const u8,
    ) types.tresult {
        if (import_id != ir_import_id) return types.kInvalidArgument;
        return if (Controller.controllerState(controller).importer.begin(entry_point, paths))
            types.kResultOk
        else
            types.kResultFalse;
    }

    pub fn loadFileImport(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
    ) ?vst3.vstgui.AudioFileImportSnapshot {
        if (import_id != ir_import_id) return null;
        const state = Controller.controllerState(controller);
        const snapshot = state.importer.snapshot();
        if (snapshot.import.status == .ready and snapshot.import.generation != state.published_import_generation) {
            state.editor.loadFrom(&state.importer) catch return snapshot;
            const generation = vst3.gui_ir_transport.nextGeneration(state.transfer_generation);
            if (Controller.sendDecodedAudioGeneration(
                controller,
                ir_import_id,
                generation,
                &state.editor,
            ) == types.kResultOk) {
                state.transfer_generation = generation;
                state.published_import_generation = snapshot.import.generation;
                updateEditorMetadata(controller, state, "Published");
            }
        }
        return snapshot;
    }

    pub fn performFileImportCommand(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
        command: vst3.vstgui.FileImportCommand,
    ) types.tresult {
        if (import_id != ir_import_id) return types.kInvalidArgument;
        const state = Controller.controllerState(controller);
        const handled = switch (command) {
            .cancel => state.importer.requestCancel(),
            .retry => state.importer.retry(),
            .reset => clearImport(controller, state),
        };
        return if (handled) types.kResultOk else types.kResultFalse;
    }

    pub fn afterStateRestore(controller: *vst.ivsteditcontroller.IEditController) void {
        const state = Controller.controllerState(controller);
        const publication = if (state.editor.snapshot().decoded_frames == 0) "Empty" else "Published";
        updateEditorMetadata(controller, state, publication);
    }

    pub fn performAction(
        controller: *vst.ivsteditcontroller.IEditController,
        group_id: u32,
        action_id: u32,
    ) types.tresult {
        const state = Controller.controllerState(controller);
        if (group_id == ir_destructive_action_group_id and action_id == clear_ir_action_id) {
            return if (clearImport(controller, state)) types.kResultOk else types.kResultFalse;
        }
        if (group_id != ir_edit_action_group_id) return types.kInvalidArgument;
        const command: core.gui_ir_editor.Command = switch (action_id) {
            trim_action_id => .trim,
            normalize_action_id => .normalize,
            reverse_action_id => .reverse,
            fade_in_action_id => .fade_in,
            fade_out_action_id => .fade_out,
            reset_action_id => .reset,
            else => return types.kInvalidArgument,
        };
        const editor_state = Controller.editorState(controller);
        const selection_start = switch (editor_state.get(ir_selection_start_state_id) orelse return types.kResultFalse) {
            .scalar => |value| value,
            else => return types.kResultFalse,
        };
        const selection_end = switch (editor_state.get(ir_selection_end_state_id) orelse return types.kResultFalse) {
            .scalar => |value| value,
            else => return types.kResultFalse,
        };
        if (!(state.editor.apply(command, selection_start, selection_end) catch false)) return types.kResultFalse;
        const generation = vst3.gui_ir_transport.nextGeneration(state.transfer_generation);
        if (Controller.sendDecodedAudioGeneration(
            controller,
            ir_import_id,
            generation,
            &state.editor,
        ) != types.kResultOk) {
            state.editor.rollbackLastEdit();
            updateEditorMetadata(controller, state, "Publish failed");
            return types.kResultFalse;
        }
        state.editor.commitLastEdit();
        state.transfer_generation = generation;
        updateEditorMetadata(controller, state, "Published");
        return types.kResultOk;
    }

    pub fn validateEditorText(
        _: *vst.ivsteditcontroller.IEditController,
        field_id: u32,
        text: []const u8,
    ) types.tresult {
        if (field_id != ir_name_state_id) return types.kInvalidArgument;
        return if (std.mem.trim(u8, text, " \t\r\n").len == 0) types.kResultFalse else types.kResultOk;
    }

    pub fn loadGuiProgress(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
    ) ?core.gui_progress.Snapshot {
        if (source_id != ir_import_id) return null;
        const snapshot = Controller.controllerState(controller).importer.snapshot().import;
        return switch (snapshot.status) {
            .idle => .{ .generation = snapshot.generation },
            .validating => .{ .mode = .indeterminate, .state = .running, .generation = snapshot.generation },
            .importing => .{ .state = .running, .value = snapshot.progress(), .generation = snapshot.generation },
            .ready => .{ .state = .complete, .value = 1.0, .generation = snapshot.generation },
            else => .{ .state = .failed, .value = snapshot.progress(), .generation = snapshot.generation },
        };
    }

    fn clearImport(controller: *vst.ivsteditcontroller.IEditController, state: *IRControllerState) bool {
        if (!state.importer.canReset()) return false;
        const generation = vst3.gui_ir_transport.nextGeneration(state.transfer_generation);
        if (Controller.clearDecodedAudio(controller, ir_import_id, generation) != types.kResultOk) return false;
        if (!state.importer.reset()) return false;
        _ = state.editor.clear();
        state.transfer_generation = generation;
        state.published_import_generation = 0;
        updateEditorMetadata(controller, state, "Empty");
        return true;
    }

    fn updateEditorMetadata(
        controller: *vst.ivsteditcontroller.IEditController,
        state: *IRControllerState,
        publish_state: []const u8,
    ) void {
        const snapshot = state.editor.snapshot();
        var format_buffer: [64]u8 = undefined;
        var original_duration_buffer: [32]u8 = undefined;
        var edited_duration_buffer: [32]u8 = undefined;
        var peak_buffer: [64]u8 = undefined;
        const format = if (snapshot.sample_rate == 0)
            "No IR loaded"
        else
            std.fmt.bufPrint(&format_buffer, "{d} Hz, {d} ch", .{ snapshot.sample_rate, snapshot.channels }) catch return;
        const original_duration = std.fmt.bufPrint(
            &original_duration_buffer,
            "{d:.3} s",
            .{if (snapshot.sample_rate == 0) 0.0 else @as(f64, @floatFromInt(snapshot.original_frames)) / @as(f64, @floatFromInt(snapshot.sample_rate))},
        ) catch return;
        const edited_duration = std.fmt.bufPrint(
            &edited_duration_buffer,
            "{d:.3} s",
            .{if (snapshot.sample_rate == 0) 0.0 else @as(f64, @floatFromInt(snapshot.decoded_frames)) / @as(f64, @floatFromInt(snapshot.sample_rate))},
        ) catch return;
        const peak_text = std.fmt.bufPrint(
            &peak_buffer,
            "{d:.3} original, {d:.3} edited",
            .{ snapshot.original_peak, snapshot.edited_peak },
        ) catch return;
        const editor_state = Controller.editorState(controller);
        editor_state.set(ir_format_state_id, .{ .text = core.editor_state.Text.init(format) catch return }) catch return;
        editor_state.set(ir_original_duration_state_id, .{ .text = core.editor_state.Text.init(original_duration) catch return }) catch return;
        editor_state.set(ir_edited_duration_state_id, .{ .text = core.editor_state.Text.init(edited_duration) catch return }) catch return;
        editor_state.set(ir_peak_state_id, .{ .text = core.editor_state.Text.init(peak_text) catch return }) catch return;
        editor_state.set(ir_publish_state_id, .{ .text = core.editor_state.Text.init(publish_state) catch return }) catch return;
    }

    pub fn loadGuiGraph(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
        output: []vst3.vstgui.GraphPoint,
    ) usize {
        if (source_id != ir_waveform_source_id) return 0;
        var preview: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.AudioFilePreviewPoint = undefined;
        const count = Controller.controllerState(controller).editor.copyPreview(&preview);
        const copied = @min(count, output.len);
        for (preview[0..copied], output[0..copied]) |point, *destination| {
            destination.* = .{ .x = point.x, .y = point.y };
        }
        return copied;
    }

    pub fn createView(
        controller: *vst.ivsteditcontroller.IEditController,
        name: types.FIDString,
    ) ?*gui.iplugview.IPlugView {
        return vst3.vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{
                .{
                    .id = wet_param_id,
                    .title = "Wet",
                    .units = "%",
                    .step_count = 0,
                    .default_normalized = 1.0,
                    .control_kind = .linear_slider,
                    .tooltip = "Blend the latency-matched dry signal with the convolved signal.",
                },
                .{
                    .id = output_param_id,
                    .title = "Output",
                    .units = "dB",
                    .step_count = 0,
                    .default_normalized = 2.0 / 3.0,
                    .control_kind = .decibel_slider,
                    .tooltip = "Adjust the final output level after the wet and dry blend.",
                },
                .{
                    .id = bypass_param_id,
                    .title = "Bypass",
                    .step_count = 1,
                    .default_normalized = 0.0,
                    .control_kind = .toggle,
                },
            },
            .graphs = &.{.{
                .title = "Impulse Response",
                .kind = .waveform,
                .style = .modulation,
                .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
                .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
                .source_id = ir_waveform_source_id,
                .source = .controller,
                .dynamic = true,
                .maximum_refresh_hz = 20,
                .viewport = .{
                    .maximum_zoom = 128.0,
                    .zoom_state_id = ir_zoom_state_id,
                    .x_offset_state_id = ir_x_offset_state_id,
                },
                .range_selection = .{
                    .minimum_span = 1.0 / @as(f64, maximum_ir_frames),
                    .step = 1.0 / 1024.0,
                    .start_state_id = ir_selection_start_state_id,
                    .end_state_id = ir_selection_end_state_id,
                },
            }},
            .file_importers = &.{.{
                .id = ir_import_id,
                .title = "Impulse Response",
                .prompt = "Drop a PCM WAV impulse response here",
                .picker_label = "Choose IR",
                .picker_title = "Choose an Impulse Response",
                .extensions = &.{".wav"},
                .maximum_files = 1,
            }},
            .action_buttons = &.{
                .{ .group_id = ir_edit_action_group_id, .id = trim_action_id, .label = "Trim", .accessible_label = "Trim to selection", .tooltip = "Load an IR to enable trimming", .failure_label = "Trim failed. Adjust the selection and retry", .role = .primary, .ready_importer_id = ir_import_id },
                .{ .group_id = ir_edit_action_group_id, .id = normalize_action_id, .label = "Normalize", .accessible_label = "Normalize selection", .tooltip = "Load an IR to enable normalization", .failure_label = "Normalize needs a selection with audio", .ready_importer_id = ir_import_id },
                .{ .group_id = ir_edit_action_group_id, .id = reverse_action_id, .label = "Reverse", .accessible_label = "Reverse selection", .tooltip = "Load an IR to enable reversing", .failure_label = "Reverse needs at least two frames", .ready_importer_id = ir_import_id },
                .{ .group_id = ir_edit_action_group_id, .id = fade_in_action_id, .label = "Fade In", .accessible_label = "Fade in selection", .tooltip = "Load an IR to enable fades", .failure_label = "Fade in needs at least two frames", .ready_importer_id = ir_import_id },
                .{ .group_id = ir_edit_action_group_id, .id = fade_out_action_id, .label = "Fade Out", .accessible_label = "Fade out selection", .tooltip = "Load an IR to enable fades", .failure_label = "Fade out needs at least two frames", .ready_importer_id = ir_import_id },
                .{ .group_id = ir_edit_action_group_id, .id = reset_action_id, .label = "Reset", .accessible_label = "Reset all impulse response edits", .tooltip = "Load an IR to enable reset", .failure_label = "Nothing to reset", .ready_importer_id = ir_import_id },
                .{
                    .group_id = ir_destructive_action_group_id,
                    .id = clear_ir_action_id,
                    .icon = .clear,
                    .accessible_label = "Clear impulse response",
                    .tooltip = "Remove the imported impulse response.",
                    .confirmation_label = "Confirm Clear IR",
                    .failure_label = "Clear failed. Try again",
                    .role = .destructive,
                    .success_focus_importer_id = ir_import_id,
                    .ready_importer_id = ir_import_id,
                },
            },
            .editable_labels = &.{
                .{
                    .field_id = ir_name_state_id,
                    .label = "IR Name",
                    .accessible_label = "Impulse response name",
                    .placeholder = "Name this impulse response",
                    .error_text = "Enter an IR name",
                    .maximum_bytes = 64,
                },
                .{ .field_id = ir_format_state_id, .label = "Format", .accessible_label = "Impulse response format", .read_only = true },
                .{ .field_id = ir_original_duration_state_id, .label = "Original", .accessible_label = "Original duration", .read_only = true },
                .{ .field_id = ir_edited_duration_state_id, .label = "Edited", .accessible_label = "Edited duration", .read_only = true },
                .{ .field_id = ir_peak_state_id, .label = "Peak", .accessible_label = "Original and edited peak", .read_only = true },
                .{ .field_id = ir_publish_state_id, .label = "State", .accessible_label = "Impulse response publication state", .read_only = true },
            },
            .progress_indicators = &.{.{
                .source_id = ir_import_id,
                .label = "Import",
                .accessible_label = "Impulse response import progress",
                .idle_text = "Choose an IR to begin",
                .running_text = "Importing IR",
                .complete_text = "IR ready",
                .failure_text = "Import failed",
            }},
            .skin = ir_skin,
            .composition = .{
                .title = "IR Loader",
                .groups = &.{
                    .{ .title = "Impulse Response", .graph_count = 1 },
                    .{ .title = "Mix", .parameter_count = 3, .first_graph = 1 },
                },
            },
        });
    }
});

const IRProcessor = struct {
    convolver: Convolver,
    dry_delay: [2][convolution_partition_size]f32,
    dry_index: usize,
    wet: core.parameters.LinearSmoother,
    output: core.parameters.LinearSmoother,
    sample_rate: f64,

    pub fn initInPlace(self: *IRProcessor) void {
        self.convolver = undefined;
        self.convolver.initInPlace(48_000);
        self.dry_delay = @splat(@splat(0.0));
        self.dry_index = 0;
        self.wet = .init(0.0);
        self.output = .init(2.0 / 3.0);
        self.sample_rate = 48_000;
    }

    pub fn prepare(self: *IRProcessor, config: core.plugin.PrepareConfig) void {
        self.sample_rate = config.sample_rate;
        const rounded_rate: u32 = @intFromFloat(@round(std.math.clamp(config.sample_rate, 8_000.0, 384_000.0)));
        _ = self.convolver.reprepareForSampleRate(rounded_rate) catch false;
    }

    pub fn reset(self: *IRProcessor) void {
        self.convolver.resetProcessing();
        self.dry_delay = @splat(@splat(0.0));
        self.dry_index = 0;
    }

    pub fn latencySamples(_: *const IRProcessor) u32 {
        return convolution_partition_size;
    }

    pub fn tailSamples(_: *const IRProcessor) u32 {
        return @intCast(maximum_ir_frames);
    }

    pub fn audioImportReceiver(self: *IRProcessor) *Convolver {
        return &self.convolver;
    }

    pub fn process(
        self: *IRProcessor,
        parameters: anytype,
        comptime Sample: type,
        context: *core.process.ProcessContext(Sample),
    ) void {
        const adopted = self.convolver.adoptPending();
        const active = self.convolver.activeMetadata();
        const requested_wet = if (parameters.getNormalizedById(bypass_param_id) >= 0.5 or active == null or active.?.frames == 0)
            0.0
        else
            parameters.getNormalizedById(wet_param_id);
        const requested_output = parameters.getNormalizedById(output_param_id);
        const smoothing_samples: usize = @intFromFloat(@max(1.0, self.sample_rate * 0.01));
        if (adopted or @abs(self.wet.targetValue() - requested_wet) > 0.000001) self.wet.setTarget(requested_wet, smoothing_samples);
        if (@abs(self.output.targetValue() - requested_output) > 0.000001) self.output.setTarget(requested_output, smoothing_samples);

        const left_input = context.inputChannel(0);
        const right_input = context.inputChannel(1);
        const left_output = context.outputChannel(0);
        const right_output = context.outputChannel(1);
        for (0..context.frameCount()) |index| {
            const left: f32 = if (left_input) |samples| @floatCast(samples[index]) else 0.0;
            const right: f32 = if (right_input) |samples| @floatCast(samples[index]) else left;
            const delayed_left = self.dry_delay[0][self.dry_index];
            const delayed_right = self.dry_delay[1][self.dry_index];
            self.dry_delay[0][self.dry_index] = left;
            self.dry_delay[1][self.dry_index] = right;
            const convolved = self.convolver.processFrame(left, right);
            const wet = self.wet.next();
            const output_db = -24.0 + 36.0 * self.output.next();
            const output_gain = std.math.pow(f64, 10.0, output_db / 20.0);
            const mixed_left = @as(f64, delayed_left) * (1.0 - wet) + @as(f64, convolved[0]) * wet;
            const mixed_right = @as(f64, delayed_right) * (1.0 - wet) + @as(f64, convolved[1]) * wet;
            if (left_output) |samples| samples[index] = @floatCast(mixed_left * output_gain);
            if (right_output) |samples| samples[index] = @floatCast(mixed_right * output_gain);
            self.dry_index = (self.dry_index + 1) % convolution_partition_size;
        }
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

    allocator: std.mem.Allocator,
    engine: *IRProcessor,

    pub fn init(allocator: std.mem.Allocator) !RuntimeProcessor {
        const engine = try allocator.create(IRProcessor);
        engine.initInPlace();
        return .{
            .allocator = allocator,
            .engine = engine,
        };
    }

    pub fn prepare(
        self: *RuntimeProcessor,
        config: core.plugin.PrepareConfig,
    ) void {
        self.engine.prepare(config);
    }

    pub fn reset(self: *RuntimeProcessor) void {
        self.engine.reset();
    }

    pub fn latencySamples(self: *const RuntimeProcessor) u32 {
        return self.engine.latencySamples();
    }

    pub fn tailSamples(self: *const RuntimeProcessor) u32 {
        return self.engine.tailSamples();
    }

    pub fn audioImportReceiver(self: *RuntimeProcessor) *Convolver {
        return self.engine.audioImportReceiver();
    }

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

    pub fn deinit(self: *RuntimeProcessor) void {
        self.allocator.destroy(self.engine);
    }
};

const Vst3IRProcessor =
    vst3.zig_vst3_plugin_runtime_adapter.Processor(
        RuntimeProcessor,
    );

const Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect(
        RuntimeProcessor,
        struct {
            pub const component_name = "IRLoaderComponent";
            pub const controller_cid = ir_controller_cid;
            pub const audio_import_target_id = ir_import_id;
        },
    );

pub const component_cid = vst3.tuid.inlineUid(0x7A0A8A10, 0x9D554843, 0x84CE2F3A, 0x49A0B44E);
pub const ir_controller_cid = vst3.tuid.inlineUid(0xF1955EA3, 0x413E4DC0, 0xA70E2997, 0x31D138AF);

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = ir_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "IR loader exports component and controller classes" {
    const factory = Factory.getPluginFactory() orelse return error.MissingFactory;
    try std.testing.expectEqual(@as(i32, 2), factory.vtable.countClasses(factory));
}

test "IR loader creates a public API editor and bounded processor" {
    try std.testing.expect(Vst3IRProcessor.hasAudioImportReceiver);
    try std.testing.expect(
        @hasDecl(RuntimeProcessor, "process64WithParameterView"),
    );
    try std.testing.expectEqual(@as(usize, 1), ir_skin.assets.len);
    try std.testing.expectEqualStrings("Avenir Next", std.mem.span(ir_skin.fonts.title_family.?));
    try std.testing.expectEqualStrings("Menlo", std.mem.span(ir_skin.fonts.value_family.?));
    try std.testing.expect(ir_skin.drawing.draw_parameter != null);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    const view = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = view.vtable.release(view);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);
    try std.testing.expectEqual(@as(u32, convolution_partition_size), Effect.processorInstance(component).latencySamples());
    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *vst.ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out orelse return error.MissingProcessor));
    defer _ = processor.vtable.release(processor);
    try std.testing.expectEqual(@as(u32, convolution_partition_size), processor.vtable.getLatencySamples(processor));
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.canProcessSampleSize(
            processor,
            @intFromEnum(
                vst.ivstaudioprocessor.SymbolicSampleSizes.kSample64,
            ),
        ),
    );
}

test "IR loader survives concurrent headless host lifecycle stress" {
    const report = try vst3.testing.vstgui_headless_host.run(struct {
        pub const component_create = Effect.create;
        pub const controller_create = Controller.create;
    }, .{});
    try std.testing.expectEqual(@as(usize, 12), report.editor_lifecycles);
    try std.testing.expect(report.process_blocks >= 128);
}

test "IR loader imports and clears one immutable processor generation" {
    var wav: [48]u8 = undefined;
    var writer = std.Io.Writer.fixed(&wav);
    try writer.writeAll("RIFF");
    try writer.writeInt(u32, wav.len - 8, .little);
    try writer.writeAll("WAVEfmt ");
    try writer.writeInt(u32, 16, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 48_000, .little);
    try writer.writeInt(u32, 96_000, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u16, 16, .little);
    try writer.writeAll("data");
    try writer.writeInt(u32, 4, .little);
    try writer.writeInt(i16, 32_767, .little);
    try writer.writeInt(i16, 0, .little);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "impulse.wav", .data = writer.buffered() });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "impulse.wav", &path);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);
    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstmessage.iconnection_point_iid, &component_connection_out));
    const component_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out orelse return error.MissingConnection));
    defer _ = component_connection.vtable.release(component_connection);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller.vtable.queryInterface(controller, &vst.ivstmessage.iconnection_point_iid, &controller_connection_out));
    const controller_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingConnection));
    defer _ = controller_connection.vtable.release(controller_connection);
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));

    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(controller, ir_import_id, .picker, &.{path[0..path_length]}));
    var attempts: usize = 0;
    while (attempts < 1_000_000) : (attempts += 1) {
        const snapshot = Controller.loadFileImport(controller, ir_import_id) orelse return error.MissingImportState;
        if (snapshot.import.status == .ready) break;
        if (snapshot.import.status != .validating and snapshot.import.status != .importing) return error.ImportFailed;
        std.Thread.yield() catch {};
    }
    try std.testing.expect(attempts < 1_000_000);
    _ = Controller.loadFileImport(controller, ir_import_id);
    const processor = Effect.processorInstance(component);
    try std.testing.expect(
        processor.audioImportReceiver().adoptPending(),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        processor.audioImportReceiver().activeMetadata().?.frames,
    );
    const format_text = switch (Controller.editorState(controller).get(ir_format_state_id) orelse return error.MissingFormatState) {
        .text => |value| value,
        else => return error.InvalidFormatState,
    };
    try std.testing.expectEqualStrings("48000 Hz, 1 ch", format_text.slice());
    const published_text = switch (Controller.editorState(controller).get(ir_publish_state_id) orelse return error.MissingPublishState) {
        .text => |value| value,
        else => return error.InvalidPublishState,
    };
    try std.testing.expectEqualStrings("Published", published_text.slice());

    try std.testing.expectEqual(types.kResultOk, Controller.performAction(
        controller,
        ir_edit_action_group_id,
        reverse_action_id,
    ));
    try std.testing.expect(
        processor.audioImportReceiver().adoptPending(),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        processor.audioImportReceiver().activeMetadata().?.frames,
    );
    try std.testing.expectEqual(types.kResultOk, Controller.performAction(
        controller,
        ir_edit_action_group_id,
        reset_action_id,
    ));
    try std.testing.expect(
        processor.audioImportReceiver().adoptPending(),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        processor.audioImportReceiver().activeMetadata().?.frames,
    );

    const StateStream = vst3.vst_stream.FixedBufferStream(8192);
    var state_stream = StateStream{};
    try std.testing.expectEqual(types.kResultOk, controller.vtable.getState(controller, state_stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, Controller.performFileImportCommand(controller, ir_import_id, .reset));
    try std.testing.expect(
        processor.audioImportReceiver().adoptPending(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        processor.audioImportReceiver().activeMetadata().?.frames,
    );
    const cleared_text = switch (Controller.editorState(controller).get(ir_publish_state_id) orelse return error.MissingPublishState) {
        .text => |value| value,
        else => return error.InvalidPublishState,
    };
    try std.testing.expectEqualStrings("Empty", cleared_text.slice());

    try Controller.editorState(controller).set(ir_publish_state_id, .{ .text = core.editor_state.Text.init("Stale") catch unreachable });
    try std.testing.expectEqual(types.kResultOk, state_stream.asStream().vtable.seek(
        state_stream.asStream(),
        0,
        @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet),
        null,
    ));
    try std.testing.expectEqual(types.kResultOk, controller.vtable.setState(controller, state_stream.asStream()));
    const restored_text = switch (Controller.editorState(controller).get(ir_publish_state_id) orelse return error.MissingPublishState) {
        .text => |value| value,
        else => return error.InvalidPublishState,
    };
    try std.testing.expectEqualStrings("Empty", restored_text.slice());
}

test "IR loader rejects clear before mutating the processor while import work is active" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);
    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstmessage.iconnection_point_iid, &component_connection_out));
    const component_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out orelse return error.MissingConnection));
    defer _ = component_connection.vtable.release(component_connection);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller.vtable.queryInterface(controller, &vst.ivstmessage.iconnection_point_iid, &controller_connection_out));
    const controller_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingConnection));
    defer _ = controller_connection.vtable.release(controller_connection);
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));

    const state = Controller.controllerState(controller);
    try std.testing.expectEqual(
        core.gui_file_importer.Status.validating,
        state.importer.model.begin(.picker, &.{"active.wav"}),
    );
    try state.importer.model.startImport(1);
    state.importer.worker.worker_running.store(true, .release);
    defer {
        state.importer.worker.worker_running.store(false, .release);
        state.importer.model.reset();
    }
    try std.testing.expectEqual(types.kResultFalse, Controller.performAction(
        controller,
        ir_destructive_action_group_id,
        clear_ir_action_id,
    ));
    try std.testing.expect(
        !Effect.processorInstance(component)
            .audioImportReceiver()
            .adoptPending(),
    );
    try std.testing.expectEqual(@as(u64, 0), state.transfer_generation);
}
