const std = @import("std");
const property_json = @import("midi_ci_property_json.zig");

pub const maximum_property_bytes = 65_535;
pub const maximum_links = 64;
pub const maximum_channels = 256;
pub const maximum_resources = 256;
pub const maximum_media_types = 16;

pub const Link = struct {
    resource: []const u8,
    res_id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    role: ?[]const u8 = null,

    pub fn valid(self: Link) bool {
        if (!validResource(self.resource)) return false;
        if (self.res_id) |value| {
            if (!validResourceId(value)) return false;
        }
        if (self.role) |value| {
            if (value.len > 32) return false;
        }
        return true;
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !Link {
        const value = try std.json.innerParse(LinkWire, allocator, source, options);
        return .{
            .resource = value.resource,
            .res_id = value.resId,
            .title = value.title,
            .role = value.role,
        };
    }
};

pub const DeviceInfo = struct {
    manufacturer_id: [3]u7,
    family_id: [2]u7,
    model_id: [2]u7,
    version_id: [4]u7,
    manufacturer: []const u8,
    family: []const u8,
    model: []const u8,
    version: []const u8,
    serial_number: ?[]const u8 = null,
    links: []const Link = &.{},

    pub fn valid(self: DeviceInfo) bool {
        if (self.manufacturer.len == 0 or self.family.len == 0 or
            self.model.len == 0 or self.version.len == 0 or
            self.links.len > maximum_links)
            return false;
        for (self.links) |link| {
            if (!link.valid()) return false;
        }
        return true;
    }

    pub fn writeJson(self: DeviceInfo, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiDeviceInfo;
        try writer.print(
            "{{\"manufacturerId\":[{d},{d},{d}],\"familyId\":[{d},{d}],\"modelId\":[{d},{d}],\"versionId\":[{d},{d},{d},{d}],\"manufacturer\":",
            .{
                self.manufacturer_id[0],
                self.manufacturer_id[1],
                self.manufacturer_id[2],
                self.family_id[0],
                self.family_id[1],
                self.model_id[0],
                self.model_id[1],
                self.version_id[0],
                self.version_id[1],
                self.version_id[2],
                self.version_id[3],
            },
        );
        try writeString(writer, self.manufacturer);
        try writer.writeAll(",\"family\":");
        try writeString(writer, self.family);
        try writer.writeAll(",\"model\":");
        try writeString(writer, self.model);
        try writer.writeAll(",\"version\":");
        try writeString(writer, self.version);
        if (self.serial_number) |value| {
            try writer.writeAll(",\"serialNumber\":");
            try writeString(writer, value);
        }
        if (self.links.len != 0) {
            try writer.writeAll(",\"links\":[");
            for (self.links, 0..) |link, index| {
                if (index != 0) try writer.writeByte(',');
                try writeLink(link, writer);
            }
            try writer.writeByte(']');
        }
        try writer.writeByte('}');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(DeviceInfo) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            DeviceInfoWire,
            allocator,
            source,
            .{ .ignore_unknown_fields = true },
        );
        errdefer parsed.deinit();
        const value = DeviceInfo{
            .manufacturer_id = parsed.value.manufacturerId,
            .family_id = parsed.value.familyId,
            .model_id = parsed.value.modelId,
            .version_id = parsed.value.versionId,
            .manufacturer = parsed.value.manufacturer,
            .family = parsed.value.family,
            .model = parsed.value.model,
            .version = parsed.value.version,
            .serial_number = parsed.value.serialNumber,
            .links = parsed.value.links,
        };
        if (!value.valid()) return error.InvalidMidiCiDeviceInfo;
        return transferParsed(DeviceInfo, parsed.arena, value);
    }
};

pub const ClusterType = enum {
    other,
    profile,
    mpe1,
};

pub const Channel = struct {
    title: []const u8,
    channel: u16,
    program_title: ?[]const u8 = null,
    bank_program: ?[3]u7 = null,
    cluster_channel_start: ?u16 = null,
    cluster_length: ?u16 = null,
    cluster_midi_mode: ?u3 = null,
    cluster_type: ClusterType = .other,
    links: []const Link = &.{},

    pub fn valid(self: Channel) bool {
        if (self.title.len == 0 or self.channel == 0 or self.channel > 256 or
            self.links.len > maximum_links)
            return false;
        const has_cluster = self.cluster_channel_start != null or
            self.cluster_length != null or
            self.cluster_midi_mode != null or
            self.cluster_type != .other;
        if (has_cluster) {
            if (self.cluster_channel_start == null or
                self.cluster_length == null)
                return false;
            const start = self.cluster_channel_start orelse return false;
            const length = self.cluster_length orelse return false;
            if (start == 0 or start > 256 or length == 0 or length > 256)
                return false;
            if (@as(u32, start) + @as(u32, length) - 1 > 256)
                return false;
            if (self.cluster_midi_mode) |mode| {
                if (mode == 0 or mode > 4) return false;
            }
        }
        for (self.links) |link| {
            if (!link.valid()) return false;
        }
        return true;
    }
};

