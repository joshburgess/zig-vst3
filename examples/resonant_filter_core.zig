const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub const FilterMode = enum { low_pass, high_pass, band_pass, notch };
pub const FilterModeParam = plug.parameters.EnumParam(FilterMode);

pub const ResonantFilter = struct {
    pub const name = "zig-vst3 Resonant Filter";
    pub const vendor = "zig-vst3";

    pub const Params = struct {
        bypass: plug.parameters.BoolParam = .{ .id = 0, .name = "Bypass", .is_bypass = true },
        mode: FilterModeParam = .{ .id = 1, .name = "Mode", .default = .low_pass },
        cutoff: plug.parameters.LogFloatParam = .{ .id = 2, .name = "Cutoff", .units = "Hz", .min = 20.0, .max = 20_000.0, .default = 1_000.0 },
        resonance: plug.parameters.LogFloatParam = .{ .id = 3, .name = "Resonance", .min = 0.1, .max = 18.0, .default = 0.707 },
        drive: plug.parameters.FloatParam = .{ .id = 4, .name = "Drive", .units = "dB", .min = 0.0, .max = 24.0, .default = 0.0 },
        mix: plug.parameters.FloatParam = .{ .id = 5, .name = "Mix", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
        output: plug.parameters.FloatParam = .{ .id = 6, .name = "Output", .units = "dB", .min = -18.0, .max = 18.0, .default = 0.0 },
    };
};

test "resonant filter metadata is valid" {
    const Spec = plug.plugin.PluginSpec(ResonantFilter);
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Resonant Filter", Spec.name);
    try std.testing.expectEqual(@as(usize, 7), Spec.ParameterSet.count);
    try spec.parameter_set.validate();
    try std.testing.expectEqual(@as(?f64, 20.0), spec.parameter_set.plainMinimumById(2));
    try std.testing.expectEqual(@as(?f64, 20_000.0), spec.parameter_set.plainMaximumById(2));
    try std.testing.expectEqual(@as(?f64, 18.0), spec.parameter_set.plainMaximumById(3));
}

test "resonant filter frequency and resonance use perceptual spacing" {
    const Spec = plug.plugin.PluginSpec(ResonantFilter);
    const spec = Spec.init(.{});
    const cutoff = spec.parameter_set.plainFromNormalizedById(2, 0.5) orelse return error.MissingParameter;
    const resonance = spec.parameter_set.plainFromNormalizedById(3, 0.5) orelse return error.MissingParameter;

    try std.testing.expectApproxEqRel(@as(f64, 632.455532), cutoff, 0.000001);
    try std.testing.expectApproxEqRel(@as(f64, 1.341640786), resonance, 0.000001);
}
