const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const mode_gain_component = @import("mode_gain_component.zig");
const mode_gain_controller = @import("mode_gain_controller.zig");
const mode_gain_spec = @import("mode_gain_spec.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const ModeGainFactory = factory.StaticFactory(.{
    .vendor = mode_gain_spec.Spec.vendor,
    .url = "https://github.com/joshburgess/zig-vst3",
}, &.{
    .{
        .cid = mode_gain_component.cid,
        .category = "Audio Module Class",
        .name = mode_gain_spec.component_class_name,
        .create = mode_gain_component.create,
    },
    .{
        .cid = mode_gain_controller.cid,
        .category = "Component Controller Class",
        .name = mode_gain_spec.controller_class_name,
        .create = mode_gain_controller.create,
    },
});

pub usingnamespace entry.Exports(ModeGainFactory);

test "mode gain export returns enumerable factory" {
    const plugin_factory = ModeGainFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Mode Gain", std.mem.sliceTo(&class_info.name, 0));
}

test "mode gain plugin root exposes zig-plug metadata" {
    const spec = mode_gain_spec.Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Mode Gain", mode_gain_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Mode Gain Controller", mode_gain_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", mode_gain_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), mode_gain_spec.Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 0), mode_gain_spec.mode_param_index);
    try std.testing.expectEqual(@as(f64, 0.0), spec.values.view(&mode_gain_spec.parameter_set).loadNormalized("mode"));
}
