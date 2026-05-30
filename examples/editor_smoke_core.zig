const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub const EditorSmoke = struct {
    pub const name = "zig-vst3 Editor Smoke";
    pub const vendor = "zig-vst3";

    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 1.0,
        },
    };
};

test "editor smoke core metadata is valid" {
    const Spec = plug.plugin.PluginSpec(EditorSmoke);
    const spec = Spec.init(.{});
    try std.testing.expectEqualStrings("zig-vst3 Editor Smoke", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 1), spec.parameter_set.parameterCount());
}
