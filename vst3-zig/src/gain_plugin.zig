const entry = @import("entry.zig");
const factory = @import("factory.zig");
const gain_component = @import("gain_component.zig");
const gain_controller = @import("gain_controller.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const plug = @import("zig-plug-core");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const GainPlugin = struct {
    pub const name = "zig-vst3 Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(gain_controller.gain_param_id, "Gain", 0.0, 1.0, 1.0),
    };
};

const GainSpec = plug.plugin.PluginSpec(GainPlugin);

const GainFactory = factory.StaticFactory(.{
    .vendor = GainSpec.vendor,
    .url = "https://github.com/joshburgess/zig-vst3",
}, &.{
    .{
        .cid = gain_component.cid,
        .category = "Audio Module Class",
        .name = GainSpec.name,
        .create = gain_component.create,
    },
    .{
        .cid = gain_controller.cid,
        .category = "Component Controller Class",
        .name = "zig-vst3 Gain Controller",
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
    const spec = GainSpec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Gain", GainSpec.name);
    try std.testing.expectEqualStrings("zig-vst3", GainSpec.vendor);
    try std.testing.expectEqual(@as(usize, 1), GainSpec.ParameterSet.count);
    try std.testing.expectEqual(@as(?f64, 1.0), spec.values.load(gain_controller.gain_param_id));
}
