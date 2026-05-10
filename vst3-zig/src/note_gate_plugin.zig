const entry = @import("entry.zig");
const factory = @import("factory.zig");
const note_gate_component = @import("note_gate_component.zig");
const note_gate_controller = @import("note_gate_controller.zig");
const note_gate_spec = @import("note_gate_spec.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

const NoteGateFactory = factory.StaticFactory3(.{
    .vendor = note_gate_spec.Spec.vendor,
    .url = note_gate_spec.Spec.url,
    .email = note_gate_spec.Spec.email,
}, &.{
    .{
        .cid = note_gate_component.cid,
        .category = note_gate_spec.Spec.component_category,
        .name = note_gate_spec.component_class_name,
        .create = note_gate_component.create,
    },
    .{
        .cid = note_gate_controller.cid,
        .category = note_gate_spec.Spec.controller_category,
        .name = note_gate_spec.controller_class_name,
        .create = note_gate_controller.create,
    },
});

pub usingnamespace entry.Exports(NoteGateFactory);

test "note gate export returns enumerable factory" {
    const plugin_factory = NoteGateFactory.getPluginFactory().?;
    var class_info: ipluginbase.PClassInfo = .{};

    try std.testing.expectEqual(@as(i32, 2), plugin_factory.vtable.countClasses(plugin_factory));
    try std.testing.expectEqual(types.kResultOk, plugin_factory.vtable.getClassInfo(plugin_factory, 0, &class_info));
    try std.testing.expectEqualStrings("zig-vst3 Note Gate", std.mem.sliceTo(&class_info.name, 0));
}

test "note gate plugin root exposes zig-plug metadata" {
    try std.testing.expectEqualStrings("zig-vst3 Note Gate", note_gate_spec.Spec.name);
    try std.testing.expectEqualStrings("zig-vst3 Note Gate Controller", note_gate_spec.controller_class_name);
    try std.testing.expectEqualStrings("zig-vst3", note_gate_spec.Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), note_gate_spec.Spec.ParameterSet.count);
}
