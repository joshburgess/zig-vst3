const std = @import("std");
const midi_ci = @import("midi_ci.zig");
const property_json = @import("midi_ci_property_json.zig");

pub const Key = struct {
    remote: midi_ci.Muid,
    resource: []const u8,
    res_id: ?[]const u8 = null,
};

pub const Entry = struct {
    key: Key,
    data: []const u8,
    generation: u64,
};

const snapshot_magic = [4]u8{ 'M', 'C', 'P', 'C' };
const snapshot_version: u8 = 1;
const snapshot_header_length = 15;
const snapshot_entry_header_length = 19;

pub fn RemoteCache(
    comptime capacity: usize,
    comptime resource_capacity: usize,
    comptime res_id_capacity: usize,
    comptime data_capacity: usize,
) type {
    if (capacity == 0)
        @compileError("MIDI-CI property cache capacity must be nonzero");
    if (resource_capacity == 0 or resource_capacity > 36)
        @compileError("MIDI-CI property cache resource capacity must be 1 through 36");
    if (res_id_capacity == 0 or res_id_capacity > 36)
        @compileError("MIDI-CI property cache resource ID capacity must be 1 through 36");
    if (data_capacity == 0)
        @compileError("MIDI-CI property cache data capacity must be nonzero");
    if (capacity > std.math.maxInt(u16))
        @compileError("MIDI-CI property cache snapshot capacity exceeds u16");
    if (data_capacity > std.math.maxInt(u32))
        @compileError("MIDI-CI property cache snapshot data capacity exceeds u32");

    return struct {
        const Self = @This();

        const Slot = struct {
            active: bool = false,
            remote: midi_ci.Muid = .{ .value = 0 },
            resource_storage: [resource_capacity]u8 = undefined,
            resource_count: usize = 0,
            has_res_id: bool = false,
            res_id_storage: [res_id_capacity]u8 = undefined,
            res_id_count: usize = 0,
            data_storage: [data_capacity]u8 = undefined,
            data_count: usize = 0,
            generation: u64 = 0,

            fn value(self: *const Slot) Entry {
                return .{
                    .key = .{
                        .remote = self.remote,
                        .resource = self.resource_storage[0..self.resource_count],
                        .res_id = if (self.has_res_id)
                            self.res_id_storage[0..self.res_id_count]
                        else
                            null,
                    },
                    .data = self.data_storage[0..self.data_count],
                    .generation = self.generation,
                };
            }
        };

        slots: [capacity]Slot = [_]Slot{.{}} ** capacity,
        active_count: usize = 0,
        next_generation: u64 = 1,

        pub fn put(
            self: *Self,
            key: Key,
            data: []const u8,
        ) !usize {
            try validateKey(key);
            const res_id_length = if (key.res_id) |value| value.len else 0;
            if (key.resource.len > resource_capacity or
                res_id_length > res_id_capacity or
                data.len > data_capacity)
                return error.MidiCiPropertyCacheValueTooLarge;

            const index = self.findIndex(key) orelse
                self.emptyIndex() orelse
                return error.MidiCiPropertyCacheCapacityExceeded;
            var replacement = Slot{
                .active = true,
                .remote = key.remote,
                .resource_count = key.resource.len,
                .has_res_id = key.res_id != null,
                .res_id_count = res_id_length,
                .data_count = data.len,
                .generation = self.takeGeneration(),
            };
            @memcpy(
                replacement.resource_storage[0..key.resource.len],
                key.resource,
            );
            if (key.res_id) |value|
                @memcpy(replacement.res_id_storage[0..value.len], value);
            @memcpy(replacement.data_storage[0..data.len], data);
            if (!self.slots[index].active) self.active_count += 1;
            self.slots[index] = replacement;
            return index;
        }

        pub fn get(self: *const Self, key: Key) !Entry {
            try validateKey(key);
            const index = self.findIndex(key) orelse
                return error.MidiCiPropertyCacheEntryNotFound;
            return self.slots[index].value();
        }

        pub fn remove(self: *Self, key: Key) !void {
            try validateKey(key);
            const index = self.findIndex(key) orelse
                return error.MidiCiPropertyCacheEntryNotFound;
            self.slots[index] = .{};
            self.active_count -= 1;
        }

        pub fn releaseRemote(self: *Self, remote: midi_ci.Muid) usize {
            if (!remote.validSource()) return 0;
            var released: usize = 0;
            for (&self.slots) |*slot| {
                if (slot.active and slot.remote.value == remote.value) {
                    slot.* = .{};
                    released += 1;
                }
            }
            self.active_count -= released;
            return released;
        }

        pub fn clear(self: *Self) void {
            self.slots = [_]Slot{.{}} ** capacity;
            self.active_count = 0;
        }

        pub fn count(self: *const Self) usize {
            return self.active_count;
        }

        pub fn snapshotSize(self: *const Self) !usize {
            if (self.active_count > capacity or self.next_generation == 0)
                return error.InvalidMidiCiPropertyCacheState;
            var size: usize = snapshot_header_length;
            var counted: usize = 0;
            for (&self.slots) |*slot| {
                if (!slot.active) continue;
                try validateSlot(slot);
                counted += 1;
                size = try addSize(size, snapshot_entry_header_length);
                size = try addSize(size, slot.resource_count);
                size = try addSize(size, slot.res_id_count);
                size = try addSize(size, slot.data_count);
            }
            if (counted != self.active_count)
                return error.InvalidMidiCiPropertyCacheState;
            return size;
        }

        pub fn writeSnapshot(
            self: *const Self,
            destination: []u8,
        ) ![]const u8 {
            const length = try self.snapshotSize();
            if (destination.len < length)
                return error.MidiCiPropertyCacheSnapshotBufferTooSmall;
            @memcpy(destination[0..4], &snapshot_magic);
            destination[4] = snapshot_version;
            std.mem.writeInt(
                u16,
                destination[5..7],
                @intCast(self.active_count),
                .little,
            );
            std.mem.writeInt(
                u64,
                destination[7..15],
                self.next_generation,
                .little,
            );
            var offset: usize = snapshot_header_length;
            for (&self.slots) |*slot| {
                if (!slot.active) continue;
                std.mem.writeInt(
                    u32,
                    destination[offset..][0..4],
                    slot.remote.value,
                    .little,
                );
                destination[offset + 4] = @intFromBool(slot.has_res_id);
                destination[offset + 5] = @intCast(slot.resource_count);
                destination[offset + 6] = @intCast(slot.res_id_count);
                std.mem.writeInt(
                    u32,
                    destination[offset + 7 ..][0..4],
                    @intCast(slot.data_count),
                    .little,
                );
                std.mem.writeInt(
                    u64,
                    destination[offset + 11 ..][0..8],
                    slot.generation,
                    .little,
                );
                offset += snapshot_entry_header_length;
                @memcpy(
                    destination[offset..][0..slot.resource_count],
                    slot.resource_storage[0..slot.resource_count],
                );
                offset += slot.resource_count;
                @memcpy(
                    destination[offset..][0..slot.res_id_count],
                    slot.res_id_storage[0..slot.res_id_count],
                );
                offset += slot.res_id_count;
                @memcpy(
                    destination[offset..][0..slot.data_count],
                    slot.data_storage[0..slot.data_count],
                );
                offset += slot.data_count;
            }
            return destination[0..offset];
        }

        pub fn restoreSnapshot(self: *Self, source: []const u8) !void {
            if (source.len < snapshot_header_length or
                !std.mem.eql(u8, source[0..4], &snapshot_magic) or
                source[4] != snapshot_version)
                return error.InvalidMidiCiPropertyCacheSnapshot;
            const entry_count = std.mem.readInt(u16, source[5..7], .little);
            if (entry_count > capacity)
                return error.MidiCiPropertyCacheCapacityExceeded;
            const next_generation =
                std.mem.readInt(u64, source[7..15], .little);
            if (next_generation == 0)
                return error.InvalidMidiCiPropertyCacheSnapshot;

            var restored = Self{ .next_generation = next_generation };
            var offset: usize = snapshot_header_length;
            for (0..entry_count) |_| {
                if (source.len - offset < snapshot_entry_header_length)
                    return error.InvalidMidiCiPropertyCacheSnapshot;
                const remote_value =
                    std.mem.readInt(u32, source[offset..][0..4], .little);
                const flags = source[offset + 4];
                const resource_length: usize = source[offset + 5];
                const res_id_length: usize = source[offset + 6];
                const data_length: usize = std.mem.readInt(
                    u32,
                    source[offset + 7 ..][0..4],
                    .little,
                );
                const generation = std.mem.readInt(
                    u64,
                    source[offset + 11 ..][0..8],
                    .little,
                );
                offset += snapshot_entry_header_length;
                if (flags & ~@as(u8, 1) != 0 or
                    resource_length > resource_capacity or
                    res_id_length > res_id_capacity or
                    data_length > data_capacity or
                    generation == 0)
                    return error.InvalidMidiCiPropertyCacheSnapshot;
                const payload_length = try addSize(
                    try addSize(resource_length, res_id_length),
                    data_length,
                );
                if (payload_length > source.len - offset)
                    return error.InvalidMidiCiPropertyCacheSnapshot;
                const resource = source[offset..][0..resource_length];
                offset += resource_length;
                const res_id_bytes = source[offset..][0..res_id_length];
                offset += res_id_length;
                const data = source[offset..][0..data_length];
                offset += data_length;
                const has_res_id = flags & 1 != 0;
                if (has_res_id != (res_id_length != 0))
                    return error.InvalidMidiCiPropertyCacheSnapshot;
                try restored.putRestored(
                    .{
                        .remote = try midi_ci.Muid.init(remote_value),
                        .resource = resource,
                        .res_id = if (has_res_id) res_id_bytes else null,
                    },
                    data,
                    generation,
                );
            }
            if (offset != source.len)
                return error.InvalidMidiCiPropertyCacheSnapshot;
            self.* = restored;
        }

        fn findIndex(self: *const Self, key: Key) ?usize {
            for (self.slots, 0..) |slot, index| {
                if (!slot.active or slot.remote.value != key.remote.value or
                    !std.mem.eql(
                        u8,
                        slot.resource_storage[0..slot.resource_count],
                        key.resource,
                    ) or slot.has_res_id != (key.res_id != null))
                    continue;
                if (key.res_id) |value| {
                    if (!std.mem.eql(
                        u8,
                        slot.res_id_storage[0..slot.res_id_count],
                        value,
                    )) continue;
                }
                return index;
            }
            return null;
        }

        fn emptyIndex(self: *const Self) ?usize {
            for (self.slots, 0..) |slot, index| {
                if (!slot.active) return index;
            }
            return null;
        }

        fn takeGeneration(self: *Self) u64 {
            const generation = self.next_generation;
            self.next_generation +%= 1;
            if (self.next_generation == 0) self.next_generation = 1;
            return generation;
        }

        fn putRestored(
            self: *Self,
            key: Key,
            data: []const u8,
            generation: u64,
        ) !void {
            try validateKey(key);
            if (self.findIndex(key) != null)
                return error.InvalidMidiCiPropertyCacheSnapshot;
            const index = self.emptyIndex() orelse
                return error.MidiCiPropertyCacheCapacityExceeded;
            const res_id_length = if (key.res_id) |value| value.len else 0;
            var slot = Slot{
                .active = true,
                .remote = key.remote,
                .resource_count = key.resource.len,
                .has_res_id = key.res_id != null,
                .res_id_count = res_id_length,
                .data_count = data.len,
                .generation = generation,
            };
            @memcpy(slot.resource_storage[0..key.resource.len], key.resource);
            if (key.res_id) |value|
                @memcpy(slot.res_id_storage[0..value.len], value);
            @memcpy(slot.data_storage[0..data.len], data);
            self.slots[index] = slot;
            self.active_count += 1;
        }

        fn validateSlot(slot: *const Slot) !void {
            if (!slot.active or
                slot.resource_count == 0 or
                slot.resource_count > resource_capacity or
                slot.res_id_count > res_id_capacity or
                slot.data_count > data_capacity or
                slot.has_res_id != (slot.res_id_count != 0) or
                slot.generation == 0)
                return error.InvalidMidiCiPropertyCacheState;
            try validateKey(slot.value().key);
        }

        fn validateKey(key: Key) !void {
            if (!key.remote.validSource()) return error.InvalidMidiCiMuid;
            if (!(property_json.RequestHeader{
                .resource = key.resource,
                .res_id = key.res_id,
            }).valid()) return error.InvalidMidiCiPropertyCacheKey;
        }
    };
}

