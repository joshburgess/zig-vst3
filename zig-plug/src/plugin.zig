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
