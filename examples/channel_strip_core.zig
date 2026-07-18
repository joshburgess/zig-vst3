const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub const Mode = enum { clean, console, limit };
pub const ModeParam = plug.parameters.EnumParam(Mode);

pub const ChannelStrip = struct {
    pub const name = "zig-vst3 Channel Strip";
    pub const vendor = "zig-vst3";

    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .units = "dB",
            .min = -24.0,
            .max = 24.0,
            .default = 0.0,
        },
        bypass: plug.parameters.BoolParam = .{
            .id = 1,
            .name = "Bypass",
            .default = false,
            .is_bypass = true,
        },
        mode: ModeParam = .{
            .id = 2,
            .name = "Mode",
            .default = .clean,
        },
    };
};

test "channel strip core metadata is valid" {
    const Spec = plug.plugin.PluginSpec(ChannelStrip);
    const spec = Spec.init(.{});
    try std.testing.expectEqualStrings("zig-vst3 Channel Strip", Spec.name);
    try std.testing.expectEqual(@as(usize, 3), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 3), spec.parameter_set.parameterCount());
}
