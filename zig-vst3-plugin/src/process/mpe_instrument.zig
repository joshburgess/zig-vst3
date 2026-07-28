const std = @import("std");
const midi1 = @import("midi1.zig");
const mpe = @import("mpe.zig");

pub const TrackingMode = enum {
    last,
    lowest,
    highest,
    all,
};

pub const KeyState = enum {
    key_down,
    sustained,
    key_down_and_sustained,

    pub fn isKeyDown(self: KeyState) bool {
        return self == .key_down or self == .key_down_and_sustained;
    }
};

pub const Note = struct {
    id: u64,
    channel_index: u8,
    initial_note: u7,
    note_on_velocity: u7,
    note_off_velocity: u7 = 0,
    pitch_bend: u14 = 8192,
    pressure: u7 = 64,
    initial_timbre: u7 = 64,
    timbre: u7 = 64,
    total_pitch_bend_semitones: f32 = 0.0,
    key_state: KeyState = .key_down,
    serial: u64,
};

pub const ChangeKind = enum {
    ignored,
    note_added,
    note_released,
    expression,
    sustain,
};

pub const Change = struct {
    kind: ChangeKind = .ignored,
    affected_count: usize = 0,
    note_id: ?u64 = null,

    pub fn changed(self: Change) bool {
        return self.kind != .ignored;
    }
};

const Expression = enum { pressure, timbre };

