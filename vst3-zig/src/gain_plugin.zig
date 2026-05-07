const entry = @import("entry.zig");
const factory = @import("factory.zig");
const gain_component = @import("gain_component.zig");
const gain_controller = @import("gain_controller.zig");
const gain_spec = @import("gain_spec.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const GainFactory = factory.StaticFactory(.{
    .vendor = gain_spec.Spec.vendor,
    .url = "https://github.com/joshburgess/zig-vst3",
}, &.{
    .{
        .cid = gain_component.cid,
        .category = "Audio Module Class",
        .name = gain_spec.component_class_name,
        .create = gain_component.create,
    },
    .{
        .cid = gain_controller.cid,
        .category = "Component Controller Class",
        .name = gain_spec.controller_class_name,
        .create = gain_controller.create,
    },
});

pub usingnamespace entry.Exports(GainFactory);

test "gain export returns enumerable factory" {
    const plugin_factory = GainFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Gain", std.mem.sliceTo(&class_info.name, 0));
}

test "gain plugin root exposes zig-plug metadata" {
    const spec = gain_spec.Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Gain", gain_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Gain Controller", gain_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", gain_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), gain_spec.Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 0), gain_spec.gain_param_index);
    try std.testing.expectEqual(@as(?f64, 1.0), spec.values.load(gain_spec.gain_param_id));
}
