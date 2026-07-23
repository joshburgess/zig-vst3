const std = @import("std");
const path_mod = @import("path.zig");

const magic = "ZRSRCREF";
pub const format_version: u16 = 1;

pub const RecoveryStatus = enum {
    empty,
    restoring,
    ready,
    missing,
    moved,
    changed,
    unsupported,
    failed,
};

pub const Identity = struct {
    byte_length: u64,
    sha256: [32]u8,

    pub fn fromBytes(bytes: []const u8) Identity {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        return .{
            .byte_length = bytes.len,
            .sha256 = digest,
        };
    }

    pub fn eql(self: Identity, other: Identity) bool {
        return self.byte_length == other.byte_length and
            std.crypto.timing_safe.eql([32]u8, self.sha256, other.sha256);
    }
};

pub const IdentityHasher = struct {
    hash: std.crypto.hash.sha2.Sha256 = .init(.{}),
    byte_length: u64 = 0,

    pub fn update(self: *IdentityHasher, bytes: []const u8) error{ResourceTooLarge}!void {
        self.byte_length = std.math.add(u64, self.byte_length, bytes.len) catch return error.ResourceTooLarge;
        self.hash.update(bytes);
    }

    pub fn final(self: *IdentityHasher) Identity {
        var digest: [32]u8 = undefined;
        self.hash.final(&digest);
        return .{
            .byte_length = self.byte_length,
            .sha256 = digest,
        };
    }
};

pub fn BoundedMetadata(comptime capacity: usize) type {
    if (capacity == 0) @compileError("bounded metadata capacity must be positive");

    return struct {
        const Self = @This();

        bytes: [capacity]u8 = undefined,
        length: usize = 0,

        pub fn init(metadata: []const u8) error{MetadataTooLong}!Self {
            if (metadata.len > capacity) return error.MetadataTooLong;
            var result = Self{};
            @memcpy(result.bytes[0..metadata.len], metadata);
            result.length = metadata.len;
            return result;
        }

        pub fn slice(self: *const Self) []const u8 {
            if (self.length > capacity) return &.{};
            return self.bytes[0..self.length];
        }
    };
}

