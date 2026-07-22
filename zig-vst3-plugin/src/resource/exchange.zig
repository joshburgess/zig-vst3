const std = @import("std");
const realtime_audit = @import("../realtime_audit.zig");

pub const PublishError = error{
    Busy,
    InvalidGeneration,
    RealtimeViolation,
};

pub fn Exchange(comptime Config: type) type {
    const Resource = Config.Resource;
    const slot_capacity: usize = Config.slot_capacity;
    if (slot_capacity == 0 or slot_capacity > std.math.maxInt(u8)) {
        @compileError("resource exchange slot capacity must fit in a nonzero u8");
    }
    const no_slot = std.math.maxInt(u8);

    return struct {
        const Self = @This();
        const SlotState = enum(u8) {
            free,
            writing,
            published,
            active,
            retired,
            reclaiming,
        };

        const Slot = struct {
            state: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(SlotState.free)),
            generation: u64 = 0,
            resource: ?*Resource = null,
        };

        pub const View = struct {
            generation: u64,
            resource: *const Resource,
        };

        slots: [slot_capacity]Slot = [_]Slot{.{}} ** slot_capacity,
        pending_slot: std.atomic.Value(u8) = std.atomic.Value(u8).init(no_slot),
        latest_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_slot: u8 = no_slot,

        pub fn publish(self: *Self, generation: u64, resource: *Resource) PublishError!void {
            if (!realtime_audit.observe(.allocation)) return error.RealtimeViolation;
            if (generation == 0 or generation <= self.latest_generation.load(.acquire)) {
                return error.InvalidGeneration;
            }
            _ = self.reclaim();
            const slot_index = self.claimFreeSlot() orelse return error.Busy;
            const slot = &self.slots[slot_index];
            slot.generation = generation;
            slot.resource = resource;
            slot.state.store(@intFromEnum(SlotState.published), .release);
            self.latest_generation.store(generation, .release);
            const replaced = self.pending_slot.swap(slot_index, .acq_rel);
            if (replaced != no_slot) {
                self.slots[replaced].state.store(@intFromEnum(SlotState.retired), .release);
            }
        }

        pub fn adoptPending(self: *Self) ?View {
            return self.adoptPendingAtOrAfter(0);
        }

        pub fn adoptPendingAtOrAfter(self: *Self, minimum_generation: u64) ?View {
            _ = realtime_audit.observe(.resource_adoption);
            const next = self.pending_slot.swap(no_slot, .acq_rel);
            if (next == no_slot) return null;
            const slot = &self.slots[next];
            if (slot.state.load(.acquire) != @intFromEnum(SlotState.published)) return null;
            if (slot.generation < minimum_generation) {
                slot.state.store(@intFromEnum(SlotState.retired), .release);
                return null;
            }
            if (self.active_slot != no_slot) {
                self.slots[self.active_slot].state.store(@intFromEnum(SlotState.retired), .release);
            }
            slot.state.store(@intFromEnum(SlotState.active), .release);
            self.active_slot = next;
            return view(slot);
        }

        pub fn active(self: *const Self) ?View {
            if (self.active_slot == no_slot) return null;
            const slot = &self.slots[self.active_slot];
            if (slot.state.load(.acquire) != @intFromEnum(SlotState.active)) return null;
            return view(slot);
        }

        pub fn retireActiveAtBlockBoundary(self: *Self) bool {
            _ = realtime_audit.observe(.resource_adoption);
            if (self.active_slot == no_slot) return false;
            self.slots[self.active_slot].state.store(@intFromEnum(SlotState.retired), .release);
            self.active_slot = no_slot;
            return true;
        }

        pub fn reclaim(self: *Self) usize {
            if (!realtime_audit.observe(.allocation)) return 0;
            var reclaimed: usize = 0;
            for (&self.slots) |*slot| {
                if (slot.state.cmpxchgStrong(
                    @intFromEnum(SlotState.retired),
                    @intFromEnum(SlotState.reclaiming),
                    .acq_rel,
                    .acquire,
                ) != null) continue;
                const resource = slot.resource orelse {
                    slot.generation = 0;
                    slot.state.store(@intFromEnum(SlotState.free), .release);
                    continue;
                };
                slot.resource = null;
                slot.generation = 0;
                Config.destroy(resource);
                slot.state.store(@intFromEnum(SlotState.free), .release);
                reclaimed += 1;
            }
            return reclaimed;
        }

        pub fn hasPending(self: *const Self) bool {
            return self.pending_slot.load(.acquire) != no_slot;
        }

        pub fn retireAllAfterProcessingStops(self: *Self) void {
            const pending = self.pending_slot.swap(no_slot, .acq_rel);
            if (pending != no_slot) {
                self.slots[pending].state.store(@intFromEnum(SlotState.retired), .release);
            }
            if (self.active_slot != no_slot) {
                self.slots[self.active_slot].state.store(@intFromEnum(SlotState.retired), .release);
                self.active_slot = no_slot;
            }
        }

        pub fn deinit(self: *Self) void {
            _ = realtime_audit.observe(.allocation);
            self.retireAllAfterProcessingStops();
            for (&self.slots) |*slot| {
                if (slot.state.load(.acquire) == @intFromEnum(SlotState.published)) {
                    slot.state.store(@intFromEnum(SlotState.retired), .release);
                }
            }
            _ = self.reclaim();
        }

        fn claimFreeSlot(self: *Self) ?u8 {
            for (&self.slots, 0..) |*slot, index| {
                if (slot.state.cmpxchgStrong(
                    @intFromEnum(SlotState.free),
                    @intFromEnum(SlotState.writing),
                    .acq_rel,
                    .acquire,
                ) == null) return @intCast(index);
            }
            return null;
        }

        fn view(slot: *const Slot) ?View {
            return .{
                .generation = slot.generation,
                .resource = slot.resource orelse return null,
            };
        }
    };
}

