const std = @import("std");
const property_json = @import("midi_ci_property_json.zig");
const resources = @import("midi_ci_property_resources.zig");

pub const maximum_modes = 256;
pub const maximum_states = 256;

pub const Mode = struct {
    mode_id: []const u8,
    title: []const u8,
    description: ?[]const u8 = null,
    links: []const resources.Link = &.{},

    pub fn valid(self: Mode) bool {
        if (!validModeId(self.mode_id) or self.title.len == 0 or
            self.links.len > resources.maximum_links)
            return false;
        for (self.links) |link| {
            if (!link.valid()) return false;
        }
        return true;
    }
};

pub const ModeList = struct {
    entries: []const Mode,

    pub fn valid(self: ModeList) bool {
        if (self.entries.len > maximum_modes) return false;
        for (self.entries, 0..) |entry, index| {
            if (!entry.valid()) return false;
            for (self.entries[0..index]) |previous| {
                if (std.mem.eql(u8, previous.mode_id, entry.mode_id))
                    return false;
            }
        }
        return true;
    }

    pub fn writeJson(self: ModeList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiModeList;
        try writer.writeByte('[');
        for (self.entries, 0..) |entry, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"modeId\":");
            try writeString(writer, entry.mode_id);
            try writer.writeAll(",\"title\":");
            try writeString(writer, entry.title);
            if (entry.description) |description| {
                try writer.writeAll(",\"description\":");
                try writeString(writer, description);
            }
            if (entry.links.len != 0) {
                try writer.writeAll(",\"links\":[");
                for (entry.links, 0..) |link, link_index| {
                    if (link_index != 0) try writer.writeByte(',');
                    try writeLink(writer, link);
                }
                try writer.writeByte(']');
            }
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(ModeList) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            []const ModeWire,
            allocator,
            source,
            .{ .ignore_unknown_fields = true },
        );
        errdefer parsed.deinit();
        if (parsed.value.len > maximum_modes)
            return error.InvalidMidiCiModeList;
        const entries = try parsed.arena.allocator().alloc(Mode, parsed.value.len);
        for (parsed.value, entries) |wire, *entry| {
            entry.* = .{
                .mode_id = wire.modeId,
                .title = wire.title,
                .description = wire.description,
                .links = wire.links,
            };
        }
        const value = ModeList{ .entries = entries };
        if (!value.valid()) return error.InvalidMidiCiModeList;
        return .{ .arena = parsed.arena, .value = value };
    }
};

pub const CurrentMode = struct {
    mode_id: []const u8,

    pub fn valid(self: CurrentMode) bool {
        return validModeId(self.mode_id);
    }

    pub fn writeJson(self: CurrentMode, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiCurrentMode;
        try writeString(writer, self.mode_id);
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(CurrentMode) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            []const u8,
            allocator,
            source,
            .{},
        );
        errdefer parsed.deinit();
        const value = CurrentMode{ .mode_id = parsed.value };
        if (!value.valid()) return error.InvalidMidiCiCurrentMode;
        return .{ .arena = parsed.arena, .value = value };
    }
};

pub const ChannelMode = enum(u3) {
    omni_on_poly = 1,
    omni_on_mono = 2,
    omni_off_poly = 3,
    omni_off_mono = 4,

    pub fn writeJson(self: ChannelMode, writer: anytype) !void {
        try writer.print("{d}", .{@intFromEnum(self)});
    }

    pub fn parseJson(source: []const u8) !ChannelMode {
        const value = try parseScalar(u3, source);
        return std.enums.fromInt(ChannelMode, value) orelse
            return error.InvalidMidiCiChannelMode;
    }
};

pub const BasicChannel = struct {
    channel: u5,

    pub fn valid(self: BasicChannel) bool {
        return self.channel >= 1 and self.channel <= 16;
    }

    pub fn writeJson(self: BasicChannel, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiBasicChannel;
        try writer.print("{d}", .{self.channel});
    }

    pub fn parseJson(source: []const u8) !BasicChannel {
        const value = BasicChannel{
            .channel = try parseScalar(u5, source),
        };
        if (!value.valid()) return error.InvalidMidiCiBasicChannel;
        return value;
    }
};

pub const LocalOn = struct {
    enabled: bool,

    pub fn writeJson(self: LocalOn, writer: anytype) !void {
        try writer.writeAll(if (self.enabled) "true" else "false");
    }

    pub fn parseJson(source: []const u8) !LocalOn {
        return .{ .enabled = try parseScalar(bool, source) };
    }
};