pub const ChannelList = struct {
    entries: []const Channel,

    pub fn valid(self: ChannelList) bool {
        if (self.entries.len > maximum_channels) return false;
        for (self.entries) |entry| {
            if (!entry.valid()) return false;
        }
        return true;
    }

    pub fn writeJson(self: ChannelList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiChannelList;
        try writer.writeByte('[');
        for (self.entries, 0..) |entry, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"title\":");
            try writeString(writer, entry.title);
            try writer.print(",\"channel\":{d}", .{entry.channel});
            if (entry.program_title) |value| {
                try writer.writeAll(",\"programTitle\":");
                try writeString(writer, value);
            }
            if (entry.bank_program) |value|
                try writer.print(
                    ",\"bankPC\":[{d},{d},{d}]",
                    .{ value[0], value[1], value[2] },
                );
            if (entry.cluster_channel_start) |value|
                try writer.print(",\"clusterChannelStart\":{d}", .{value});
            if (entry.cluster_length) |value|
                try writer.print(",\"clusterLength\":{d}", .{value});
            if (entry.cluster_midi_mode) |value|
                try writer.print(",\"clusterMidiMode\":{d}", .{value});
            if (entry.cluster_type != .other) {
                try writer.writeAll(",\"clusterType\":");
                try writeString(writer, @tagName(entry.cluster_type));
            }
            if (entry.links.len != 0) {
                try writer.writeAll(",\"links\":[");
                for (entry.links, 0..) |link, link_index| {
                    if (link_index != 0) try writer.writeByte(',');
                    try writeLink(link, writer);
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
    ) !std.json.Parsed(ChannelList) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            []const ChannelWire,
            allocator,
            source,
            .{ .ignore_unknown_fields = true },
        );
        errdefer parsed.deinit();
        if (parsed.value.len > maximum_channels)
            return error.InvalidMidiCiChannelList;
        const channels = try parsed.arena.allocator().alloc(Channel, parsed.value.len);
        for (parsed.value, channels) |wire, *channel| {
            channel.* = .{
                .title = wire.title,
                .channel = wire.channel,
                .program_title = wire.programTitle,
                .bank_program = wire.bankPC,
                .cluster_channel_start = wire.clusterChannelStart,
                .cluster_length = wire.clusterLength,
                .cluster_midi_mode = wire.clusterMidiMode,
                .cluster_type = wire.clusterType,
                .links = wire.links,
            };
        }
        const value = ChannelList{ .entries = channels };
        if (!value.valid()) return error.InvalidMidiCiChannelList;
        return transferParsed(ChannelList, parsed.arena, value);
    }
};

pub const SetSupport = enum {
    none,
    full,
    partial,
};

pub const Resource = struct {
    resource: []const u8,
    can_get: bool = true,
    can_set: SetSupport = .none,
    can_subscribe: bool = false,
    require_res_id: bool = false,
    can_paginate: bool = false,
    media_types: []const []const u8 = &.{"application/json"},
    encodings: []const property_json.Encoding = &.{.ascii},

    pub fn valid(self: Resource) bool {
        if (!validResource(self.resource) or
            self.media_types.len == 0 or
            self.media_types.len > maximum_media_types or
            self.encodings.len == 0 or
            self.encodings.len > std.meta.tags(property_json.Encoding).len)
            return false;
        for (self.media_types) |media_type| {
            if (media_type.len == 0 or media_type.len > 75) return false;
        }
        var seen_encodings = [_]bool{false} **
            std.meta.tags(property_json.Encoding).len;
        for (self.encodings) |encoding| {
            const index = @intFromEnum(encoding);
            if (seen_encodings[index]) return false;
            seen_encodings[index] = true;
        }
        return true;
    }
};

