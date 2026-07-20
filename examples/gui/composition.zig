const std = @import("std");
const ui = @import("zig-vst3").vstgui;

pub const editor: ui.EditorDescription = .{
    .parameters = &.{
        .{ .id = 0, .title = "Gain", .units = "dB", .step_count = 0, .default_normalized = 0.5, .control_kind = .decibel_slider },
        .{ .id = 1, .title = "Bypass", .step_count = 1, .default_normalized = 0.0, .control_kind = .toggle },
    },
    .skin = .{ .theme = .default, .layout = .parameter_workspace },
    .composition = .{
        .title = "Focused Effect",
        .groups = &.{.{ .title = "Output", .parameter_count = 2 }},
    },
};

test "focused composition uses the declarative public surface" {
    try std.testing.expectEqual(@as(usize, 2), editor.parameters.len);
    const title = editor.composition.title orelse return error.MissingCompositionTitle;
    try std.testing.expectEqualStrings("Focused Effect", std.mem.span(title));
}