pub fn Reference(comptime path_capacity: usize, comptime metadata_capacity: usize) type {
    if (path_capacity > std.math.maxInt(u32)) @compileError("resource path capacity exceeds state format");
    if (metadata_capacity > std.math.maxInt(u32)) @compileError("resource metadata capacity exceeds state format");

    return struct {
        const Self = @This();

        pub const Path = path_mod.BoundedPath(path_capacity);
        pub const Metadata = BoundedMetadata(metadata_capacity);
        pub const maximum_encoded_size = magic.len + 2 + 1 + 4 + 4 + 4 + 8 + 32 + path_capacity + metadata_capacity;

        path: Path,
        identity: Identity,
        resource_schema_version: u32,
        metadata: Metadata,

        pub fn init(
            path: []const u8,
            identity: Identity,
            resource_schema_version: u32,
            metadata: []const u8,
        ) !Self {
            return .{
                .path = try Path.init(path),
                .identity = identity,
                .resource_schema_version = resource_schema_version,
                .metadata = try Metadata.init(metadata),
            };
        }

        pub fn encodedSize(self: *const Self) usize {
            if (!self.valid()) return maximum_encoded_size + 1;
            return maximum_encoded_size - path_capacity - metadata_capacity + self.path.length + self.metadata.length;
        }

        pub fn write(self: *const Self, writer: anytype) !void {
            if (self.path.length == 0) return error.InvalidPath;
            if (self.path.length > path_capacity) return error.PathTooLong;
            if (self.metadata.length > metadata_capacity) return error.MetadataTooLong;
            try writer.writeAll(magic);
            try writer.writeInt(u16, format_version, .little);
            try writer.writeByte(1);
            try writer.writeInt(u32, self.resource_schema_version, .little);
            try writer.writeInt(u32, @intCast(self.path.length), .little);
            try writer.writeInt(u32, @intCast(self.metadata.length), .little);
            try writer.writeInt(u64, self.identity.byte_length, .little);
            try writer.writeAll(&self.identity.sha256);
            try writer.writeAll(self.path.slice());
            try writer.writeAll(self.metadata.slice());
        }

        pub fn read(reader: anytype) !Self {
            var stored_magic: [magic.len]u8 = undefined;
            try reader.readSliceAll(&stored_magic);
            if (!std.mem.eql(u8, &stored_magic, magic)) return error.InvalidResourceStateMagic;
            if (try reader.takeInt(u16, .little) != format_version) return error.UnsupportedResourceStateVersion;
            if (try reader.takeByte() != 1) return error.InvalidResourceStateTag;
            const schema_version = try reader.takeInt(u32, .little);
            const path_length = try reader.takeInt(u32, .little);
            const metadata_length = try reader.takeInt(u32, .little);
            if (path_length == 0) return error.InvalidPath;
            if (path_length > path_capacity) return error.PathTooLong;
            if (metadata_length > metadata_capacity) return error.MetadataTooLong;
            const identity = Identity{
                .byte_length = try reader.takeInt(u64, .little),
                .sha256 = undefined,
            };
            var restored_identity = identity;
            try reader.readSliceAll(&restored_identity.sha256);
            var path_bytes: [path_capacity]u8 = undefined;
            var metadata_bytes: [metadata_capacity]u8 = undefined;
            try reader.readSliceAll(path_bytes[0..path_length]);
            try reader.readSliceAll(metadata_bytes[0..metadata_length]);
            return init(
                path_bytes[0..path_length],
                restored_identity,
                schema_version,
                metadata_bytes[0..metadata_length],
            );
        }

        pub fn classifyCandidate(self: *const Self, candidate_path: []const u8, candidate_identity: Identity) RecoveryStatus {
            if (!self.valid()) return .failed;
            if (!self.identity.eql(candidate_identity)) return .changed;
            return if (std.mem.eql(u8, self.path.slice(), candidate_path)) .ready else .moved;
        }

        fn valid(self: *const Self) bool {
            return self.path.length > 0 and self.path.length <= path_capacity and
                self.metadata.length <= metadata_capacity;
        }
    };
}

pub fn State(comptime path_capacity: usize, comptime metadata_capacity: usize) type {
    const Linked = Reference(path_capacity, metadata_capacity);
    return union(enum) {
        const Self = @This();

        pub const maximum_encoded_size = 1 + Linked.maximum_encoded_size;

        empty,
        linked: Linked,

        pub fn encodedSize(self: *const Self) usize {
            return switch (self.*) {
                .empty => 1,
                .linked => |*linked| 1 + linked.encodedSize(),
            };
        }

        pub fn write(self: *const Self, writer: anytype) !void {
            switch (self.*) {
                .empty => try writer.writeByte(0),
                .linked => |*linked| {
                    try writer.writeByte(1);
                    try linked.write(writer);
                },
            }
        }

        pub fn read(reader: anytype) !Self {
            return switch (try reader.takeByte()) {
                0 => .empty,
                1 => .{ .linked = try Linked.read(reader) },
                else => error.InvalidResourceStateTag,
            };
        }
    };
}

