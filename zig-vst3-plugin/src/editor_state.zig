const std = @import("std");

pub const wire_version: u16 = 1;
pub const maximum_fields: usize = 64;
pub const maximum_text_bytes: usize = 96;
pub const maximum_envelope_points: usize = 32;
pub const maximum_migrations: usize = 256;
pub const maximum_entry_payload_bytes: usize = 1 + maximum_envelope_points * 20;
pub const encoded_header_size: usize = 8 + @sizeOf(u16) * 4;
pub const encoded_entry_header_size: usize = @sizeOf(u32) + @sizeOf(u8) + @sizeOf(u16);

const magic = "ZGUISTAT";
const fuzz_seed = magic ++
    "\x01\x00\x01\x00\x01\x00\x00\x00" ++
    "\x01\x00\x00\x00\x01\x01\x00\x01";

pub const Kind = enum(u8) {
    boolean = 1,
    integer = 2,
    scalar = 3,
    index = 4,
    point_id = 5,
    point = 6,
    text = 7,
    envelope = 8,
};

pub const Point = struct {
    id: u32,
    x: f64,
    y: f64,
};

pub const Text = struct {
    bytes: [maximum_text_bytes]u8 = @splat(0),
    len: u8 = 0,

    pub fn init(value: []const u8) !Text {
        if (value.len > maximum_text_bytes) return error.EditorStateTextTooLong;
        if (!std.unicode.utf8ValidateSlice(value))
            return error.InvalidEditorStateTextEncoding;
        var result = Text{};
        @memcpy(result.bytes[0..value.len], value);
        result.len = @intCast(value.len);
        return result;
    }

    pub fn slice(self: *const Text) []const u8 {
        if (!self.valid()) return &.{};
        return self.bytes[0..self.len];
    }

    pub fn valid(self: *const Text) bool {
        return self.len <= maximum_text_bytes and
            std.unicode.utf8ValidateSlice(self.bytes[0..self.len]);
    }
};

pub const Envelope = struct {
    points: [maximum_envelope_points]Point = @splat(.{ .id = 0, .x = 0, .y = 0 }),
    len: u8 = 0,

    pub fn init(points: []const Point) !Envelope {
        if (points.len > maximum_envelope_points) return error.EditorStateEnvelopeTooLarge;
        try validatePoints(points);
        var result = Envelope{};
        @memcpy(result.points[0..points.len], points);
        result.len = @intCast(points.len);
        return result;
    }

    pub fn slice(self: *const Envelope) []const Point {
        if (!self.valid()) return &.{};
        return self.points[0..self.len];
    }

    pub fn valid(self: *const Envelope) bool {
        if (self.len > maximum_envelope_points) return false;
        validatePoints(self.points[0..self.len]) catch return false;
        return true;
    }
};

pub const Value = union(Kind) {
    boolean: bool,
    integer: i64,
    scalar: f64,
    index: u32,
    point_id: u32,
    point: Point,
    text: Text,
    envelope: Envelope,

    pub fn kind(self: Value) Kind {
        return std.meta.activeTag(self);
    }
};

pub const Field = struct {
    id: u32,
    default: Value,
};

pub const Migration = struct {
    from_version: u16,
    old_id: u32,
    new_id: u32,
};

pub const ReadReport = struct {
    decoded_count: usize,
    restored_count: usize,
    ignored_count: usize,
    source_schema_version: u16,
};