fn addSize(left: usize, right: usize) !usize {
    return std.math.add(usize, left, right) catch
        return error.MidiCiPropertyCacheSnapshotTooLarge;
}

test "MIDI-CI property cache replaces values transactionally" {
    const Cache = RemoteCache(2, 36, 36, 8);
    const remote = try midi_ci.Muid.init(1);
    const key = Key{
        .remote = remote,
        .resource = "State",
        .res_id = "main",
    };
    var cache = Cache{};
    const index = try cache.put(key, "one");
    const first = try cache.get(key);
    try std.testing.expectEqualStrings("one", first.data);

    try std.testing.expectError(
        error.MidiCiPropertyCacheValueTooLarge,
        cache.put(key, "too-large"),
    );
    try std.testing.expectEqualStrings("one", (try cache.get(key)).data);
    try std.testing.expectEqual(index, try cache.put(key, "two"));
    const second = try cache.get(key);
    try std.testing.expectEqualStrings("two", second.data);
    try std.testing.expect(second.generation > first.generation);
    try std.testing.expectEqual(@as(usize, 1), cache.count());
}

test "MIDI-CI property cache bounds entries and releases remotes" {
    const Cache = RemoteCache(2, 12, 12, 8);
    const first = try midi_ci.Muid.init(1);
    const second = try midi_ci.Muid.init(2);
    var cache = Cache{};
    _ = try cache.put(.{ .remote = first, .resource = "State" }, "a");
    _ = try cache.put(.{ .remote = second, .resource = "State" }, "b");
    try std.testing.expectError(
        error.MidiCiPropertyCacheCapacityExceeded,
        cache.put(.{ .remote = first, .resource = "DeviceInfo" }, "c"),
    );
    try std.testing.expectEqual(@as(usize, 1), cache.releaseRemote(first));
    try std.testing.expectEqual(@as(usize, 1), cache.count());
    try std.testing.expectError(
        error.MidiCiPropertyCacheEntryNotFound,
        cache.get(.{ .remote = first, .resource = "State" }),
    );
    try std.testing.expectEqualStrings(
        "b",
        (try cache.get(.{ .remote = second, .resource = "State" })).data,
    );
}

