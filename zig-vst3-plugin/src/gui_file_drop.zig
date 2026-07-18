const std = @import("std");

pub const maximum_files = 8;
pub const maximum_path_bytes = 1024;
pub const maximum_extensions = 8;
pub const maximum_extension_bytes = 16;

pub const Status = enum {
    idle,
    acceptable,
    rejected_type,
    rejected_count,
    rejected_path,
    handler_failed,
    accepted,
};

pub const Path = struct {
    bytes: [maximum_path_bytes]u8 = undefined,
    len: u16 = 0,

    pub fn init(value: []const u8) !Path {
        if (value.len == 0 or value.len > maximum_path_bytes or std.mem.indexOfScalar(u8, value, 0) != null) {
            return error.InvalidPath;
        }
        var result = Path{};
        @memcpy(result.bytes[0..value.len], value);
        result.len = @intCast(value.len);
        return result;
    }

    pub fn slice(self: *const Path) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub fn DropZone(comptime file_capacity: usize, comptime extension_capacity: usize) type {
    if (file_capacity == 0 or file_capacity > maximum_files) {
        @compileError("file drop capacity must be between 1 and 8 files");
    }
    if (extension_capacity == 0 or extension_capacity > maximum_extensions) {
        @compileError("file drop extension capacity must be between 1 and 8 extensions");
    }

    return struct {
        const Self = @This();

        extensions: [extension_capacity][maximum_extension_bytes]u8 = @splat(@splat(0)),
        extension_lengths: [extension_capacity]u8 = @splat(0),
        extension_count: u8 = 0,
        paths: [file_capacity]Path = undefined,
        path_count: u8 = 0,
        status: Status = .idle,

        pub fn init(extensions: []const []const u8) !Self {
            if (extensions.len == 0 or extensions.len > extension_capacity) return error.InvalidExtensionCount;
            var result = Self{};
            for (extensions, 0..) |extension, index| {
                if (extension.len < 2 or extension.len > maximum_extension_bytes or extension[0] != '.' or
                    std.mem.indexOfScalar(u8, extension, 0) != null) return error.InvalidExtension;
                for (extension) |character| {
                    if (!std.ascii.isAlphanumeric(character) and character != '.') return error.InvalidExtension;
                }
                for (extensions[0..index]) |previous| {
                    if (std.ascii.eqlIgnoreCase(previous, extension)) return error.DuplicateExtension;
                }
                for (extension, 0..) |character, character_index| {
                    result.extensions[index][character_index] = std.ascii.toLower(character);
                }
                result.extension_lengths[index] = @intCast(extension.len);
            }
            result.extension_count = @intCast(extensions.len);
            return result;
        }

        pub fn inspect(self: *Self, values: []const []const u8) Status {
            self.path_count = 0;
            if (values.len == 0 or values.len > file_capacity) {
                self.status = .rejected_count;
                return self.status;
            }
            for (values, 0..) |value, index| {
                self.paths[index] = Path.init(value) catch {
                    self.status = .rejected_path;
                    return self.status;
                };
                if (!self.accepts(self.paths[index].slice())) {
                    self.status = .rejected_type;
                    return self.status;
                }
                self.path_count += 1;
            }
            self.status = .acceptable;
            return self.status;
        }

        pub fn complete(self: *Self, accepted: bool) void {
            self.status = if (accepted) .accepted else .handler_failed;
        }

        pub fn reset(self: *Self) void {
            self.path_count = 0;
            self.status = .idle;
        }

        fn accepts(self: *const Self, path: []const u8) bool {
            for (self.extensions[0..self.extension_count], self.extension_lengths[0..self.extension_count]) |extension, length| {
                if (path.len >= length and std.ascii.eqlIgnoreCase(path[path.len - length ..], extension[0..length])) return true;
            }
            return false;
        }
    };
}

test "drop zone filters bounded paths without retaining caller storage" {
    const Zone = DropZone(2, 2);
    var zone = try Zone.init(&.{ ".wav", ".aiff" });
    var caller = [_]u8{ '/', 't', 'm', 'p', '/', 'K', 'i', 'c', 'k', '.', 'W', 'A', 'V' };
    try std.testing.expectEqual(Status.acceptable, zone.inspect(&.{&caller}));
    caller[5] = 'X';
    try std.testing.expectEqualStrings("/tmp/Kick.WAV", zone.paths[0].slice());
    zone.complete(true);
    try std.testing.expectEqual(Status.accepted, zone.status);
}

test "drop zone distinguishes count path type and handler failures" {
    const Zone = DropZone(1, 1);
    var zone = try Zone.init(&.{".wav"});
    try std.testing.expectEqual(Status.rejected_count, zone.inspect(&.{}));
    try std.testing.expectEqual(Status.rejected_count, zone.inspect(&.{ "a.wav", "b.wav" }));
    try std.testing.expectEqual(Status.rejected_type, zone.inspect(&.{"a.mid"}));
    const oversized = [_]u8{'a'} ** (maximum_path_bytes + 1);
    try std.testing.expectEqual(Status.rejected_path, zone.inspect(&.{&oversized}));
    try std.testing.expectEqual(Status.acceptable, zone.inspect(&.{"a.wav"}));
    zone.complete(false);
    try std.testing.expectEqual(Status.handler_failed, zone.status);
}

test "drop zone rejects malformed and duplicate extensions" {
    const Zone = DropZone(2, 2);
    try std.testing.expectError(error.InvalidExtension, Zone.init(&.{"wav"}));
    try std.testing.expectError(error.InvalidExtension, Zone.init(&.{".wave file"}));
    try std.testing.expectError(error.DuplicateExtension, Zone.init(&.{ ".wav", ".WAV" }));
}
