const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");
const voice_mix_component = @import("voice_mix_component.zig");
const voice_mix_controller = @import("voice_mix_controller.zig");
const voice_mix_spec = @import("voice_mix_spec.zig");

const VoiceMixFactory = factory.StaticFactory(.{
    .vendor = voice_mix_spec.Spec.vendor,
    .url = voice_mix_spec.Spec.url,
    .email = voice_mix_spec.Spec.email,
}, &.{
    .{
        .cid = voice_mix_component.cid,
        .category = voice_mix_spec.Spec.component_category,
        .name = voice_mix_spec.component_class_name,
        .create = voice_mix_component.create,
    },
    .{
        .cid = voice_mix_controller.cid,
        .category = voice_mix_spec.Spec.controller_category,
        .name = voice_mix_spec.controller_class_name,
        .create = voice_mix_controller.create,
    },
});

pub usingnamespace entry.Exports(VoiceMixFactory);

test "voice mix export returns enumerable factory" {
    const plugin_factory = VoiceMixFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Voice Mix", std.mem.sliceTo(&class_info.name, 0));
}

test "voice mix plugin root exposes zig-plug metadata" {
    const spec = voice_mix_spec.Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3 Voice Mix", voice_mix_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Voice Mix Controller", voice_mix_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", voice_mix_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), voice_mix_spec.Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 0), voice_mix_spec.voices_param_index);
    try std.testing.expectEqual(@as(f64, 0.0), spec.values.view(&voice_mix_spec.parameter_set).loadNormalized("voices"));
}