pub const ResourceList = struct {
    entries: []const Resource,

    pub fn valid(self: ResourceList) bool {
        if (self.entries.len > maximum_resources) return false;
        for (self.entries, 0..) |entry, index| {
            if (!entry.valid() or
                std.mem.eql(u8, entry.resource, "ResourceList"))
                return false;
            for (self.entries[0..index]) |previous| {
                if (std.mem.eql(u8, previous.resource, entry.resource))
                    return false;
            }
        }
        return true;
    }

    pub fn writeJson(self: ResourceList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiResourceList;
        try writer.writeByte('[');
        for (self.entries, 0..) |entry, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"resource\":");
            try writeString(writer, entry.resource);
            if (!entry.can_get)
                try writer.writeAll(",\"canGet\":false");
            if (entry.can_set != .none) {
                try writer.writeAll(",\"canSet\":");
                try writeString(writer, @tagName(entry.can_set));
            }
            if (entry.can_subscribe)
                try writer.writeAll(",\"canSubscribe\":true");
            if (entry.require_res_id)
                try writer.writeAll(",\"requireResId\":true");
            if (entry.can_paginate)
                try writer.writeAll(",\"canPaginate\":true");
            if (!defaultMediaTypes(entry.media_types)) {
                try writer.writeAll(",\"mediaTypes\":[");
                for (entry.media_types, 0..) |media_type, media_index| {
                    if (media_index != 0) try writer.writeByte(',');
                    try writeString(writer, media_type);
                }
                try writer.writeByte(']');
            }
            if (!defaultEncodings(entry.encodings)) {
                try writer.writeAll(",\"encodings\":[");
                for (entry.encodings, 0..) |encoding, encoding_index| {
                    if (encoding_index != 0) try writer.writeByte(',');
                    try writeString(writer, encoding.text());
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
    ) !std.json.Parsed(ResourceList) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            []const ResourceWire,
            allocator,
            source,
            .{ .ignore_unknown_fields = true },
        );
        errdefer parsed.deinit();
        if (parsed.value.len > maximum_resources)
            return error.InvalidMidiCiResourceList;
        const entries = try parsed.arena.allocator().alloc(
            Resource,
            parsed.value.len,
        );
        for (parsed.value, entries) |wire, *entry| {
            const encodings = try parsed.arena.allocator().alloc(
                property_json.Encoding,
                wire.encodings.len,
            );
            for (wire.encodings, encodings) |text, *encoding|
                encoding.* = try property_json.Encoding.parse(text);
            entry.* = .{
                .resource = wire.resource,
                .can_get = wire.canGet,
                .can_set = wire.canSet,
                .can_subscribe = wire.canSubscribe,
                .require_res_id = wire.requireResId,
                .can_paginate = wire.canPaginate,
                .media_types = wire.mediaTypes,
                .encodings = encodings,
            };
        }
        const value = ResourceList{ .entries = entries };
        if (!value.valid()) return error.InvalidMidiCiResourceList;
        return transferParsed(ResourceList, parsed.arena, value);
    }
};

pub fn parseJsonSchema(
    allocator: std.mem.Allocator,
    source: []const u8,
) !std.json.Parsed(std.json.Value) {
    try validatePropertyData(source);
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        source,
        .{},
    );
    errdefer parsed.deinit();
    switch (parsed.value) {
        .object => {},
        else => return error.InvalidMidiCiJsonSchema,
    }
    return parsed;
}

const LinkWire = struct {
    resource: []const u8,
    resId: ?[]const u8 = null,
    title: ?[]const u8 = null,
    role: ?[]const u8 = null,
};

const DeviceInfoWire = struct {
    manufacturerId: [3]u7,
    familyId: [2]u7,
    modelId: [2]u7,
    versionId: [4]u7,
    manufacturer: []const u8,
    family: []const u8,
    model: []const u8,
    version: []const u8,
    serialNumber: ?[]const u8 = null,
    links: []const Link = &.{},
};

const ChannelWire = struct {
    title: []const u8,
    channel: u16,
    programTitle: ?[]const u8 = null,
    bankPC: ?[3]u7 = null,
    clusterChannelStart: ?u16 = null,
    clusterLength: ?u16 = null,
    clusterMidiMode: ?u3 = null,
    clusterType: ClusterType = .other,
    links: []const Link = &.{},
};

const ResourceWire = struct {
    resource: []const u8,
    canGet: bool = true,
    canSet: SetSupport = .none,
    canSubscribe: bool = false,
    requireResId: bool = false,
    canPaginate: bool = false,
    mediaTypes: []const []const u8 = &.{"application/json"},
    encodings: []const []const u8 = &.{"ASCII"},
};

fn validatePropertyData(source: []const u8) !void {
    if (source.len == 0 or source.len > maximum_property_bytes)
        return error.InvalidMidiCiPropertyDataLength;
    for (source) |byte| {
        if (byte > 0x7f) return error.InvalidMidiCiPropertyDataByte;
    }
}

fn validResource(source: []const u8) bool {
    if (source.len == 0 or source.len > 36) return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '-') return false;
    }
    return true;
}

