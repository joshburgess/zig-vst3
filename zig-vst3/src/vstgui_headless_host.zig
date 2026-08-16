const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const vst_parameter_changes = @import("vst_parameter_changes.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

const maximum_parameters = 64;
const maximum_frames = 128;

const default_sizes = [_]iplugview.ViewRect{
    .{ .right = 480, .bottom = 480 },
    .{ .right = 900, .bottom = 700 },
    .{ .right = 1280, .bottom = 960 },
    .{ .right = 640, .bottom = 560 },
};

pub const Options = struct {
    editor_iterations: usize = 12,
    minimum_process_blocks: usize = 128,
    frames_per_block: usize = 64,
    sizes: []const iplugview.ViewRect = &default_sizes,
};

pub const Report = struct {
    editor_lifecycles: usize,
    resize_operations: usize,
    process_blocks: usize,
    automated_parameters: usize,
};

const WorkerFailure = enum(u8) {
    none,
    parameter_queue,
    parameter_point,
    process,
};

const Worker = struct {
    processor: *ivstaudioprocessor.IAudioProcessor,
    parameter_ids: [maximum_parameters]vsttypes.ParamID,
    parameter_count: usize,
    frames_per_block: usize,
    has_audio_input: bool,
    minimum_blocks: usize,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    blocks: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    failure: std.atomic.Value(WorkerFailure) = std.atomic.Value(WorkerFailure).init(.none),

    fn process(self: *Worker) void {
        var input_left: [maximum_frames]f32 = undefined;
        var input_right: [maximum_frames]f32 = undefined;
        var output_left: [maximum_frames]f32 = undefined;
        var output_right: [maximum_frames]f32 = undefined;
        for (&input_left, 0..) |*sample, index| sample.* = if (index % 2 == 0) 0.25 else -0.25;
        for (&input_right, 0..) |*sample, index| sample.* = if (index % 3 == 0) -0.125 else 0.125;

        var input_channels = [_][*]f32{ &input_left, &input_right };
        var output_channels = [_][*]f32{ &output_left, &output_right };
        var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
            .numChannels = 2,
            .channelBuffers = .{ .channelBuffers32 = input_channels[0..].ptr },
        }};
        var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
            .numChannels = 2,
            .channelBuffers = .{ .channelBuffers32 = output_channels[0..].ptr },
        }};

        self.started.store(true, .release);
        var block_index: usize = 0;
        while (!self.stop.load(.acquire) or block_index < self.minimum_blocks) : (block_index += 1) {
            @memset(&output_left, 0);
            @memset(&output_right, 0);

            const Changes = vst_parameter_changes.ParameterChanges(1, 1);
            var changes = Changes{};
            if (self.parameter_count > 0) {
                const parameter_id = self.parameter_ids[block_index % self.parameter_count];
                const queue = changes.addQueue(parameter_id) orelse {
                    self.failure.store(.parameter_queue, .release);
                    return;
                };
                const value = @as(f64, @floatFromInt(block_index % 101)) / 100.0;
                if (queue.appendPoint(0, value) != types.kResultOk) {
                    self.failure.store(.parameter_point, .release);
                    return;
                }
            }

            var data = ivstaudioprocessor.ProcessData{
                .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
                .numSamples = @intCast(self.frames_per_block),
                .numInputs = if (self.has_audio_input) 1 else 0,
                .numOutputs = 1,
                .inputs = if (self.has_audio_input) &inputs else null,
                .outputs = &outputs,
                .inputParameterChanges = if (self.parameter_count > 0) changes.asInterface() else null,
            };
            if (self.processor.vtable.process(self.processor, &data) != types.kResultOk) {
                self.failure.store(.process, .release);
                return;
            }
            self.blocks.store(block_index + 1, .release);
        }
    }
};

