const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub const ImpulseResponseLoader = struct {
    pub const name = "zig-vst3 IR Loader";
    pub const vendor = "zig-vst3";

    pub const Params = struct {
        wet: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Wet",
            .units = "%",
            .min = 0.0,
            .max = 100.0,
            .default = 100.0,
        },
        output: plug.parameters.FloatParam = .{
            .id = 1,
            .name = "Output",
            .units = "dB",
            .min = -24.0,
            .max = 12.0,
            .default = 0.0,
        },
        bypass: plug.parameters.BoolParam = .{
            .id = 2,
            .name = "Bypass",
            .default = false,
            .is_bypass = true,
        },
    };
};

test "IR loader core metadata is valid" {
    const Spec = plug.plugin.PluginSpec(ImpulseResponseLoader);
    const spec = Spec.init(.{});
    try std.testing.expectEqualStrings("zig-vst3 IR Loader", Spec.name);
    try std.testing.expectEqual(@as(usize, 3), spec.parameter_set.parameterCount());
}
