const shared = @import("../common.zig");
const std = @import("std");

pub fn validateRequiredMetadataString(value: []const u8) !void {
    if (value.len == 0) return error.EmptyPluginMetadata;
    try validateOptionalMetadataString(value);
}

pub fn validateOptionalMetadataString(value: []const u8) !void {
    if (shared.containsNul(value)) return error.InvalidPluginMetadata;
}

test "required plugin metadata rejects empty or nul-terminated text" {
    try std.testing.expectError(error.EmptyPluginMetadata, validateRequiredMetadataString(""));
    try std.testing.expectError(error.InvalidPluginMetadata, validateRequiredMetadataString("bad\x00name"));
    try validateRequiredMetadataString("Example");
}

test "optional plugin metadata permits empty text but rejects embedded nul bytes" {
    try validateOptionalMetadataString("");
    try validateOptionalMetadataString("https://example.com");
    try std.testing.expectError(error.InvalidPluginMetadata, validateOptionalMetadataString("https://example.com\x00"));
}
