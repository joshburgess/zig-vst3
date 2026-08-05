const std = @import("std");
const core = @import("zig-vst3-plugin-core");

pub const RuntimeState = core.plugin.RuntimeState;

pub fn Processor(comptime Plugin: type) type {
    return ProcessorWithParameters(Plugin, .{});
}

pub fn ProcessorWithParameters(
    comptime Plugin: type,
    comptime params: Plugin.Params,
) type {
    const Runtime = core.plugin.ProcessorRuntime(Plugin);
    const Spec = core.plugin.PluginSpec(Plugin);
    const has_resource_path_receiver =
        @hasDecl(Plugin, "resourcePathReceiver");
    const has_audio_import_receiver =
        @hasDecl(Plugin, "audioImportReceiver");
    const ResourcePathReceiver =
        if (has_resource_path_receiver)
            @typeInfo(@TypeOf(Plugin.resourcePathReceiver))
                .@"fn".return_type orelse
                @compileError("resourcePathReceiver must return a receiver pointer")
        else
            void;
    const AudioImportReceiver =
        if (has_audio_import_receiver)
            @typeInfo(@TypeOf(Plugin.audioImportReceiver))
                .@"fn".return_type orelse
                @compileError("audioImportReceiver must return a receiver pointer")
        else
            void;

    return struct {
        const Self = @This();
        const has_component_state =
            @hasDecl(
                Plugin,
                "component_state_maximum_encoded_size",
            );

        pub const component_state_maximum_encoded_size =
            if (has_component_state)
                Plugin.component_state_maximum_encoded_size
            else
                0;
        pub const hasResourcePathReceiver =
            has_resource_path_receiver;
        pub const hasAudioImportReceiver =
            has_audio_import_receiver;
        pub const hasGuiTelemetryLoad =
            @hasDecl(Plugin, "guiTelemetryLoad");
        pub const hasGuiGraphLoad =
            @hasDecl(Plugin, "guiGraphLoad");
        pub const hasGuiTelemetryLoadText =
            @hasDecl(Plugin, "guiTelemetryLoadText");
        pub const hasGuiTelemetryEditorOpened =
            @hasDecl(Plugin, "guiTelemetryEditorOpened");
        pub const hasGuiTelemetryEditorClosed =
            @hasDecl(Plugin, "guiTelemetryEditorClosed");

        runtime: Runtime,
        last_prepare_config: ?core.plugin.PrepareConfig = null,
        last_process_succeeded: bool = true,

        pub fn initInPlaceWithAllocator(
            self: *Self,
            allocator: std.mem.Allocator,
        ) !void {
            try self.runtime.initInto(allocator, params);
            self.last_prepare_config = null;
            self.last_process_succeeded = true;
        }

        pub fn initWithAllocator(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            try self.initInPlaceWithAllocator(allocator);
            return self;
        }

        pub fn prepareChecked(
            self: *Self,
            config: core.plugin.PrepareConfig,
        ) !void {
            try self.runtime.prepare(config);
            self.last_prepare_config = config;
        }

        pub fn activateChecked(self: *Self) !void {
            if (self.runtime.runtimeState() == .initialized) {
                const config = self.last_prepare_config orelse
                    return error.ProcessorNotPrepared;
                try self.runtime.prepare(config);
            }
            try self.runtime.activate();
        }

        pub fn deactivateChecked(self: *Self) !void {
            try self.runtime.deactivate();
            try self.runtime.releaseResources();
        }

        pub fn reset(self: *Self) void {
            if (self.runtime.runtimeState() == .initialized) return;
            self.runtime.instance.reset();
        }

        pub fn syncParameterValues(
            self: *Self,
            values: *const core.parameters.ParameterValues(Plugin.Params),
        ) void {
            self.runtime.instance.parameterValues().copyFrom(values);
        }

        pub fn afterParameterStateRestore(self: *Self) void {
            self.runtime.instance.afterStateRestore();
        }

        pub fn supportsSampleType(
            _: *const Self,
            comptime Sample: type,
        ) bool {
            return if (Sample == f32)
                Spec.has_process32_hook
            else if (Sample == f64)
                Spec.has_process64_hook
            else
                false;
        }

        pub fn process(
            self: *Self,
            parameter_state: anytype,
            comptime Sample: type,
            context: *core.process.BoundedProcessContext(
                Sample,
                Spec.auxiliary_audio_bus_capacity,
            ),
        ) void {
            self.syncParameterValues(&parameter_state.values);
            if (Sample == f32) {
                self.runtime.process(context) catch {
                    self.last_process_succeeded = false;
                    return;
                };
            } else if (Sample == f64) {
                self.runtime.process64(context) catch {
                    self.last_process_succeeded = false;
                    return;
                };
            } else {
                self.last_process_succeeded = false;
                return;
            }
            self.last_process_succeeded = true;
        }

        pub fn processSucceeded(self: *const Self) bool {
            return self.last_process_succeeded;
        }

        pub fn latencySamples(self: *const Self) u32 {
            return self.runtime.latencySamples();
        }

        pub fn tailSamples(self: *const Self) u32 {
            return self.runtime.tailSamples();
        }

        pub fn bindHostRequests(
            self: *Self,
            requests: *core.plugin.HostRequestSink,
        ) void {
            self.runtime.instance.bindHostRequests(requests);
        }

        pub fn writeComponentState(
            self: *const Self,
            writer: anytype,
        ) !void {
            if (comptime has_component_state)
                try self.runtime.instance.plugin.writeComponentState(
                    writer,
                );
        }

        pub fn readComponentState(
            self: *Self,
            reader: anytype,
        ) !void {
            if (comptime has_component_state)
                try self.runtime.instance.plugin.readComponentState(
                    reader,
                );
        }

        pub fn afterComponentStateRestore(self: *Self) void {
            if (comptime @hasDecl(
                Plugin,
                "afterComponentStateRestore",
            ))
                self.runtime.instance.plugin
                    .afterComponentStateRestore();
        }

        pub fn componentConnectionReady(self: *Self) void {
            if (comptime @hasDecl(
                Plugin,
                "componentConnectionReady",
            ))
                self.runtime.instance.plugin.componentConnectionReady();
        }

        pub fn resourcePathReceiver(
            self: *Self,
        ) ResourcePathReceiver {
            if (comptime has_resource_path_receiver)
                return self.runtime.instance.plugin
                    .resourcePathReceiver();
        }

        pub fn audioImportReceiver(
            self: *Self,
        ) AudioImportReceiver {
            if (comptime has_audio_import_receiver)
                return self.runtime.instance.plugin
                    .audioImportReceiver();
        }

        pub fn guiTelemetryLoad(
            self: *Self,
            source_id: u32,
        ) f64 {
            if (comptime @hasDecl(Plugin, "guiTelemetryLoad"))
                return self.runtime.instance.plugin
                    .guiTelemetryLoad(source_id);
            return 0.0;
        }

        pub fn guiGraphLoad(
            self: *Self,
            source_id: u32,
            output: []core.gui_graph.Point,
        ) usize {
            if (comptime @hasDecl(Plugin, "guiGraphLoad"))
                return self.runtime.instance.plugin
                    .guiGraphLoad(source_id, output);
            return 0;
        }

        pub fn guiTelemetryLoadText(
            self: *Self,
            source_id: u32,
            output: []u8,
        ) usize {
            if (comptime @hasDecl(
                Plugin,
                "guiTelemetryLoadText",
            ))
                return self.runtime.instance.plugin
                    .guiTelemetryLoadText(source_id, output);
            return 0;
        }

        pub fn guiTelemetryEditorOpened(self: *Self) void {
            if (comptime @hasDecl(
                Plugin,
                "guiTelemetryEditorOpened",
            ))
                self.runtime.instance.plugin
                    .guiTelemetryEditorOpened();
        }

        pub fn guiTelemetryEditorClosed(self: *Self) void {
            if (comptime @hasDecl(
                Plugin,
                "guiTelemetryEditorClosed",
            ))
                self.runtime.instance.plugin
                    .guiTelemetryEditorClosed();
        }

        pub fn deinit(self: *Self) void {
            self.runtime.deinit();
        }
    };
}