pub const ExternalSync = struct {
    enabled: bool,

    pub fn writeJson(self: ExternalSync, writer: anytype) !void {
        try writer.writeAll(if (self.enabled) "true" else "false");
    }

    pub fn parseJson(source: []const u8) !ExternalSync {
        return .{ .enabled = try parseScalar(bool, source) };
    }
};

pub const State = struct {
    title: []const u8,
    state_id: []const u8,
    state_revision: ?[]const u8 = null,
    timestamp: ?u64 = null,
    description: ?[]const u8 = null,
    size: ?u64 = null,
    links: []const resources.Link = &.{},

    pub fn valid(self: State) bool {
        if (self.title.len == 0 or !validId(self.state_id) or
            self.links.len > resources.maximum_links)
            return false;
        for (self.links) |link| {
            if (!link.valid()) return false;
        }
        return true;
    }
};

pub const StateList = struct {
    entries: []const State,

    pub fn valid(self: StateList) bool {
        if (self.entries.len > maximum_states) return false;
        for (self.entries, 0..) |entry, index| {
            if (!entry.valid()) return false;
            for (self.entries[0..index]) |previous| {
                if (std.mem.eql(u8, previous.state_id, entry.state_id))
                    return false;
            }
        }
        return true;
    }

    pub fn writeJson(self: StateList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiStateList;
        try writer.writeByte('[');
        for (self.entries, 0..) |entry, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"title\":");
            try writeString(writer, entry.title);
            try writer.writeAll(",\"stateId\":");
            try writeString(writer, entry.state_id);
            if (entry.state_revision) |revision| {
                try writer.writeAll(",\"stateRev\":");
                try writeString(writer, revision);
            }
            if (entry.timestamp) |timestamp|
                try writer.print(",\"timestamp\":{d}", .{timestamp});
            if (entry.description) |description| {
                try writer.writeAll(",\"description\":");
                try writeString(writer, description);
            }
            if (entry.size) |size|
                try writer.print(",\"size\":{d}", .{size});
            if (entry.links.len != 0) {
                try writer.writeAll(",\"links\":[");
                for (entry.links, 0..) |link, link_index| {
                    if (link_index != 0) try writer.writeByte(',');
                    try writeLink(writer, link);
                }
                try writer.writeByte(']');
            }
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(StateList) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            []const StateWire,
            allocator,
            source,
            .{ .ignore_unknown_fields = true },
        );
        errdefer parsed.deinit();
        if (parsed.value.len > maximum_states)
            return error.InvalidMidiCiStateList;
        const entries = try parsed.arena.allocator().alloc(State, parsed.value.len);
        for (parsed.value, entries) |wire, *entry| {
            entry.* = .{
                .title = wire.title,
                .state_id = wire.stateId,
                .state_revision = wire.stateRev,
                .timestamp = wire.timestamp,
                .description = wire.description,
                .size = wire.size,
                .links = wire.links,
            };
        }
        const value = StateList{ .entries = entries };
        if (!value.valid()) return error.InvalidMidiCiStateList;
        return .{ .arena = parsed.arena, .value = value };
    }
};

pub const mode_list_resource = resources.Resource{ .resource = "ModeList" };
pub const current_mode_resource = resources.Resource{
    .resource = "CurrentMode",
    .can_set = .full,
};
pub const channel_mode_resource = resources.Resource{ .resource = "ChannelMode" };
pub const basic_channel_rx_resource = resources.Resource{
    .resource = "BasicChannelRx",
    .can_set = .full,
};
pub const basic_channel_tx_resource = resources.Resource{
    .resource = "BasicChannelTx",
    .can_set = .full,
};
pub const local_on_resource = resources.Resource{
    .resource = "LocalOn",
    .can_set = .full,
};
pub const external_sync_resource = resources.Resource{
    .resource = "ExternalSync",
    .can_set = .full,
};
pub const state_list_resource = resources.Resource{ .resource = "StateList" };
pub const state_resource = resources.Resource{
    .resource = "State",
    .can_set = .full,
    .require_res_id = true,
    .media_types = &.{"application/octet-stream"},
    .encodings = &.{property_json.Encoding.mcoded7},
};

const ModeWire = struct {
    modeId: []const u8,
    title: []const u8,
    description: ?[]const u8 = null,
    links: []const resources.Link = &.{},
};

