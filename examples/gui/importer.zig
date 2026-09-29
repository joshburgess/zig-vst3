const std = @import("std");
const ui = @import("zig-vst3").vstgui;

pub const audio: ui.FileImporter = .{
    .id = 1,
    .title = "Sample",
    .prompt = "Drop a WAV or AIFF sample here",
    .picker_label = "Choose Sample",
    .picker_title = "Choose a Sample",
    .extensions = &.{ ".wav", ".aif", ".aiff" },
    .maximum_files = 1,
};

test "focused importer includes equivalent drop and picker entry points" {
    try ui.validateFileImporter(audio);
    try std.testing.expectEqual(@as(usize, 3), audio.extensions.len);
    try std.testing.expect(std.mem.span(audio.picker_label).len != 0);
}
