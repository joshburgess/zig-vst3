const std = @import("std");
const realtime_audit = @import("../realtime_audit.zig");
const serial_generation = @import("../serial_generation.zig");

pub const PublishError = error{
    Busy,
    InvalidGeneration,
    RealtimeViolation,
};

pub fn Exchange(comptime Config: type) type {
    const Resource = Config.Resource;
    const slot_capacity: usize = Config.slot_capacity;
    const mutable_active: bool = if (@hasDecl(Config, "mutable_active")) Config.mutable_active else false;
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
            generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
            resource: ?*Resource = null,
        };

        pub const View = struct {
            generation: u64,
            resource: *const Resource,
        };

        pub const MutableView = struct {
            generation: u64,
            resource: *Resource,
        };

        slots: [slot_capacity]Slot = [_]Slot{.{}} ** slot_capacity,
        pending_slot: std.atomic.Value(u8) = std.atomic.Value(u8).init(no_slot),
        latest_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_slot: u8 = no_slot,

        pub fn publish(self: *Self, generation: u64, resource: *Resource) PublishError!void {
            if (!realtime_audit.observe(.allocation)) return error.RealtimeViolation;
            if (!serial_generation.after(generation, self.latest_generation.load(.acquire))) {
                return error.InvalidGeneration;
            }
            _ = self.reclaim();
            const slot_index = self.claimFreeSlot() orelse return error.Busy;
            const slot = &self.slots[slot_index];
            slot.generation.store(generation, .unordered);
            slot.resource = resource;
            slot.state.store(@intFromEnum(SlotState.published), .release);
            self.latest_generation.store(generation, .release);
            const replaced = self.pending_slot.swap(slot_index, .acq_rel);
            if (validSlotIndex(replaced)) {
                self.slots[replaced].state.store(@intFromEnum(SlotState.retired), .release);
            }
        }

        pub fn adoptPending(self: *Self) ?View {
            return self.adoptPendingBounded(null, null);
        }

        pub fn adoptPendingAtOrAfter(self: *Self, minimum_generation: u64) ?View {
            return self.adoptPendingBounded(minimum_generation, null);
        }

        pub fn adoptPendingThrough(self: *Self, maximum_generation: u64) ?View {
            return self.adoptPendingBounded(null, maximum_generation);
        }

        pub fn adoptPendingInRange(self: *Self, minimum_generation: u64, maximum_generation: u64) ?View {
            return self.adoptPendingBounded(
                if (minimum_generation == 0) null else minimum_generation,
                maximum_generation,
            );
        }

        fn adoptPendingBounded(self: *Self, minimum_generation: ?u64, maximum_generation: ?u64) ?View {
            _ = realtime_audit.observe(.resource_adoption);
            while (true) {
                const next = self.pending_slot.load(.acquire);
                if (next == no_slot) return null;
                if (!validSlotIndex(next)) {
                    _ = self.pending_slot.cmpxchgStrong(next, no_slot, .acq_rel, .acquire);
                    return null;
                }
                const slot = &self.slots[next];
                if (slot.state.load(.acquire) != @intFromEnum(SlotState.published)) return null;
                const generation = slot.generation.load(.acquire);
                if (generation == 0) {
                    if (self.pending_slot.cmpxchgStrong(next, no_slot, .acq_rel, .acquire) != null) continue;
                    slot.state.store(@intFromEnum(SlotState.retired), .release);
                    return null;
                }
                if (maximum_generation) |maximum| {
                    if (!serial_generation.atOrBefore(generation, maximum)) return null;
                }
                if (self.pending_slot.cmpxchgStrong(next, no_slot, .acq_rel, .acquire) != null) continue;
                if (minimum_generation) |minimum| {
                    if (!serial_generation.atOrAfter(generation, minimum)) {
                        slot.state.store(@intFromEnum(SlotState.retired), .release);
                        return null;
                    }
                }
                if (validSlotIndex(self.active_slot)) {
                    self.slots[self.active_slot].state.store(@intFromEnum(SlotState.retired), .release);
                }
                slot.state.store(@intFromEnum(SlotState.active), .release);
                self.active_slot = next;
                return view(slot);
            }
        }

        pub fn active(self: *const Self) ?View {
            if (!validSlotIndex(self.active_slot)) return null;
            const slot = &self.slots[self.active_slot];
            if (slot.state.load(.acquire) != @intFromEnum(SlotState.active)) return null;
            return view(slot);
        }

        pub fn activeMutable(self: *Self) ?MutableView {
            if (!mutable_active) @compileError("mutable active resources require Config.mutable_active = true");
            if (!validSlotIndex(self.active_slot)) return null;
            const slot = &self.slots[self.active_slot];
            if (slot.state.load(.acquire) != @intFromEnum(SlotState.active)) return null;
            return .{
                .generation = slot.generation.load(.acquire),
                .resource = slot.resource orelse return null,
            };
        }

        pub fn retireActiveAtBlockBoundary(self: *Self) bool {
            _ = realtime_audit.observe(.resource_adoption);
            if (!validSlotIndex(self.active_slot)) {
                self.active_slot = no_slot;
                return false;
            }
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
                    slot.generation.store(0, .unordered);
                    slot.state.store(@intFromEnum(SlotState.free), .release);
                    continue;
                };
                slot.resource = null;
                slot.generation.store(0, .unordered);
                Config.destroy(resource);
                slot.state.store(@intFromEnum(SlotState.free), .release);
                reclaimed += 1;
            }
            return reclaimed;
        }

        pub fn hasPending(self: *const Self) bool {
            return validSlotIndex(self.pending_slot.load(.acquire));
        }

        pub fn retireAllAfterProcessingStops(self: *Self) void {
            const pending = self.pending_slot.swap(no_slot, .acq_rel);
            if (validSlotIndex(pending)) {
                self.slots[pending].state.store(@intFromEnum(SlotState.retired), .release);
            }
            if (validSlotIndex(self.active_slot)) {
                self.slots[self.active_slot].state.store(@intFromEnum(SlotState.retired), .release);
            }
            self.active_slot = no_slot;
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
                .generation = slot.generation.load(.acquire),
                .resource = slot.resource orelse return null,
            };
        }

        fn validSlotIndex(index: u8) bool {
            return index < slot_capacity;
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

test "resource exchange contains malformed public slot indices" {
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
    exchange.pending_slot.store(9, .release);
    exchange.active_slot = 9;
    try std.testing.expect(!exchange.hasPending());
    try std.testing.expectEqual(@as(?ModelExchange.View, null), exchange.adoptPending());
    try std.testing.expectEqual(@as(?ModelExchange.View, null), exchange.active());
    try std.testing.expect(!exchange.retireActiveAtBlockBoundary());

    exchange.pending_slot.store(9, .release);
    const resource = try std.heap.page_allocator.create(Model);
    resource.* = .{ .value = 7 };
    try exchange.publish(1, resource);
    try std.testing.expectEqual(@as(u8, 7), exchange.adoptPending().?.resource.value);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());
}