test "resource exchange publishes adopts and reclaims immutable generations" {
    const counters = struct {
        var destroyed = std.atomic.Value(u32).init(0);
    };
    const Model = struct { gain: f32 };
    const ModelExchange = Exchange(struct {
        pub const Resource = Model;
        pub const slot_capacity = 3;

        pub fn destroy(resource: *Model) void {
            std.heap.page_allocator.destroy(resource);
            _ = counters.destroyed.fetchAdd(1, .acq_rel);
        }
    });

    counters.destroyed.store(0, .release);
    var exchange: ModelExchange = .{};
    defer exchange.deinit();
    const first = try std.heap.page_allocator.create(Model);
    first.* = .{ .gain = 1.0 };
    try exchange.publish(1, first);
    try std.testing.expectEqual(@as(u64, 1), exchange.adoptPending().?.generation);

    const second = try std.heap.page_allocator.create(Model);
    second.* = .{ .gain = 2.0 };
    try exchange.publish(2, second);
    const third = try std.heap.page_allocator.create(Model);
    third.* = .{ .gain = 3.0 };
    try exchange.publish(3, third);
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());
    const active = exchange.adoptPending().?;
    try std.testing.expectEqual(@as(u64, 3), active.generation);
    try std.testing.expectEqual(@as(f32, 3.0), active.resource.gain);
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());
    try std.testing.expectEqual(@as(u32, 3), counters.destroyed.load(.acquire));
}

test "resource exchange reports bounded capacity and stale generations" {
    const Model = struct { value: u8 };
    const SingleExchange = Exchange(struct {
        pub const Resource = Model;
        pub const slot_capacity = 1;

        pub fn destroy(resource: *Model) void {
            std.heap.page_allocator.destroy(resource);
        }
    });

    var exchange: SingleExchange = .{};
    defer exchange.deinit();
    const first = try std.heap.page_allocator.create(Model);
    first.* = .{ .value = 1 };
    try exchange.publish(1, first);
    _ = exchange.adoptPending();
    const second = try std.heap.page_allocator.create(Model);
    second.* = .{ .value = 2 };
    try std.testing.expectError(error.Busy, exchange.publish(2, second));
    std.heap.page_allocator.destroy(second);
    const stale = try std.heap.page_allocator.create(Model);
    stale.* = .{ .value = 3 };
    try std.testing.expectError(error.InvalidGeneration, exchange.publish(1, stale));
    std.heap.page_allocator.destroy(stale);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());
}

