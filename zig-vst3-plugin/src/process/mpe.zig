const std = @import("std");
const midi1 = @import("midi1.zig");
const midi_rpn = @import("midi_rpn.zig");

pub const ZoneType = enum {
    lower,
    upper,
};

pub const Zone = struct {
    zone_type: ZoneType,
    member_channel_count: u8 = 0,
    per_note_pitch_bend_range: u8 = 48,
    master_pitch_bend_range: u8 = 2,

    pub fn init(
        zone_type: ZoneType,
        member_channel_count: u8,
        per_note_pitch_bend_range: u8,
        master_pitch_bend_range: u8,
    ) !Zone {
        const zone = Zone{
            .zone_type = zone_type,
            .member_channel_count = member_channel_count,
            .per_note_pitch_bend_range = per_note_pitch_bend_range,
            .master_pitch_bend_range = master_pitch_bend_range,
        };
        try zone.validate();
        return zone;
    }

    pub fn validate(self: Zone) !void {
        if (self.member_channel_count > 15) return error.InvalidMpeMemberChannelCount;
        if (self.per_note_pitch_bend_range > 96 or self.master_pitch_bend_range > 96) {
            return error.InvalidMpePitchBendRange;
        }
    }

    pub fn active(self: Zone) bool {
        return self.valid() and self.member_channel_count != 0;
    }

    pub fn valid(self: Zone) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn masterChannel(self: Zone) ?u8 {
        if (!self.valid()) return null;
        return switch (self.zone_type) {
            .lower => 0,
            .upper => 15,
        };
    }

    pub fn firstMemberChannel(self: Zone) ?u8 {
        if (!self.active()) return null;
        return switch (self.zone_type) {
            .lower => 1,
            .upper => 15 - self.member_channel_count,
        };
    }

    pub fn lastMemberChannel(self: Zone) ?u8 {
        if (!self.active()) return null;
        return switch (self.zone_type) {
            .lower => self.member_channel_count,
            .upper => 14,
        };
    }

    pub fn isMemberChannel(self: Zone, channel_index: u8) bool {
        const first = self.firstMemberChannel() orelse return false;
        const last = self.lastMemberChannel() orelse return false;
        return channel_index >= first and channel_index <= last;
    }

    pub fn usesChannel(self: Zone, channel_index: u8) bool {
        if (!self.active()) return false;
        return channel_index == self.masterChannel().? or self.isMemberChannel(channel_index);
    }
};

pub const Layout = struct {
    lower: Zone = .{ .zone_type = .lower },
    upper: Zone = .{ .zone_type = .upper },

    pub fn init(lower: Zone, upper: Zone) !Layout {
        const layout = Layout{ .lower = lower, .upper = upper };
        try layout.validate();
        return layout;
    }

    pub fn validate(self: Layout) !void {
        if (self.lower.zone_type != .lower or self.upper.zone_type != .upper) {
            return error.InvalidMpeZoneType;
        }
        try self.lower.validate();
        try self.upper.validate();
        if (self.lower.active() and self.upper.active() and
            @as(u16, self.lower.member_channel_count) + self.upper.member_channel_count > 14)
        {
            return error.OverlappingMpeZones;
        }
    }

    pub fn valid(self: Layout) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn active(self: Layout) bool {
        return self.valid() and (self.lower.active() or self.upper.active());
    }

    pub fn clear(self: *Layout) void {
        self.* = .{};
    }

    pub fn setLower(self: *Layout, zone: Zone) !void {
        var replacement = self.*;
        replacement.lower = zone;
        try replacement.validate();
        self.* = replacement;
    }

    pub fn setUpper(self: *Layout, zone: Zone) !void {
        var replacement = self.*;
        replacement.upper = zone;
        try replacement.validate();
        self.* = replacement;
    }

    pub fn memberZone(self: Layout, channel_index: u8) ?ZoneType {
        if (!self.valid()) return null;
        if (self.lower.isMemberChannel(channel_index)) return .lower;
        if (self.upper.isMemberChannel(channel_index)) return .upper;
        return null;
    }

    pub fn masterZone(self: Layout, channel_index: u8) ?ZoneType {
        if (!self.valid()) return null;
        if (self.lower.active() and channel_index == self.lower.masterChannel().?) return .lower;
        if (self.upper.active() and channel_index == self.upper.masterChannel().?) return .upper;
        return null;
    }

    fn applyConfiguration(self: *Layout, zone_type: ZoneType, member_channel_count: u8) !bool {
        if (member_channel_count > 15) return error.InvalidMpeMemberChannelCount;
        var replacement = self.*;
        switch (zone_type) {
            .lower => {
                replacement.lower.member_channel_count = member_channel_count;
                if (member_channel_count != 0 and replacement.upper.active()) {
                    replacement.upper.member_channel_count = @min(
                        replacement.upper.member_channel_count,
                        14 -| member_channel_count,
                    );
                }
            },
            .upper => {
                replacement.upper.member_channel_count = member_channel_count;
                if (member_channel_count != 0 and replacement.lower.active()) {
                    replacement.lower.member_channel_count = @min(
                        replacement.lower.member_channel_count,
                        14 -| member_channel_count,
                    );
                }
            },
        }
        try replacement.validate();
        if (std.meta.eql(self.*, replacement)) return false;
        self.* = replacement;
        return true;
    }
};

