const shared = @import("../common.zig");

pub fn validateRequiredMetadataString(value: []const u8) !void {
    if (value.len == 0) return error.EmptyPluginMetadata;
    try validateOptionalMetadataString(value);
}

pub fn validateOptionalMetadataString(value: []const u8) !void {
    if (shared.containsNul(value)) return error.InvalidPluginMetadata;
}