fn validResourceId(source: []const u8) bool {
    if (source.len == 0 or source.len > 36) return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn writeString(writer: anytype, source: []const u8) !void {
    try writer.print("{f}", .{
        std.json.fmt(source, .{ .escape_unicode = true }),
    });
}

fn writeLink(link: Link, writer: anytype) !void {
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

fn defaultMediaTypes(values: []const []const u8) bool {
    return values.len == 1 and
        std.mem.eql(u8, values[0], "application/json");
}

fn defaultEncodings(values: []const property_json.Encoding) bool {
    return values.len == 1 and values[0] == .ascii;
}

fn transferParsed(
    comptime T: type,
    arena: *std.heap.ArenaAllocator,
    value: T,
) std.json.Parsed(T) {
    return .{ .arena = arena, .value = value };
}

test "DeviceInfo round trips identity strings links and escaped Unicode" {
    const links = [_]Link{.{ .resource = "X-SystemSettings" }};
    const expected = DeviceInfo{
        .manufacturer_id = .{ 0x7d, 0, 0 },
        .family_id = .{ 1, 0 },
        .model_id = .{ 48, 0 },
        .version_id = .{ 0, 0, 1, 0 },
        .manufacturer = "Educational Use",
        .family = "Test Range",
        .model = "Piano \xe2\x99\xaa",
        .version = "1.0",
        .serial_number = "abc123",
        .links = &links,
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try expected.writeJson(&output.writer);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\\u266a") != null);
    const parsed = try DeviceInfo.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqual(expected.manufacturer_id, parsed.value.manufacturer_id);
    try std.testing.expectEqualStrings(expected.model, parsed.value.model);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.links.len);
}

test "ChannelList round trips channels clusters programs and links" {
    const links = [_]Link{.{ .resource = "ProgramList", .res_id = "presets" }};
    const entries = [_]Channel{
        .{
            .title = "Lead",
            .channel = 1,
            .program_title = "Piano",
            .bank_program = .{ 1, 0, 76 },
            .links = &links,
        },
        .{
            .title = "MPE Lower",
            .channel = 1,
            .cluster_channel_start = 2,
            .cluster_length = 6,
            .cluster_midi_mode = 4,
            .cluster_type = .mpe1,
        },
    };
    const expected = ChannelList{ .entries = &entries };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try expected.writeJson(&output.writer);
    const parsed = try ChannelList.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.entries.len);
    try std.testing.expectEqual(
        ClusterType.mpe1,
        parsed.value.entries[1].cluster_type,
    );
}

test "Foundational resources reject malformed bounds" {
    try std.testing.expectError(
        error.InvalidMidiCiChannelList,
        ChannelList.parseJson(
            std.testing.allocator,
            "[{\"title\":\"Bad\",\"channel\":0}]",
        ),
    );
    try std.testing.expectError(
        error.Overflow,
        DeviceInfo.parseJson(
            std.testing.allocator,
            "{\"manufacturerId\":[128,0,0],\"familyId\":[0,0],\"modelId\":[0,0],\"versionId\":[0,0,0,0],\"manufacturer\":\"M\",\"family\":\"F\",\"model\":\"X\",\"version\":\"1\"}",
        ),
    );
    try std.testing.expectError(
        error.InvalidMidiCiJsonSchema,
        parseJsonSchema(std.testing.allocator, "[]"),
    );
}

test "ResourceList applies defaults and round trips capability overrides" {
    const media_types = [_][]const u8{"application/octet-stream"};
    const encodings = [_]property_json.Encoding{.mcoded7};
    const resources = [_]Resource{
        .{ .resource = "DeviceInfo" },
        .{
            .resource = "ChannelList",
            .can_subscribe = true,
            .can_paginate = true,
        },
        .{
            .resource = "X-Sample",
            .can_get = false,
            .can_set = .full,
            .require_res_id = true,
            .media_types = &media_types,
            .encodings = &encodings,
        },
    };
    const expected = ResourceList{ .entries = &resources };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try expected.writeJson(&output.writer);
    const parsed = try ResourceList.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.value.entries.len);
    try std.testing.expect(parsed.value.entries[0].can_get);
    try std.testing.expectEqual(
        SetSupport.full,
        parsed.value.entries[2].can_set,
    );
    try std.testing.expectEqual(
        property_json.Encoding.mcoded7,
        parsed.value.entries[2].encodings[0],
    );
}

test "ResourceList rejects itself duplicates and unsupported encodings" {
    const invalid = [_][]const u8{
        "[{\"resource\":\"ResourceList\"}]",
        "[{\"resource\":\"DeviceInfo\"},{\"resource\":\"DeviceInfo\"}]",
        "[{\"resource\":\"DeviceInfo\",\"encodings\":[\"unknown\"]}]",
    };
    for (invalid) |source| {
        if (ResourceList.parseJson(std.testing.allocator, source)) |parsed| {
            parsed.deinit();
            return error.TestExpectedError;
        } else |_| {}
    }
}
