const std = @import("std");
const midi_ci = @import("midi_ci.zig");
const profile = @import("midi_ci_profile.zig");

pub const Entry = struct {
    address: midi_ci.Address = .function_block,
    id: profile.Id = .{ .bytes = @splat(0) },
    enabled: bool = false,
    channels: u14 = 0,
};

const empty_entry = Entry{};

pub const SpecificDataRequest = struct {
    address: midi_ci.Address,
    version: u5,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    profile: profile.Id,
    data: []const u8,
};

pub fn BorrowedHost(
    comptime capacity: usize,
    comptime details_capacity: usize,
    comptime Delegate: type,
) type {
    return struct {
        const Self = @This();
        const ProfileReply = profile.Reply(capacity);
        const ProfileDetailsReply = profile.DetailsReply(details_capacity);

        source: midi_ci.Muid,
        version: u5,
        entries: *[capacity]Entry,
        count: *usize,
        delegate: *Delegate,

        pub fn profiles(self: *const Self) []const Entry {
            if (!self.valid()) return &.{};
            return self.entries[0..self.count.*];
        }

        pub fn validate(self: *const Self) !void {
            if (!self.source.validSource() or
                self.version < 1 or self.version > 2 or
                self.count.* > capacity)
            {
                return error.InvalidMidiCiProfileHostState;
            }
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        pub fn addProfile(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
        ) !profile.Presence {
            try self.validate();
            if (self.version != 2) return error.UnsupportedMidiCiVersion;
            if (self.find(address, id) != null)
                return error.MidiCiProfileAlreadyRegistered;
            if (self.count.* >= capacity)
                return error.MidiCiProfileHostCapacityExceeded;
            self.entries[self.count.*] = .{
                .address = address,
                .id = id,
            };
            self.count.* += 1;
            return .{
                .kind = .added,
                .address = address,
                .source = self.source,
                .profile = id,
            };
        }

        pub fn removeProfile(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
        ) !profile.Presence {
            try self.validate();
            if (self.version != 2) return error.UnsupportedMidiCiVersion;
            const index = self.find(address, id) orelse
                return error.MidiCiProfileNotRegistered;
            const remaining = self.count.* - index - 1;
            if (remaining > 0) {
                std.mem.copyForwards(
                    Entry,
                    self.entries[index .. index + remaining],
                    self.entries[index + 1 .. index + 1 + remaining],
                );
            }
            self.count.* -= 1;
            self.entries[self.count.*] = empty_entry;
            return .{
                .kind = .removed,
                .address = address,
                .source = self.source,
                .profile = id,
            };
        }

        pub fn setEnabled(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
            enabled: bool,
            channels: u14,
        ) !profile.Report {
            try self.validate();
            const profile_entry = try self.entry(address, id);
            try validateChannels(address, enabled, channels);
            profile_entry.enabled = enabled;
            profile_entry.channels = if (enabled) channels else 0;
            return self.report(profile_entry.*, self.version);
        }

        pub fn handleInquiry(
            self: *const Self,
            inquiry: profile.Inquiry,
            response_address: midi_ci.Address,
        ) !ProfileReply {
            try self.validate();
            if (!inquiry.valid())
                return error.InvalidMidiCiProfileInquiry;
            try self.validateRequest(
                inquiry.source,
                inquiry.destination,
                inquiry.version,
            );
            if (!addressRespondsTo(inquiry.address, response_address))
                return error.MidiCiProfileInquiryAddressMismatch;

            var enabled_storage: [capacity]profile.Id = undefined;
            var disabled_storage: [capacity]profile.Id = undefined;
            var enabled_count: usize = 0;
            var disabled_count: usize = 0;
            for (self.profiles()) |entry_value| {
                if (!addressEqual(entry_value.address, response_address))
                    continue;
                if (entry_value.enabled) {
                    enabled_storage[enabled_count] = entry_value.id;
                    enabled_count += 1;
                } else {
                    disabled_storage[disabled_count] = entry_value.id;
                    disabled_count += 1;
                }
            }
            return .{
                .address = response_address,
                .version = inquiry.version,
                .source = self.source,
                .destination = inquiry.source,
                .enabled = try profile.List(capacity).init(
                    enabled_storage[0..enabled_count],
                ),
                .disabled = try profile.List(capacity).init(
                    disabled_storage[0..disabled_count],
                ),
            };
        }

        pub fn handleSet(
            self: *Self,
            request: profile.Set,
        ) !profile.Report {
            try self.validate();
            if (!request.valid())
                return error.InvalidMidiCiProfileSet;
            try self.validateRequest(
                request.source,
                request.destination,
                request.version,
            );
            const entry_value = try self.entry(request.address, request.profile);
            if (!try self.delegate.profileEnablementRequested(request))
                return self.report(entry_value.*, request.version);

            switch (request.kind) {
                .on => {
                    const channels = request.channels;
                    try validateChannels(request.address, true, channels);
                    entry_value.enabled = true;
                    entry_value.channels = channels;
                },
                .off => {
                    entry_value.enabled = false;
                    entry_value.channels = 0;
                },
            }
            return self.report(entry_value.*, request.version);
        }

        pub fn handleDetails(
            self: *Self,
            inquiry: profile.DetailsInquiry,
        ) !ProfileDetailsReply {
            try self.validate();
            try self.validateRequest(
                inquiry.source,
                inquiry.destination,
                2,
            );
            _ = try self.entry(inquiry.address, inquiry.profile);
            const data = try self.delegate.profileDetails(inquiry);
            return ProfileDetailsReply.init(
                inquiry.address,
                self.source,
                inquiry.source,
                inquiry.profile,
                inquiry.target,
                data,
            );
        }

        pub fn handleSpecificData(
            self: *Self,
            message: anytype,
        ) !void {
            try self.validate();
            if (!message.valid())
                return error.InvalidMidiCiProfileSpecificData;
            try self.validateRequest(
                message.source,
                message.destination,
                message.version,
            );
            _ = try self.entry(message.address, message.profile);
            try self.delegate.profileSpecificData(.{
                .address = message.address,
                .version = message.version,
                .source = message.source,
                .destination = message.destination,
                .profile = message.profile,
                .data = message.data(),
            });
        }

        fn validateRequest(
            self: *const Self,
            source: midi_ci.Muid,
            destination: midi_ci.Muid,
            version: u5,
        ) !void {
            if (!source.validSource() or destination.value != self.source.value)
                return error.MidiCiMuidMismatch;
            if (source.value == self.source.value)
                return error.MidiCiMuidCollision;
            if (version < 1 or version > self.version)
                return error.UnsupportedMidiCiVersion;
        }

        fn find(
            self: *const Self,
            address: midi_ci.Address,
            id: profile.Id,
        ) ?usize {
            for (self.profiles(), 0..) |entry_value, index| {
                if (addressEqual(entry_value.address, address) and
                    std.meta.eql(entry_value.id, id))
                    return index;
            }
            return null;
        }

        fn entry(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
        ) !*Entry {
            const index = self.find(address, id) orelse
                return error.MidiCiProfileNotRegistered;
            return &self.entries[index];
        }

        fn report(
            self: *const Self,
            entry_value: Entry,
            version: u5,
        ) profile.Report {
            return .{
                .kind = if (entry_value.enabled) .enabled else .disabled,
                .address = entry_value.address,
                .version = version,
                .source = self.source,
                .profile = entry_value.id,
                .channels = if (version == 1) 0 else entry_value.channels,
            };
        }
    };
}

pub fn Host(
    comptime capacity: usize,
    comptime details_capacity: usize,
    comptime Delegate: type,
) type {
    return struct {
        const Self = @This();
        const Inner = BorrowedHost(capacity, details_capacity, Delegate);

        source: midi_ci.Muid,
        version: u5 = 2,
        entries: [capacity]Entry = @splat(empty_entry),
        count: usize = 0,
        delegate: *Delegate,

        pub fn init(
            source: midi_ci.Muid,
            version: u5,
            delegate: *Delegate,
        ) !Self {
            if (!source.validSource())
                return error.InvalidMidiCiMuid;
            if (version < 1 or version > 2)
                return error.UnsupportedMidiCiVersion;
            return .{
                .source = source,
                .version = version,
                .delegate = delegate,
            };
        }

        pub fn profiles(self: *const Self) []const Entry {
            if (!self.valid()) return &.{};
            return self.entries[0..self.count];
        }

        pub fn validate(self: *const Self) !void {
            if (!self.source.validSource() or
                self.version < 1 or self.version > 2 or
                self.count > capacity)
            {
                return error.InvalidMidiCiProfileHostState;
            }
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        pub fn addProfile(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
        ) !profile.Presence {
            var host = self.inner();
            return host.addProfile(address, id);
        }

        pub fn removeProfile(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
        ) !profile.Presence {
            var host = self.inner();
            return host.removeProfile(address, id);
        }

        pub fn setEnabled(
            self: *Self,
            address: midi_ci.Address,
            id: profile.Id,
            enabled: bool,
            channels: u14,
        ) !profile.Report {
            var host = self.inner();
            return host.setEnabled(address, id, enabled, channels);
        }

        pub fn handleInquiry(
            self: *Self,
            inquiry: profile.Inquiry,
            response_address: midi_ci.Address,
        ) !profile.Reply(capacity) {
            var host = self.inner();
            return host.handleInquiry(inquiry, response_address);
        }

        pub fn handleSet(
            self: *Self,
            request: profile.Set,
        ) !profile.Report {
            var host = self.inner();
            return host.handleSet(request);
        }

        pub fn handleDetails(
            self: *Self,
            inquiry: profile.DetailsInquiry,
        ) !profile.DetailsReply(details_capacity) {
            var host = self.inner();
            return host.handleDetails(inquiry);
        }

        pub fn handleSpecificData(
            self: *Self,
            message: anytype,
        ) !void {
            var host = self.inner();
            return host.handleSpecificData(message);
        }

        fn inner(self: *Self) Inner {
            return .{
                .source = self.source,
                .version = self.version,
                .entries = &self.entries,
                .count = &self.count,
                .delegate = self.delegate,
            };
        }
    };
}

fn validateChannels(
    address: midi_ci.Address,
    enabled: bool,
    channels: u14,
) !void {
    if (!enabled and channels != 0)
        return error.InvalidMidiCiProfileChannelCount;
    switch (address) {
        .channel => {
            if (channels > 256)
                return error.InvalidMidiCiProfileChannelCount;
        },
        .group, .function_block => {
            if (channels != 0)
                return error.InvalidMidiCiProfileChannelCount;
        },
    }
}

fn addressRespondsTo(
    inquiry: midi_ci.Address,
    response: midi_ci.Address,
) bool {
    return switch (inquiry) {
        .channel => |channel| switch (response) {
            .channel => |other| channel == other,
            else => false,
        },
        .group => response == .group,
        .function_block => true,
    };
}

fn addressEqual(left: midi_ci.Address, right: midi_ci.Address) bool {
    return switch (left) {
        .channel => |channel| switch (right) {
            .channel => |other| channel == other,
            else => false,
        },
        .group => right == .group,
        .function_block => right == .function_block,
    };
}

const TestDelegate = struct {
    const profile_details_capacity = 16;

    accept_enablement: bool = true,
    details: []const u8 = &.{ 1, 2, 3 },
    specific_data_calls: usize = 0,

    pub fn profileEnablementRequested(
        self: *@This(),
        request: profile.Set,
    ) !bool {
        _ = request;
        return self.accept_enablement;
    }

    pub fn profileDetails(
        self: *@This(),
        inquiry: profile.DetailsInquiry,
    ) ![]const u8 {
        _ = inquiry;
        return self.details;
    }

    pub fn profileSpecificData(
        self: *@This(),
        request: SpecificDataRequest,
    ) !void {
        if (request.data.len == 0)
            return error.EmptyProfileSpecificData;
        self.specific_data_calls += 1;
    }
};

test "MIDI-CI Profile Host manages inquiry and enablement state" {
    const local = try midi_ci.Muid.init(0x1020);
    const remote = try midi_ci.Muid.init(0x3040);
    const id = profile.Id.standard(1, 2, 3, 4);
    var delegate = TestDelegate{};
    var host = try Host(4, 16, TestDelegate).init(local, 2, &delegate);

    const added = try host.addProfile(.{ .channel = 3 }, id);
    try std.testing.expectEqual(profile.PresenceKind.added, added.kind);
    const reply = try host.handleInquiry(.{
        .address = .function_block,
        .source = remote,
        .destination = local,
    }, .{ .channel = 3 });
    try std.testing.expectEqual(@as(usize, 0), reply.enabled.slice().len);
    try std.testing.expectEqual(@as(usize, 1), reply.disabled.slice().len);

    const enabled = try host.handleSet(.{
        .kind = .on,
        .address = .{ .channel = 3 },
        .source = remote,
        .destination = local,
        .profile = id,
        .channels = 8,
    });
    try std.testing.expectEqual(profile.ReportKind.enabled, enabled.kind);
    try std.testing.expectEqual(@as(u14, 8), enabled.channels);

    delegate.accept_enablement = false;
    const unchanged = try host.handleSet(.{
        .kind = .off,
        .address = .{ .channel = 3 },
        .source = remote,
        .destination = local,
        .profile = id,
    });
    try std.testing.expectEqual(profile.ReportKind.enabled, unchanged.kind);
    try std.testing.expectEqual(@as(u14, 8), unchanged.channels);
}

test "MIDI-CI Profile Host dispatches details and specific data" {
    const local = try midi_ci.Muid.init(0x1122);
    const remote = try midi_ci.Muid.init(0x3344);
    const id = profile.Id.standard(2, 3, 4, 5);
    var delegate = TestDelegate{};
    var host = try Host(2, 16, TestDelegate).init(local, 2, &delegate);
    _ = try host.addProfile(.function_block, id);

    const details = try host.handleDetails(.{
        .source = remote,
        .destination = local,
        .profile = id,
        .target = 1,
    });
    try std.testing.expectEqualSlices(u8, delegate.details, details.data());

    const Data = profile.SpecificData(8);
    const data = try Data.init(
        .function_block,
        2,
        remote,
        local,
        id,
        &.{ 7, 6 },
    );
    try host.handleSpecificData(data);
    try std.testing.expectEqual(@as(usize, 1), delegate.specific_data_calls);

    const removed = try host.removeProfile(.function_block, id);
    try std.testing.expectEqual(profile.PresenceKind.removed, removed.kind);
    try std.testing.expectEqual(@as(usize, 0), host.profiles().len);
    try std.testing.expectEqualDeep(empty_entry, host.entries[0]);
}

test "MIDI-CI Profile Host preserves version and transactional registry state" {
    const local = try midi_ci.Muid.init(0x5566);
    const remote = try midi_ci.Muid.init(0x7788);
    const first = profile.Id.standard(3, 4, 5, 6);
    const second = profile.Id.standard(3, 4, 5, 7);
    var delegate = TestDelegate{};
    var host = try Host(1, 16, TestDelegate).init(local, 2, &delegate);
    try std.testing.expectEqualDeep(empty_entry, host.entries[0]);

    _ = try host.addProfile(.{ .channel = 2 }, first);
    try std.testing.expectError(
        error.MidiCiProfileAlreadyRegistered,
        host.addProfile(.{ .channel = 2 }, first),
    );
    try std.testing.expectError(
        error.MidiCiProfileHostCapacityExceeded,
        host.addProfile(.function_block, second),
    );
    try std.testing.expectEqual(@as(usize, 1), host.profiles().len);

    const report = try host.handleSet(.{
        .kind = .on,
        .address = .{ .channel = 2 },
        .version = 1,
        .source = remote,
        .destination = local,
        .profile = first,
    });
    try std.testing.expectEqual(@as(u5, 1), report.version);
    try std.testing.expectEqual(@as(u14, 0), report.channels);

    const local_report = try host.setEnabled(
        .{ .channel = 2 },
        first,
        false,
        0,
    );
    try std.testing.expectEqual(profile.ReportKind.disabled, local_report.kind);
    try std.testing.expectError(
        error.InvalidMidiCiProfileSet,
        host.handleSet(.{
            .kind = .off,
            .address = .{ .channel = 2 },
            .source = remote,
            .destination = local,
            .profile = first,
            .channels = 1,
        }),
    );
    try std.testing.expect(!host.profiles()[0].enabled);

    host.count = std.math.maxInt(usize);
    try std.testing.expect(!host.valid());
    try std.testing.expectEqual(@as(usize, 0), host.profiles().len);
    try std.testing.expectError(
        error.InvalidMidiCiProfileHostState,
        host.addProfile(.function_block, second),
    );
    try std.testing.expectError(
        error.InvalidMidiCiProfileHostState,
        host.handleInquiry(.{
            .source = remote,
            .destination = local,
        }, .function_block),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        host.count,
    );
    host.count = 1;
    try std.testing.expect(host.valid());
}