test "resource exchange rejects pending generations older than a restore boundary" {
    const Model = struct { value: u8 };
    const ModelExchange = Exchange(struct {
        pub const Resource = Model;
        pub const slot_capacity = 2;

        pub fn destroy(resource: *Model) void {
            std.heap.page_allocator.destroy(resource);
        }
    });

    var exchange: ModelExchange = .{};
    defer exchange.deinit();
    const stale = try std.heap.page_allocator.create(Model);
    stale.* = .{ .value = 1 };
    try exchange.publish(1, stale);
    try std.testing.expect(exchange.adoptPendingAtOrAfter(2) == null);
    try std.testing.expect(exchange.active() == null);
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());

    const restored = try std.heap.page_allocator.create(Model);
    restored.* = .{ .value = 2 };
    try exchange.publish(2, restored);
    try std.testing.expectEqual(@as(u64, 2), exchange.adoptPendingAtOrAfter(2).?.generation);
}

test "resource exchange audio operations are lock free and allocation free" {
    const Model = struct { value: u8 };
    const ModelExchange = Exchange(struct {
        pub const Resource = Model;
        pub const slot_capacity = 2;

        pub fn destroy(resource: *Model) void {
            std.heap.page_allocator.destroy(resource);
        }
    });

    var exchange: ModelExchange = .{};
    defer exchange.deinit();
    const resource = try std.heap.page_allocator.create(Model);
    resource.* = .{ .value = 7 };
    try exchange.publish(1, resource);
    const scope = realtime_audit.Scope.enter();
    const adopted = exchange.adoptPending().?;
    try std.testing.expectEqual(@as(u8, 7), adopted.resource.value);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    const report = scope.leave();
    try std.testing.expect(report.clean());
    try std.testing.expectEqual(@as(u32, 2), report.count(.resource_adoption));
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());
}

test "resource exchange remains bounded during concurrent replacement" {
    const counters = struct {
        var destroyed = std.atomic.Value(u32).init(0);
    };
    const Model = struct { generation: u64 };
    const ModelExchange = Exchange(struct {
        pub const Resource = Model;
        pub const slot_capacity = 4;

        pub fn destroy(resource: *Model) void {
            std.heap.page_allocator.destroy(resource);
            _ = counters.destroyed.fetchAdd(1, .acq_rel);
        }
    });
    const AudioWorker = struct {
        exchange: *ModelExchange,
        publishing_done: *const std.atomic.Value(bool),
        highest_generation: *std.atomic.Value(u64),

        fn run(self: @This()) void {
            while (!self.publishing_done.load(.acquire) or self.exchange.hasPending()) {
                if (self.exchange.adoptPending()) |active| {
                    var previous = self.highest_generation.load(.acquire);
                    while (active.generation > previous) {
                        previous = self.highest_generation.cmpxchgWeak(previous, active.generation, .acq_rel, .acquire) orelse break;
                    }
                    std.debug.assert(active.generation == active.resource.generation);
                }
                std.Thread.yield() catch {};
            }
            _ = self.exchange.retireActiveAtBlockBoundary();
        }
    };

    const publication_count: u32 = 1_000;
    counters.destroyed.store(0, .release);
    var exchange: ModelExchange = .{};
    defer exchange.deinit();
    var publishing_done = std.atomic.Value(bool).init(false);
    var highest_generation = std.atomic.Value(u64).init(0);
    const audio_thread = try std.Thread.spawn(.{}, AudioWorker.run, .{AudioWorker{
        .exchange = &exchange,
        .publishing_done = &publishing_done,
        .highest_generation = &highest_generation,
    }});

    for (1..publication_count + 1) |generation| {
        const resource = try std.heap.page_allocator.create(Model);
        resource.* = .{ .generation = @intCast(generation) };
        while (true) {
            exchange.publish(@intCast(generation), resource) catch |err| switch (err) {
                error.Busy => {
                    _ = exchange.reclaim();
                    std.Thread.yield() catch {};
                    continue;
                },
                else => return err,
            };
            break;
        }
        _ = exchange.reclaim();
    }
    publishing_done.store(true, .release);
    audio_thread.join();
    _ = exchange.reclaim();
    try std.testing.expectEqual(@as(u64, publication_count), highest_generation.load(.acquire));
    try std.testing.expectEqual(publication_count, counters.destroyed.load(.acquire));
}