pub fn Instrument(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        layout: mpe.Layout,
        notes_storage: [capacity]Note = undefined,
        note_count: usize = 0,
        pitch_tracking: TrackingMode = .last,
        pressure_tracking: TrackingMode = .last,
        timbre_tracking: TrackingMode = .last,
        manager_pitch_bend: [2]u14 = .{ 8192, 8192 },
        sustain_down: [2]bool = .{ false, false },
        next_id: u64 = 1,
        next_serial: u64 = 1,

        pub fn init(layout: mpe.Layout) !Self {
            try layout.validate();
            return .{ .layout = layout };
        }

        pub fn reset(self: *Self, layout: mpe.Layout) !void {
            try layout.validate();
            self.* = .{ .layout = layout };
        }

        pub fn setLayout(self: *Self, layout: mpe.Layout) !void {
            try self.reset(layout);
        }

        pub fn valid(self: *const Self) bool {
            if (!self.layout.valid() or self.note_count > capacity) return false;
            for (self.notes_storage[0..self.note_count], 0..) |active_note, index| {
                if (active_note.id == 0 or active_note.serial == 0 or
                    self.layout.memberZone(active_note.channel_index) == null or
                    !std.math.isFinite(active_note.total_pitch_bend_semitones))
                {
                    return false;
                }
                for (self.notes_storage[0..index]) |previous_note| {
                    if (previous_note.id == active_note.id or previous_note.serial == active_note.serial) {
                        return false;
                    }
                }
            }
            return true;
        }

        pub fn notes(self: *const Self) []const Note {
            if (!self.valid()) return &.{};
            return self.notes_storage[0..self.note_count];
        }

        pub fn note(self: *const Self, id: u64) ?*const Note {
            for (self.notes()) |*active_note| {
                if (active_note.id == id) return active_note;
            }
            return null;
        }

        pub fn process(self: *Self, message: midi1.Message) !Change {
            if (!self.valid()) return error.InvalidMpeInstrumentState;
            if (!message.valid()) return error.InvalidMidiMessage;

            const channel_index = message.channel() orelse return error.InvalidMidiMessage;
            const kind = message.kind() orelse return error.InvalidMidiMessage;
            return switch (kind) {
                .note_on => if (message.data2().? == 0)
                    try self.releaseNote(channel_index, @intCast(message.data1().?), 0)
                else
                    try self.addNote(channel_index, @intCast(message.data1().?), @intCast(message.data2().?)),
                .note_off => try self.releaseNote(
                    channel_index,
                    @intCast(message.data1().?),
                    @intCast(message.data2().?),
                ),
                .pitch_bend => self.applyPitchBend(channel_index, message.pitchBendValue().?),
                .channel_pressure => self.applyPressure(channel_index, @intCast(message.data1().?)),
                .polyphonic_key_pressure => self.applyPolyphonicPressure(
                    channel_index,
                    @intCast(message.data1().?),
                    @intCast(message.data2().?),
                ),
                .control_change => try self.applyControlChange(
                    channel_index,
                    message.data1().?,
                    @intCast(message.data2().?),
                ),
                .program_change => .{},
            };
        }

        pub fn allNotesOff(self: *Self) usize {
            if (!self.valid()) return 0;
            const released_count = self.note_count;
            self.note_count = 0;
            self.sustain_down = .{ false, false };
            return released_count;
        }

        fn addNote(self: *Self, channel_index: u8, note_number: u7, velocity: u7) !Change {
            const zone_type = self.layout.memberZone(channel_index) orelse return .{};
            if (self.note_count == capacity) return error.MpeNoteCapacityExceeded;
            if (self.next_id == 0 or self.next_serial == 0) return error.MpeIdentifierExhausted;

            const id = self.next_id;
            const serial = self.next_serial;
            self.next_id +%= 1;
            self.next_serial +%= 1;
            const state: KeyState = if (self.sustain_down[zoneIndex(zone_type)])
                .key_down_and_sustained
            else
                .key_down;
            self.notes_storage[self.note_count] = .{
                .id = id,
                .channel_index = channel_index,
                .initial_note = note_number,
                .note_on_velocity = velocity,
                .key_state = state,
                .serial = serial,
            };
            self.note_count += 1;
            self.updateTotalPitchBend(&self.notes_storage[self.note_count - 1], zone_type);
            return .{ .kind = .note_added, .affected_count = 1, .note_id = id };
        }

        fn releaseNote(
            self: *Self,
            channel_index: u8,
            note_number: u7,
            velocity: u7,
        ) !Change {
            const zone_type = self.layout.memberZone(channel_index) orelse return .{};
            const index = self.mostRecentMatchingNote(channel_index, note_number) orelse return .{};
            const id = self.notes_storage[index].id;
            if (self.sustain_down[zoneIndex(zone_type)]) {
                self.notes_storage[index].note_off_velocity = velocity;
                self.notes_storage[index].key_state = .sustained;
            } else {
                self.removeNote(index);
            }
            return .{ .kind = .note_released, .affected_count = 1, .note_id = id };
        }

        fn applyPitchBend(self: *Self, channel_index: u8, value: u14) Change {
            if (self.layout.masterZone(channel_index)) |zone_type| {
                self.manager_pitch_bend[zoneIndex(zone_type)] = value;
                var affected: usize = 0;
                for (self.notes_storage[0..self.note_count]) |*active_note| {
                    if (self.layout.memberZone(active_note.channel_index) == zone_type) {
                        self.updateTotalPitchBend(active_note, zone_type);
                        affected += 1;
                    }
                }
                return expressionChange(affected);
            }
            const zone_type = self.layout.memberZone(channel_index) orelse return .{};
            var affected: usize = 0;
            for (self.notes_storage[0..self.note_count]) |*active_note| {
                if (active_note.channel_index == channel_index and
                    self.selected(active_note, channel_index, self.pitch_tracking))
                {
                    active_note.pitch_bend = value;
                    self.updateTotalPitchBend(active_note, zone_type);
                    affected += 1;
                }
            }
            return expressionChange(affected);
        }

        fn applyPressure(self: *Self, channel_index: u8, value: u7) Change {
            if (self.layout.masterZone(channel_index)) |zone_type| {
                return self.broadcastExpression(zone_type, .pressure, value);
            }
            if (self.layout.memberZone(channel_index) == null) return .{};
            return self.applyTrackedExpression(channel_index, .pressure, value, self.pressure_tracking);
        }

        fn applyPolyphonicPressure(
            self: *Self,
            channel_index: u8,
            note_number: u7,
            value: u7,
        ) Change {
            if (self.layout.memberZone(channel_index) == null) return .{};
            var affected: usize = 0;
            for (self.notes_storage[0..self.note_count]) |*active_note| {
                if (active_note.channel_index == channel_index and
                    active_note.initial_note == note_number)
                {
                    active_note.pressure = value;
                    affected += 1;
                }
            }
            return expressionChange(affected);
        }

        fn applyControlChange(
            self: *Self,
            channel_index: u8,
            controller: u8,
            value: u7,
        ) !Change {
            if (controller == 74) {
                if (self.layout.masterZone(channel_index)) |zone_type| {
                    return self.broadcastExpression(zone_type, .timbre, value);
                }
                if (self.layout.memberZone(channel_index) == null) return .{};
                return self.applyTrackedExpression(channel_index, .timbre, value, self.timbre_tracking);
            }
            if (controller == 64) {
                const zone_type = self.layout.masterZone(channel_index) orelse return .{};
                return self.setSustain(zone_type, value >= 64);
            }
            return .{};
        }

        fn broadcastExpression(
            self: *Self,
            zone_type: mpe.ZoneType,
            expression: Expression,
            value: u7,
        ) Change {
            var affected: usize = 0;
            for (self.notes_storage[0..self.note_count]) |*active_note| {
                if (self.layout.memberZone(active_note.channel_index) == zone_type) {
                    setExpression(active_note, expression, value);
                    affected += 1;
                }
            }
            return expressionChange(affected);
        }

        fn applyTrackedExpression(
            self: *Self,
            channel_index: u8,
            expression: Expression,
            value: u7,
            mode: TrackingMode,
        ) Change {
            var affected: usize = 0;
            for (self.notes_storage[0..self.note_count]) |*active_note| {
                if (active_note.channel_index == channel_index and
                    self.selected(active_note, channel_index, mode))
                {
                    setExpression(active_note, expression, value);
                    affected += 1;
                }
            }
            return expressionChange(affected);
        }

        fn setSustain(self: *Self, zone_type: mpe.ZoneType, down: bool) Change {
            const zone_index = zoneIndex(zone_type);
            if (self.sustain_down[zone_index] == down) return .{};
            self.sustain_down[zone_index] = down;

            var affected: usize = 0;
            if (down) {
                for (self.notes_storage[0..self.note_count]) |*active_note| {
                    if (self.layout.memberZone(active_note.channel_index) == zone_type and
                        active_note.key_state == .key_down)
                    {
                        active_note.key_state = .key_down_and_sustained;
                        affected += 1;
                    }
                }
            } else {
                var index: usize = 0;
                while (index < self.note_count) {
                    const active_note = &self.notes_storage[index];
                    if (self.layout.memberZone(active_note.channel_index) != zone_type) {
                        index += 1;
                    } else switch (active_note.key_state) {
                        .sustained => {
                            self.removeNote(index);
                            affected += 1;
                        },
                        .key_down_and_sustained => {
                            active_note.key_state = .key_down;
                            affected += 1;
                            index += 1;
                        },
                        .key_down => index += 1,
                    }
                }
            }
            return .{ .kind = .sustain, .affected_count = affected };
        }

        fn selected(
            self: *const Self,
            candidate: *const Note,
            channel_index: u8,
            mode: TrackingMode,
        ) bool {
            if (mode == .all) return true;
            var selected_note: ?*const Note = null;
            for (self.notes()) |*active_note| {
                if (active_note.channel_index != channel_index or !active_note.key_state.isKeyDown()) continue;
                if (selected_note == null or preferred(active_note, selected_note.?, mode)) {
                    selected_note = active_note;
                }
            }
            return selected_note != null and selected_note.?.id == candidate.id;
        }

        fn mostRecentMatchingNote(
            self: *const Self,
            channel_index: u8,
            note_number: u7,
        ) ?usize {
            var selected_index: ?usize = null;
            for (self.notes(), 0..) |active_note, index| {
                if (active_note.channel_index != channel_index or
                    active_note.initial_note != note_number or
                    !active_note.key_state.isKeyDown())
                {
                    continue;
                }
                if (selected_index == null or
                    active_note.serial > self.notes_storage[selected_index.?].serial)
                {
                    selected_index = index;
                }
            }
            return selected_index;
        }

        fn updateTotalPitchBend(
            self: *const Self,
            active_note: *Note,
            zone_type: mpe.ZoneType,
        ) void {
            const zone = switch (zone_type) {
                .lower => self.layout.lower,
                .upper => self.layout.upper,
            };
            const note_bend = midi1.normalizedPitchBend(active_note.pitch_bend) *
                @as(f32, @floatFromInt(zone.per_note_pitch_bend_range));
            const manager_bend = midi1.normalizedPitchBend(
                self.manager_pitch_bend[zoneIndex(zone_type)],
            ) * @as(f32, @floatFromInt(zone.master_pitch_bend_range));
            active_note.total_pitch_bend_semitones = note_bend + manager_bend;
        }

        fn removeNote(self: *Self, index: usize) void {
            self.note_count -= 1;
            if (index != self.note_count) {
                self.notes_storage[index] = self.notes_storage[self.note_count];
            }
        }
    };
}

