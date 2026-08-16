const std = @import("std");

const slot_count = 3;
const writer_locked = std.math.maxInt(u32);

pub fn Publisher(comptime State: type) type {
    if (@sizeOf(State) == 0)
        @compileError("realtime snapshots require nonempty state");

    return struct {
        const Self = @This();

        const Slot = struct {
            value: State,
            generation: u64,
            readers: std.atomic.Value(u32),
        };

        pub const Snapshot = struct {
            value: State,
            generation: u64,
        };

        slots: [slot_count]Slot,
        active_slot: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        next_generation: u64 = 1,

        pub fn init(initial: State) Self {
            var slots: [slot_count]Slot = undefined;
            for (&slots) |*slot| {
                slot.* = .{
                    .value = initial,
                    .generation = 0,
                    .readers = std.atomic.Value(u32).init(0),
                };
            }
            return .{
                .slots = slots,
            };
        }

        /// Publishes from the single non-realtime writer.
        pub fn publish(self: *Self, value: State) !u64 {
            const active = self.active_slot.load(.acquire);
            if (active >= slot_count)
                return error.InvalidRealtimeSnapshotPublisher;

            var selected: ?u8 = null;
            for (0..slot_count) |index| {
                const candidate: u8 = @intCast(index);
                if (candidate == active) continue;
                if (self.slots[candidate].readers.cmpxchgStrong(
                    0,
                    writer_locked,
                    .acq_rel,
                    .acquire,
                ) == null) {
                    selected = candidate;
                    break;
                }
            }
            const slot_index = selected orelse
                return error.RealtimeSnapshotUnavailable;
            const slot = &self.slots[slot_index];
            const generation = self.nextUniqueGeneration() catch |err| {
                slot.readers.store(0, .release);
                return err;
            };

            slot.value = value;
            slot.generation = generation;
            slot.readers.store(0, .release);
            self.active_slot.store(slot_index, .release);
            return generation;
        }

        /// Attempts one bounded read from the single realtime reader.
        pub fn tryRead(self: *Self) ?Snapshot {
            const selected = self.active_slot.load(.acquire);
            if (selected >= slot_count) return null;
            const slot = &self.slots[selected];
            const readers = slot.readers.load(.acquire);
            if (readers >= writer_locked - 1) return null;
            if (slot.readers.cmpxchgStrong(
                readers,
                readers + 1,
                .acq_rel,
                .acquire,
            ) != null) return null;
            if (self.active_slot.load(.acquire) != selected) {
                _ = slot.readers.fetchSub(1, .release);
                return null;
            }

            const generation = slot.generation;
            const value = slot.value;
            _ = slot.readers.fetchSub(1, .release);
            return .{ .value = value, .generation = generation };
        }

        pub fn readOr(
            self: *Self,
            fallback: Snapshot,
        ) Snapshot {
            return self.tryRead() orelse fallback;
        }

        fn nextUniqueGeneration(self: *Self) !u64 {
            var candidate = self.next_generation;
            for (0..slot_count + 1) |_| {
                if (candidate == 0) candidate = 1;
                var collision = false;
                for (self.slots) |slot| {
                    if (slot.generation == candidate) {
                        collision = true;
                        break;
                    }
                }
                if (!collision) {
                    self.next_generation = candidate +% 1;
                    if (self.next_generation == 0)
                        self.next_generation = 1;
                    return candidate;
                }
                candidate +%= 1;
            }
            return error.InvalidRealtimeSnapshotPublisher;
        }
    };
}

