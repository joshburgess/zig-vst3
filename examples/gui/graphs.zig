const std = @import("std");
const ui = @import("zig-vst3").vstgui;

pub const transfer: ui.Graph = .{
    .title = "Transfer",
    .kind = .transfer_function,
    .x_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Input" },
    .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Output" },
    .points = &.{ .{ .x = -1.0, .y = -0.8 }, .{ .x = 0.0, .y = 0.0 }, .{ .x = 1.0, .y = 0.8 } },
};

pub const spectrum: ui.Graph = .{
    .title = "Spectrum",
    .kind = .spectrum,
    .x_axis = .{ .minimum = 20.0, .maximum = 20_000.0, .scale = .logarithmic, .label = "Hz" },
    .y_axis = .{ .minimum = -96.0, .maximum = 0.0, .scale = .decibels, .label = "dB" },
    .source_id = 1,
    .dynamic = true,
    .maximum_refresh_hz = 30,
};

test "focused graph declarations distinguish fixed and dynamic data" {
    try std.testing.expectEqual(@as(usize, 3), transfer.points.len);
    try std.testing.expect(spectrum.dynamic);
    try std.testing.expectEqual(@as(u32, 30), spectrum.maximum_refresh_hz);
}