pub const StealPolicy = enum {
    reject,
    oldest,
};

pub const Assignment = struct {
    id: u64,
    note: u7,
    channel_index: u8,
    serial: u64,
};

pub const Allocation = struct {
    assignment: Assignment,
    stolen: ?Assignment = null,
};

pub const MemberChannelAllocator = struct {
    zone: mpe.Zone,
    assignments_storage: [15]Assignment = undefined,
    assignment_count: usize = 0,
    next_id: u64 = 1,
    next_serial: u64 = 1,

    pub fn init(zone: mpe.Zone) !MemberChannelAllocator {
        try zone.validate();
        return .{ .zone = zone };
    }

    pub fn reset(self: *MemberChannelAllocator, zone: mpe.Zone) !void {
        try zone.validate();
        self.* = .{ .zone = zone };
    }

    pub fn valid(self: *const MemberChannelAllocator) bool {
        if (!self.zone.valid() or
            self.assignment_count > self.assignments_storage.len or
            self.assignment_count > self.zone.member_channel_count)
        {
            return false;
        }
        for (self.assignments_storage[0..self.assignment_count], 0..) |active_assignment, index| {
            if (active_assignment.id == 0 or active_assignment.serial == 0 or
                !self.zone.isMemberChannel(active_assignment.channel_index))
            {
                return false;
            }
            for (self.assignments_storage[0..index]) |previous_assignment| {
                if (previous_assignment.id == active_assignment.id or
                    previous_assignment.serial == active_assignment.serial or
                    previous_assignment.channel_index == active_assignment.channel_index)
                {
                    return false;
                }
            }
        }
        return true;
    }

    pub fn assignments(self: *const MemberChannelAllocator) []const Assignment {
        if (!self.valid()) return &.{};
        return self.assignments_storage[0..self.assignment_count];
    }

    pub fn assignment(self: *const MemberChannelAllocator, id: u64) ?*const Assignment {
        for (self.assignments()) |*active_assignment| {
            if (active_assignment.id == id) return active_assignment;
        }
        return null;
    }

    pub fn allocate(
        self: *MemberChannelAllocator,
        note_number: u7,
        policy: StealPolicy,
    ) !Allocation {
        if (!self.valid()) return error.InvalidMpeAllocatorState;
        if (!self.zone.active()) return error.NoMpeMemberChannels;
        if (self.next_id == 0 or self.next_serial == 0) return error.MpeIdentifierExhausted;

        const id = self.next_id;
        const serial = self.next_serial;
        self.next_id +%= 1;
        self.next_serial +%= 1;

        if (self.firstFreeChannel()) |channel_index| {
            const active_assignment = Assignment{
                .id = id,
                .note = note_number,
                .channel_index = channel_index,
                .serial = serial,
            };
            self.assignments_storage[self.assignment_count] = active_assignment;
            self.assignment_count += 1;
            return .{ .assignment = active_assignment };
        }

        if (policy == .reject) {
            self.next_id -%= 1;
            self.next_serial -%= 1;
            return error.NoFreeMpeMemberChannel;
        }

        const oldest_index = self.oldestAssignmentIndex();
        const stolen = self.assignments_storage[oldest_index];
        const replacement = Assignment{
            .id = id,
            .note = note_number,
            .channel_index = stolen.channel_index,
            .serial = serial,
        };
        self.assignments_storage[oldest_index] = replacement;
        return .{ .assignment = replacement, .stolen = stolen };
    }

    pub fn release(self: *MemberChannelAllocator, id: u64) ?Assignment {
        if (!self.valid()) return null;
        for (self.assignments_storage[0..self.assignment_count], 0..) |active_assignment, index| {
            if (active_assignment.id != id) continue;
            self.assignment_count -= 1;
            if (index != self.assignment_count) {
                self.assignments_storage[index] = self.assignments_storage[self.assignment_count];
            }
            return active_assignment;
        }
        return null;
    }

    fn firstFreeChannel(self: *const MemberChannelAllocator) ?u8 {
        const first = self.zone.firstMemberChannel() orelse return null;
        const last = self.zone.lastMemberChannel() orelse return null;
        var channel_index = first;
        while (channel_index <= last) : (channel_index += 1) {
            var used = false;
            for (self.assignments()) |active_assignment| {
                if (active_assignment.channel_index == channel_index) {
                    used = true;
                    break;
                }
            }
            if (!used) return channel_index;
        }
        return null;
    }

    fn oldestAssignmentIndex(self: *const MemberChannelAllocator) usize {
        var oldest_index: usize = 0;
        for (self.assignments_storage[1..self.assignment_count], 1..) |active_assignment, index| {
            const oldest = self.assignments_storage[oldest_index];
            if (active_assignment.serial < oldest.serial or
                (active_assignment.serial == oldest.serial and
                    active_assignment.channel_index < oldest.channel_index))
            {
                oldest_index = index;
            }
        }
        return oldest_index;
    }
};