pub fn ReferencePublisher(
    comptime State: type,
    comptime capacity: usize,
) type {
    if (@sizeOf(State) == 0)
        @compileError("realtime references require nonempty state");
    if (capacity < 3 or capacity > 64)
        @compileError("realtime reference slot count must be between 3 and 64");

    return struct {
        const Self = @This();

        const Slot = struct {
            value: State,
            generation: u64,
            references: std.atomic.Value(u32),
        };

        pub const Handle = struct {
            publisher: ?*Self,
            slot: u8,
            retained_generation: u64,

            pub fn value(self: *const Handle) ?*const State {
                const owner = self.publisher orelse return null;
                if (self.slot >= capacity) return null;
                const slot = &owner.slots[self.slot];
                const current = slot.references.load(.acquire);
                if (current == 0 or current == writer_locked or
                    slot.generation != self.retained_generation)
                {
                    return null;
                }
                return &slot.value;
            }

            pub fn generation(self: *const Handle) ?u64 {
                if (self.value() == null) return null;
                return self.retained_generation;
            }

            /// Creates another independently released reference.
            pub fn retain(self: *const Handle) ?Handle {
                const owner = self.publisher orelse return null;
                if (self.slot >= capacity) return null;
                const references =
                    &owner.slots[self.slot].references;
                const current = references.load(.acquire);
                if (current == 0 or current >= writer_locked - 1)
                    return null;
                if (owner.slots[self.slot].generation !=
                    self.retained_generation)
                {
                    return null;
                }
                if (references.cmpxchgStrong(
                    current,
                    current + 1,
                    .acq_rel,
                    .acquire,
                ) != null) return null;
                return .{
                    .publisher = owner,
                    .slot = self.slot,
                    .retained_generation = self.retained_generation,
                };
            }

            /// Releases this handle once. Later calls are harmless.
            pub fn release(self: *Handle) void {
                const owner = self.publisher orelse return;
                self.publisher = null;
                if (self.slot >= capacity) return;
                const slot = &owner.slots[self.slot];
                var current = slot.references.load(.acquire);
                while (true) {
                    if (current == 0 or current == writer_locked or
                        slot.generation != self.retained_generation)
                    {
                        return;
                    }
                    current = slot.references.cmpxchgWeak(
                        current,
                        current - 1,
                        .release,
                        .acquire,
                    ) orelse return;
                }
            }
        };

        pub const Writer = struct {
            publisher: ?*Self,
            slot: u8,

            pub fn value(self: *Writer) ?*State {
                const owner = self.publisher orelse return null;
                if (self.slot >= capacity) return null;
                if (owner.slots[self.slot].references.load(.acquire) !=
                    writer_locked)
                {
                    return null;
                }
                return &owner.slots[self.slot].value;
            }

            pub fn commit(self: *Writer) !u64 {
                const owner = self.publisher orelse
                    return error.InvalidRealtimeReferenceWriter;
                if (self.slot >= capacity)
                    return error.InvalidRealtimeReferenceWriter;
                const slot = &owner.slots[self.slot];
                if (slot.references.load(.acquire) != writer_locked)
                    return error.InvalidRealtimeReferenceWriter;

                const generation = try owner.nextUniqueGeneration();
                slot.generation = generation;
                slot.references.store(0, .release);
                owner.active_slot.store(self.slot, .release);
                self.publisher = null;
                return generation;
            }

            /// Cancels this reservation once. Later calls are harmless.
            pub fn cancel(self: *Writer) void {
                const owner = self.publisher orelse return;
                self.publisher = null;
                if (self.slot >= capacity) return;
                const slot = &owner.slots[self.slot];
                if (slot.references.load(.acquire) == writer_locked)
                    slot.references.store(0, .release);
            }
        };

        slots: [capacity]Slot,
        active_slot: std.atomic.Value(u8),
        next_generation: u64,

        pub fn init(initial: State) Self {
            var slots: [capacity]Slot = undefined;
            for (&slots) |*slot| {
                slot.* = .{
                    .value = initial,
                    .generation = 0,
                    .references = std.atomic.Value(u32).init(0),
                };
            }
            return .{
                .slots = slots,
                .active_slot = std.atomic.Value(u8).init(0),
                .next_generation = 1,
            };
        }

        /// Reserves one inactive generation for the single control writer.
        pub fn beginPublish(self: *Self) !Writer {
            const active = self.active_slot.load(.acquire);
            if (active >= capacity)
                return error.InvalidRealtimeReferencePublisher;

            var selected: ?u8 = null;
            for (0..capacity) |index| {
                const candidate: u8 = @intCast(index);
                if (candidate == active) continue;
                const references =
                    &self.slots[candidate].references;
                if (references.cmpxchgStrong(
                    0,
                    writer_locked,
                    .acq_rel,
                    .acquire,
                ) == null) {
                    selected = candidate;
                    break;
                }
            }
            const slot_index = selected orelse
                return error.RealtimeReferenceUnavailable;
            return .{
                .publisher = self,
                .slot = slot_index,
            };
        }

        /// Reserves a mutable copy of the active generation.
        ///
        /// The bounded copy fails without waiting when no inactive slot can be
        /// reserved or the active generation cannot be pinned.
        pub fn beginUpdate(self: *Self) !Writer {
            var writer = try self.beginPublish();
            errdefer writer.cancel();

            var source: ?Handle = null;
            for (0..capacity) |_| {
                source = self.tryAcquire();
                if (source != null) break;
            }
            var handle = source orelse
                return error.RealtimeReferenceSnapshotUnavailable;
            defer handle.release();

            const current = handle.value() orelse
                return error.InvalidRealtimeReferencePublisher;
            const destination = writer.value() orelse
                return error.InvalidRealtimeReferenceWriter;
            destination.* = current.*;
            return writer;
        }

        /// Publishes through one bounded attempt per non-active slot.
        pub fn publish(self: *Self, value: State) !u64 {
            var writer = try self.beginPublish();
            defer writer.cancel();
            const destination = writer.value() orelse
                return error.InvalidRealtimeReferenceWriter;
            destination.* = value;
            return writer.commit();
        }

        /// Attempts one bounded reference acquisition without waiting.
        pub fn tryAcquire(self: *Self) ?Handle {
            const selected = self.active_slot.load(.acquire);
            if (selected >= capacity) return null;
            const slot = &self.slots[selected];
            const current = slot.references.load(.acquire);
            if (current >= writer_locked - 1) return null;
            if (slot.references.cmpxchgStrong(
                current,
                current + 1,
                .acq_rel,
                .acquire,
            ) != null) return null;
            if (self.active_slot.load(.acquire) != selected) {
                _ = slot.references.fetchSub(1, .release);
                return null;
            }
            return .{
                .publisher = self,
                .slot = selected,
                .retained_generation = slot.generation,
            };
        }

        fn nextUniqueGeneration(self: *Self) !u64 {
            var candidate = self.next_generation;
            for (0..capacity + 1) |_| {
                if (candidate == 0) candidate = 1;
                var collision = false;
                for (&self.slots) |*slot| {
                    if (slot.generation == candidate) {
                        collision = true;
                        break;
                    }
                }
                if (!collision) {
                    self.next_generation = candidate +% 1;
                    if (self.next_generation == 0)
                        self.next_generation = 1;
                    return candidate;
                }
                candidate +%= 1;
            }
            return error.InvalidRealtimeReferencePublisher;
        }
    };
}

