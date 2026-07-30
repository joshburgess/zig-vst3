const std = @import("std");
const resources = @import("midi_ci_property_resources.zig");

pub const maximum_controllers = 2_048;
pub const maximum_map_entries = 2_048;

pub const ControllerType = enum {
    cc,
    ch_press,
    p_press,
    nrpn,
    rpn,
    p_bend,
    pnrc,
    pnac,
    pnp,

    fn text(self: ControllerType) []const u8 {
        return switch (self) {
            .cc => "cc",
            .ch_press => "chPress",
            .p_press => "pPress",
            .nrpn => "nrpn",
            .rpn => "rpn",
            .p_bend => "pBend",
            .pnrc => "pnrc",
            .pnac => "pnac",
            .pnp => "pnp",
        };
    }
};

pub const Direction = enum {
    absolute,
    relative,
    both,
    none,
};

pub const TypeHint = enum {
    continuous,
    momentary,
    toggle,
    relative,
    value_select,

    fn text(self: TypeHint) []const u8 {
        return if (self == .value_select) "valueSelect" else @tagName(self);
    }
};

pub const Controller = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    channel: ?u16 = null,
    controller_type: ControllerType,
    controller_index: ?[]const u7 = null,
    priority: ?u3 = null,
    default_value: ?u32 = null,
    transmit: Direction = .absolute,
    recognize: Direction = .absolute,
    significant_bits: u6 = 32,
    parameter_path: ?[]const u8 = null,
    type_hint: ?TypeHint = null,
    controller_map_id: ?[]const u8 = null,
    step_count: ?u32 = null,
    minimum_maximum: ?[2]u32 = null,
    default_cc_map: bool = false,

    pub fn valid(self: Controller) bool {
        if (self.title.len == 0 or self.significant_bits == 0 or
            self.significant_bits > 32)
            return false;
        if (self.channel) |channel| {
            if (channel == 0 or channel > 256) return false;
        }
        if (self.priority) |priority| {
            if (priority == 0 or priority > 5) return false;
        }
        const index_required = switch (self.controller_type) {
            .ch_press, .p_press, .p_bend, .pnp => false,
            else => true,
        };
        if (self.controller_index) |index| {
            if (index.len == 0 or index.len > 2) return false;
        } else if (index_required) return false;
        if (self.parameter_path) |path| {
            if (!validJsonPointer(path)) return false;
        }
        if (self.controller_map_id) |map_id| {
            if (!validId(map_id)) return false;
        }
        if (self.type_hint == .value_select and self.controller_map_id == null)
            return false;
        if (self.step_count) |count| {
            if (count == 0 or self.minimum_maximum != null) return false;
        }
        if (self.minimum_maximum) |range| {
            if (range[0] > range[1]) return false;
        }
        if (self.default_cc_map and self.controller_type != .cc) return false;
        return true;
    }
};

