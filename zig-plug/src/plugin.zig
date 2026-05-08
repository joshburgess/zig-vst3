const std = @import("std");
const parameters = @import("parameters.zig");
const process_api = @import("process.zig");
const state = @import("state.zig");

pub fn PluginSpec(comptime Plugin: type) type {
    if (!@hasDecl(Plugin, "Params")) {
        @compileError("Plugin must declare Params");
    }
    if (!@hasDecl(Plugin, "name")) {
        @compileError("Plugin must declare name");
    }
    if (!@hasDecl(Plugin, "vendor")) {
        @compileError("Plugin must declare vendor");
    }

    return struct {
        const Self = @This();

        pub const Params = Plugin.Params;
        pub const ParameterSet = parameters.ParameterSet(Params);
        pub const ParameterValues = parameters.ParameterValues(Params);
        pub const name = Plugin.name;
        pub const vendor = Plugin.vendor;
        pub const has_init = @hasDecl(Plugin, "init");
        pub const has_prepare = @hasDecl(Plugin, "prepare");
        pub const has_process = @hasDecl(Plugin, "process");
        pub const has_process_with_parameters = @hasDecl(Plugin, "processWithParameters");
        pub const has_process64 = @hasDecl(Plugin, "process64");
        pub const has_process64_with_parameters = @hasDecl(Plugin, "process64WithParameters");
        pub const has_deinit = @hasDecl(Plugin, "deinit");

        parameter_set: ParameterSet,
        values: ParameterValues,

        pub fn init(params: Params) Self {
            const set = ParameterSet.init(params);
            return .{
                .parameter_set = set,
                .values = ParameterValues.init(&set),
            };
        }
    };
}

pub const PrepareConfig = struct {
    sample_rate: f64,
    max_block_size: u32,
};

pub fn PluginInstance(comptime Plugin: type) type {
    validateLifecycle(Plugin);

    return struct {
        const Self = @This();
        pub const Spec = PluginSpec(Plugin);

        spec: Spec,
        plugin: Plugin,

        pub fn init(allocator: std.mem.Allocator, params: Plugin.Params) !Self {
            const plugin = if (Spec.has_init)
                try Plugin.init(allocator)
            else
                Plugin{};

            return .{
                .spec = Spec.init(params),
                .plugin = plugin,
            };
        }

        pub fn prepare(self: *Self, config: PrepareConfig) void {
            if (Spec.has_prepare) {
                self.plugin.prepare(config);
            }
        }

        pub fn parameterSet(self: *const Self) *const Spec.ParameterSet {
            return &self.spec.parameter_set;
        }

        pub fn parameterValues(self: *Self) *Spec.ParameterValues {
            return &self.spec.values;
        }

        pub fn parameterValuesConst(self: *const Self) *const Spec.ParameterValues {
            return &self.spec.values;
        }

        pub fn applyParameterChanges(self: *Self, changes: process_api.ParameterChanges) void {
            self.spec.values.applyChanges(&self.spec.parameter_set, changes);
        }

        pub fn writeParameterState(self: *const Self, writer: anytype) !void {
            try state.writeParameterState(Plugin.Params, &self.spec.parameter_set, &self.spec.values, writer);
        }

        pub fn readParameterState(self: *Self, reader: anytype) !void {
            try state.readParameterState(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader);
        }

        pub fn readParameterStateWithMigrations(
            self: *Self,
            reader: anytype,
            migrations: []const state.ParameterIdMigration,
        ) !void {
            try state.readParameterStateWithMigrations(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader, migrations);
        }

        pub fn process(self: *Self, context: *process_api.ProcessContext(f32)) void {
            self.applyParameterChanges(context.parameter_changes);
            if (Spec.has_process_with_parameters) {
                self.plugin.processWithParameters(context, &self.spec.parameter_set, &self.spec.values);
            } else if (Spec.has_process) {
                self.plugin.process(context);
            }
        }

        pub fn process64(self: *Self, context: *process_api.ProcessContext(f64)) void {
            self.applyParameterChanges(context.parameter_changes);
            if (Spec.has_process64_with_parameters) {
                self.plugin.process64WithParameters(context, &self.spec.parameter_set, &self.spec.values);
            } else if (Spec.has_process64) {
                self.plugin.process64(context);
            }
        }

        pub fn deinit(self: *Self) void {
            if (Spec.has_deinit) {
                self.plugin.deinit();
            }
        }
    };
}

