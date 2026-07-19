const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub const FilterType = enum { low_shelf, bell, high_shelf };
pub const FilterTypeParam = plug.parameters.EnumParam(FilterType);

pub const ParametricEq = struct {
    pub const name = "zig-vst3 Parametric EQ";
    pub const vendor = "zig-vst3";

    pub const Params = struct {
        bypass: plug.parameters.BoolParam = .{
            .id = 0,
            .name = "Bypass",
            .is_bypass = true,
        },
        output: plug.parameters.FloatParam = .{
            .id = 1,
            .name = "Output",
            .units = "dB",
            .min = -18.0,
            .max = 18.0,
            .default = 0.0,
        },
        low_enabled: plug.parameters.BoolParam = .{ .id = 10, .name = "Low Enable", .default = true },
        low_type: FilterTypeParam = .{ .id = 11, .name = "Low Type", .default = .low_shelf },
        low_frequency: plug.parameters.LogFloatParam = .{ .id = 12, .name = "Low Frequency", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 120.0 },
        low_gain: plug.parameters.FloatParam = .{ .id = 13, .name = "Low Gain", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        low_q: plug.parameters.LogFloatParam = .{ .id = 14, .name = "Low Q", .min = 0.1, .max = 18.0, .default = 0.707 },
        mid_enabled: plug.parameters.BoolParam = .{ .id = 20, .name = "Mid Enable", .default = true },
        mid_type: FilterTypeParam = .{ .id = 21, .name = "Mid Type", .default = .bell },
        mid_frequency: plug.parameters.LogFloatParam = .{ .id = 22, .name = "Mid Frequency", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 1_000.0 },
        mid_gain: plug.parameters.FloatParam = .{ .id = 23, .name = "Mid Gain", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        mid_q: plug.parameters.LogFloatParam = .{ .id = 24, .name = "Mid Q", .min = 0.1, .max = 18.0, .default = 1.0 },
        high_enabled: plug.parameters.BoolParam = .{ .id = 30, .name = "High Enable", .default = true },
        high_type: FilterTypeParam = .{ .id = 31, .name = "High Type", .default = .high_shelf },
        high_frequency: plug.parameters.LogFloatParam = .{ .id = 32, .name = "High Frequency", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 8_000.0 },
        high_gain: plug.parameters.FloatParam = .{ .id = 33, .name = "High Gain", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
        high_q: plug.parameters.LogFloatParam = .{ .id = 34, .name = "High Q", .min = 0.1, .max = 18.0, .default = 0.707 },
    };
};

test "parametric EQ core metadata is valid" {
    const Spec = plug.plugin.PluginSpec(ParametricEq);
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Parametric EQ", Spec.name);
    try std.testing.expectEqual(@as(usize, 17), Spec.ParameterSet.count);
    try spec.parameter_set.validate();
    try std.testing.expectEqual(@as(?f64, 20.0), spec.parameter_set.plainMinimumById(12));
    try std.testing.expectEqual(@as(?f64, 20_000.0), spec.parameter_set.plainMaximumById(12));
}

test "parametric EQ frequency parameters use perceptual spacing" {
    const Spec = plug.plugin.PluginSpec(ParametricEq);
    const spec = Spec.init(.{});
    const midpoint = spec.parameter_set.plainFromNormalizedById(22, 0.5) orelse return error.MissingParameter;

    try std.testing.expectApproxEqRel(@as(f64, 632.455532), midpoint, 0.000001);
}