test "MIDI-CI property cache snapshots round trip generations" {
    const Cache = RemoteCache(3, 12, 12, 16);
    const first = try midi_ci.Muid.init(1);
    const second = try midi_ci.Muid.init(2);
    var source = Cache{};
    _ = try source.put(
        .{ .remote = first, .resource = "State", .res_id = "main" },
        "alpha",
    );
    _ = try source.put(
        .{ .remote = second, .resource = "DeviceInfo" },
        "beta",
    );
    const first_generation = (try source.get(.{
        .remote = first,
        .resource = "State",
        .res_id = "main",
    })).generation;

    var storage: [128]u8 = undefined;
    const snapshot = try source.writeSnapshot(&storage);
    try std.testing.expectEqual(try source.snapshotSize(), snapshot.len);
    var restored = Cache{};
    try restored.restoreSnapshot(snapshot);
    try std.testing.expectEqual(@as(usize, 2), restored.count());
    const restored_first = try restored.get(.{
        .remote = first,
        .resource = "State",
        .res_id = "main",
    });
    try std.testing.expectEqualStrings("alpha", restored_first.data);
    try std.testing.expectEqual(first_generation, restored_first.generation);
    try std.testing.expectEqualStrings(
        "beta",
        (try restored.get(.{
            .remote = second,
            .resource = "DeviceInfo",
        })).data,
    );
    _ = try restored.put(
        .{ .remote = first, .resource = "State", .res_id = "main" },
        "new",
    );
    try std.testing.expect((try restored.get(.{
        .remote = first,
        .resource = "State",
        .res_id = "main",
    })).generation > first_generation);
}