pub fn validateLifecycle(comptime Plugin: type) void {
    if (@hasDecl(Plugin, "init")) {
        const init_info = @typeInfo(@TypeOf(Plugin.init)).@"fn";
        if (init_info.params.len != 1 or init_info.params[0].type.? != std.mem.Allocator) {
            @compileError("init must be fn (std.mem.Allocator) !Plugin");
        }
        const return_type = init_info.return_type orelse @compileError("init must return !Plugin");
        const return_info = @typeInfo(return_type);
        if (return_info != .error_union or return_info.error_union.payload != Plugin) {
            @compileError("init must return !Plugin");
        }
    }
    if (@hasDecl(Plugin, "prepare")) {
        const prepare = @typeInfo(@TypeOf(Plugin.prepare)).@"fn";
        if (prepare.params.len != 2 or prepare.params[0].type.? != *Plugin or prepare.params[1].type.? != PrepareConfig or prepare.return_type.? != void) {
            @compileError("prepare must be fn (*Plugin, PrepareConfig) void");
        }
    }
    if (@hasDecl(Plugin, "process")) {
        const process = @typeInfo(@TypeOf(Plugin.process)).@"fn";
        if (process.params.len != 2 or process.params[0].type.? != *Plugin or process.params[1].type.? != *process_api.ProcessContext(f32) or process.return_type.? != void) {
            @compileError("process must be fn (*Plugin, *process.ProcessContext(f32)) void");
        }
    }
    if (@hasDecl(Plugin, "processWithParameters")) {
        const process = @typeInfo(@TypeOf(Plugin.processWithParameters)).@"fn";
        if (process.params.len != 4 or
            process.params[0].type.? != *Plugin or
            process.params[1].type.? != *process_api.ProcessContext(f32) or
            process.params[2].type.? != *const parameters.ParameterSet(Plugin.Params) or
            process.params[3].type.? != *const parameters.ParameterValues(Plugin.Params) or
            process.return_type.? != void)
        {
            @compileError("processWithParameters must be fn (*Plugin, *process.ProcessContext(f32), *const ParameterSet, *const ParameterValues) void");
        }
    }
    if (@hasDecl(Plugin, "process64")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64)).@"fn";
        if (process64.params.len != 2 or process64.params[0].type.? != *Plugin or process64.params[1].type.? != *process_api.ProcessContext(f64) or process64.return_type.? != void) {
            @compileError("process64 must be fn (*Plugin, *process.ProcessContext(f64)) void");
        }
    }
    if (@hasDecl(Plugin, "process64WithParameters")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64WithParameters)).@"fn";
        if (process64.params.len != 4 or
            process64.params[0].type.? != *Plugin or
            process64.params[1].type.? != *process_api.ProcessContext(f64) or
            process64.params[2].type.? != *const parameters.ParameterSet(Plugin.Params) or
            process64.params[3].type.? != *const parameters.ParameterValues(Plugin.Params) or
            process64.return_type.? != void)
        {
            @compileError("process64WithParameters must be fn (*Plugin, *process.ProcessContext(f64), *const ParameterSet, *const ParameterValues) void");
        }
    }
    if (@hasDecl(Plugin, "deinit")) {
        const deinit = @typeInfo(@TypeOf(Plugin.deinit)).@"fn";
        if (deinit.params.len != 1 or deinit.params[0].type.? != *Plugin or deinit.return_type.? != void) {
            @compileError("deinit must be fn (*Plugin) void");
        }
    }
}

test "plugin spec exposes metadata and parameter defaults" {
    const Gain = struct {
        pub const name = "Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        };
    };
    const Spec = PluginSpec(Gain);
    var spec = Spec.init(.{});

    try std.testing.expectEqualStrings("Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqualStrings("Gain", spec.parameter_set.name(0).?);
    try std.testing.expectEqual(@as(?f64, 1.0), spec.values.load(0));
    try std.testing.expect(spec.values.store(0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), spec.values.load(0));
}

test "plugin spec detects lifecycle declarations" {
    const Meter = struct {
        pub const name = "Meter";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(_: *@This(), _: PrepareConfig) void {}
        pub fn process(_: *@This(), _: *process_api.ProcessContext(f32)) void {}
        pub fn processWithParameters(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {}
        pub fn process64(_: *@This(), _: *process_api.ProcessContext(f64)) void {}
        pub fn process64WithParameters(
            _: *@This(),
            _: *process_api.ProcessContext(f64),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {}
        pub fn deinit(_: *@This()) void {}
    };
    const Spec = PluginSpec(Meter);
    validateLifecycle(Meter);

    try std.testing.expect(Spec.has_init);
    try std.testing.expect(Spec.has_prepare);
    try std.testing.expect(Spec.has_process);
    try std.testing.expect(Spec.has_process_with_parameters);
    try std.testing.expect(Spec.has_process64);
    try std.testing.expect(Spec.has_process64_with_parameters);
    try std.testing.expect(Spec.has_deinit);
}

test "plugin spec allows missing lifecycle declarations during prototype phase" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Minimal);

    try std.testing.expect(!Spec.has_init);
    try std.testing.expect(!Spec.has_prepare);
    try std.testing.expect(!Spec.has_process);
    try std.testing.expect(!Spec.has_process_with_parameters);
    try std.testing.expect(!Spec.has_process64);
    try std.testing.expect(!Spec.has_process64_with_parameters);
    try std.testing.expect(!Spec.has_deinit);
}

test "plugin instance drives declared lifecycle hooks" {
    const Gain = struct {
        prepared: bool = false,
        processed: bool = false,
        deinitialized: bool = false,

        pub const name = "Instance Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(self: *@This(), config: PrepareConfig) void {
            self.prepared = config.sample_rate == 48_000.0 and config.max_block_size == 64;
        }

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.processed = true;
            for (0..context.outputs.channels.len) |channel| {
                const input = context.inputs.channel(channel) orelse continue;
                const output = context.outputs.channel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * 0.5;
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            self.deinitialized = true;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f32).init(&input_channels),
        .outputs = try process_api.AudioOutputs(f32).init(&output_channels),
    };

    try std.testing.expectEqual(@as(?f64, 0.5), instance.spec.values.load(0));
    instance.prepare(.{ .sample_rate = 48_000.0, .max_block_size = 64 });
    instance.process(&context);
    instance.deinit();

    try std.testing.expect(instance.plugin.prepared);
    try std.testing.expect(instance.plugin.processed);
    try std.testing.expect(instance.plugin.deinitialized);
    try std.testing.expectEqual(@as(f32, 0.125), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(?f64, 0.5), instance.parameterValuesConst().loadById(instance.parameterSet(), 0));
}