pub fn run(comptime Config: type, options: Options) !Report {
    if (options.editor_iterations == 0 or options.minimum_process_blocks == 0) return error.EmptyStressRun;
    if (options.frames_per_block == 0 or options.frames_per_block > maximum_frames) return error.InvalidBlockSize;
    if (options.sizes.len == 0) return error.MissingEditorSizes;

    var component_out: ?*anyopaque = null;
    if (Config.component_create(@ptrCast(&ivstcomponent.icomponent_iid), &component_out) != types.kResultOk) return error.ComponentCreationFailed;
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);

    var processor_out: ?*anyopaque = null;
    if (component.vtable.queryInterface(component, &ivstaudioprocessor.iaudio_processor_iid, &processor_out) != types.kResultOk) return error.MissingAudioProcessor;
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out orelse return error.MissingAudioProcessor));
    defer _ = processor.vtable.release(processor);

    var controller_out: ?*anyopaque = null;
    if (Config.controller_create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out) != types.kResultOk) return error.ControllerCreationFailed;
    const controller: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    if (controller.vtable.createView(controller, null)) |unexpected| {
        _ = unexpected.vtable.release(unexpected);
        return error.NullEditorNameAccepted;
    }
    if (controller.vtable.createView(controller, "not-an-editor")) |unexpected| {
        _ = unexpected.vtable.release(unexpected);
        return error.UnknownEditorNameAccepted;
    }

    var component_connection_out: ?*anyopaque = null;
    if (component.vtable.queryInterface(component, &ivstmessage.iconnection_point_iid, &component_connection_out) != types.kResultOk) return error.MissingComponentConnection;
    const component_connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out orelse return error.MissingComponentConnection));
    defer _ = component_connection.vtable.release(component_connection);

    var controller_connection_out: ?*anyopaque = null;
    if (controller.vtable.queryInterface(controller, &ivstmessage.iconnection_point_iid, &controller_connection_out) != types.kResultOk) return error.MissingControllerConnection;
    const controller_connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingControllerConnection));
    defer _ = controller_connection.vtable.release(controller_connection);

    if (controller_connection.vtable.connect(controller_connection, component_connection) != types.kResultOk) return error.ControllerConnectionFailed;
    defer _ = controller_connection.vtable.disconnect(controller_connection, component_connection);
    if (component_connection.vtable.connect(component_connection, controller_connection) != types.kResultOk) return error.ComponentConnectionFailed;
    defer _ = component_connection.vtable.disconnect(component_connection, controller_connection);

    var setup = ivstaudioprocessor.ProcessSetup{
        .processMode = @intFromEnum(ivstaudioprocessor.ProcessModes.kRealtime),
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .maxSamplesPerBlock = @intCast(options.frames_per_block),
        .sampleRate = 48_000,
    };
    if (processor.vtable.setupProcessing(processor, &setup) != types.kResultOk) return error.SetupProcessingFailed;
    if (component.vtable.setActive(component, 1) != types.kResultOk) return error.ActivationFailed;
    defer _ = component.vtable.setActive(component, 0);
    if (processor.vtable.setProcessing(processor, 1) != types.kResultOk) return error.StartProcessingFailed;
    defer _ = processor.vtable.setProcessing(processor, 0);
    var malformed_process = ivstaudioprocessor.ProcessData{ .numSamples = -1 };
    if (processor.vtable.process(processor, &malformed_process) == types.kResultOk) return error.MalformedProcessAccepted;

    var parameter_ids: [maximum_parameters]vsttypes.ParamID = @splat(0);
    const declared_parameter_count = controller.vtable.getParameterCount(controller);
    const parameter_count: usize = if (declared_parameter_count <= 0) 0 else @min(@as(usize, @intCast(declared_parameter_count)), maximum_parameters);
    if (parameter_count == 0) return error.MissingAutomationParameter;
    var invalid_parameter = ivsteditcontroller.ParameterInfo{};
    if (controller.vtable.getParameterInfo(controller, -1, &invalid_parameter) == types.kResultOk or
        controller.vtable.getParameterInfo(controller, declared_parameter_count, &invalid_parameter) == types.kResultOk)
    {
        return error.InvalidParameterIndexAccepted;
    }
    for (0..parameter_count) |index| {
        var info = ivsteditcontroller.ParameterInfo{};
        if (controller.vtable.getParameterInfo(controller, @intCast(index), &info) != types.kResultOk) return error.ParameterInfoFailed;
        parameter_ids[index] = info.id;
    }

    const audio_input_count = component.vtable.getBusCount(
        component,
        @intFromEnum(ivstcomponent.MediaTypes.kAudio),
        @intFromEnum(ivstcomponent.BusDirections.kInput),
    );
    var worker = Worker{
        .processor = processor,
        .parameter_ids = parameter_ids,
        .parameter_count = parameter_count,
        .frames_per_block = options.frames_per_block,
        .has_audio_input = audio_input_count > 0,
        .minimum_blocks = options.minimum_process_blocks,
    };
    const thread = try std.Thread.spawn(.{}, Worker.process, .{&worker});
    var joined = false;
    defer {
        if (!joined) {
            worker.stop.store(true, .release);
            thread.join();
        }
    }
    while (!worker.started.load(.acquire)) std.Thread.yield() catch {};

    var resize_operations: usize = 0;
    for (0..options.editor_iterations) |iteration| {
        const view = controller.vtable.createView(controller, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
        defer _ = view.vtable.release(view);

        var initial = iplugview.ViewRect{};
        if (view.vtable.getSize(view, &initial) != types.kResultOk) return error.EditorSizeUnavailable;
        _ = view.vtable.onFocus(view, 1);
        _ = view.vtable.onKeyDown(view, 0, iplugview.VirtualKeyCode.tab, 0);
        _ = view.vtable.onKeyUp(view, 0, iplugview.VirtualKeyCode.tab, 0);

        for (options.sizes, 0..) |requested, size_index| {
            var constrained = requested;
            if (view.vtable.checkSizeConstraint(view, &constrained) != types.kResultOk) return error.EditorConstraintFailed;
            if (view.vtable.onSize(view, &constrained) != types.kResultOk) return error.EditorResizeFailed;
            var accepted = iplugview.ViewRect{};
            if (view.vtable.getSize(view, &accepted) != types.kResultOk) return error.EditorSizeUnavailable;
            if (accepted.right <= accepted.left or accepted.bottom <= accepted.top) return error.InvalidAcceptedEditorSize;
            resize_operations += 1;

            if ((iteration + size_index) % 2 == 0) {
                _ = view.vtable.onFocus(view, 0);
                _ = view.vtable.onFocus(view, 1);
            }
        }
        var malformed_size = iplugview.ViewRect{ .left = 100, .top = 100, .right = -100, .bottom = -100 };
        if (view.vtable.checkSizeConstraint(view, &malformed_size) == types.kResultOk and
            (malformed_size.right <= malformed_size.left or malformed_size.bottom <= malformed_size.top))
        {
            return error.InvalidEditorConstraintResult;
        }
        _ = view.vtable.onFocus(view, 0);
    }

    worker.stop.store(true, .release);
    thread.join();
    joined = true;
    const failure = worker.failure.load(.acquire);
    switch (failure) {
        .none => {},
        .parameter_queue => return error.AutomationQueueFailed,
        .parameter_point => return error.AutomationPointFailed,
        .process => return error.AudioProcessingFailed,
    }

    return .{
        .editor_lifecycles = options.editor_iterations,
        .resize_operations = resize_operations,
        .process_blocks = worker.blocks.load(.acquire),
        .automated_parameters = parameter_count,
    };
}
