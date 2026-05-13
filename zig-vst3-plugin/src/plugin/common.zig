const std = @import("std");

pub fn validateRequiredMetadataString(value: []const u8) !void {
    if (value.len == 0) return error.EmptyPluginMetadata;
    try validateOptionalMetadataString(value);
}

pub fn validateOptionalMetadataString(value: []const u8) !void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidPluginMetadata;
}
