const editor_smoke_component = @import("editor_smoke_component.zig");
const editor_smoke_controller = @import("editor_smoke_controller.zig");
const editor_smoke_spec = @import("editor_smoke_spec.zig");
const entry = @import("entry.zig");
const factory = @import("factory.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const EditorSmokeFactory = factory.StaticFactory3(.{
    .vendor = editor_smoke_spec.Spec.vendor,
    .url = editor_smoke_spec.Spec.url,
    .email = editor_smoke_spec.Spec.email,
}, &.{
    .{
        .cid = editor_smoke_component.cid,
        .category = editor_smoke_spec.Spec.component_category,
        .name = editor_smoke_spec.component_class_name,
        .create = editor_smoke_component.create,
    },
    .{
        .cid = editor_smoke_controller.cid,
        .category = editor_smoke_spec.Spec.controller_category,
        .name = editor_smoke_spec.controller_class_name,
        .create = editor_smoke_controller.create,
    },
});

comptime {
    entry.exportPlugin(EditorSmokeFactory);
}

test "editor smoke export returns enumerable factory" {
    const plugin_factory = EditorSmokeFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Editor Smoke", std.mem.sliceTo(&class_info.name, 0));
}