test "plugin instance applies parameter changes to owned values" {
    const Gain = struct {
        pub const name = "Instance Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 99, .sample_offset = 0, .normalized = 1.0 },
    };
    const view = try process_api.ParameterChanges.init(&changes, 1);

    instance.applyParameterChanges(view);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.parameterValues().loadById(instance.parameterSet(), 0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterValues().loadById(instance.parameterSet(), 99));
}

test "plugin instance applies process parameter changes before dispatch" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Process Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.observed = context.parameter_changes.latest(0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.25 },
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.parameterValuesConst().loadById(instance.parameterSet(), 0));
    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance passes reflected parameters to state-aware process hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance State Aware Process";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn processWithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.loadById(set, 0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.25 },
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance applies process64 parameter changes before dispatch" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Process64 Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64(self: *@This(), context: *process_api.ProcessContext(f64)) void {
            self.observed = context.parameter_changes.latest(0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.75 },
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.parameterValuesConst().loadById(instance.parameterSet(), 0));
    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance passes reflected parameters to state-aware process64 hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance State Aware Process64";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64WithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.loadById(set, 0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.75 },
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance round-trips owned parameter state" {
    const Gain = struct {
        pub const name = "Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 1.0),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var restored = try Instance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(Gain.Params)]u8 = undefined;

    try std.testing.expect(instance.parameterValues().storeById(instance.parameterSet(), 0, 0.25));
    try std.testing.expect(instance.parameterValues().storeById(instance.parameterSet(), 1, 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try instance.writeParameterState(out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try restored.readParameterState(in_stream.reader());

    try std.testing.expectEqual(@as(?f64, 0.25), restored.parameterValues().loadById(restored.parameterSet(), 0));
    try std.testing.expectEqual(@as(?f64, 0.75), restored.parameterValues().loadById(restored.parameterSet(), 1));
}

test "plugin instance reads parameter state with migrations" {
    const OldGain = struct {
        pub const name = "Old Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(7, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const NewGain = struct {
        pub const name = "New Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            output: parameters.FloatParam = parameters.FloatParam.init(11, "Output", 0.0, 1.0, 0.5),
        };
    };
    const OldInstance = PluginInstance(OldGain);
    const NewInstance = PluginInstance(NewGain);
    var old_instance = try OldInstance.init(std.testing.allocator, .{});
    var new_instance = try NewInstance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(OldGain.Params)]u8 = undefined;

    try std.testing.expect(old_instance.parameterValues().storeById(old_instance.parameterSet(), 7, 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try old_instance.writeParameterState(out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try new_instance.readParameterStateWithMigrations(in_stream.reader(), &.{
        .{ .old_id = 7, .new_id = 11 },
    });

    try std.testing.expectEqual(@as(?f64, 0.25), new_instance.parameterValues().loadById(new_instance.parameterSet(), 11));
}

test "plugin instance accepts metadata-only plugins" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Instance = PluginInstance(Minimal);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f64{0.25};
    var output = [_]f64{0.0};
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f64).init(&input_channels),
        .outputs = try process_api.AudioOutputs(f64).init(&output_channels),
    };

    instance.prepare(.{ .sample_rate = 48_000.0, .max_block_size = 1 });
    instance.process64(&context);
    instance.deinit();

    try std.testing.expectEqualStrings("Minimal", Instance.Spec.name);
    try std.testing.expectEqual(@as(f64, 0.0), output[0]);
}