pub fn Store(comptime schema_version: u16, comptime fields: []const Field) type {
    if (schema_version == 0) @compileError("editor state schema version must be nonzero");
    if (fields.len > maximum_fields) @compileError("editor state supports at most 64 declared fields");
    validateFields(fields);

    return struct {
        const Self = @This();

        values: [fields.len]Value,

        pub const version = schema_version;
        pub const field_count = fields.len;

        pub fn init() Self {
            var result: Self = undefined;
            inline for (fields, 0..) |field, index| result.values[index] = field.default;
            return result;
        }

        pub fn get(self: *const Self, id: u32) ?Value {
            const index = fieldIndex(id) orelse return null;
            const value = self.values[index];
            validateValue(value) catch return null;
            return value;
        }

        pub fn set(self: *Self, id: u32, value: Value) !void {
            const index = fieldIndex(id) orelse return error.UnknownEditorStateField;
            if (fields[index].default.kind() != value.kind()) return error.EditorStateTypeMismatch;
            try validateValue(value);
            self.values[index] = value;
        }

        pub fn setUnsigned(self: *Self, id: u32, value: u32) !void {
            const index = fieldIndex(id) orelse return error.UnknownEditorStateField;
            self.values[index] = switch (fields[index].default) {
                .index => .{ .index = value },
                .point_id => .{ .point_id = value },
                else => return error.EditorStateTypeMismatch,
            };
        }

        pub fn reset(self: *Self, id: u32) !void {
            const index = fieldIndex(id) orelse return error.UnknownEditorStateField;
            self.values[index] = fields[index].default;
        }

        pub fn valid(self: *const Self) bool {
            for (self.values) |value| {
                validateValue(value) catch return false;
            }
            return true;
        }

        pub fn encodedSize(self: *const Self) usize {
            if (!self.valid()) return maximumEncodedSize() + 1;
            var size = encoded_header_size;
            for (self.values) |value| size += encoded_entry_header_size + valuePayloadSize(value);
            return size;
        }

        pub fn write(self: *const Self, writer: anytype) !void {
            for (self.values) |value| try validateValue(value);
            if (self.encodedSize() > maximumEncodedSize()) return error.EditorStateTooLarge;
            try writer.writeAll(magic);
            try writer.writeInt(u16, wire_version, .little);
            try writer.writeInt(u16, schema_version, .little);
            try writer.writeInt(u16, @intCast(fields.len), .little);
            try writer.writeInt(u16, 0, .little);
            inline for (fields, 0..) |field, index| {
                const value = self.values[index];
                const payload_size = valuePayloadSize(value);
                try writer.writeInt(u32, field.id, .little);
                try writer.writeByte(@intFromEnum(value.kind()));
                try writer.writeInt(u16, @intCast(payload_size), .little);
                try writeValue(value, writer);
            }
        }

        pub fn read(self: *Self, reader: anytype, migrations: []const Migration) !ReadReport {
            const migration_index = try MigrationIndex.init(migrations, schema_version);
            var header_magic: [magic.len]u8 = undefined;
            try reader.readSliceAll(&header_magic);
            if (!std.mem.eql(u8, &header_magic, magic)) return error.InvalidEditorStateMagic;
            if (try reader.takeInt(u16, .little) != wire_version) return error.UnsupportedEditorStateWireVersion;
            const source_version = try reader.takeInt(u16, .little);
            if (source_version == 0 or source_version > schema_version) return error.UnsupportedEditorStateSchemaVersion;
            const entry_count = try reader.takeInt(u16, .little);
            if (entry_count > maximum_fields) return error.EditorStateTooManyFields;
            if (try reader.takeInt(u16, .little) != 0) return error.InvalidEditorStateHeader;

            var restored = Self.init();
            var seen: [fields.len]bool = @splat(false);
            var report = ReadReport{
                .decoded_count = entry_count,
                .restored_count = 0,
                .ignored_count = 0,
                .source_schema_version = source_version,
            };
            var scratch: [maximum_entry_payload_bytes]u8 = undefined;
            for (0..entry_count) |_| {
                const stored_id = try reader.takeInt(u32, .little);
                const raw_kind = try reader.takeByte();
                const payload_len = try reader.takeInt(u16, .little);
                if (payload_len > scratch.len) return error.EditorStateEntryTooLarge;
                try reader.readSliceAll(scratch[0..payload_len]);
                const id = migration_index.migratedId(source_version, stored_id);
                const index = fieldIndex(id) orelse {
                    report.ignored_count += 1;
                    continue;
                };
                if (seen[index]) return error.DuplicateEditorStateField;
                seen[index] = true;
                const kind: Kind = switch (raw_kind) {
                    1...8 => @enumFromInt(raw_kind),
                    else => {
                        report.ignored_count += 1;
                        continue;
                    },
                };
                if (kind != fields[index].default.kind()) return error.EditorStateTypeMismatch;
                var payload_reader = std.Io.Reader.fixed(scratch[0..payload_len]);
                const value = try readValue(kind, &payload_reader, payload_len);
                try validateValue(value);
                restored.values[index] = value;
                report.restored_count += 1;
            }
            self.* = restored;
            return report;
        }

        pub fn maximumEncodedSize() usize {
            return encoded_header_size + fields.len * (encoded_entry_header_size + maximum_entry_payload_bytes);
        }

        fn fieldIndex(id: u32) ?usize {
            inline for (fields, 0..) |field, index| if (field.id == id) return index;
            return null;
        }
    };
}

