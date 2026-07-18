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
pub const maximum_ir_frames: usize = 131_072;
pub const convolution_partition_size: usize = 512;

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
const AudioImporter = vst3.vstgui.DecodedAudioFileImporter(maximum_ir_frames);

const IRControllerState = struct {
    importer: AudioImporter,
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
            const generation = state.transfer_generation +% 1;
            if (generation != 0 and Controller.sendDecodedAudioGeneration(
                controller,
                ir_import_id,
                generation,
                &state.importer,
            ) == types.kResultOk) {
                state.transfer_generation = generation;
                state.published_import_generation = snapshot.import.generation;
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

    fn clearImport(controller: *vst.ivsteditcontroller.IEditController, state: *IRControllerState) bool {
        const generation = state.transfer_generation +% 1;
        if (generation == 0 or Controller.clearDecodedAudio(controller, ir_import_id, generation) != types.kResultOk) return false;
        if (!state.importer.reset()) return false;
        state.transfer_generation = generation;
        state.published_import_generation = 0;
        return true;
    }

    pub fn loadGuiGraph(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
        output: []vst3.vstgui.GraphPoint,
    ) usize {
        if (source_id != ir_waveform_source_id) return 0;
        var preview: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.AudioFilePreviewPoint = undefined;
        const count = Controller.controllerState(controller).importer.copyPreview(&preview);
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
            }},
            .file_drops = &.{.{
                .id = ir_import_id,
                .title = "Impulse Response",
                .prompt = "Drop a PCM WAV impulse response here",
                .picker_label = "Choose IR",
                .picker_title = "Choose an Impulse Response",
                .extensions = &.{".wav"},
                .maximum_files = 1,
            }},
            .skin = .{ .theme = .alternate, .layout = .adaptive },
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

const Effect = vst3.zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "IRLoaderComponent";
    pub const controller_cid = ir_controller_cid;
    pub const Params = Spec.Params;
    pub const parameter_set = &ir_parameter_set;
    pub const audio_import_target_id = ir_import_id;
    pub const Processor = IRProcessor;
});

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
    try std.testing.expect(processor.convolver.adoptPending());
    try std.testing.expectEqual(@as(usize, 2), processor.convolver.activeMetadata().?.frames);

    try std.testing.expectEqual(types.kResultOk, Controller.performFileImportCommand(controller, ir_import_id, .reset));
    try std.testing.expect(processor.convolver.adoptPending());
    try std.testing.expectEqual(@as(usize, 0), processor.convolver.activeMetadata().?.frames);
}