pub const AllControllerList = struct {
    entries: []const Controller,

    pub fn valid(self: AllControllerList) bool {
        return validControllerList(self.entries, true);
    }

    pub fn writeJson(self: AllControllerList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiAllControllerList;
        try writeControllers(writer, self.entries, true);
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(AllControllerList) {
        const parsed = try parseControllers(allocator, source);
        errdefer parsed.deinit();
        const value = AllControllerList{ .entries = parsed.value };
        if (!value.valid()) return error.InvalidMidiCiAllControllerList;
        return .{ .arena = parsed.arena, .value = value };
    }
};

pub const ChannelControllerList = struct {
    entries: []const Controller,

    pub fn valid(self: ChannelControllerList) bool {
        return validControllerList(self.entries, false);
    }

    pub fn writeJson(self: ChannelControllerList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiChannelControllerList;
        try writeControllers(writer, self.entries, false);
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(ChannelControllerList) {
        const parsed = try parseControllers(allocator, source);
        errdefer parsed.deinit();
        const value = ChannelControllerList{ .entries = parsed.value };
        if (!value.valid()) return error.InvalidMidiCiChannelControllerList;
        return .{ .arena = parsed.arena, .value = value };
    }
};

pub const ControllerMapEntry = struct {
    value: u32,
    title: []const u8,

    pub fn valid(self: ControllerMapEntry) bool {
        return self.title.len != 0;
    }
};

pub const ControllerMapList = struct {
    entries: []const ControllerMapEntry,

    pub fn valid(self: ControllerMapList) bool {
        if (self.entries.len > maximum_map_entries) return false;
        for (self.entries, 0..) |entry, index| {
            if (!entry.valid()) return false;
            for (self.entries[0..index]) |previous| {
                if (previous.value == entry.value) return false;
            }
        }
        return true;
    }

    pub fn writeJson(self: ControllerMapList, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiControllerMapList;
        try writer.writeByte('[');
        for (self.entries, 0..) |entry, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.print("{{\"value\":{d},\"title\":", .{entry.value});
            try writeString(writer, entry.title);
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(ControllerMapList) {
        try validatePropertyData(source);
        var parsed = try std.json.parseFromSlice(
            []const ControllerMapEntry,
            allocator,
            source,
            .{ .ignore_unknown_fields = true },
        );
        errdefer parsed.deinit();
        const value = ControllerMapList{ .entries = parsed.value };
        if (!value.valid()) return error.InvalidMidiCiControllerMapList;
        return .{ .arena = parsed.arena, .value = value };
    }
};

pub const all_controller_list_resource = resources.Resource{
    .resource = "AllCtrlList",
};
pub const channel_controller_list_resource = resources.Resource{
    .resource = "ChCtrlList",
    .require_res_id = true,
};
pub const controller_map_list_resource = resources.Resource{
    .resource = "CtrlMapList",
    .require_res_id = true,
};

const ControllerWire = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    channel: ?u16 = null,
    ctrlType: WireControllerType,
    ctrlIndex: ?[]const u7 = null,
    priority: ?u3 = null,
    default: ?u32 = null,
    transmit: Direction = .absolute,
    recognize: Direction = .absolute,
    numSigBits: u6 = 32,
    paramPath: ?[]const u8 = null,
    typeHint: ?WireTypeHint = null,
    ctrlMapId: ?[]const u8 = null,
    stepCount: ?u32 = null,
    minMax: ?[2]u32 = null,
    defaultCCMap: bool = false,
};

const WireControllerType = enum {
    cc,
    chPress,
    pPress,
    nrpn,
    rpn,
    pBend,
    pnrc,
    pnac,
    pnp,

    fn model(self: WireControllerType) ControllerType {
        return switch (self) {
            .cc => .cc,
            .chPress => .ch_press,
            .pPress => .p_press,
            .nrpn => .nrpn,
            .rpn => .rpn,
            .pBend => .p_bend,
            .pnrc => .pnrc,
            .pnac => .pnac,
            .pnp => .pnp,
        };
    }
};

const WireTypeHint = enum {
    continuous,
    momentary,
    toggle,
    relative,
    valueSelect,

    fn model(self: WireTypeHint) TypeHint {
        return switch (self) {
            .continuous => .continuous,
            .momentary => .momentary,
            .toggle => .toggle,
            .relative => .relative,
            .valueSelect => .value_select,
        };
    }
};

fn parseControllers(
    allocator: std.mem.Allocator,
    source: []const u8,
) !std.json.Parsed([]const Controller) {
    try validatePropertyData(source);
    var parsed = try std.json.parseFromSlice(
        []const ControllerWire,
        allocator,
        source,
        .{ .ignore_unknown_fields = true },
    );
    errdefer parsed.deinit();
    if (parsed.value.len > maximum_controllers)
        return error.InvalidMidiCiControllerList;
    const entries = try parsed.arena.allocator().alloc(
        Controller,
        parsed.value.len,
    );
    for (parsed.value, entries) |wire, *entry| {
        entry.* = .{
            .title = wire.title,
            .description = wire.description,
            .channel = wire.channel,
            .controller_type = wire.ctrlType.model(),
            .controller_index = wire.ctrlIndex,
            .priority = wire.priority,
            .default_value = wire.default,
            .transmit = wire.transmit,
            .recognize = wire.recognize,
            .significant_bits = wire.numSigBits,
            .parameter_path = wire.paramPath,
            .type_hint = if (wire.typeHint) |hint| hint.model() else null,
            .controller_map_id = wire.ctrlMapId,
            .step_count = wire.stepCount,
            .minimum_maximum = wire.minMax,
            .default_cc_map = wire.defaultCCMap,
        };
    }
    return .{ .arena = parsed.arena, .value = entries };
}

fn validControllerList(entries: []const Controller, all_channels: bool) bool {
    if (entries.len > maximum_controllers) return false;
    for (entries, 0..) |entry, index| {
        if (!entry.valid() or (entry.channel != null) != all_channels)
            return false;
        var duplicate_count: usize = 0;
        var complementary = false;
        for (entries[0..index]) |previous| {
            if (!sameIdentity(previous, entry)) continue;
            duplicate_count += 1;
            complementary = (previous.transmit == .none and
                entry.recognize == .none) or
                (previous.recognize == .none and entry.transmit == .none);
        }
        if (duplicate_count > 1 or (duplicate_count == 1 and !complementary))
            return false;
    }
    return true;
}

fn sameIdentity(a: Controller, b: Controller) bool {
    if (a.channel != b.channel or a.controller_type != b.controller_type)
        return false;
    if (a.controller_index == null or b.controller_index == null)
        return a.controller_index == null and b.controller_index == null;
    return std.mem.eql(u7, a.controller_index.?, b.controller_index.?);
}

fn writeControllers(writer: anytype, entries: []const Controller, include_channel: bool) !void {
    try writer.writeByte('[');
    for (entries, 0..) |entry, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll("{\"title\":");
        try writeString(writer, entry.title);
        if (entry.description) |value| {
            try writer.writeAll(",\"description\":");
            try writeString(writer, value);
        }
        if (include_channel)
            try writer.print(",\"channel\":{d}", .{entry.channel.?});
        try writer.writeAll(",\"ctrlType\":");
        try writeString(writer, entry.controller_type.text());
        if (entry.controller_index) |values| {
            try writer.writeAll(",\"ctrlIndex\":[");
            for (values, 0..) |value, value_index| {
                if (value_index != 0) try writer.writeByte(',');
                try writer.print("{d}", .{value});
            }
            try writer.writeByte(']');
        }
        if (entry.priority) |value| try writer.print(",\"priority\":{d}", .{value});
        if (entry.default_value) |value| try writer.print(",\"default\":{d}", .{value});
        if (entry.transmit != .absolute) {
            try writer.writeAll(",\"transmit\":");
            try writeString(writer, @tagName(entry.transmit));
        }
        if (entry.recognize != .absolute) {
            try writer.writeAll(",\"recognize\":");
            try writeString(writer, @tagName(entry.recognize));
        }
        if (entry.significant_bits != 32)
            try writer.print(",\"numSigBits\":{d}", .{entry.significant_bits});
        if (entry.parameter_path) |value| {
            try writer.writeAll(",\"paramPath\":");
            try writeString(writer, value);
        }
        if (entry.type_hint) |value| {
            try writer.writeAll(",\"typeHint\":");
            try writeString(writer, value.text());
        }
        if (entry.controller_map_id) |value| {
            try writer.writeAll(",\"ctrlMapId\":");
            try writeString(writer, value);
        }
        if (entry.step_count) |value| try writer.print(",\"stepCount\":{d}", .{value});
        if (entry.minimum_maximum) |value|
            try writer.print(",\"minMax\":[{d},{d}]", .{ value[0], value[1] });
        if (entry.default_cc_map)
            try writer.writeAll(",\"defaultCCMap\":true");
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn validJsonPointer(source: []const u8) bool {
    if (source.len > 256 or (source.len != 0 and source[0] != '/')) return false;
    var index: usize = 0;
    while (index < source.len) : (index += 1) {
        if (source[index] != '~') continue;
        index += 1;
        if (index == source.len or
            (source[index] != '0' and source[index] != '1'))
            return false;
    }
    return true;
}

fn validId(source: []const u8) bool {
    if (source.len == 0 or source.len > 36) return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn validatePropertyData(source: []const u8) !void {
    if (source.len == 0 or source.len > resources.maximum_property_bytes)
        return error.InvalidMidiCiPropertyDataLength;
    for (source) |byte| {
        if (byte > 0x7f) return error.InvalidMidiCiPropertyDataByte;
    }
}

fn writeString(writer: anytype, source: []const u8) !void {
    try writer.print("{f}", .{
        std.json.fmt(source, .{ .escape_unicode = true }),
    });
}

test "controller resources round trip channel scope and value maps" {
    const index = [_]u7{ 7, 39 };
    const controllers = [_]Controller{.{
        .title = "Volume",
        .channel = 17,
        .controller_type = .cc,
        .controller_index = &index,
        .priority = 1,
        .default_value = std.math.maxInt(u32),
        .parameter_path = "/mixer/volume",
        .minimum_maximum = .{ 0, std.math.maxInt(u32) },
    }};
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try (AllControllerList{ .entries = &controllers }).writeJson(&output.writer);
    const parsed = try AllControllerList.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?u16, 17), parsed.value.entries[0].channel);
    try std.testing.expectEqual(ControllerType.cc, parsed.value.entries[0].controller_type);

    output.clearRetainingCapacity();
    const map = [_]ControllerMapEntry{
        .{ .value = 0, .title = "Off" },
        .{ .value = std.math.maxInt(u32), .title = "On" },
    };
    try (ControllerMapList{ .entries = &map }).writeJson(&output.writer);
    const parsed_map = try ControllerMapList.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed_map.deinit();
    try std.testing.expectEqual(std.math.maxInt(u32), parsed_map.value.entries[1].value);
}

test "controller resources enforce scope shape and paired duplicates" {
    const index = [_]u7{2};
    const pair = [_]Controller{
        .{
            .title = "Vibrato",
            .controller_type = .cc,
            .controller_index = &index,
            .transmit = .none,
        },
        .{
            .title = "Wheel",
            .controller_type = .cc,
            .controller_index = &index,
            .recognize = .none,
        },
    };
    try std.testing.expect((ChannelControllerList{ .entries = &pair }).valid());
    try std.testing.expect(!(AllControllerList{ .entries = &pair }).valid());
    try std.testing.expect(!(Controller{
        .title = "Bad",
        .controller_type = .cc,
        .controller_index = &index,
        .type_hint = .value_select,
    }).valid());
    try std.testing.expect(!(Controller{
        .title = "Bad",
        .controller_type = .nrpn,
        .controller_index = &index,
        .step_count = 4,
        .minimum_maximum = .{ 0, 3 },
    }).valid());

    const invalid_all = [_][]const u8{
        "[{\"title\":\"No channel\",\"ctrlType\":\"cc\",\"ctrlIndex\":[1]}]",
        "[{\"title\":\"No index\",\"channel\":1,\"ctrlType\":\"cc\"}]",
        "[{\"title\":\"Bad bits\",\"channel\":1,\"ctrlType\":\"pBend\",\"numSigBits\":0}]",
        "[{\"title\":\"Bad pointer\",\"channel\":1,\"ctrlType\":\"pBend\",\"paramPath\":\"not/a/pointer\"}]",
        "[{\"title\":\"Bad selection\",\"channel\":1,\"ctrlType\":\"pBend\",\"typeHint\":\"valueSelect\"}]",
        "[{\"title\":\"Conflicting range\",\"channel\":1,\"ctrlType\":\"pBend\",\"stepCount\":4,\"minMax\":[0,3]}]",
    };
    for (invalid_all) |source| {
        if (AllControllerList.parseJson(std.testing.allocator, source)) |parsed| {
            parsed.deinit();
            return error.TestExpectedError;
        } else |_| {}
    }
    try std.testing.expectError(
        error.InvalidMidiCiControllerMapList,
        ControllerMapList.parseJson(
            std.testing.allocator,
            "[{\"value\":1,\"title\":\"One\"},{\"value\":1,\"title\":\"Again\"}]",
        ),
    );
}
