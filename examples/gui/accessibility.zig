const std = @import("std");
const ui = @import("zig-vst3").vstgui;

pub const import_progress: ui.ProgressIndicator = .{
    .source_id = 1,
    .label = "Import",
    .accessible_label = "Sample import progress",
    .idle_text = "Choose a sample",
    .running_text = "Importing sample",
    .complete_text = "Sample ready",
    .failure_text = "Import failed. Try again",
};

pub const clear_sample: ui.ActionButton = .{
    .group_id = 1,
    .id = 1,
    .label = "Clear",
    .accessible_label = "Clear imported sample",
    .tooltip = "Remove the imported sample",
    .confirmation_label = "Clear sample?",
    .failure_label = "Could not clear the sample",
    .role = .destructive,
};

test "focused accessibility declarations provide nonvisual state and recovery text" {
    try ui.validateProgressIndicators(&.{import_progress});
    try ui.validateActionButtons(&.{clear_sample});
    const label = clear_sample.label orelse return error.MissingVisibleLabel;
    try std.testing.expect(std.mem.span(clear_sample.accessible_label).len > std.mem.span(label).len);
}