pub const Synchronizer = struct {
    layout: Layout = .{},
    rpn_decoder: midi_rpn.Decoder = .{},

    pub fn init(layout: Layout) !Synchronizer {
        try layout.validate();
        return .{ .layout = layout };
    }

    pub fn reset(self: *Synchronizer, layout: Layout) !void {
        try layout.validate();
        self.* = .{ .layout = layout };
    }

    pub fn push(self: *Synchronizer, message: midi1.Message) !bool {
        try self.layout.validate();
        const event = try self.rpn_decoder.push(message) orelse return false;
        if (event.value_lsb != null) return false;
        return switch (event.parameter_number) {
            6 => try self.applyConfiguration(event),
            0 => try self.applyPitchBendRange(event),
            else => false,
        };
    }

    fn applyConfiguration(self: *Synchronizer, event: midi_rpn.Event) !bool {
        const zone_type: ZoneType = switch (event.channel_index) {
            0 => .lower,
            15 => .upper,
            else => return false,
        };
        return self.layout.applyConfiguration(zone_type, event.value_msb);
    }

    fn applyPitchBendRange(self: *Synchronizer, event: midi_rpn.Event) !bool {
        if (event.value_msb > 96) return error.InvalidMpePitchBendRange;
        if (self.layout.masterZone(event.channel_index)) |zone_type| {
            const range: u8 = event.value_msb;
            return switch (zone_type) {
                .lower => updateRange(&self.layout.lower.master_pitch_bend_range, range),
                .upper => updateRange(&self.layout.upper.master_pitch_bend_range, range),
            };
        }
        if (self.layout.memberZone(event.channel_index)) |zone_type| {
            const range: u8 = event.value_msb;
            return switch (zone_type) {
                .lower => updateRange(&self.layout.lower.per_note_pitch_bend_range, range),
                .upper => updateRange(&self.layout.upper.per_note_pitch_bend_range, range),
            };
        }
        return false;
    }
};

pub fn configurationMessages(zone_type: ZoneType, member_channel_count: u8) ![3]midi1.Message {
    if (member_channel_count > 15) return error.InvalidMpeMemberChannelCount;
    const channel_index: u8 = switch (zone_type) {
        .lower => 0,
        .upper => 15,
    };
    return midi_rpn.coarseMessages(channel_index, 6, @intCast(member_channel_count));
}

pub fn pitchBendRangeMessages(channel_index: u8, semitones: u8) ![3]midi1.Message {
    if (semitones > 96) return error.InvalidMpePitchBendRange;
    return midi_rpn.coarseMessages(channel_index, 0, @intCast(semitones));
}

fn updateRange(destination: *u8, value: u8) bool {
    if (destination.* == value) return false;
    destination.* = value;
    return true;
}