fn validateFields(comptime fields: []const Field) void {
    for (fields, 0..) |field, index| {
        if (field.id == 0) @compileError("editor state field IDs must be nonzero");
        validateValue(field.default) catch @compileError("invalid editor state default value");
        for (fields[0..index]) |previous| {
            if (previous.id == field.id) @compileError("editor state field IDs must be unique");
        }
    }
}

fn validateValue(value: Value) !void {
    switch (value) {
        .scalar => |number| if (!std.math.isFinite(number)) return error.InvalidEditorStateNumber,
        .point => |point| try validatePoint(point),
        .text => |text| {
            if (text.len > maximum_text_bytes)
                return error.EditorStateTextTooLong;
            if (!text.valid())
                return error.InvalidEditorStateTextEncoding;
        },
        .envelope => |envelope| {
            if (envelope.len > maximum_envelope_points) return error.EditorStateEnvelopeTooLarge;
            try validatePoints(envelope.points[0..envelope.len]);
        },
        else => {},
    }
}

fn validatePoint(point: Point) !void {
    if (point.id == 0) return error.InvalidEditorStatePoint;
    if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) return error.InvalidEditorStatePoint;
}

fn validatePoints(points: []const Point) !void {
    var previous_x: f64 = -1;
    for (points, 0..) |point, index| {
        try validatePoint(point);
        if (point.x < previous_x) return error.InvalidEditorStateEnvelopeOrder;
        previous_x = point.x;
        for (points[0..index]) |previous| {
            if (previous.id == point.id) return error.DuplicateEditorStatePoint;
        }
    }
}

fn valuePayloadSize(value: Value) usize {
    return switch (value) {
        .boolean => 1,
        .integer, .scalar => 8,
        .index, .point_id => 4,
        .point => 20,
        .text => |text| text.len,
        .envelope => |envelope| 1 + @as(usize, envelope.len) * 20,
    };
}

fn writeValue(value: Value, writer: anytype) !void {
    switch (value) {
        .boolean => |boolean| try writer.writeByte(@intFromBool(boolean)),
        .integer => |integer| try writer.writeInt(i64, integer, .little),
        .scalar => |scalar| try writer.writeInt(u64, @bitCast(scalar), .little),
        .index => |index| try writer.writeInt(u32, index, .little),
        .point_id => |id| try writer.writeInt(u32, id, .little),
        .point => |point| try writePoint(point, writer),
        .text => |text| try writer.writeAll(text.slice()),
        .envelope => |envelope| {
            try writer.writeByte(envelope.len);
            for (envelope.slice()) |point| try writePoint(point, writer);
        },
    }
}

fn writePoint(point: Point, writer: anytype) !void {
    try writer.writeInt(u32, point.id, .little);
    try writer.writeInt(u64, @bitCast(point.x), .little);
    try writer.writeInt(u64, @bitCast(point.y), .little);
}

