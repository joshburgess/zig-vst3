const std = @import("std");
const gui = @import("zig-vst3-plugin").gui;

pub fn constrainedSize(requested: gui.Size) gui.Size {
    return gui.constrained(.{ .resizable = .{
        .minimum = .{ .width = 480, .height = 360 },
        .maximum = .{ .width = 1280, .height = 960 },
    } }, requested);
}

pub fn validScale(scale: f64) bool {
    return (gui.Scale{ .x = scale, .y = scale }).valid();
}

test "toolkit-neutral lifecycle helpers bound host sizes and scale" {
    try std.testing.expectEqual(gui.Size{ .width = 480, .height = 960 }, constrainedSize(.{ .width = 120, .height = 2000 }));
    try std.testing.expect(validScale(2.0));
    try std.testing.expect(!validScale(0.0));
}