test "MPE zones classify lower and upper channel ranges" {
    const lower = try Zone.init(.lower, 4, 48, 2);
    try std.testing.expectEqual(@as(?u8, 0), lower.masterChannel());
    try std.testing.expectEqual(@as(?u8, 1), lower.firstMemberChannel());
    try std.testing.expectEqual(@as(?u8, 4), lower.lastMemberChannel());
    try std.testing.expect(lower.isMemberChannel(1));
    try std.testing.expect(lower.isMemberChannel(4));
    try std.testing.expect(!lower.isMemberChannel(5));

    const upper = try Zone.init(.upper, 3, 24, 2);
    try std.testing.expectEqual(@as(?u8, 15), upper.masterChannel());
    try std.testing.expectEqual(@as(?u8, 12), upper.firstMemberChannel());
    try std.testing.expectEqual(@as(?u8, 14), upper.lastMemberChannel());
    try std.testing.expect(upper.isMemberChannel(12));
    try std.testing.expect(upper.isMemberChannel(14));
    try std.testing.expect(!upper.isMemberChannel(11));
}

test "MPE layout rejects overlap and updates transactionally" {
    var layout = try Layout.init(
        try Zone.init(.lower, 8, 48, 2),
        try Zone.init(.upper, 6, 48, 2),
    );
    try std.testing.expect(layout.active());
    try std.testing.expectEqual(ZoneType.lower, layout.memberZone(8).?);
    try std.testing.expectEqual(ZoneType.upper, layout.memberZone(9).?);
    try std.testing.expectEqual(ZoneType.lower, layout.masterZone(0).?);
    try std.testing.expectEqual(ZoneType.upper, layout.masterZone(15).?);

    const before = layout;
    try std.testing.expectError(
        error.OverlappingMpeZones,
        layout.setLower(try Zone.init(.lower, 9, 48, 2)),
    );
    try std.testing.expectEqualDeep(before, layout);

    try layout.setUpper(try Zone.init(.upper, 0, 48, 2));
    try layout.setLower(try Zone.init(.lower, 15, 48, 2));
    try std.testing.expect(layout.lower.usesChannel(15));
    try std.testing.expect(layout.masterZone(15) == null);
}

test "MPE zones reject invalid retained state and clear recovers" {
    try std.testing.expectError(
        error.InvalidMpeMemberChannelCount,
        Zone.init(.lower, 16, 48, 2),
    );
    try std.testing.expectError(
        error.InvalidMpePitchBendRange,
        Zone.init(.upper, 1, 97, 2),
    );

    var layout = Layout{};
    layout.lower.member_channel_count = 16;
    try std.testing.expect(!layout.valid());
    try std.testing.expect(layout.memberZone(1) == null);
    layout.clear();
    try std.testing.expect(layout.valid());
    try std.testing.expect(!layout.active());
}

test "MPE synchronizer applies configuration with newest-zone priority" {
    var synchronizer = try Synchronizer.init(try Layout.init(
        try Zone.init(.lower, 8, 48, 2),
        try Zone.init(.upper, 6, 48, 2),
    ));

    _ = try synchronizer.push(try midi1.Message.controlChange(15, 100, 6));
    _ = try synchronizer.push(try midi1.Message.controlChange(15, 101, 0));
    try std.testing.expect(try synchronizer.push(try midi1.Message.controlChange(15, 6, 10)));
    try std.testing.expectEqual(@as(u8, 10), synchronizer.layout.upper.member_channel_count);
    try std.testing.expectEqual(@as(u8, 4), synchronizer.layout.lower.member_channel_count);

    _ = try synchronizer.push(try midi1.Message.controlChange(0, 100, 6));
    _ = try synchronizer.push(try midi1.Message.controlChange(0, 101, 0));
    try std.testing.expect(try synchronizer.push(try midi1.Message.controlChange(0, 6, 15)));
    try std.testing.expectEqual(@as(u8, 15), synchronizer.layout.lower.member_channel_count);
    try std.testing.expectEqual(@as(u8, 0), synchronizer.layout.upper.member_channel_count);

    const before = synchronizer.layout;
    try std.testing.expectError(
        error.InvalidMpeMemberChannelCount,
        synchronizer.push(try midi1.Message.controlChange(0, 6, 16)),
    );
    try std.testing.expectEqualDeep(before, synchronizer.layout);
}