fn setExpression(active_note: *Note, expression: Expression, value: u7) void {
    switch (expression) {
        .pressure => active_note.pressure = value,
        .timbre => active_note.timbre = value,
    }
}

fn preferred(candidate: *const Note, current: *const Note, mode: TrackingMode) bool {
    return switch (mode) {
        .last => candidate.serial > current.serial,
        .lowest => candidate.initial_note < current.initial_note or
            (candidate.initial_note == current.initial_note and candidate.serial > current.serial),
        .highest => candidate.initial_note > current.initial_note or
            (candidate.initial_note == current.initial_note and candidate.serial > current.serial),
        .all => false,
    };
}

fn expressionChange(affected_count: usize) Change {
    if (affected_count == 0) return .{};
    return .{ .kind = .expression, .affected_count = affected_count };
}

fn zoneIndex(zone_type: mpe.ZoneType) usize {
    return @intFromEnum(zone_type);
}

test "MPE instrument tracks notes expression and combined pitch bend" {
    const TestInstrument = Instrument(8);
    var instrument = try TestInstrument.init(try mpe.Layout.init(
        try mpe.Zone.init(.lower, 4, 48, 2),
        try mpe.Zone.init(.upper, 0, 48, 2),
    ));

    const added = try instrument.process(try midi1.Message.noteOn(1, 60, 100));
    try std.testing.expectEqual(ChangeKind.note_added, added.kind);
    try std.testing.expectEqual(@as(usize, 1), instrument.notes().len);
    try std.testing.expectEqual(@as(u7, 64), instrument.notes()[0].pressure);

    const note_bend = try instrument.process(try midi1.Message.pitchBend(1, 16383));
    try std.testing.expectEqual(@as(usize, 1), note_bend.affected_count);
    try std.testing.expectApproxEqAbs(
        @as(f32, 48.0),
        instrument.notes()[0].total_pitch_bend_semitones,
        0.0001,
    );

    _ = try instrument.process(try midi1.Message.pitchBend(0, 0));
    try std.testing.expectApproxEqAbs(
        @as(f32, 46.0),
        instrument.notes()[0].total_pitch_bend_semitones,
        0.0001,
    );
    _ = try instrument.process(try midi1.Message.channelPressure(1, 99));
    _ = try instrument.process(try midi1.Message.controlChange(1, 74, 12));
    try std.testing.expectEqual(@as(u7, 99), instrument.notes()[0].pressure);
    try std.testing.expectEqual(@as(u7, 12), instrument.notes()[0].timbre);
}

