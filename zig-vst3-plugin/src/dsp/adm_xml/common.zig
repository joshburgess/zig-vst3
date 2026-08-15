const std = @import("std");
const adm = @import("../adm.zig");

pub fn isXmlNamespaceDeclaration(attribute_name: []const u8) bool {
    return std.mem.eql(u8, attribute_name, "xmlns") or
        std.mem.startsWith(u8, attribute_name, "xmlns:");
}

pub const DeclarationSpec = struct {
    kind: adm.IdentifierKind,
    attribute_name: []const u8,
};

pub fn declarationSpec(local_name: []const u8) ?DeclarationSpec {
    if (std.mem.eql(u8, local_name, "audioProgramme"))
        return .{ .kind = .programme, .attribute_name = "audioProgrammeID" };
    if (std.mem.eql(u8, local_name, "audioContent"))
        return .{ .kind = .content, .attribute_name = "audioContentID" };
    if (std.mem.eql(u8, local_name, "audioObject"))
        return .{ .kind = .object, .attribute_name = "audioObjectID" };
    if (std.mem.eql(u8, local_name, "audioPackFormat"))
        return .{ .kind = .pack_format, .attribute_name = "audioPackFormatID" };
    if (std.mem.eql(u8, local_name, "audioChannelFormat"))
        return .{ .kind = .channel_format, .attribute_name = "audioChannelFormatID" };
    if (std.mem.eql(u8, local_name, "audioStreamFormat"))
        return .{ .kind = .stream_format, .attribute_name = "audioStreamFormatID" };
    if (std.mem.eql(u8, local_name, "audioTrackFormat"))
        return .{ .kind = .track_format, .attribute_name = "audioTrackFormatID" };
    if (std.mem.eql(u8, local_name, "audioTrackUID"))
        return .{ .kind = .track_uid, .attribute_name = "UID" };
    if (std.mem.eql(u8, local_name, "alternativeValueSet"))
        return .{ .kind = .alternative_value_set, .attribute_name = "alternativeValueSetID" };
    if (std.mem.startsWith(u8, local_name, "audioBlockFormat"))
        return .{ .kind = .block_format, .attribute_name = "audioBlockFormatID" };
    return null;
}

pub fn insideAfe(afe_depth: ?usize, element_depth: usize) bool {
    const depth = afe_depth orelse return false;
    return element_depth > depth;
}