fn readValue(kind: Kind, reader: anytype, payload_len: usize) !Value {
    return switch (kind) {
        .boolean => blk: {
            if (payload_len != 1) return error.InvalidEditorStatePayloadSize;
            const raw = try reader.takeByte();
            if (raw > 1) return error.InvalidEditorStateBoolean;
            break :blk .{ .boolean = raw == 1 };
        },
        .integer => blk: {
            if (payload_len != 8) return error.InvalidEditorStatePayloadSize;
            break :blk .{ .integer = try reader.takeInt(i64, .little) };
        },
        .scalar => blk: {
            if (payload_len != 8) return error.InvalidEditorStatePayloadSize;
            break :blk .{ .scalar = @bitCast(try reader.takeInt(u64, .little)) };
        },
        .index => blk: {
            if (payload_len != 4) return error.InvalidEditorStatePayloadSize;
            break :blk .{ .index = try reader.takeInt(u32, .little) };
        },
        .point_id => blk: {
            if (payload_len != 4) return error.InvalidEditorStatePayloadSize;
            break :blk .{ .point_id = try reader.takeInt(u32, .little) };
        },
        .point => blk: {
            if (payload_len != 20) return error.InvalidEditorStatePayloadSize;
            break :blk .{ .point = try readPoint(reader) };
        },
        .text => blk: {
            if (payload_len > maximum_text_bytes) return error.EditorStateTextTooLong;
            var text = Text{};
            try reader.readSliceAll(text.bytes[0..payload_len]);
            text.len = @intCast(payload_len);
            if (!text.valid()) return error.InvalidEditorStateTextEncoding;
            break :blk .{ .text = text };
        },
        .envelope => blk: {
            if (payload_len < 1) return error.InvalidEditorStatePayloadSize;
            var envelope = Envelope{};
            envelope.len = try reader.takeByte();
            if (envelope.len > maximum_envelope_points) return error.EditorStateEnvelopeTooLarge;
            if (payload_len != 1 + @as(usize, envelope.len) * 20) return error.InvalidEditorStatePayloadSize;
            for (envelope.points[0..envelope.len]) |*point| point.* = try readPoint(reader);
            break :blk .{ .envelope = envelope };
        },
    };
}

fn readPoint(reader: anytype) !Point {
    return .{
        .id = try reader.takeInt(u32, .little),
        .x = @bitCast(try reader.takeInt(u64, .little)),
        .y = @bitCast(try reader.takeInt(u64, .little)),
    };
}

const MigrationIndex = struct {
    entries: [maximum_migrations]Migration = undefined,
    len: usize = 0,
    current_version: u16,

    fn init(migrations: []const Migration, current_version: u16) !MigrationIndex {
        if (migrations.len > maximum_migrations)
            return error.EditorStateMigrationLimitExceeded;

        var result = MigrationIndex{ .current_version = current_version };
        result.len = migrations.len;
        @memcpy(result.entries[0..migrations.len], migrations);
        for (result.entries[0..result.len]) |migration| {
            if (migration.from_version == 0 or migration.from_version >= current_version)
                return error.InvalidEditorStateMigration;
            if (migration.old_id == 0 or migration.new_id == 0)
                return error.InvalidEditorStateMigration;
        }

        var index: usize = 1;
        while (index < result.len) : (index += 1) {
            const value = result.entries[index];
            var insertion = index;
            while (insertion != 0 and lessThan(value, result.entries[insertion - 1])) {
                result.entries[insertion] = result.entries[insertion - 1];
                insertion -= 1;
            }
            result.entries[insertion] = value;
        }
        index = 1;
        while (index < result.len) : (index += 1) {
            const migration = result.entries[index];
            const previous = result.entries[index - 1];
            if (previous.from_version == migration.from_version and previous.old_id == migration.old_id)
                return error.DuplicateEditorStateMigration;
        }
        return result;
    }

    fn migratedId(self: *const MigrationIndex, source_version: u16, stored_id: u32) u32 {
        var id = stored_id;
        var start: usize = 0;
        while (start < self.len) {
            const version = self.entries[start].from_version;
            var end = start + 1;
            while (end < self.len and self.entries[end].from_version == version) : (end += 1) {}
            if (version >= source_version and version < self.current_version) {
                for (self.entries[start..end]) |migration| {
                    if (migration.old_id == id) {
                        id = migration.new_id;
                        break;
                    }
                }
            }
            start = end;
        }
        return id;
    }

    fn lessThan(left: Migration, right: Migration) bool {
        if (left.from_version != right.from_version)
            return left.from_version < right.from_version;
        return left.old_id < right.old_id;
    }
};