test "realtime snapshot publishes monotonic fixed-storage state" {
    const State = struct { gain: f32, mode: u8 };
    var publisher = Publisher(State).init(.{ .gain = 1.0, .mode = 0 });
    const initial = publisher.tryRead().?;
    try std.testing.expectEqual(@as(u64, 0), initial.generation);
    try std.testing.expectEqual(@as(f32, 1.0), initial.value.gain);

    try std.testing.expectEqual(
        @as(u64, 1),
        try publisher.publish(.{ .gain = 0.5, .mode = 2 }),
    );
    const next = publisher.tryRead().?;
    try std.testing.expectEqual(@as(u64, 1), next.generation);
    try std.testing.expectEqual(@as(f32, 0.5), next.value.gain);
    try std.testing.expectEqual(@as(u8, 2), next.value.mode);
}

test "realtime snapshot stress test does not expose torn state" {
    const State = struct {
        first: u64,
        second: u64,
        checksum: u64,
    };
    const Shared = struct {
        publisher: Publisher(State),
        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        invalid_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),

        fn write(shared: *@This()) void {
            for (1..100_001) |index| {
                const value: u64 = @intCast(index);
                _ = shared.publisher.publish(.{
                    .first = value,
                    .second = value,
                    .checksum = value ^ 0xA5A5_A5A5_A5A5_A5A5,
                }) catch continue;
            }
            shared.done.store(true, .release);
        }

        fn read(shared: *@This()) void {
            var last = shared.publisher.tryRead() orelse return;
            while (!shared.done.load(.acquire)) {
                const snapshot = shared.publisher.readOr(last);
                last = snapshot;
                if (snapshot.value.first != snapshot.value.second or
                    snapshot.value.checksum !=
                        snapshot.value.first ^ 0xA5A5_A5A5_A5A5_A5A5)
                {
                    _ = shared.invalid_reads.fetchAdd(1, .monotonic);
                }
            }
        }
    };

    var shared = Shared{
        .publisher = Publisher(State).init(.{
            .first = 0,
            .second = 0,
            .checksum = 0xA5A5_A5A5_A5A5_A5A5,
        }),
    };
    const writer = try std.Thread.spawn(.{}, Shared.write, .{&shared});
    const reader = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    writer.join();
    reader.join();
    try std.testing.expectEqual(
        @as(u64, 0),
        shared.invalid_reads.load(.acquire),
    );
}