test "MPE instrument applies tracking modes and manager broadcasts" {
    const TestInstrument = Instrument(8);
    var instrument = try TestInstrument.init(try mpe.Layout.init(
        try mpe.Zone.init(.lower, 3, 48, 2),
        try mpe.Zone.init(.upper, 0, 48, 2),
    ));
    _ = try instrument.process(try midi1.Message.noteOn(2, 72, 100));
    _ = try instrument.process(try midi1.Message.noteOn(2, 60, 90));

    instrument.pressure_tracking = .lowest;
    const pressure = try instrument.process(try midi1.Message.channelPressure(2, 80));
    try std.testing.expectEqual(@as(usize, 1), pressure.affected_count);
    try std.testing.expectEqual(@as(u7, 64), instrument.notes()[0].pressure);
    try std.testing.expectEqual(@as(u7, 80), instrument.notes()[1].pressure);

    instrument.timbre_tracking = .all;
    const timbre = try instrument.process(try midi1.Message.controlChange(2, 74, 20));
    try std.testing.expectEqual(@as(usize, 2), timbre.affected_count);
    const broadcast = try instrument.process(try midi1.Message.channelPressure(0, 30));
    try std.testing.expectEqual(@as(usize, 2), broadcast.affected_count);
    for (instrument.notes()) |active_note| {
        try std.testing.expectEqual(@as(u7, 30), active_note.pressure);
        try std.testing.expectEqual(@as(u7, 20), active_note.timbre);
    }
}