test "fuzz failure-atomic bounded editor state restore" {
    try std.testing.fuzz({}, fuzzEditorStateRestore, .{
        .corpus = &.{fuzz_seed},
    });
}

fn fuzzEditorStateRestore(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    const State = Store(3, &.{
        .{ .id = 2, .default = .{ .text = comptime Text.init("default") catch unreachable } },
        .{ .id = 3, .default = .{ .boolean = false } },
    });
    const migrations = [_]Migration{
        .{ .from_version = 2, .old_id = 9, .new_id = 3 },
        .{ .from_version = 1, .old_id = 1, .new_id = 9 },
    };
    var storage: [State.maximumEncodedSize()]u8 = undefined;
    const length = smith.slice(&storage);
    var reader = std.Io.Reader.fixed(storage[0..length]);
    var state = State.init();
    try state.set(2, .{ .text = try Text.init("unchanged") });
    try state.set(3, .{ .boolean = true });
    if (state.read(&reader, &migrations)) |report| {
        if (report.decoded_count > maximum_fields or
            report.restored_count > report.decoded_count or
            report.ignored_count > report.decoded_count or
            !state.valid())
        {
            return error.InvalidEditorStateFuzzResult;
        }
    } else |_| {
        try std.testing.expectEqualStrings("unchanged", state.get(2).?.text.slice());
        try std.testing.expect(state.get(3).?.boolean);
    }
}

test "editor state round trips every supported value" {
    const default_text = comptime Text.init("all") catch unreachable;
    const default_envelope = comptime Envelope.init(&.{
        .{ .id = 1, .x = 0, .y = 0.25 },
        .{ .id = 2, .x = 1, .y = 0.75 },
    }) catch unreachable;
    const State = Store(1, &.{
        .{ .id = 1, .default = .{ .boolean = false } },
        .{ .id = 2, .default = .{ .integer = -2 } },
        .{ .id = 3, .default = .{ .scalar = 0.5 } },
        .{ .id = 4, .default = .{ .index = 0 } },
        .{ .id = 5, .default = .{ .point_id = 1 } },
        .{ .id = 6, .default = .{ .point = .{ .id = 1, .x = 0.25, .y = 0.75 } } },
        .{ .id = 7, .default = .{ .text = default_text } },
        .{ .id = 8, .default = .{ .envelope = default_envelope } },
    });
    var source = State.init();
    try source.set(1, .{ .boolean = true });
    try source.set(4, .{ .index = 3 });
    try source.set(7, .{ .text = try Text.init("bright") });

    var bytes: [State.maximumEncodedSize()]u8 = undefined;
    var output = std.Io.Writer.fixed(&bytes);
    try source.write(&output);
    var input = std.Io.Reader.fixed(output.buffered());
    var restored = State.init();
    const report = try restored.read(&input, &.{});
    try std.testing.expectEqual(@as(usize, 8), report.restored_count);
    try std.testing.expectEqual(true, restored.get(1).?.boolean);
    try std.testing.expectEqual(@as(u32, 3), restored.get(4).?.index);
    try std.testing.expectEqualStrings("bright", restored.get(7).?.text.slice());
    try std.testing.expectEqual(@as(usize, 2), restored.get(8).?.envelope.slice().len);
}

test "editor state decode is transactional and ignores unknown fields" {
    const State = Store(1, &.{.{ .id = 1, .default = .{ .boolean = false } }});
    var bytes: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try writer.writeAll(magic);
    try writer.writeInt(u16, wire_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u16, 0, .little);
    try writer.writeInt(u32, 99, .little);
    try writer.writeByte(@intFromEnum(Kind.index));
    try writer.writeInt(u16, 4, .little);
    try writer.writeInt(u32, 7, .little);
    try writer.writeInt(u32, 1, .little);
    try writer.writeByte(@intFromEnum(Kind.boolean));
    try writer.writeInt(u16, 1, .little);
    try writer.writeByte(2);

    var state = State.init();
    try state.set(1, .{ .boolean = true });
    var reader = std.Io.Reader.fixed(writer.buffered());
    try std.testing.expectError(error.InvalidEditorStateBoolean, state.read(&reader, &.{}));
    try std.testing.expect(state.get(1).?.boolean);
}