test "realtime snapshot publisher rejects hostile active state" {
    var publisher = Publisher(u32).init(1);
    publisher.active_slot.store(99, .release);
    try std.testing.expect(publisher.tryRead() == null);
    try std.testing.expectError(
        error.InvalidRealtimeSnapshotPublisher,
        publisher.publish(2),
    );
}

test "realtime snapshot publisher skips zero generation" {
    var publisher = Publisher(u32).init(1);
    publisher.next_generation = 0;
    try std.testing.expectEqual(@as(u64, 1), try publisher.publish(2));
    try std.testing.expectEqual(@as(u64, 2), publisher.next_generation);

    publisher.next_generation = std.math.maxInt(u64);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        try publisher.publish(3),
    );
    try std.testing.expectEqual(@as(u64, 1), publisher.next_generation);
    try std.testing.expectEqual(@as(u64, 2), try publisher.publish(4));
}

test "realtime references pin generations and reclaim released slots" {
    const Shared = ReferencePublisher(struct { gain: f32 }, 3);
    var publisher = Shared.init(.{ .gain = 1.0 });
    var initial = publisher.tryAcquire().?;
    var retained = initial.retain().?;
    try std.testing.expectEqual(@as(u64, 0), initial.generation().?);

    _ = try publisher.publish(.{ .gain = 0.5 });
    var middle = publisher.tryAcquire().?;
    defer middle.release();
    _ = try publisher.publish(.{ .gain = 0.25 });
    try std.testing.expectError(
        error.RealtimeReferenceUnavailable,
        publisher.publish(.{ .gain = 0.125 }),
    );
    try std.testing.expectError(
        error.RealtimeReferenceUnavailable,
        publisher.beginUpdate(),
    );
    try std.testing.expectEqual(@as(f32, 1.0), initial.value().?.gain);
    try std.testing.expectEqual(@as(f32, 0.5), middle.value().?.gain);

    initial.release();
    retained.release();
    try std.testing.expect(initial.value() == null);
    try std.testing.expectEqual(
        @as(u64, 3),
        try publisher.publish(.{ .gain = 0.125 }),
    );
}

test "realtime reference writer commits in-place state" {
    const State = struct {
        samples: [4]f32,
        checksum: f32,
    };
    const Shared = ReferencePublisher(State, 3);
    var publisher = Shared.init(.{
        .samples = @splat(0),
        .checksum = 0,
    });
    var writer = try publisher.beginPublish();
    defer writer.cancel();
    const state = writer.value().?;
    state.samples = .{ 1, 2, 3, 4 };
    state.checksum = 10;
    try std.testing.expectEqual(@as(u64, 1), try writer.commit());
    try std.testing.expect(writer.value() == null);

    var handle = publisher.tryAcquire().?;
    defer handle.release();
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 2, 3, 4 },
        &handle.value().?.samples,
    );
    try std.testing.expectEqual(
        @as(f32, 10),
        handle.value().?.checksum,
    );
}

