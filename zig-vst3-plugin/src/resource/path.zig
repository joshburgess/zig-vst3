const std = @import("std");

pub fn BoundedPath(comptime capacity: usize) type {
    if (capacity == 0) @compileError("bounded path capacity must be positive");

    return struct {
        const Self = @This();

        bytes: [capacity]u8 = @splat(0),
        length: usize = 0,

        pub fn init(path: []const u8) error{ InvalidPath, PathTooLong }!Self {
            if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidPath;
            if (path.len > capacity) return error.PathTooLong;
            var result = Self{};
            @memcpy(result.bytes[0..path.len], path);
            result.length = path.len;
            return result;
        }

        pub fn slice(self: *const Self) []const u8 {
            if (self.length == 0 or self.length > capacity) return &.{};
            const path = self.bytes[0..self.length];
            if (std.mem.indexOfScalar(u8, path, 0) != null) return &.{};
            return path;
        }
    };
}

test "bounded path owns validated inline storage" {
    var source = [_]u8{ '/', 't', 'm', 'p', '/', 'm', 'o', 'd', 'e', 'l' };
    const path = try BoundedPath(16).init(&source);
    source[5] = 'x';
    try std.testing.expectEqualStrings("/tmp/model", path.slice());
    for (path.bytes[path.length..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectError(error.InvalidPath, BoundedPath(16).init(""));
    try std.testing.expectError(error.InvalidPath, BoundedPath(16).init("bad\x00path"));
    try std.testing.expectError(error.PathTooLong, BoundedPath(4).init("model"));
}

test "bounded path slice rejects malformed direct lengths" {
    var path = try BoundedPath(4).init("path");
    path.length = 5;
    try std.testing.expectEqual(@as(usize, 0), path.slice().len);
    path.length = 0;
    try std.testing.expectEqual(@as(usize, 0), path.slice().len);
}

test "bounded path slice rejects an embedded nul introduced by direct mutation" {
    var path = try BoundedPath(8).init("model");
    path.bytes[2] = 0;
    try std.testing.expectEqual(@as(usize, 0), path.slice().len);
}