test "editor state reports and skips a valid unknown field" {
    const State = Store(1, &.{.{ .id = 1, .default = .{ .boolean = false } }});
    var bytes: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try writer.writeAll(magic);
    try writer.writeInt(u16, wire_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u16, 0, .little);
    try writer.writeInt(u32, 99, .little);
    try writer.writeByte(255);
    try writer.writeInt(u16, 3, .little);
    try writer.writeAll("new");
    try writer.writeInt(u32, 1, .little);
    try writer.writeByte(@intFromEnum(Kind.boolean));
    try writer.writeInt(u16, 1, .little);
    try writer.writeByte(1);

    var reader = std.Io.Reader.fixed(writer.buffered());
    var state = State.init();
    const report = try state.read(&reader, &.{});
    try std.testing.expect(state.get(1).?.boolean);
    try std.testing.expectEqual(@as(usize, 1), report.restored_count);
    try std.testing.expectEqual(@as(usize, 1), report.ignored_count);
}

test "editor state migrates field IDs between schema versions" {
    const Old = Store(1, &.{.{ .id = 4, .default = .{ .index = 0 } }});
    const New = Store(2, &.{.{ .id = 9, .default = .{ .index = 1 } }});
    var old = Old.init();
    try old.set(4, .{ .index = 7 });
    var bytes: [Old.maximumEncodedSize()]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try old.write(&writer);
    var reader = std.Io.Reader.fixed(writer.buffered());
    var new = New.init();
    const report = try new.read(&reader, &.{.{ .from_version = 1, .old_id = 4, .new_id = 9 }});
    try std.testing.expectEqual(@as(u32, 7), new.get(9).?.index);
    try std.testing.expectEqual(@as(u16, 1), report.source_schema_version);
}

test "editor state migration work is bounded at the exact limit" {
    const Old = Store(1, &.{.{ .id = 1, .default = .{ .index = 0 } }});
    const New = Store(maximum_migrations + 1, &.{.{
        .id = maximum_migrations + 1,
        .default = .{ .index = 0 },
    }});
    var migrations: [maximum_migrations]Migration = undefined;
    for (&migrations, 1..) |*migration, version| {
        migration.* = .{
            .from_version = @intCast(version),
            .old_id = @intCast(version),
            .new_id = @intCast(version + 1),
        };
    }

    var old = Old.init();
    try old.set(1, .{ .index = 19 });
    var bytes: [Old.maximumEncodedSize()]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try old.write(&writer);
    var reader = std.Io.Reader.fixed(writer.buffered());
    var new = New.init();
    const report = try new.read(&reader, &migrations);
    try std.testing.expectEqual(@as(usize, 1), report.restored_count);
    try std.testing.expectEqual(@as(u32, 19), new.get(maximum_migrations + 1).?.index);

    var too_many: [maximum_migrations + 1]Migration = undefined;
    @memcpy(too_many[0..maximum_migrations], &migrations);
    too_many[maximum_migrations] = .{
        .from_version = 1,
        .old_id = maximum_migrations + 2,
        .new_id = maximum_migrations + 3,
    };
    try new.set(maximum_migrations + 1, .{ .index = 23 });
    var rejected_reader = std.Io.Reader.fixed(writer.buffered());
    try std.testing.expectError(
        error.EditorStateMigrationLimitExceeded,
        new.read(&rejected_reader, &too_many),
    );
    try std.testing.expectEqual(@as(usize, 0), rejected_reader.seek);
    try std.testing.expectEqual(@as(u32, 23), new.get(maximum_migrations + 1).?.index);
}