test "MIDI-CI property cache snapshot restore is transactional" {
    const Cache = RemoteCache(2, 12, 12, 8);
    const remote = try midi_ci.Muid.init(1);
    var cache = Cache{};
    _ = try cache.put(.{ .remote = remote, .resource = "State" }, "old");
    _ = try cache.put(.{ .remote = remote, .resource = "Other" }, "new");
    var storage: [128]u8 = undefined;
    const valid = try cache.writeSnapshot(&storage);

    var malformed = [_]u8{0} ** 128;
    @memcpy(malformed[0..valid.len], valid);
    malformed[4] = 2;
    try std.testing.expectError(
        error.InvalidMidiCiPropertyCacheSnapshot,
        cache.restoreSnapshot(malformed[0..valid.len]),
    );
    try std.testing.expectEqualStrings(
        "old",
        (try cache.get(.{ .remote = remote, .resource = "State" })).data,
    );

    for (0..valid.len) |length| {
        try std.testing.expectError(
            error.InvalidMidiCiPropertyCacheSnapshot,
            cache.restoreSnapshot(valid[0..length]),
        );
    }
    try std.testing.expectEqual(@as(usize, 2), cache.count());

    @memcpy(malformed[0..valid.len], valid);
    const second_resource_offset =
        snapshot_header_length +
        snapshot_entry_header_length + "State".len + "old".len +
        snapshot_entry_header_length;
    @memcpy(
        malformed[second_resource_offset..][0.."State".len],
        "State",
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyCacheSnapshot,
        cache.restoreSnapshot(malformed[0..valid.len]),
    );
    try std.testing.expectEqualStrings(
        "new",
        (try cache.get(.{ .remote = remote, .resource = "Other" })).data,
    );
    try std.testing.expectError(
        error.MidiCiPropertyCacheSnapshotBufferTooSmall,
        cache.writeSnapshot(storage[0 .. valid.len - 1]),
    );
}