test "MPE synchronizer applies master and member pitch-bend ranges" {
    var synchronizer = try Synchronizer.init(try Layout.init(
        try Zone.init(.lower, 4, 48, 2),
        try Zone.init(.upper, 3, 48, 2),
    ));

    _ = try synchronizer.push(try midi1.Message.controlChange(0, 101, 0));
    _ = try synchronizer.push(try midi1.Message.controlChange(0, 100, 0));
    try std.testing.expect(try synchronizer.push(try midi1.Message.controlChange(0, 6, 12)));
    try std.testing.expectEqual(@as(u8, 12), synchronizer.layout.lower.master_pitch_bend_range);

    _ = try synchronizer.push(try midi1.Message.controlChange(2, 101, 0));
    _ = try synchronizer.push(try midi1.Message.controlChange(2, 100, 0));
    try std.testing.expect(try synchronizer.push(try midi1.Message.controlChange(2, 6, 24)));
    try std.testing.expectEqual(@as(u8, 24), synchronizer.layout.lower.per_note_pitch_bend_range);

    _ = try synchronizer.push(try midi1.Message.controlChange(12, 101, 0));
    _ = try synchronizer.push(try midi1.Message.controlChange(12, 100, 0));
    try std.testing.expect(try synchronizer.push(try midi1.Message.controlChange(12, 6, 36)));
    try std.testing.expectEqual(@as(u8, 36), synchronizer.layout.upper.per_note_pitch_bend_range);

    const before = synchronizer.layout;
    try std.testing.expectError(
        error.InvalidMpePitchBendRange,
        synchronizer.push(try midi1.Message.controlChange(12, 6, 97)),
    );
    try std.testing.expectEqualDeep(before, synchronizer.layout);
}

test "MPE synchronizer ignores unsupported RPN channels parameters and LSB data" {
    var synchronizer = Synchronizer{};
    _ = try synchronizer.push(try midi1.Message.controlChange(1, 101, 0));
    _ = try synchronizer.push(try midi1.Message.controlChange(1, 100, 6));
    try std.testing.expect(!try synchronizer.push(try midi1.Message.controlChange(1, 6, 4)));
    try std.testing.expect(!synchronizer.layout.active());

    _ = try synchronizer.push(try midi1.Message.controlChange(0, 101, 0));
    _ = try synchronizer.push(try midi1.Message.controlChange(0, 100, 7));
    try std.testing.expect(!try synchronizer.push(try midi1.Message.controlChange(0, 6, 4)));
    try std.testing.expect(!try synchronizer.push(try midi1.Message.controlChange(0, 38, 1)));
    try std.testing.expect(!try synchronizer.push(try midi1.Message.noteOn(0, 60, 100)));
}

test "MPE message helpers configure zones and pitch-bend ranges" {
    var synchronizer = Synchronizer{};
    const configure = try configurationMessages(.lower, 4);
    for (configure) |message| {
        _ = try synchronizer.push(message);
    }
    try std.testing.expectEqual(@as(u8, 4), synchronizer.layout.lower.member_channel_count);

    const master_range = try pitchBendRangeMessages(0, 12);
    for (master_range) |message| {
        _ = try synchronizer.push(message);
    }
    try std.testing.expectEqual(@as(u8, 12), synchronizer.layout.lower.master_pitch_bend_range);

    const member_range = try pitchBendRangeMessages(2, 24);
    for (member_range) |message| {
        _ = try synchronizer.push(message);
    }
    try std.testing.expectEqual(@as(u8, 24), synchronizer.layout.lower.per_note_pitch_bend_range);

    try std.testing.expectError(
        error.InvalidMpeMemberChannelCount,
        configurationMessages(.upper, 16),
    );
    try std.testing.expectError(
        error.InvalidMpePitchBendRange,
        pitchBendRangeMessages(0, 97),
    );
    try std.testing.expectError(
        error.InvalidMidiChannel,
        pitchBendRangeMessages(16, 2),
    );
}

test "MPE synchronizer rejects malformed retained layouts and reset recovers" {
    var synchronizer = Synchronizer{};
    synchronizer.layout.lower.member_channel_count = 16;
    try std.testing.expectError(
        error.InvalidMpeMemberChannelCount,
        synchronizer.push(try midi1.Message.noteOn(0, 60, 100)),
    );
    try synchronizer.reset(.{});
    try std.testing.expect(!try synchronizer.push(try midi1.Message.noteOn(0, 60, 100)));
}
