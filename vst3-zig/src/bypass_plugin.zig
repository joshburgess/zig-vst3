const bypass_component = @import("bypass_component.zig");
const bypass_controller = @import("bypass_controller.zig");
const bypass_spec = @import("bypass_spec.zig");
const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const BypassFactory = factory.StaticFactory(.{
    .vendor = bypass_spec.Spec.vendor,
    .url = bypass_spec.Spec.url,
    .email = bypass_spec.Spec.email,
}, &.{
    .{
        .cid = bypass_component.cid,
        .category = bypass_spec.Spec.component_category,
        .name = bypass_spec.component_class_name,
        .create = bypass_component.create,
    },
    .{
        .cid = bypass_controller.cid,
        .category = bypass_spec.Spec.controller_category,
        .name = bypass_spec.controller_class_name,
        .create = bypass_controller.create,
    },
});

pub usingnamespace entry.Exports(BypassFactory);

test "bypass export returns enumerable factory" {
    const plugin_factory = BypassFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Bypass", std.mem.sliceTo(&class_info.name, 0));
}

test "bypass plugin root exposes zig-plug metadata" {
    const spec = bypass_spec.Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Bypass", bypass_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Bypass Controller", bypass_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", bypass_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), bypass_spec.Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 0), bypass_spec.bypass_param_index);
    try std.testing.expectEqual(@as(f64, 0.0), spec.values.view(&bypass_spec.parameter_set).loadNormalized("bypass"));
}
