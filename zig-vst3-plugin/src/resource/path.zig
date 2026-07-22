const std = @import("std");

pub fn BoundedPath(comptime capacity: usize) type {
    if (capacity == 0) @compileError("bounded path capacity must be positive");

    return struct {
        const Self = @This();

        bytes: [capacity]u8 = undefined,
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
            return self.bytes[0..self.length];
        }
    };
}

test "bounded path owns validated inline storage" {
    var source = [_]u8{ '/', 't', 'm', 'p', '/', 'm', 'o', 'd', 'e', 'l' };
    const path = try BoundedPath(16).init(&source);
    source[5] = 'x';
    try std.testing.expectEqualStrings("/tmp/model", path.slice());
    try std.testing.expectError(error.InvalidPath, BoundedPath(16).init(""));
    try std.testing.expectError(error.InvalidPath, BoundedPath(16).init("bad\x00path"));
    try std.testing.expectError(error.PathTooLong, BoundedPath(4).init("model"));
}