test "realtime reference update preserves unchanged active state" {
    const State = struct {
        gain: f32,
        mode: u8,
        checksum: u32,
    };
    const Shared = ReferencePublisher(State, 3);
    var publisher = Shared.init(.{
        .gain = 1.0,
        .mode = 2,
        .checksum = 0x1234_5678,
    });
    var previous = publisher.tryAcquire().?;
    defer previous.release();

    var writer = try publisher.beginUpdate();
    defer writer.cancel();
    const pending = writer.value().?;
    pending.gain = 0.25;
    try std.testing.expectEqual(@as(u64, 1), try writer.commit());

    try std.testing.expectEqual(
        @as(f32, 1.0),
        previous.value().?.gain,
    );
    var current = publisher.tryAcquire().?;
    defer current.release();
    try std.testing.expectEqual(@as(f32, 0.25), current.value().?.gain);
    try std.testing.expectEqual(@as(u8, 2), current.value().?.mode);
    try std.testing.expectEqual(
        @as(u32, 0x1234_5678),
        current.value().?.checksum,
    );
}

test "cancelled realtime reference update preserves active state" {
    const Shared = ReferencePublisher(struct { first: u32, second: u32 }, 3);
    var publisher = Shared.init(.{ .first = 1, .second = 2 });
    var writer = try publisher.beginUpdate();
    writer.value().?.first = 99;
    writer.cancel();

    var current = publisher.tryAcquire().?;
    defer current.release();
    try std.testing.expectEqual(@as(u64, 0), current.generation().?);
    try std.testing.expectEqual(@as(u32, 1), current.value().?.first);
    try std.testing.expectEqual(@as(u32, 2), current.value().?.second);
}

test "cancelled realtime reference writer preserves active generation" {
    const Shared = ReferencePublisher(u64, 3);
    var publisher = Shared.init(7);
    var writer = try publisher.beginPublish();
    writer.value().?.* = 99;
    writer.cancel();
    writer.cancel();

    var handle = publisher.tryAcquire().?;
    defer handle.release();
    try std.testing.expectEqual(@as(u64, 0), handle.generation().?);
    try std.testing.expectEqual(@as(u64, 7), handle.value().?.*);
    try std.testing.expectEqual(@as(u64, 1), try publisher.publish(8));
}

test "realtime reference writer rejects reuse after commit" {
    const Shared = ReferencePublisher(u32, 3);
    var publisher = Shared.init(1);
    var writer = try publisher.beginPublish();
    writer.value().?.* = 2;
    _ = try writer.commit();
    try std.testing.expectError(
        error.InvalidRealtimeReferenceWriter,
        writer.commit(),
    );
}

test "realtime reference handles release once and generations roll over" {
    const Shared = ReferencePublisher(u64, 3);
    var publisher = Shared.init(0);
    var handle = publisher.tryAcquire().?;
    handle.release();
    handle.release();

    publisher.next_generation = std.math.maxInt(u64);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        try publisher.publish(1),
    );
    try std.testing.expectEqual(@as(u64, 1), try publisher.publish(2));
    var current = publisher.tryAcquire().?;
    defer current.release();
    try std.testing.expectEqual(@as(u64, 1), current.generation().?);
    try std.testing.expectEqual(@as(u64, 2), current.value().?.*);
}

test "realtime reference rollover avoids a pinned generation" {
    const Shared = ReferencePublisher(u64, 3);
    var publisher = Shared.init(0);
    try std.testing.expectEqual(@as(u64, 1), try publisher.publish(10));
    var pinned = publisher.tryAcquire().?;
    defer pinned.release();

    publisher.next_generation = std.math.maxInt(u64);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        try publisher.publish(11),
    );
    try std.testing.expectEqual(@as(u64, 2), try publisher.publish(12));
    try std.testing.expectEqual(@as(u64, 1), pinned.generation().?);
    try std.testing.expectEqual(@as(u64, 10), pinned.value().?.*);
}

