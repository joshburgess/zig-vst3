const builtin = @import("builtin");
const core = @import("zig-vst3-plugin-core");
const shared = @import("mono_gain_lv2_shared.zig");
const vst3 = @import("zig-vst3");

pub const uri = shared.uri ++ "#vstgui-ui";

const platform: core.gui.Platform = switch (builtin.os.tag) {
    .macos => .macos,
    .windows => .windows,
    .linux => .x11,
    else => @compileError(
        "the Mono Gain LV2 VSTGUI UI requires a desktop platform",
    ),
};

const VstguiBackend = vst3.vstgui_lv2_backend.Backend(.{
    .controls = &.{.{
        .parameter_id = 0,
        .kind = .decibel_slider,
        .tooltip = "Adjust the output gain.",
    }},
    .initial_size = .{ .width = 400, .height = 300 },
    .resize_policy = .{
        .resizable = .{
            .minimum = .{ .width = 320, .height = 240 },
            .maximum = .{ .width = 800, .height = 600 },
        },
    },
});

pub const Adapter = core.lv2.ui.Adapter(
    shared.MonoGain,
    shared.Adapter,
    shared.uri,
    uri,
    .{},
    platform,
    VstguiBackend,
);

pub export fn lv2ui_descriptor(
    index: u32,
) callconv(.c) ?*const core.lv2.ui.Descriptor {
    return Adapter.descriptorAt(index);
}

test "Mono Gain exports one VSTGUI LV2 UI descriptor" {
    const std = @import("std");
    const descriptor = lv2ui_descriptor(0) orelse
        return error.MissingDescriptor;
    try std.testing.expectEqualStrings(
        uri,
        std.mem.span(descriptor.URI),
    );
    try std.testing.expect(lv2ui_descriptor(1) == null);
}
