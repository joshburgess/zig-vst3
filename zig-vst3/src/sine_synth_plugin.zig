const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const sine_synth_component = @import("sine_synth_component.zig");
const sine_synth_controller = @import("sine_synth_controller.zig");
const sine_synth_spec = @import("sine_synth_spec.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const SineSynthFactory = factory.StaticFactory3(.{
    .vendor = sine_synth_spec.Spec.vendor,
    .url = sine_synth_spec.Spec.url,
    .email = sine_synth_spec.Spec.email,
}, &.{
    .{
        .cid = sine_synth_component.cid,
        .category = sine_synth_spec.Spec.component_category,
        .name = sine_synth_spec.component_class_name,
        .create = sine_synth_component.create,
    },
    .{
        .cid = sine_synth_controller.cid,
        .category = sine_synth_spec.Spec.controller_category,
        .name = sine_synth_spec.controller_class_name,
        .create = sine_synth_controller.create,
    },
});

comptime {
    entry.exportPlugin(SineSynthFactory);
}

test "sine synth export returns enumerable factory" {
    const plugin_factory = SineSynthFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Sine Synth", std.mem.sliceTo(&class_info.name, 0));
}

test "sine synth plugin root exposes zig-vst3-plugin metadata" {
    const spec = sine_synth_spec.Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Sine Synth", sine_synth_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Sine Synth Controller", sine_synth_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", sine_synth_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 9), sine_synth_spec.Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 0), sine_synth_spec.level_param_index);
    try std.testing.expectEqual(@as(f64, 0.1), spec.values.view(&sine_synth_spec.parameter_set).loadNormalized("level"));
}