test "MPE instrument sustains and releases notes without allocation" {
    const TestInstrument = Instrument(4);
    var instrument = try TestInstrument.init(try mpe.Layout.init(
        try mpe.Zone.init(.lower, 2, 48, 2),
        try mpe.Zone.init(.upper, 0, 48, 2),
    ));
    const added = try instrument.process(try midi1.Message.noteOn(1, 60, 100));
    _ = try instrument.process(try midi1.Message.controlChange(0, 64, 127));
    try std.testing.expectEqual(KeyState.key_down_and_sustained, instrument.notes()[0].key_state);

    const released = try instrument.process(try midi1.Message.noteOff(1, 60, 45));
    try std.testing.expectEqual(added.note_id, released.note_id);
    try std.testing.expectEqual(@as(usize, 1), instrument.notes().len);
    try std.testing.expectEqual(KeyState.sustained, instrument.notes()[0].key_state);
    try std.testing.expectEqual(@as(u7, 45), instrument.notes()[0].note_off_velocity);

    const pedal_up = try instrument.process(try midi1.Message.controlChange(0, 64, 0));
    try std.testing.expectEqual(ChangeKind.sustain, pedal_up.kind);
    try std.testing.expectEqual(@as(usize, 1), pedal_up.affected_count);
    try std.testing.expectEqual(@as(usize, 0), instrument.notes().len);
}

test "MPE instrument rejects capacity overflow transactionally" {
    const TestInstrument = Instrument(1);
    var instrument = try TestInstrument.init(try mpe.Layout.init(
        try mpe.Zone.init(.lower, 1, 48, 2),
        try mpe.Zone.init(.upper, 0, 48, 2),
    ));
    _ = try instrument.process(try midi1.Message.noteOn(1, 60, 100));
    const before = instrument.notes()[0];
    try std.testing.expectError(
        error.MpeNoteCapacityExceeded,
        instrument.process(try midi1.Message.noteOn(1, 64, 100)),
    );
    try std.testing.expectEqual(@as(usize, 1), instrument.notes().len);
    try std.testing.expectEqualDeep(before, instrument.notes()[0]);
}

test "MPE instrument contains malformed retained state and reset recovers" {
    const TestInstrument = Instrument(2);
    const layout = try mpe.Layout.init(
        try mpe.Zone.init(.lower, 1, 48, 2),
        try mpe.Zone.init(.upper, 0, 48, 2),
    );
    var instrument = try TestInstrument.init(layout);
    _ = try instrument.process(try midi1.Message.noteOn(1, 60, 100));
    instrument.notes_storage[0].channel_index = 15;
    try std.testing.expect(!instrument.valid());
    try std.testing.expectError(
        error.InvalidMpeInstrumentState,
        instrument.process(try midi1.Message.noteOff(1, 60, 0)),
    );
    try instrument.reset(layout);
    try std.testing.expect(instrument.valid());

    instrument.note_count = 3;
    try std.testing.expectEqual(@as(usize, 0), instrument.notes().len);
    try std.testing.expectEqual(@as(usize, 0), instrument.allNotesOff());
}