test "editor state applies at most one migration per schema version" {
    const index = try MigrationIndex.init(&.{
        .{ .from_version = 1, .old_id = 2, .new_id = 3 },
        .{ .from_version = 1, .old_id = 1, .new_id = 2 },
        .{ .from_version = 2, .old_id = 2, .new_id = 4 },
    }, 3);
    try std.testing.expectEqual(@as(u32, 4), index.migratedId(1, 1));
    try std.testing.expectError(
        error.DuplicateEditorStateMigration,
        MigrationIndex.init(&.{
            .{ .from_version = 1, .old_id = 1, .new_id = 2 },
            .{ .from_version = 1, .old_id = 1, .new_id = 3 },
        }, 3),
    );
}

test "editor state rejects every truncated prefix transactionally" {
    const State = Store(1, &.{
        .{ .id = 1, .default = .{ .boolean = false } },
        .{ .id = 2, .default = .{ .scalar = 0.25 } },
        .{ .id = 3, .default = .{ .text = comptime Text.init("empty") catch unreachable } },
    });
    var source = State.init();
    try source.set(1, .{ .boolean = true });
    try source.set(2, .{ .scalar = 0.75 });
    try source.set(3, .{ .text = try Text.init("restored") });
    var bytes: [State.maximumEncodedSize()]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try source.write(&writer);
    const encoded = writer.buffered();

    for (0..encoded.len) |prefix_length| {
        var destination = State.init();
        try destination.set(1, .{ .boolean = true });
        try destination.set(2, .{ .scalar = 0.5 });
        try destination.set(3, .{ .text = try Text.init("unchanged") });
        var reader = std.Io.Reader.fixed(encoded[0..prefix_length]);
        if (destination.read(&reader, &.{})) |_| {
            std.debug.print("editor state truncation unexpectedly decoded prefix={} full={}\n", .{ prefix_length, encoded.len });
            return error.TruncatedEditorStateAccepted;
        } else |_| {}
        try std.testing.expect(destination.get(1).?.boolean);
        try std.testing.expectEqual(@as(f64, 0.5), destination.get(2).?.scalar);
        try std.testing.expectEqualStrings("unchanged", destination.get(3).?.text.slice());
    }
}

test "editor state generated mutations remain bounded and transactional" {
    const seed = 0xe017_57a7_2026_0720;
    const State = Store(1, &.{
        .{ .id = 1, .default = .{ .boolean = false } },
        .{ .id = 2, .default = .{ .integer = -4 } },
        .{ .id = 3, .default = .{ .scalar = 0.25 } },
        .{ .id = 4, .default = .{ .text = comptime Text.init("default") catch unreachable } },
    });
    var source = State.init();
    try source.set(1, .{ .boolean = true });
    try source.set(2, .{ .integer = 42 });
    try source.set(3, .{ .scalar = 0.75 });
    try source.set(4, .{ .text = try Text.init("generated") });
    var encoded_storage: [State.maximumEncodedSize()]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded_storage);
    try source.write(&writer);
    const encoded = writer.buffered();
    var random_state = std.Random.DefaultPrng.init(seed);
    const random = random_state.random();

    for (0..512) |case_index| {
        var mutated: [State.maximumEncodedSize()]u8 = undefined;
        @memcpy(mutated[0..encoded.len], encoded);
        const mutation_count = 1 + random.uintLessThan(usize, 4);
        for (0..mutation_count) |_| {
            const index = random.uintLessThan(usize, encoded.len);
            mutated[index] ^= @as(u8, 1) << @as(u3, @intCast(random.uintLessThan(u8, 8)));
        }
        var destination = State.init();
        try destination.set(2, .{ .integer = 99 });
        var reader = std.Io.Reader.fixed(mutated[0..encoded.len]);
        if (destination.read(&reader, &.{})) |_| {
            const scalar = destination.get(3).?.scalar;
            const text = destination.get(4).?.text;
            if (!std.math.isFinite(scalar) or !text.valid()) {
                std.debug.print("editor state seed={x} case={} decoded an invalid value\n", .{ seed, case_index });
                return error.InvalidGeneratedEditorState;
            }
        } else |_| {
            try std.testing.expectEqual(@as(i64, 99), destination.get(2).?.integer);
        }
    }
}

