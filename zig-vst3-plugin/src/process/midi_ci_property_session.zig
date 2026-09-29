const std = @import("std");
const midi_ci = @import("midi_ci.zig");
const property = @import("midi_ci_property.zig");
const property_json = @import("midi_ci_property_json.zig");

pub const ReceiveResult = union(enum) {
    more: u7,
    complete: u7,
    aborted: u7,
    timeout_wait: u7,
    terminated: u7,
    timed_out: u7,
};

pub const SubscriptionUpdate = union(enum) {
    partial: u7,
    full: u7,
    notify: u7,
    ended: u7,
};

pub const Subscription = struct {
    remote: midi_ci.Muid,
    resource: []const u8,
    subscribe_id: []const u8,
};

pub fn SubscriptionRegistry(comptime capacity: usize) type {
    if (capacity == 0 or capacity > 127)
        @compileError("MIDI-CI subscription capacity must be 1 through 127");
    return struct {
        const Self = @This();

        const Entry = struct {
            active: bool = false,
            remote: midi_ci.Muid = .{ .value = 0 },
            resource_storage: [36]u8 = @splat(0),
            resource_count: u6 = 0,
            id_storage: [8]u8 = @splat(0),
            id_count: u4 = 0,

            fn value(self: *const Entry) Subscription {
                return .{
                    .remote = self.remote,
                    .resource = self.resource_storage[0..self.resource_count],
                    .subscribe_id = self.id_storage[0..self.id_count],
                };
            }
        };

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        active_count: usize = 0,

        pub fn register(
            self: *Self,
            remote: midi_ci.Muid,
            resource: []const u8,
            subscribe_id: []const u8,
        ) !u7 {
            try self.validate();
            if (!remote.validSource()) return error.InvalidMidiCiMuid;
            if (!(property_json.SubscriptionHeader{
                .command = .start,
                .resource = resource,
            }).valid()) return error.InvalidMidiCiPropertyResource;
            if (!(property_json.SubscriptionHeader{
                .command = .partial,
                .subscribe_id = subscribe_id,
            }).valid()) return error.InvalidMidiCiPropertySubscribeId;
            if (self.find(remote, subscribe_id) != null)
                return error.MidiCiPropertySubscriptionAlreadyExists;
            const index = self.emptySlot() orelse
                return error.MidiCiPropertySubscriptionCapacityExceeded;
            var entry = Entry{
                .active = true,
                .remote = remote,
                .resource_count = @intCast(resource.len),
                .id_count = @intCast(subscribe_id.len),
            };
            @memcpy(entry.resource_storage[0..resource.len], resource);
            @memcpy(entry.id_storage[0..subscribe_id.len], subscribe_id);
            self.entries[index] = entry;
            self.active_count += 1;
            return @intCast(index);
        }

        pub fn accept(
            self: *Self,
            remote: midi_ci.Muid,
            header: property_json.SubscriptionHeader,
        ) !SubscriptionUpdate {
            try self.validate();
            if (!header.valid()) return error.InvalidMidiCiPropertySubscriptionHeader;
            if (header.command == .start)
                return error.InvalidMidiCiPropertySubscriptionCommand;
            const subscribe_id = header.subscribe_id orelse
                return error.InvalidMidiCiPropertySubscribeId;
            const handle = self.find(remote, subscribe_id) orelse
                return error.MidiCiPropertySubscriptionNotFound;
            return switch (header.command) {
                .partial => .{ .partial = handle },
                .full => .{ .full = handle },
                .notify => .{ .notify = handle },
                .end => result_value: {
                    try self.release(handle);
                    break :result_value .{ .ended = handle };
                },
                .start => error.InvalidMidiCiPropertySubscriptionCommand,
            };
        }

        pub fn get(self: *const Self, handle: u7) !Subscription {
            try self.validate();
            if (handle >= capacity or !self.entries[handle].active)
                return error.InvalidMidiCiPropertySubscriptionHandle;
            return self.entries[handle].value();
        }

        pub fn findHandle(
            self: *const Self,
            remote: midi_ci.Muid,
            subscribe_id: []const u8,
        ) ?u7 {
            if (!self.valid()) return null;
            return self.find(remote, subscribe_id);
        }

        pub fn release(self: *Self, handle: u7) !void {
            try self.validate();
            if (handle >= capacity or !self.entries[handle].active)
                return error.InvalidMidiCiPropertySubscriptionHandle;
            self.entries[handle] = .{};
            self.active_count -= 1;
        }

        pub fn releaseRemote(self: *Self, remote: midi_ci.Muid) usize {
            var released: usize = 0;
            for (&self.entries) |*entry| {
                if (entry.active and entry.remote.value == remote.value) {
                    entry.* = .{};
                    released += 1;
                }
            }
            self.active_count = self.countActiveEntries();
            return released;
        }

        pub fn activeCount(self: *const Self) usize {
            return self.countActiveEntries();
        }

        pub fn validate(self: *const Self) !void {
            var counted: usize = 0;
            for (&self.entries, 0..) |*entry, index| {
                if (!entry.active) continue;
                if (!entry.remote.validSource() or
                    entry.resource_count == 0 or
                    entry.resource_count > entry.resource_storage.len or
                    entry.id_count == 0 or
                    entry.id_count > entry.id_storage.len)
                    return error.InvalidMidiCiPropertySubscriptionState;
                const value = entry.value();
                if (!(property_json.SubscriptionHeader{
                    .command = .start,
                    .resource = value.resource,
                }).valid() or !(property_json.SubscriptionHeader{
                    .command = .partial,
                    .subscribe_id = value.subscribe_id,
                }).valid()) {
                    return error.InvalidMidiCiPropertySubscriptionState;
                }
                for (self.entries[0..index]) |earlier| {
                    if (!earlier.active or
                        earlier.remote.value != entry.remote.value)
                        continue;
                    if (std.mem.eql(
                        u8,
                        earlier.id_storage[0..earlier.id_count],
                        value.subscribe_id,
                    )) return error.InvalidMidiCiPropertySubscriptionState;
                }
                counted += 1;
            }
            if (counted != self.active_count)
                return error.InvalidMidiCiPropertySubscriptionState;
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        fn find(
            self: *const Self,
            remote: midi_ci.Muid,
            subscribe_id: []const u8,
        ) ?u7 {
            for (self.entries, 0..) |entry, index| {
                if (!entry.active or entry.remote.value != remote.value)
                    continue;
                const value = entry.value();
                if (std.mem.eql(u8, value.subscribe_id, subscribe_id))
                    return @intCast(index);
            }
            return null;
        }

        fn emptySlot(self: *const Self) ?usize {
            for (self.entries, 0..) |entry, index| {
                if (!entry.active) return index;
            }
            return null;
        }

        fn countActiveEntries(self: *const Self) usize {
            var result: usize = 0;
            for (self.entries) |entry| {
                if (entry.active) result += 1;
            }
            return result;
        }
    };
}

pub fn Initiator(
    comptime capacity: usize,
    comptime header_capacity: usize,
    comptime data_capacity: usize,
) type {
    if (capacity == 0 or capacity > 127)
        @compileError("MIDI-CI Property Exchange session capacity must be 1 through 127");
    const Reassembly = property.Reassembler(header_capacity, data_capacity);
    const Message = property.DataMessage(header_capacity, data_capacity);
    return struct {
        const Self = @This();
        pub const DataMessage = Message;

        const State = enum {
            unused,
            sending,
            pending,
            complete,
            aborted,
        };

        const Slot = struct {
            state: State = .unused,
            destination: midi_ci.Muid = .{ .value = 0 },
            request_kind: property.DataKind = .get,
            version: u5 = 2,
            declared_total: u14 = 0,
            next_chunk: u14 = 1,
            response: Reassembly = .{},
        };

        source: midi_ci.Muid,
        version: u5,
        request_ids: property.RequestIds(capacity) = .{},
        slots: [capacity]Slot = [_]Slot{.{}} ** capacity,

        pub fn init(source: midi_ci.Muid, version: u5) !Self {
            if (!source.validSource()) return error.InvalidMidiCiMuid;
            if (version != 1 and version != 2)
                return error.UnsupportedMidiCiVersion;
            return .{ .source = source, .version = version };
        }

        pub fn begin(
            self: *Self,
            kind: property.DataKind,
            destination: midi_ci.Muid,
            header: []const u8,
            total_chunks: u14,
            data: []const u8,
        ) !Message {
            try self.validate();
            if (!requestKind(kind)) return error.InvalidMidiCiPropertyRequestKind;
            if (!destination.validSource() or destination.value == self.source.value)
                return error.InvalidMidiCiPropertyDestination;
            const request_id = try self.request_ids.acquire();
            errdefer self.request_ids.release(request_id) catch {};
            const message = try Message.init(
                kind,
                self.version,
                self.source,
                destination,
                request_id,
                header,
                total_chunks,
                1,
                data,
            );
            const final = total_chunks == 1;
            self.slots[request_id] = .{
                .state = if (final) .pending else .sending,
                .destination = destination,
                .request_kind = kind,
                .version = self.version,
                .declared_total = total_chunks,
                .next_chunk = 2,
            };
            return message;
        }

        pub fn continueRequest(
            self: *Self,
            request_id: u7,
            total_chunks: u14,
            data: []const u8,
        ) !Message {
            const slot = try self.mutableActiveSlot(request_id);
            if (slot.state != .sending)
                return error.InvalidMidiCiPropertySessionState;
            const chunk_number = slot.next_chunk;
            if (slot.declared_total != 0) {
                if (total_chunks != slot.declared_total)
                    return error.InvalidMidiCiPropertyChunkSequence;
            } else if (total_chunks != 0 and total_chunks != chunk_number) {
                return error.InvalidMidiCiPropertyChunkSequence;
            }
            const message = try Message.init(
                slot.request_kind,
                slot.version,
                self.source,
                slot.destination,
                request_id,
                &.{},
                total_chunks,
                chunk_number,
                data,
            );
            const final = total_chunks != 0 and total_chunks == chunk_number;
            if (final) {
                slot.state = .pending;
            } else {
                if (chunk_number == std.math.maxInt(u14))
                    return error.InvalidMidiCiPropertyChunkSequence;
                slot.next_chunk += 1;
            }
            return message;
        }

        pub fn accept(self: *Self, message: anytype) !ReceiveResult {
            if (!message.valid()) return error.InvalidMidiCiPropertyData;
            if (message.kind == .notify)
                return error.MidiCiPropertyNotifyStatusRequired;
            const slot = try self.correlatedSlot(message);
            if (slot.state != .pending)
                return error.InvalidMidiCiPropertySessionState;
            if (message.kind != replyKind(slot.request_kind))
                return error.MidiCiPropertyReplyKindMismatch;
            const result = try slot.response.push(message);
            return switch (result) {
                .more => .{ .more = message.request_id },
                .complete => result_value: {
                    slot.state = .complete;
                    break :result_value .{ .complete = message.request_id };
                },
                .aborted => result_value: {
                    slot.state = .aborted;
                    break :result_value .{ .aborted = message.request_id };
                },
            };
        }

        pub fn acceptNotify(
            self: *Self,
            message: anytype,
            status: property_json.NotifyStatus,
        ) !ReceiveResult {
            if (!message.valid()) return error.InvalidMidiCiPropertyData;
            if (message.kind != .notify)
                return error.MidiCiPropertyNotifyExpected;
            if (message.total_chunks != 1 or
                message.chunk_number != 1 or
                message.data_count != 0)
                return error.InvalidMidiCiPropertyNotify;
            const expected_header: []const u8 = switch (status) {
                .timeout_wait => "{\"status\":100}",
                .terminate => "{\"status\":144}",
                .timeout => "{\"status\":408}",
            };
            if (!std.mem.eql(u8, message.header(), expected_header))
                return error.MidiCiPropertyNotifyStatusMismatch;
            const slot = try self.correlatedSlot(message);
            if (slot.state != .pending)
                return error.InvalidMidiCiPropertySessionState;
            return switch (status) {
                .timeout_wait => .{ .timeout_wait = message.request_id },
                .terminate => result_value: {
                    try self.release(message.request_id);
                    break :result_value .{ .terminated = message.request_id };
                },
                .timeout => result_value: {
                    try self.release(message.request_id);
                    break :result_value .{ .timed_out = message.request_id };
                },
            };
        }

        pub fn response(self: *const Self, request_id: u7) !*const Reassembly {
            const slot = try self.activeSlot(request_id);
            if (slot.state != .complete and slot.state != .aborted)
                return error.MidiCiPropertyResponseIncomplete;
            return &slot.response;
        }

        pub fn release(self: *Self, request_id: u7) !void {
            _ = try self.mutableActiveSlot(request_id);
            try self.request_ids.release(request_id);
            self.slots[request_id] = .{};
        }

        pub fn cancel(self: *Self, request_id: u7) !void {
            try self.release(request_id);
        }

        pub fn releaseRemote(self: *Self, remote: midi_ci.Muid) usize {
            if (!self.valid()) return 0;
            var released: usize = 0;
            for (&self.slots, 0..) |*slot, request_id| {
                const id: u7 = @intCast(request_id);
                if (self.request_ids.isActive(id) and
                    slot.destination.value == remote.value)
                {
                    self.request_ids.release(id) catch continue;
                    slot.* = .{};
                    released += 1;
                }
            }
            return released;
        }

        pub fn activeCount(self: *const Self) usize {
            if (!self.valid()) return 0;
            return self.request_ids.count();
        }

        pub fn validate(self: *const Self) !void {
            if (!self.source.validSource() or
                (self.version != 1 and self.version != 2) or
                !self.request_ids.valid())
            {
                return error.InvalidMidiCiPropertySessionState;
            }
            for (&self.slots, 0..) |*slot, index| {
                const request_id: u7 = @intCast(index);
                const active = self.request_ids.isActive(request_id);
                if (active == (slot.state == .unused))
                    return error.InvalidMidiCiPropertySessionState;
                if (!active) continue;
                if (!slot.destination.validSource() or
                    slot.destination.value == self.source.value or
                    !requestKind(slot.request_kind) or
                    slot.version != self.version or
                    !slot.response.valid())
                {
                    return error.InvalidMidiCiPropertySessionState;
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        fn correlatedSlot(self: *Self, message: anytype) !*Slot {
            if (message.destination.value != self.source.value)
                return error.MidiCiMuidMismatch;
            const slot = try self.mutableActiveSlot(message.request_id);
            if (message.source.value != slot.destination.value or
                message.version != slot.version)
                return error.MidiCiPropertyReplyMismatch;
            return slot;
        }

        fn activeSlot(self: *const Self, request_id: u7) !*const Slot {
            try self.validate();
            if (!self.request_ids.isActive(request_id))
                return error.InvalidMidiCiPropertyRequestId;
            return &self.slots[request_id];
        }

        fn mutableActiveSlot(self: *Self, request_id: u7) !*Slot {
            try self.validate();
            if (!self.request_ids.isActive(request_id))
                return error.InvalidMidiCiPropertyRequestId;
            return &self.slots[request_id];
        }
    };
}

pub fn Responder(
    comptime capacity: usize,
    comptime header_capacity: usize,
    comptime data_capacity: usize,
) type {
    if (capacity == 0 or capacity > 127)
        @compileError("MIDI-CI Property Exchange session capacity must be 1 through 127");
    const Reassembly = property.Reassembler(header_capacity, data_capacity);
    const Message = property.DataMessage(header_capacity, data_capacity);
    return struct {
        const Self = @This();
        pub const DataMessage = Message;

        const Slot = struct {
            active: bool = false,
            request: Reassembly = .{},
            response_started: bool = false,
            response_declared_total: u14 = 0,
            response_next_chunk: u14 = 1,
        };

        source: midi_ci.Muid,
        slots: [capacity]Slot = [_]Slot{.{}} ** capacity,
        active_count: usize = 0,

        pub fn init(source: midi_ci.Muid) !Self {
            if (!source.validSource()) return error.InvalidMidiCiMuid;
            return .{ .source = source };
        }

        pub fn push(self: *Self, message: anytype) !ReceiveResult {
            try self.validate();
            if (!message.valid()) return error.InvalidMidiCiPropertyData;
            if (!requestKind(message.kind))
                return error.InvalidMidiCiPropertyRequestKind;
            if (message.destination.value != self.source.value or
                message.source.value == self.source.value)
                return error.MidiCiMuidMismatch;

            if (self.find(message.source, message.request_id)) |handle| {
                const slot = &self.slots[handle];
                if (slot.request.complete)
                    return error.InvalidMidiCiPropertySessionState;
                return receiveInto(slot, message, @intCast(handle));
            }

            const handle = self.emptySlot() orelse
                return error.MidiCiPropertyResponderCapacityExceeded;
            var reassembly = Reassembly{};
            const result = try reassembly.push(message);
            self.slots[handle] = .{ .active = true, .request = reassembly };
            self.active_count += 1;
            return receiveResult(result, @intCast(handle));
        }

        pub fn request(self: *const Self, handle: u7) !*const Reassembly {
            const slot = try self.activeSlot(handle);
            if (!slot.request.complete)
                return error.MidiCiPropertyRequestIncomplete;
            return &slot.request;
        }

        pub fn reply(
            self: *Self,
            handle: u7,
            header: []const u8,
            total_chunks: u14,
            data: []const u8,
        ) !Message {
            const slot = try self.mutableActiveSlot(handle);
            if (!slot.request.complete or slot.request.aborted)
                return error.InvalidMidiCiPropertySessionState;
            const chunk_number = slot.response_next_chunk;
            if (slot.response_started and header.len != 0)
                return error.InvalidMidiCiPropertyChunkSequence;
            if (slot.response_started) {
                if (slot.response_declared_total != 0) {
                    if (total_chunks != slot.response_declared_total)
                        return error.InvalidMidiCiPropertyChunkSequence;
                } else if (total_chunks != 0 and total_chunks != chunk_number) {
                    return error.InvalidMidiCiPropertyChunkSequence;
                }
            } else if (chunk_number != 1) {
                return error.InvalidMidiCiPropertySessionState;
            }

            const message = try Message.init(
                replyKind(slot.request.kind),
                slot.request.version,
                self.source,
                slot.request.source,
                slot.request.request_id,
                header,
                total_chunks,
                chunk_number,
                data,
            );
            const final = total_chunks != 0 and total_chunks == chunk_number;
            if (final) {
                self.release(handle) catch return error.InvalidMidiCiPropertySessionState;
            } else {
                if (chunk_number == std.math.maxInt(u14))
                    return error.InvalidMidiCiPropertyChunkSequence;
                slot.response_started = true;
                slot.response_declared_total = total_chunks;
                slot.response_next_chunk += 1;
            }
            return message;
        }

        pub fn release(self: *Self, handle: u7) !void {
            try self.validate();
            _ = try self.mutableActiveSlot(handle);
            self.slots[handle] = .{};
            self.active_count -= 1;
        }

        pub fn releaseRemote(self: *Self, remote: midi_ci.Muid) usize {
            var released: usize = 0;
            for (&self.slots) |*slot| {
                if (slot.active and slot.request.source.value == remote.value) {
                    slot.* = .{};
                    released += 1;
                }
            }
            self.active_count = self.countActiveSlots();
            return released;
        }

        pub fn activeCount(self: *const Self) usize {
            return self.countActiveSlots();
        }

        pub fn validate(self: *const Self) !void {
            try self.validateCount();
            if (!self.source.validSource())
                return error.InvalidMidiCiPropertyResponderState;
            for (self.slots, 0..) |slot, index| {
                if (!slot.active) continue;
                if (!slot.request.valid() or
                    !slot.request.started or
                    !slot.request.source.validSource() or
                    slot.request.source.value == self.source.value or
                    slot.request.destination.value != self.source.value or
                    !requestKind(slot.request.kind) or
                    (slot.request.version != 1 and slot.request.version != 2))
                {
                    return error.InvalidMidiCiPropertyResponderState;
                }
                if (slot.response_started) {
                    if (slot.response_next_chunk < 2)
                        return error.InvalidMidiCiPropertyResponderState;
                } else if (slot.response_declared_total != 0 or
                    slot.response_next_chunk != 1)
                {
                    return error.InvalidMidiCiPropertyResponderState;
                }
                for (self.slots[0..index]) |earlier| {
                    if (earlier.active and
                        earlier.request.source.value == slot.request.source.value and
                        earlier.request.request_id == slot.request.request_id)
                    {
                        return error.InvalidMidiCiPropertyResponderState;
                    }
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        fn find(self: *const Self, source: midi_ci.Muid, request_id: u7) ?usize {
            for (self.slots, 0..) |slot, index| {
                if (slot.active and
                    slot.request.source.value == source.value and
                    slot.request.request_id == request_id)
                    return index;
            }
            return null;
        }

        fn emptySlot(self: *const Self) ?usize {
            for (self.slots, 0..) |slot, index| {
                if (!slot.active) return index;
            }
            return null;
        }

        fn validateCount(self: *const Self) !void {
            if (self.active_count != self.countActiveSlots())
                return error.InvalidMidiCiPropertyResponderState;
        }

        fn countActiveSlots(self: *const Self) usize {
            var result: usize = 0;
            for (self.slots) |slot| {
                if (slot.active) result += 1;
            }
            return result;
        }

        fn activeSlot(self: *const Self, handle: u7) !*const Slot {
            try self.validate();
            if (handle >= capacity or !self.slots[handle].active)
                return error.InvalidMidiCiPropertyRequestHandle;
            return &self.slots[handle];
        }

        fn mutableActiveSlot(self: *Self, handle: u7) !*Slot {
            try self.validate();
            if (handle >= capacity or !self.slots[handle].active)
                return error.InvalidMidiCiPropertyRequestHandle;
            return &self.slots[handle];
        }

        fn receiveInto(slot: *Slot, message: anytype, handle: u7) !ReceiveResult {
            const result = try slot.request.push(message);
            return receiveResult(result, handle);
        }
    };
}

fn requestKind(kind: property.DataKind) bool {
    return kind == .get or kind == .set or kind == .subscription;
}

fn replyKind(kind: property.DataKind) property.DataKind {
    return switch (kind) {
        .get => .get_reply,
        .set => .set_reply,
        .subscription => .subscription_reply,
        else => kind,
    };
}

fn receiveResult(result: property.ChunkResult, handle: u7) ReceiveResult {
    return switch (result) {
        .more => .{ .more = handle },
        .complete => .{ .complete = handle },
        .aborted => .{ .aborted = handle },
    };
}

test "Property Exchange sessions transact chunked get and set data" {
    const SessionInitiator = Initiator(2, 32, 64);
    const SessionResponder = Responder(2, 32, 64);
    var initiator = try SessionInitiator.init(try midi_ci.Muid.init(1), 2);
    var responder = try SessionResponder.init(try midi_ci.Muid.init(2));

    try initiator.validate();
    initiator.slots[0].state = .pending;
    try std.testing.expect(!initiator.valid());
    try std.testing.expectEqual(@as(usize, 0), initiator.activeCount());
    try std.testing.expectError(
        error.InvalidMidiCiPropertySessionState,
        initiator.begin(
            .get,
            responder.source,
            "{\"resource\":\"DeviceInfo\"}",
            1,
            &.{},
        ),
    );
    initiator.slots[0] = .{};
    try initiator.validate();

    const get = try initiator.begin(
        .get,
        responder.source,
        "{\"resource\":\"DeviceInfo\"}",
        1,
        &.{},
    );
    const get_handle = switch (try responder.push(get)) {
        .complete => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const request = try responder.request(get_handle);
    try std.testing.expectEqual(property.DataKind.get, request.kind);
    const first_reply = try responder.reply(
        get_handle,
        "{\"status\":200}",
        2,
        "{\"manufacturer\":\"Acme\",",
    );
    try std.testing.expectEqual(
        ReceiveResult{ .more = get.request_id },
        try initiator.accept(first_reply),
    );
    const second_reply = try responder.reply(
        get_handle,
        &.{},
        2,
        "\"model\":\"One\"}",
    );
    try std.testing.expectEqual(
        ReceiveResult{ .complete = get.request_id },
        try initiator.accept(second_reply),
    );
    const response = try initiator.response(get.request_id);
    try std.testing.expectEqualSlices(
        u8,
        "{\"manufacturer\":\"Acme\",\"model\":\"One\"}",
        response.data(),
    );
    try initiator.release(get.request_id);

    const first_set = try initiator.begin(
        .set,
        responder.source,
        "{\"resource\":\"State\"}",
        2,
        "abc",
    );
    try std.testing.expectEqual(
        ReceiveResult{ .more = 0 },
        try responder.push(first_set),
    );
    const second_set = try initiator.continueRequest(
        first_set.request_id,
        2,
        "def",
    );
    const set_handle = switch (try responder.push(second_set)) {
        .complete => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualSlices(
        u8,
        "abcdef",
        (try responder.request(set_handle)).data(),
    );
    const set_reply = try responder.reply(
        set_handle,
        "{\"status\":200}",
        1,
        &.{},
    );
    try std.testing.expectEqual(
        ReceiveResult{ .complete = first_set.request_id },
        try initiator.accept(set_reply),
    );
}

test "Property Exchange initiator correlates notifications and failures transactionally" {
    const Session = Initiator(2, 16, 16);
    const Message = property.DataMessage(16, 16);
    const local = try midi_ci.Muid.init(1);
    const remote = try midi_ci.Muid.init(2);
    var session = try Session.init(local, 2);
    const request = try session.begin(.get, remote, "{}", 1, &.{});
    const wrong = try Message.init(
        .get_reply,
        2,
        try midi_ci.Muid.init(3),
        local,
        request.request_id,
        "{}",
        1,
        1,
        &.{},
    );
    try std.testing.expectError(
        error.MidiCiPropertyReplyMismatch,
        session.accept(wrong),
    );
    try std.testing.expectEqual(@as(usize, 1), session.activeCount());

    const notify = try Message.init(
        .notify,
        2,
        remote,
        local,
        request.request_id,
        "{\"status\":100}",
        1,
        1,
        &.{},
    );
    try std.testing.expectEqual(
        ReceiveResult{ .timeout_wait = request.request_id },
        try session.acceptNotify(notify, .timeout_wait),
    );
    try std.testing.expectEqual(@as(usize, 1), session.activeCount());
    try std.testing.expectError(
        error.MidiCiPropertyNotifyStatusMismatch,
        session.acceptNotify(notify, .timeout),
    );
    const timeout = try Message.init(
        .notify,
        2,
        remote,
        local,
        request.request_id,
        "{\"status\":408}",
        1,
        1,
        &.{},
    );
    try std.testing.expectEqual(
        ReceiveResult{ .timed_out = request.request_id },
        try session.acceptNotify(timeout, .timeout),
    );
    try std.testing.expectEqual(@as(usize, 0), session.activeCount());
}

test "Property Exchange sessions enforce capacity and lifecycle" {
    const SessionInitiator = Initiator(1, 8, 8);
    const SessionResponder = Responder(1, 8, 8);
    const local = try midi_ci.Muid.init(1);
    const remote = try midi_ci.Muid.init(2);
    var initiator = try SessionInitiator.init(local, 2);
    const first = try initiator.begin(.set, remote, "{}", 0, "a");
    try std.testing.expectError(
        error.MidiCiPropertyRequestIdsExhausted,
        initiator.begin(.get, remote, "{}", 1, &.{}),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyChunkSequence,
        initiator.continueRequest(first.request_id, 4, "b"),
    );
    try std.testing.expectEqual(@as(usize, 1), initiator.activeCount());
    try initiator.cancel(first.request_id);

    var responder = try SessionResponder.init(remote);
    const request = try property.DataMessage(8, 8).init(
        .set,
        2,
        local,
        remote,
        7,
        "{}",
        2,
        1,
        "a",
    );
    _ = try responder.push(request);
    const other = try property.DataMessage(8, 8).init(
        .get,
        2,
        try midi_ci.Muid.init(3),
        remote,
        1,
        "{}",
        1,
        1,
        &.{},
    );
    try std.testing.expectError(
        error.MidiCiPropertyResponderCapacityExceeded,
        responder.push(other),
    );
    try std.testing.expectEqual(@as(usize, 1), responder.activeCount());
}

test "Property Exchange subscription registry owns lifecycle identifiers" {
    const Registry = SubscriptionRegistry(2);
    const remote = try midi_ci.Muid.init(2);
    var registry = Registry{};
    for (registry.entries) |entry|
        try std.testing.expectEqualDeep(@TypeOf(entry){}, entry);
    const handle = try registry.register(remote, "ChannelList", "sub_1");
    const stored = registry.entries[handle];
    for (stored.resource_storage[stored.resource_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (stored.id_storage[stored.id_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqualStrings(
        "ChannelList",
        (try registry.get(handle)).resource,
    );
    try std.testing.expectEqual(
        SubscriptionUpdate{ .partial = handle },
        try registry.accept(remote, .{
            .command = .partial,
            .subscribe_id = "sub_1",
        }),
    );
    try std.testing.expectError(
        error.MidiCiPropertySubscriptionAlreadyExists,
        registry.register(remote, "DeviceInfo", "sub_1"),
    );
    const other = try registry.register(remote, "DeviceInfo", "sub_2");
    try std.testing.expectError(
        error.MidiCiPropertySubscriptionCapacityExceeded,
        registry.register(try midi_ci.Muid.init(3), "State", "sub_3"),
    );
    try std.testing.expectEqual(
        SubscriptionUpdate{ .ended = handle },
        try registry.accept(remote, .{
            .command = .end,
            .subscribe_id = "sub_1",
        }),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionHandle,
        registry.get(handle),
    );
    try std.testing.expectEqualDeep(
        @TypeOf(registry.entries[handle]){},
        registry.entries[handle],
    );
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());
    try std.testing.expectEqual(@as(usize, 1), registry.releaseRemote(remote));
    try std.testing.expectEqual(@as(usize, 0), registry.activeCount());
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionHandle,
        registry.get(other),
    );
    try std.testing.expectEqualDeep(
        @TypeOf(registry.entries[other]){},
        registry.entries[other],
    );
}

test "Property Exchange registries contain malformed retained counts" {
    const Registry = SubscriptionRegistry(2);
    const SessionResponder = Responder(2, 16, 16);
    const Message = property.DataMessage(16, 16);
    const local = try midi_ci.Muid.init(1);
    const remote = try midi_ci.Muid.init(2);

    var registry = Registry{};
    const handle = try registry.register(remote, "State", "sub_1");
    registry.entries[handle].resource_storage[0] = '_';
    try std.testing.expect(!registry.valid());
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionState,
        registry.get(handle),
    );
    registry.entries[handle].resource_storage[0] = 'S';
    const duplicate = try registry.register(remote, "DeviceInfo", "sub_2");
    registry.entries[duplicate].id_storage[4] = '1';
    try std.testing.expect(!registry.valid());
    try std.testing.expectEqual(
        @as(?u7, null),
        registry.findHandle(remote, "sub_1"),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionState,
        registry.release(duplicate),
    );
    registry.entries[duplicate].id_storage[4] = '2';
    try registry.validate();
    try registry.release(duplicate);
    registry.active_count = std.math.maxInt(usize);
    try std.testing.expect(!registry.valid());
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionState,
        registry.register(remote, "DeviceInfo", "sub_2"),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionState,
        registry.release(handle),
    );
    try std.testing.expectEqual(@as(usize, 1), registry.releaseRemote(remote));
    try std.testing.expect(registry.valid());

    var responder = try SessionResponder.init(local);
    const request = try Message.init(
        .get,
        2,
        remote,
        local,
        7,
        "{}",
        1,
        1,
        &.{},
    );
    const request_handle = switch (try responder.push(request)) {
        .complete => |value| value,
        else => return error.TestUnexpectedResult,
    };
    responder.active_count = std.math.maxInt(usize);
    try std.testing.expectEqual(@as(usize, 1), responder.activeCount());
    try std.testing.expectError(
        error.InvalidMidiCiPropertyResponderState,
        responder.release(request_handle),
    );
    try std.testing.expectEqual(@as(usize, 1), responder.releaseRemote(remote));
    try std.testing.expectEqual(@as(usize, 0), responder.activeCount());

    const malformed_handle = switch (try responder.push(request)) {
        .complete => |value| value,
        else => return error.TestUnexpectedResult,
    };
    responder.slots[malformed_handle].request.header_count = 17;
    try std.testing.expect(!responder.valid());
    try std.testing.expectError(
        error.InvalidMidiCiPropertyResponderState,
        responder.request(malformed_handle),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyResponderState,
        responder.push(request),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyResponderState,
        responder.release(malformed_handle),
    );
    try std.testing.expectEqual(@as(usize, 1), responder.releaseRemote(remote));
    try responder.validate();
}

test "Property Exchange sessions release all state for a remote" {
    const SessionInitiator = Initiator(3, 32, 64);
    const SessionResponder = Responder(3, 32, 64);
    const Message = property.DataMessage(32, 64);
    const local = try midi_ci.Muid.init(1);
    const first_remote = try midi_ci.Muid.init(2);
    const second_remote = try midi_ci.Muid.init(3);
    var initiator = try SessionInitiator.init(local, 2);
    var responder = try SessionResponder.init(local);

    _ = try initiator.begin(.get, first_remote, "{}", 1, &.{});
    _ = try initiator.begin(.get, second_remote, "{}", 1, &.{});
    _ = try responder.push(try Message.init(
        .get,
        2,
        first_remote,
        local,
        4,
        "{}",
        1,
        1,
        &.{},
    ));
    _ = try responder.push(try Message.init(
        .get,
        2,
        second_remote,
        local,
        5,
        "{}",
        1,
        1,
        &.{},
    ));

    try std.testing.expectEqual(@as(usize, 1), initiator.releaseRemote(first_remote));
    try std.testing.expectEqual(@as(usize, 1), responder.releaseRemote(first_remote));
    try std.testing.expectEqual(@as(usize, 1), initiator.activeCount());
    try std.testing.expectEqual(@as(usize, 1), responder.activeCount());
}