const StateWire = struct {
    title: []const u8,
    stateId: []const u8,
    stateRev: ?[]const u8 = null,
    timestamp: ?u64 = null,
    description: ?[]const u8 = null,
    size: ?u64 = null,
    links: []const resources.Link = &.{},
};

fn parseScalar(comptime T: type, source: []const u8) !T {
    try validatePropertyData(source);
    const parsed = try std.json.parseFromSlice(T, std.heap.page_allocator, source, .{});
    defer parsed.deinit();
    return parsed.value;
}

fn validatePropertyData(source: []const u8) !void {
    if (source.len == 0 or source.len > resources.maximum_property_bytes)
        return error.InvalidMidiCiPropertyDataLength;
    for (source) |byte| {
        if (byte > 0x7f) return error.InvalidMidiCiPropertyDataByte;
    }
}

fn validId(source: []const u8) bool {
    if (source.len == 0 or source.len > 36) return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn validModeId(source: []const u8) bool {
    return source.len != 0 and source.len <= 36;
}

fn writeString(writer: anytype, source: []const u8) !void {
    try writer.print("{f}", .{
        std.json.fmt(source, .{ .escape_unicode = true }),
    });
}

fn writeLink(writer: anytype, link: resources.Link) !void {
    if (!link.valid()) return error.InvalidMidiCiPropertyLink;
    try writer.writeAll("{\"resource\":");
    try writeString(writer, link.resource);
    if (link.res_id) |value| {
        try writer.writeAll(",\"resId\":");
        try writeString(writer, value);
    }
    if (link.title) |value| {
        try writer.writeAll(",\"title\":");
        try writeString(writer, value);
    }
    if (link.role) |value| {
        try writer.writeAll(",\"role\":");
        try writeString(writer, value);
    }
    try writer.writeByte('}');
}

test "standard resource lists round trip modes states and links" {
    const links = [_]resources.Link{.{ .resource = "State", .res_id = "programs" }};
    const modes = [_]Mode{.{
        .mode_id = "multi_channel",
        .title = "Multi Channel",
        .description = "Independent parts",
    }};
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try (ModeList{ .entries = &modes }).writeJson(&output.writer);
    const parsed_modes = try ModeList.parseJson(std.testing.allocator, output.written());
    defer parsed_modes.deinit();
    try std.testing.expectEqualStrings(
        "multi_channel",
        parsed_modes.value.entries[0].mode_id,
    );

    output.clearRetainingCapacity();
    const states = [_]State{.{
        .title = "Programs",
        .state_id = "programs",
        .state_revision = "42",
        .timestamp = 1_700_000_000,
        .size = 4096,
        .links = &links,
    }};
    try (StateList{ .entries = &states }).writeJson(&output.writer);
    const parsed_states = try StateList.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed_states.deinit();
    try std.testing.expectEqual(@as(?u64, 4096), parsed_states.value.entries[0].size);
    try std.testing.expectEqualStrings(
        "programs",
        parsed_states.value.entries[0].links[0].res_id.?,
    );
}

test "simple standard resources parse and write their scalar values" {
    const current = try CurrentMode.parseJson(std.testing.allocator, "\"single\"");
    defer current.deinit();
    try std.testing.expectEqualStrings("single", current.value.mode_id);
    try std.testing.expectEqual(ChannelMode.omni_off_poly, try ChannelMode.parseJson("3"));
    try std.testing.expectEqual(@as(u5, 16), (try BasicChannel.parseJson("16")).channel);
    try std.testing.expect((try LocalOn.parseJson("true")).enabled);
    try std.testing.expect(!(try ExternalSync.parseJson("false")).enabled);
}

test "standard resources reject malformed identities bounds and duplicates" {
    try std.testing.expectError(
        error.InvalidMidiCiModeList,
        ModeList.parseJson(
            std.testing.allocator,
            "[{\"modeId\":\"\",\"title\":\"Bad\"}]",
        ),
    );
    try std.testing.expectError(
        error.InvalidMidiCiStateList,
        StateList.parseJson(
            std.testing.allocator,
            "[{\"title\":\"A\",\"stateId\":\"same\"},{\"title\":\"B\",\"stateId\":\"same\"}]",
        ),
    );
    try std.testing.expectError(
        error.InvalidMidiCiChannelMode,
        ChannelMode.parseJson("5"),
    );
    try std.testing.expectError(
        error.InvalidMidiCiBasicChannel,
        BasicChannel.parseJson("0"),
    );
}