test "stale realtime reference copy cannot access a reused slot" {
    const Shared = ReferencePublisher(u64, 3);
    var publisher = Shared.init(0);
    _ = try publisher.publish(10);
    var handle = publisher.tryAcquire().?;
    var stale = handle;
    handle.release();

    _ = try publisher.publish(20);
    _ = try publisher.publish(30);
    try std.testing.expect(stale.value() == null);
    try std.testing.expect(stale.generation() == null);
    try std.testing.expect(stale.retain() == null);
    stale.release();

    var current = publisher.tryAcquire().?;
    defer current.release();
    try std.testing.expectEqual(@as(u64, 30), current.value().?.*);
}

test "concurrent malformed reference copies cannot underflow a slot" {
    const SharedPublisher = ReferencePublisher(u64, 3);
    const Shared = struct {
        publisher: SharedPublisher = SharedPublisher.init(7),
        handles: [2]SharedPublisher.Handle = undefined,
        round: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        completed: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

        fn releaseCopies(shared: *@This(), index: usize) void {
            var observed_round: u32 = 0;
            while (true) {
                const current_round = shared.round.load(.acquire);
                if (current_round == std.math.maxInt(u32)) return;
                if (current_round == observed_round) {
                    std.Thread.yield() catch {};
                    continue;
                }
                shared.handles[index].release();
                observed_round = current_round;
                _ = shared.completed.fetchAdd(1, .release);
            }
        }
    };

    var shared = Shared{};
    const first = try std.Thread.spawn(
        .{},
        Shared.releaseCopies,
        .{ &shared, 0 },
    );
    const second = try std.Thread.spawn(
        .{},
        Shared.releaseCopies,
        .{ &shared, 1 },
    );
    for (1..4_097) |round| {
        const handle = shared.publisher.tryAcquire().?;
        shared.handles = .{ handle, handle };
        shared.completed.store(0, .release);
        shared.round.store(@intCast(round), .release);
        while (shared.completed.load(.acquire) != 2)
            std.Thread.yield() catch {};
        try std.testing.expectEqual(
            @as(u32, 0),
            shared.publisher.slots[0].references.load(.acquire),
        );
    }
    shared.round.store(std.math.maxInt(u32), .release);
    first.join();
    second.join();
}

test "realtime reference publisher rejects hostile active state" {
    const Shared = ReferencePublisher(u32, 4);
    var publisher = Shared.init(1);
    publisher.active_slot.store(99, .release);
    try std.testing.expect(publisher.tryAcquire() == null);
    try std.testing.expectError(
        error.InvalidRealtimeReferencePublisher,
        publisher.publish(2),
    );
    try std.testing.expectError(
        error.InvalidRealtimeReferencePublisher,
        publisher.beginUpdate(),
    );
}

test "failed realtime reference update releases its reservation" {
    const Shared = ReferencePublisher(u32, 3);
    var publisher = Shared.init(1);
    publisher.slots[0].references.store(writer_locked, .release);
    try std.testing.expectError(
        error.RealtimeReferenceSnapshotUnavailable,
        publisher.beginUpdate(),
    );
    publisher.slots[0].references.store(0, .release);
    try std.testing.expectEqual(@as(u64, 1), try publisher.publish(2));
}

