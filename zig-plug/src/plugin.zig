const std = @import("std");
const parameters = @import("parameters.zig");

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
        if (process.params.len != 1 or process.params[0].type.? != *Plugin or process.return_type.? != void) {
            @compileError("process must be fn (*Plugin) void until the audio process contract lands");
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
        pub fn process(_: *@This()) void {}
        pub fn deinit(_: *@This()) void {}
    };
    const Spec = PluginSpec(Meter);
    validateLifecycle(Meter);

    try std.testing.expect(Spec.has_init);
    try std.testing.expect(Spec.has_prepare);
    try std.testing.expect(Spec.has_process);
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
    try std.testing.expect(!Spec.has_deinit);
}