test "editor state rejects malformed direct bounded values before writing" {
    const State = Store(1, &.{
        .{ .id = 1, .default = .{ .text = comptime Text.init("default") catch unreachable } },
        .{ .id = 2, .default = .{ .envelope = comptime Envelope.init(&.{}) catch unreachable } },
        .{ .id = 3, .default = .{ .scalar = 0.5 } },
    });
    var state = State.init();
    try std.testing.expect(state.valid());
    state.values[0].text.len = maximum_text_bytes + 1;
    try std.testing.expect(!state.valid());
    try std.testing.expectEqual(@as(?Value, null), state.get(1));
    try std.testing.expectEqual(State.maximumEncodedSize() + 1, state.encodedSize());
    try std.testing.expectEqual(@as(usize, 0), state.values[0].text.slice().len);
    var bytes: [State.maximumEncodedSize()]u8 = undefined;
    var text_writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(error.EditorStateTextTooLong, state.write(&text_writer));
    try std.testing.expectEqual(@as(usize, 0), text_writer.end);

    state.values[0].text = try Text.init("valid");
    state.values[0].text.bytes[0] = 0xff;
    try std.testing.expect(!state.valid());
    try std.testing.expectEqual(@as(?Value, null), state.get(1));
    try std.testing.expectEqual(
        @as(usize, 0),
        state.values[0].text.slice().len,
    );
    var encoding_writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.InvalidEditorStateTextEncoding,
        state.write(&encoding_writer),
    );
    try std.testing.expectEqual(@as(usize, 0), encoding_writer.end);

    state.values[0].text = try Text.init("valid");
    state.values[1].envelope.len = maximum_envelope_points + 1;
    try std.testing.expect(!state.valid());
    try std.testing.expectEqual(@as(?Value, null), state.get(2));
    try std.testing.expectEqual(@as(usize, 0), state.values[1].envelope.slice().len);
    var envelope_writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(error.EditorStateEnvelopeTooLarge, state.write(&envelope_writer));
    try std.testing.expectEqual(@as(usize, 0), envelope_writer.end);

    state.values[1].envelope = try Envelope.init(&.{.{
        .id = 1,
        .x = 0.5,
        .y = 0.5,
    }});
    state.values[1].envelope.points[0].id = 0;
    try std.testing.expect(!state.values[1].envelope.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        state.values[1].envelope.slice().len,
    );
    try std.testing.expect(!state.valid());

    state.values[1].envelope = try Envelope.init(&.{});
    state.values[2].scalar = std.math.nan(f64);
    try std.testing.expect(!state.valid());
    try std.testing.expectEqual(@as(?Value, null), state.get(3));
    try state.reset(3);
    try std.testing.expect(state.valid());
}

test "editor state text requires bounded UTF-8" {
    try std.testing.expectError(
        error.InvalidEditorStateTextEncoding,
        Text.init(&.{ 0xc3, 0x28 }),
    );
    const text = try Text.init("Hall \xe2\x98\x83");
    try std.testing.expect(text.valid());
    try std.testing.expectEqualStrings("Hall \xe2\x98\x83", text.slice());
}

test "editor state rejects malformed encoded UTF-8 transactionally" {
    const State = Store(1, &.{.{
        .id = 1,
        .default = .{ .text = comptime Text.init("default") catch unreachable },
    }});
    var source = State.init();
    try source.set(1, .{ .text = try Text.init("valid") });
    var bytes: [State.maximumEncodedSize()]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try source.write(&writer);
    const payload_offset = encoded_header_size + encoded_entry_header_size;
    bytes[payload_offset] = 0xff;

    var destination = State.init();
    try destination.set(1, .{ .text = try Text.init("unchanged") });
    var reader = std.Io.Reader.fixed(bytes[0..writer.end]);
    try std.testing.expectError(
        error.InvalidEditorStateTextEncoding,
        destination.read(&reader, &.{}),
    );
    try std.testing.expectEqualStrings(
        "unchanged",
        destination.get(1).?.text.slice(),
    );
}