test "VST3 processor adapter carries lifecycle, parameters, and precision support" {
    const Gain = struct {
        const Receiver = struct {
            value: u32 = 0,
        };

        prepare_count: usize = 0,
        activate_count: usize = 0,
        deactivate_count: usize = 0,
        release_count: usize = 0,
        restored_count: usize = 0,
        editor_open_count: usize = 0,
        editor_close_count: usize = 0,
        resource_receiver: Receiver = .{ .value = 41 },
        audio_receiver: Receiver = .{ .value = 43 },

        pub const name = "Adapter Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: core.parameters.FloatParam =
                core.parameters.FloatParam.init(
                    7,
                    "Gain",
                    0.0,
                    1.0,
                    0.5,
                ),
        };

        pub fn prepare(
            self: *@This(),
            _: core.plugin.PrepareConfig,
        ) void {
            self.prepare_count += 1;
        }

        pub fn activate(self: *@This()) void {
            self.activate_count += 1;
        }

        pub fn deactivate(self: *@This()) void {
            self.deactivate_count += 1;
        }

        pub fn releaseResources(self: *@This()) void {
            self.release_count += 1;
        }

        pub fn afterStateRestore(self: *@This()) void {
            self.restored_count += 1;
        }

        pub fn latencySamples(_: *const @This()) u32 {
            return 17;
        }

        pub fn tailSamples(_: *const @This()) u32 {
            return 29;
        }

        pub fn resourcePathReceiver(
            self: *@This(),
        ) *Receiver {
            return &self.resource_receiver;
        }

        pub fn audioImportReceiver(
            self: *@This(),
        ) *Receiver {
            return &self.audio_receiver;
        }

        pub fn guiTelemetryLoad(
            _: *@This(),
            source_id: u32,
        ) f64 {
            return @floatFromInt(source_id);
        }

        pub fn guiGraphLoad(
            _: *@This(),
            source_id: u32,
            output: []core.gui_graph.Point,
        ) usize {
            if (output.len == 0) return 0;
            output[0] = .{
                .x = @floatFromInt(source_id),
                .y = 0.5,
            };
            return 1;
        }

        pub fn guiTelemetryLoadText(
            _: *@This(),
            source_id: u32,
            output: []u8,
        ) usize {
            if (source_id != 7 or output.len < 4) return 0;
            @memcpy(output[0..4], "text");
            return 4;
        }

        pub fn guiTelemetryEditorOpened(self: *@This()) void {
            self.editor_open_count += 1;
        }

        pub fn guiTelemetryEditorClosed(self: *@This()) void {
            self.editor_close_count += 1;
        }

        pub fn processWithParameterView(
            _: *@This(),
            context: *core.process.ProcessContext(f32),
            view: core.parameters.ParameterView(Params),
        ) void {
            const gain: f32 = @floatCast(view.load("gain"));
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            for (input, output) |sample, *destination|
                destination.* = sample * gain;
        }
    };

    const Adapter = Processor(Gain);
    var adapter: Adapter = undefined;
    try adapter.initInPlaceWithAllocator(std.testing.allocator);
    defer adapter.deinit();

    try std.testing.expect(adapter.supportsSampleType(f32));
    try std.testing.expect(!adapter.supportsSampleType(f64));
    try std.testing.expect(Adapter.hasResourcePathReceiver);
    try std.testing.expect(Adapter.hasAudioImportReceiver);
    try std.testing.expect(Adapter.hasGuiTelemetryLoad);
    try std.testing.expect(Adapter.hasGuiGraphLoad);
    try std.testing.expect(Adapter.hasGuiTelemetryLoadText);
    try std.testing.expect(Adapter.hasGuiTelemetryEditorOpened);
    try std.testing.expect(Adapter.hasGuiTelemetryEditorClosed);
    try std.testing.expectEqual(
        @as(u32, 41),
        adapter.resourcePathReceiver().value,
    );
    try std.testing.expectEqual(
        @as(u32, 43),
        adapter.audioImportReceiver().value,
    );
    try std.testing.expectEqual(
        @as(f64, 9.0),
        adapter.guiTelemetryLoad(9),
    );
    var graph: [1]core.gui_graph.Point = undefined;
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.guiGraphLoad(3, &graph),
    );
    try std.testing.expectEqual(
        core.gui_graph.Point{ .x = 3.0, .y = 0.5 },
        graph[0],
    );
    var text_buffer: [4]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        adapter.guiTelemetryLoadText(7, &text_buffer),
    );
    try std.testing.expectEqualStrings("text", &text_buffer);
    adapter.guiTelemetryEditorOpened();
    adapter.guiTelemetryEditorClosed();
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.editor_open_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.editor_close_count,
    );
    try std.testing.expectEqual(@as(u32, 17), adapter.latencySamples());
    try std.testing.expectEqual(@as(u32, 29), adapter.tailSamples());
    try adapter.prepareChecked(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
    });
    try adapter.activateChecked();

    const Set = core.parameters.ParameterSet(Gain.Params);
    const Values = core.parameters.ParameterValues(Gain.Params);
    const State = struct {
        values: Values,
    };
    const set = Set.init(.{});
    var state = State{ .values = Values.init(&set) };
    _ = state.values.storeById(&set, 7, 0.25);

    const input = [_]f32{ 1.0, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try core.process.ProcessContext(f32).init(
        48_000.0,
        &inputs,
        &outputs,
    );
    adapter.process(&state, f32, &context);

    try std.testing.expect(adapter.processSucceeded());
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, -0.125 },
        &output,
    );
    adapter.afterParameterStateRestore();
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.restored_count,
    );

    try adapter.deactivateChecked();
    try adapter.activateChecked();
    try std.testing.expectEqual(
        @as(usize, 2),
        adapter.runtime.instance.plugin.prepare_count,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        adapter.runtime.instance.plugin.activate_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.deactivate_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.release_count,
    );

    const ConfiguredAdapter = ProcessorWithParameters(Gain, .{
        .gain = core.parameters.FloatParam.init(
            7,
            "Gain",
            0.0,
            1.0,
            0.8,
        ),
    });
    var configured_adapter =
        try ConfiguredAdapter.initWithAllocator(std.testing.allocator);
    defer configured_adapter.deinit();
    try std.testing.expectEqual(
        @as(?f64, 0.8),
        configured_adapter.runtime.instance
            .parameterValuesConst().load(0),
    );
}