test "MPE instrument generated message sequences remain bounded" {
    const InstrumentUnderTest = Instrument(16);
    const layout = try mpe.Layout.init(
        try mpe.Zone.init(.lower, 4, 48, 2),
        try mpe.Zone.init(.upper, 0, 48, 2),
    );
    var random_state = std.Random.DefaultPrng.init(0x4d50_4520_2026_0724);
    const random = random_state.random();

    for (0..32) |_| {
        var instrument = try InstrumentUnderTest.init(layout);
        for (0..256) |_| {
            const channel_index = random.uintLessThan(u8, 6);
            const note_number = random.uintLessThan(u8, 128);
            const value = random.uintLessThan(u8, 128);
            switch (random.uintLessThan(u8, 6)) {
                0 => {
                    const message = try midi1.Message.noteOn(channel_index, note_number, value);
                    if (instrument.note_count == 16 and layout.memberZone(channel_index) != null and value != 0) {
                        try std.testing.expectError(error.MpeNoteCapacityExceeded, instrument.process(message));
                    } else {
                        _ = try instrument.process(message);
                    }
                },
                1 => _ = try instrument.process(
                    try midi1.Message.noteOff(channel_index, note_number, value),
                ),
                2 => _ = try instrument.process(
                    try midi1.Message.pitchBend(channel_index, random.int(u14)),
                ),
                3 => _ = try instrument.process(
                    try midi1.Message.channelPressure(channel_index, value),
                ),
                4 => _ = try instrument.process(
                    try midi1.Message.controlChange(channel_index, 74, value),
                ),
                else => _ = try instrument.process(
                    try midi1.Message.controlChange(channel_index, 64, value),
                ),
            }
            try std.testing.expect(instrument.valid());
            try std.testing.expect(instrument.notes().len <= 16);
        }
    }
}

test "member channel allocator is deterministic and reports stealing" {
    var allocator = try MemberChannelAllocator.init(try mpe.Zone.init(.lower, 2, 48, 2));
    const first = try allocator.allocate(60, .reject);
    const second = try allocator.allocate(64, .reject);
    try std.testing.expectEqual(@as(u8, 1), first.assignment.channel_index);
    try std.testing.expectEqual(@as(u8, 2), second.assignment.channel_index);
    try std.testing.expectError(
        error.NoFreeMpeMemberChannel,
        allocator.allocate(67, .reject),
    );

    const stolen = try allocator.allocate(67, .oldest);
    try std.testing.expectEqual(first.assignment.id, stolen.stolen.?.id);
    try std.testing.expectEqual(@as(u8, 1), stolen.assignment.channel_index);
    try std.testing.expect(allocator.assignment(first.assignment.id) == null);
    try std.testing.expectEqualDeep(second.assignment, allocator.release(second.assignment.id).?);
    const reused = try allocator.allocate(69, .reject);
    try std.testing.expectEqual(@as(u8, 2), reused.assignment.channel_index);
}

test "member channel allocator rejects malformed retained state and reset recovers" {
    const zone = try mpe.Zone.init(.lower, 2, 48, 2);
    var allocator = try MemberChannelAllocator.init(zone);
    _ = try allocator.allocate(60, .reject);
    allocator.assignments_storage[0].channel_index = 15;
    try std.testing.expect(!allocator.valid());
    try std.testing.expectError(
        error.InvalidMpeAllocatorState,
        allocator.allocate(62, .reject),
    );
    try allocator.reset(zone);
    try std.testing.expect(allocator.valid());

    allocator.assignment_count = 16;
    try std.testing.expectEqual(@as(usize, 0), allocator.assignments().len);
}

test "member channel allocator generated operations preserve invariants" {
    var random_state = std.Random.DefaultPrng.init(0x4d50_4541_2026_0724);
    const random = random_state.random();
    var allocator = try MemberChannelAllocator.init(try mpe.Zone.init(.upper, 8, 48, 2));

    for (0..2048) |_| {
        if (allocator.assignment_count != 0 and random.boolean()) {
            const index = random.uintLessThan(usize, allocator.assignment_count);
            const id = allocator.assignments()[index].id;
            _ = allocator.release(id);
        } else {
            _ = try allocator.allocate(@intCast(random.uintLessThan(u8, 128)), .oldest);
        }
        try std.testing.expect(allocator.valid());
        try std.testing.expect(allocator.assignments().len <= 8);
    }
}

test "upper member channel allocator uses ascending member channels" {
    var allocator = try MemberChannelAllocator.init(try mpe.Zone.init(.upper, 3, 48, 2));
    try std.testing.expectEqual(@as(u8, 12), (try allocator.allocate(60, .reject)).assignment.channel_index);
    try std.testing.expectEqual(@as(u8, 13), (try allocator.allocate(62, .reject)).assignment.channel_index);
    try std.testing.expectEqual(@as(u8, 14), (try allocator.allocate(64, .reject)).assignment.channel_index);

    var inactive = try MemberChannelAllocator.init(try mpe.Zone.init(.lower, 0, 48, 2));
    try std.testing.expectError(error.NoMpeMemberChannels, inactive.allocate(60, .reject));
}