test "resource reference round trips a maximum length path" {
    const Stored = Reference(32, 24);
    const path = "12345678901234567890123456789012";
    const source = "bounded model fixture";
    const stored = try Stored.init(path, Identity.fromBytes(source), 7, "Linear, 48 kHz");
    var encoded: [Stored.maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try stored.write(&writer);
    try std.testing.expectEqual(stored.encodedSize(), writer.end);

    var reader = std.Io.Reader.fixed(encoded[0..writer.end]);
    const restored = try Stored.read(&reader);
    try std.testing.expectEqualStrings(path, restored.path.slice());
    try std.testing.expect(stored.identity.eql(restored.identity));
    try std.testing.expectEqual(@as(u32, 7), restored.resource_schema_version);
    try std.testing.expectEqualStrings("Linear, 48 kHz", restored.metadata.slice());
}

test "resource reference rejects malformed lengths transactionally" {
    const Stored = Reference(8, 8);
    const stored = try Stored.init("model", Identity.fromBytes("fixture"), 1, "linear");
    var encoded: [Stored.maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try stored.write(&writer);
    const path_length_offset = magic.len + 2 + 1 + 4;
    std.mem.writeInt(u32, encoded[path_length_offset..][0..4], 9, .little);
    var reader = std.Io.Reader.fixed(encoded[0..writer.end]);
    try std.testing.expectError(error.PathTooLong, Stored.read(&reader));
}

test "resource identity detects changed and moved files" {
    const Stored = Reference(32, 16);
    const original = Identity.fromBytes("original model");
    const stored = try Stored.init("/models/a.nam", original, 1, "Linear");
    try std.testing.expectEqual(RecoveryStatus.ready, stored.classifyCandidate("/models/a.nam", original));
    try std.testing.expectEqual(RecoveryStatus.moved, stored.classifyCandidate("/models/b.nam", original));
    try std.testing.expectEqual(RecoveryStatus.changed, stored.classifyCandidate("/models/a.nam", Identity.fromBytes("replacement model")));
}

test "resource reference rejects malformed direct storage lengths" {
    const Stored = Reference(8, 8);
    var stored = try Stored.init("model", Identity.fromBytes("fixture"), 1, "linear");
    var encoded: [Stored.maximum_encoded_size]u8 = undefined;

    stored.path.length = 9;
    try std.testing.expectEqual(Stored.maximum_encoded_size + 1, stored.encodedSize());
    var path_writer = std.Io.Writer.fixed(&encoded);
    try std.testing.expectError(error.PathTooLong, stored.write(&path_writer));
    try std.testing.expectEqual(RecoveryStatus.failed, stored.classifyCandidate("model", stored.identity));

    stored.path.length = 5;
    stored.metadata.length = 9;
    var metadata_writer = std.Io.Writer.fixed(&encoded);
    try std.testing.expectError(error.MetadataTooLong, stored.write(&metadata_writer));

    stored.metadata.length = 6;
    stored.path.length = 0;
    var empty_path_writer = std.Io.Writer.fixed(&encoded);
    try std.testing.expectError(error.InvalidPath, stored.write(&empty_path_writer));
}

test "streamed identity matches one-shot identity" {
    var hasher = IdentityHasher{};
    try hasher.update("bounded ");
    try hasher.update("model fixture");
    try std.testing.expect(Identity.fromBytes("bounded model fixture").eql(hasher.final()));
}

test "resource state represents empty and linked resources" {
    const Stored = State(32, 16);
    var empty_bytes: [Stored.maximum_encoded_size]u8 = undefined;
    var empty_writer = std.Io.Writer.fixed(&empty_bytes);
    const empty: Stored = .empty;
    try empty.write(&empty_writer);
    var empty_reader = std.Io.Reader.fixed(empty_bytes[0..empty_writer.end]);
    try std.testing.expectEqual(Stored.empty, try Stored.read(&empty_reader));

    const linked = try Reference(32, 16).init("/models/a.nam", Identity.fromBytes("fixture"), 1, "Linear");
    const state: Stored = .{ .linked = linked };
    var linked_bytes: [Stored.maximum_encoded_size]u8 = undefined;
    var linked_writer = std.Io.Writer.fixed(&linked_bytes);
    try state.write(&linked_writer);
    var linked_reader = std.Io.Reader.fixed(linked_bytes[0..linked_writer.end]);
    const restored = try Stored.read(&linked_reader);
    try std.testing.expectEqualStrings("/models/a.nam", restored.linked.path.slice());
}