test "realtime references remain stable across multiple readers" {
    const State = struct {
        first: u64,
        second: u64,
        checksum: u64,
    };
    const PublisherType = ReferencePublisher(State, 8);
    const Shared = struct {
        publisher: PublisherType,
        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        invalid_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        successful_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),

        fn write(shared: *@This()) void {
            for (1..100_001) |index| {
                const value: u64 = @intCast(index);
                _ = shared.publisher.publish(.{
                    .first = value,
                    .second = value,
                    .checksum = value ^ 0x5A5A_5A5A_5A5A_5A5A,
                }) catch continue;
            }
            shared.done.store(true, .release);
        }

        fn read(shared: *@This()) void {
            while (!shared.done.load(.acquire)) {
                var handle =
                    shared.publisher.tryAcquire() orelse continue;
                var retained = handle.retain() orelse {
                    handle.release();
                    continue;
                };
                const value = handle.value() orelse {
                    retained.release();
                    handle.release();
                    continue;
                };
                const retained_value = retained.value() orelse {
                    retained.release();
                    handle.release();
                    continue;
                };
                std.Thread.yield() catch {};
                if (value.first != value.second or
                    value.checksum !=
                        value.first ^ 0x5A5A_5A5A_5A5A_5A5A or
                    retained.generation() != handle.generation() or
                    retained_value.first != value.first or
                    retained_value.second != value.second or
                    retained_value.checksum != value.checksum)
                {
                    _ = shared.invalid_reads.fetchAdd(1, .monotonic);
                }
                _ = shared.successful_reads.fetchAdd(1, .monotonic);
                retained.release();
                handle.release();
            }
        }
    };

    var shared = Shared{
        .publisher = PublisherType.init(.{
            .first = 0,
            .second = 0,
            .checksum = 0x5A5A_5A5A_5A5A_5A5A,
        }),
    };
    var readers: [4]std.Thread = undefined;
    for (&readers) |*reader|
        reader.* = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    while (shared.successful_reads.load(.acquire) == 0)
        std.Thread.yield() catch {};
    const writer = try std.Thread.spawn(.{}, Shared.write, .{&shared});
    writer.join();
    for (&readers) |reader| reader.join();
    try std.testing.expectEqual(
        @as(u64, 0),
        shared.invalid_reads.load(.acquire),
    );
    try std.testing.expect(shared.successful_reads.load(.acquire) > 0);
}

test "realtime reference updates remain coherent across multiple readers" {
    const State = struct {
        first: u64,
        second: u64,
        retained: u64,
    };
    const PublisherType = ReferencePublisher(State, 8);
    const Shared = struct {
        publisher: PublisherType,
        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        invalid_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        successful_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),

        fn write(shared: *@This()) void {
            for (1..50_001) |index| {
                var writer =
                    shared.publisher.beginUpdate() catch continue;
                const pending = writer.value() orelse {
                    writer.cancel();
                    continue;
                };
                const value: u64 = @intCast(index);
                pending.first = value;
                pending.second = value;
                _ = writer.commit() catch {
                    writer.cancel();
                    continue;
                };
            }
            shared.done.store(true, .release);
        }

        fn read(shared: *@This()) void {
            while (!shared.done.load(.acquire)) {
                var handle =
                    shared.publisher.tryAcquire() orelse continue;
                const value = handle.value() orelse {
                    handle.release();
                    continue;
                };
                if (value.first != value.second or
                    value.retained != 0xC0FF_EE00_CAFE_BABE)
                {
                    _ = shared.invalid_reads.fetchAdd(1, .monotonic);
                }
                _ = shared.successful_reads.fetchAdd(1, .monotonic);
                handle.release();
            }
        }
    };

    var shared = Shared{
        .publisher = PublisherType.init(.{
            .first = 0,
            .second = 0,
            .retained = 0xC0FF_EE00_CAFE_BABE,
        }),
    };
    var readers: [4]std.Thread = undefined;
    for (&readers) |*reader|
        reader.* = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    while (shared.successful_reads.load(.acquire) == 0)
        std.Thread.yield() catch {};
    const writer = try std.Thread.spawn(.{}, Shared.write, .{&shared});
    writer.join();
    for (&readers) |reader| reader.join();
    try std.testing.expectEqual(
        @as(u64, 0),
        shared.invalid_reads.load(.acquire),
    );
    try std.testing.expect(shared.successful_reads.load(.acquire) > 0);
}