test "resource exchange contains a malformed pending generation" {
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
    const malformed = try std.heap.page_allocator.create(Model);
    malformed.* = .{ .value = 1 };
    try exchange.publish(1, malformed);
    const pending = exchange.pending_slot.load(.acquire);
    exchange.slots[pending].generation.store(0, .release);

    try std.testing.expectEqual(@as(?ModelExchange.View, null), exchange.adoptPending());
    try std.testing.expect(!exchange.hasPending());
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());

    const recovered = try std.heap.page_allocator.create(Model);
    recovered.* = .{ .value = 2 };
    try exchange.publish(2, recovered);
    try std.testing.expectEqual(@as(u8, 2), exchange.adoptPending().?.resource.value);
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

test "resource exchange retains a pending generation until adoption is approved" {
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
    resource.* = .{ .value = 9 };
    try exchange.publish(4, resource);
    try std.testing.expect(exchange.adoptPendingThrough(3) == null);
    try std.testing.expect(exchange.hasPending());
    const adopted = exchange.adoptPendingThrough(4).?;
    try std.testing.expectEqual(@as(u64, 4), adopted.generation);
    try std.testing.expectEqual(@as(u8, 9), adopted.resource.value);
}

test "resource exchange preserves publication ordering across generation rollover" {
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
    exchange.latest_generation.store(std.math.maxInt(u64) - 1, .release);

    const before_wrap = try std.heap.page_allocator.create(Model);
    before_wrap.* = .{ .value = 1 };
    try exchange.publish(std.math.maxInt(u64), before_wrap);
    try std.testing.expectEqual(std.math.maxInt(u64), exchange.adoptPending().?.generation);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());

    const after_wrap = try std.heap.page_allocator.create(Model);
    after_wrap.* = .{ .value = 2 };
    try exchange.publish(1, after_wrap);
    try std.testing.expect(exchange.adoptPendingThrough(std.math.maxInt(u64)) == null);
    try std.testing.expect(exchange.hasPending());
    try std.testing.expectEqual(@as(u64, 1), exchange.adoptPendingAtOrAfter(std.math.maxInt(u64)).?.generation);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    try std.testing.expectEqual(@as(usize, 1), exchange.reclaim());

    const stale = try std.heap.page_allocator.create(Model);
    stale.* = .{ .value = 3 };
    try std.testing.expectError(
        error.InvalidGeneration,
        exchange.publish(std.math.maxInt(u64) - 1, stale),
    );
    std.heap.page_allocator.destroy(stale);
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

test "resource exchange transfers exclusive mutable runtime state" {
    const Runtime = struct { state: f32 };
    const RuntimeExchange = Exchange(struct {
        pub const Resource = Runtime;
        pub const slot_capacity = 2;
        pub const mutable_active = true;

        pub fn destroy(resource: *Runtime) void {
            std.heap.page_allocator.destroy(resource);
        }
    });

    var exchange: RuntimeExchange = .{};
    defer exchange.deinit();
    const runtime = try std.heap.page_allocator.create(Runtime);
    runtime.* = .{ .state = 0.0 };
    try exchange.publish(1, runtime);

    const first_scope = realtime_audit.Scope.enter();
    _ = exchange.adoptPending();
    exchange.activeMutable().?.resource.state = 0.75;
    try std.testing.expectEqual(@as(f32, 0.75), exchange.activeMutable().?.resource.state);
    try std.testing.expect(first_scope.leave().clean());

    const replacement = try std.heap.page_allocator.create(Runtime);
    replacement.* = .{ .state = 0.25 };
    try exchange.publish(2, replacement);
    const replacement_scope = realtime_audit.Scope.enter();
    try std.testing.expectEqual(@as(u64, 2), exchange.adoptPending().?.generation);
    try std.testing.expectEqual(@as(f32, 0.25), exchange.activeMutable().?.resource.state);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
    try std.testing.expect(replacement_scope.leave().clean());
    try std.testing.expectEqual(@as(usize, 2), exchange.reclaim());
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
