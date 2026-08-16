const std = @import("std");

pub const max_auxiliary_audio_buses = 8;
pub const max_audio_buses_per_direction =
    max_auxiliary_audio_buses + 1;

pub const AudioBusLayout = enum {
    none,
    mono,
    stereo,
    surround_3_0,
    quadraphonic,
    surround_5_0,
    surround_5_1,
    surround_7_0,
    surround_7_1,
    surround_5_1_2,
    surround_7_1_4,
    ambisonic_first_order,
    ambisonic_second_order,
    ambisonic_third_order,
    stereo_wide,
    stereo_surround,
    stereo_center,
    stereo_side,
    surround_3_0_music,
    surround_3_1,
    surround_3_1_music,
    surround_4_0_cine,
    surround_4_1,
    surround_4_1_cine,
    surround_6_0,
    surround_6_0_cine,
    surround_6_1,
    surround_6_1_cine,
    surround_7_0_sdds,
    surround_7_1_sdds,
    surround_5_0_2,
    surround_5_0_4,
    surround_5_1_4,
    surround_7_0_2,
    surround_7_1_2,
    surround_7_0_4,
    ambisonic_fourth_order,
    ambisonic_fifth_order,
    ambisonic_sixth_order,
    ambisonic_seventh_order,

    pub fn channelCount(self: AudioBusLayout) u8 {
        return switch (self) {
            .none => 0,
            .mono => 1,
            .stereo,
            .stereo_wide,
            .stereo_surround,
            .stereo_center,
            .stereo_side,
            => 2,
            .surround_3_0, .surround_3_0_music => 3,
            .surround_3_1,
            .surround_3_1_music,
            .quadraphonic,
            .surround_4_0_cine,
            .ambisonic_first_order,
            => 4,
            .surround_4_1,
            .surround_4_1_cine,
            .surround_5_0,
            => 5,
            .surround_5_1,
            .surround_6_0,
            .surround_6_0_cine,
            => 6,
            .surround_6_1,
            .surround_6_1_cine,
            .surround_7_0,
            .surround_7_0_sdds,
            .surround_5_0_2,
            => 7,
            .surround_7_1,
            .surround_7_1_sdds,
            .surround_5_1_2,
            => 8,
            .surround_5_0_4,
            .surround_7_0_2,
            .ambisonic_second_order,
            => 9,
            .surround_5_1_4, .surround_7_1_2 => 10,
            .surround_7_0_4 => 11,
            .surround_7_1_4 => 12,
            .ambisonic_third_order => 16,
            .ambisonic_fourth_order => 25,
            .ambisonic_fifth_order => 36,
            .ambisonic_sixth_order => 49,
            .ambisonic_seventh_order => 64,
        };
    }

    pub fn hasBus(self: AudioBusLayout) bool {
        return self != .none;
    }
};

pub const AudioBusDirection = enum {
    input,
    output,
};

pub const AudioBusLayoutSet = struct {
    bits: u64,

    pub fn init(layouts: []const AudioBusLayout) !AudioBusLayoutSet {
        var result = AudioBusLayoutSet{ .bits = 0 };
        for (layouts) |layout| {
            if (!layout.hasBus())
                return error.InvalidDynamicAudioBusLayout;
            result.bits |= layoutBit(layout);
        }
        if (result.bits == 0)
            return error.EmptyDynamicAudioBusLayouts;
        return result;
    }

    pub fn single(layout: AudioBusLayout) !AudioBusLayoutSet {
        return init(&.{layout});
    }

    pub fn contains(
        self: AudioBusLayoutSet,
        layout: AudioBusLayout,
    ) bool {
        return layout.hasBus() and self.bits & layoutBit(layout) != 0;
    }

    pub fn valid(self: AudioBusLayoutSet) bool {
        const layout_count =
            @typeInfo(AudioBusLayout).@"enum".fields.len;
        const valid_bits =
            (@as(u64, 1) << @intCast(layout_count)) - 1;
        return self.bits != 0 and
            self.bits & layoutBit(.none) == 0 and
            self.bits & ~valid_bits == 0;
    }
};

pub const DynamicAudioBus = struct {
    layout: AudioBusLayout,
    supported_layouts: AudioBusLayoutSet,
    default_active: bool,
    active: bool = true,

    pub fn init(
        layout: AudioBusLayout,
        supported_layouts: AudioBusLayoutSet,
        active: bool,
    ) !DynamicAudioBus {
        const result = DynamicAudioBus{
            .layout = layout,
            .supported_layouts = supported_layouts,
            .default_active = active,
            .active = active,
        };
        if (!result.valid())
            return error.InvalidDynamicAudioBus;
        return result;
    }

    pub fn fixed(
        layout: AudioBusLayout,
        active: bool,
    ) !DynamicAudioBus {
        return init(
            layout,
            try AudioBusLayoutSet.single(layout),
            active,
        );
    }

    pub fn valid(self: DynamicAudioBus) bool {
        return self.layout.hasBus() and
            self.supported_layouts.valid() and
            self.supported_layouts.contains(self.layout);
    }
};

pub const DynamicAudioBusState = struct {
    layout: AudioBusLayout,
    default_active: bool,
    active: bool,
};

pub fn BoundedDynamicAudioBusSnapshot(
    comptime maximum_auxiliary_buses: usize,
) type {
    validateDynamicAudioBusCapacity(maximum_auxiliary_buses);
    const maximum_audio_buses = maximum_auxiliary_buses + 1;

    return struct {
        const Self = @This();
        pub const auxiliary_capacity = maximum_auxiliary_buses;
        pub const bus_capacity = maximum_audio_buses;

        input_layouts: [maximum_audio_buses]AudioBusLayout =
            @splat(.none),
        output_layouts: [maximum_audio_buses]AudioBusLayout =
            @splat(.none),
        input_active: [maximum_audio_buses]bool = @splat(false),
        output_active: [maximum_audio_buses]bool = @splat(false),
        input_default_active: [maximum_audio_buses]bool = @splat(false),
        output_default_active: [maximum_audio_buses]bool = @splat(false),
        input_count: u8 = 0,
        output_count: u8 = 0,
        generation: u64 = 0,

        pub fn busCount(
            self: *const Self,
            direction: AudioBusDirection,
        ) usize {
            if (!self.valid()) return 0;
            return switch (direction) {
                .input => self.input_count,
                .output => self.output_count,
            };
        }

        pub fn bus(
            self: *const Self,
            direction: AudioBusDirection,
            index: usize,
        ) ?DynamicAudioBusState {
            if (index >= self.busCount(direction)) return null;
            return switch (direction) {
                .input => .{
                    .layout = self.input_layouts[index],
                    .default_active = self.input_default_active[index],
                    .active = self.input_active[index],
                },
                .output => .{
                    .layout = self.output_layouts[index],
                    .default_active = self.output_default_active[index],
                    .active = self.output_active[index],
                },
            };
        }

        pub fn valid(self: *const Self) bool {
            if (@inComptime())
                @setEvalBranchQuota(100_000);
            if (self.input_count > maximum_audio_buses or
                self.output_count > maximum_audio_buses)
                return false;
            for (self.input_layouts[0..self.input_count]) |layout|
                if (!layout.hasBus()) return false;
            for (self.output_layouts[0..self.output_count]) |layout|
                if (!layout.hasBus()) return false;
            for (self.input_layouts[self.input_count..]) |layout|
                if (layout != .none) return false;
            for (self.output_layouts[self.output_count..]) |layout|
                if (layout != .none) return false;
            for (self.input_active[self.input_count..]) |active|
                if (active) return false;
            for (self.output_active[self.output_count..]) |active|
                if (active) return false;
            for (self.input_default_active[self.input_count..]) |active|
                if (active) return false;
            for (self.output_default_active[self.output_count..]) |active|
                if (active) return false;
            return true;
        }
    };
}

pub const DynamicAudioBusSnapshot =
    BoundedDynamicAudioBusSnapshot(max_auxiliary_audio_buses);

pub fn BoundedDynamicAudioBusTopology(
    comptime maximum_auxiliary_buses: usize,
) type {
    validateDynamicAudioBusCapacity(maximum_auxiliary_buses);
    const maximum_audio_buses = maximum_auxiliary_buses + 1;
    const Snapshot =
        BoundedDynamicAudioBusSnapshot(maximum_auxiliary_buses);

    return struct {
        const Self = @This();
        pub const SnapshotType = Snapshot;
        pub const auxiliary_capacity = maximum_auxiliary_buses;
        pub const bus_capacity = maximum_audio_buses;
        pub const maximum_encoded_size =
            3 + 2 * maximum_audio_buses * 11;

        input_buses: [maximum_audio_buses]DynamicAudioBus =
            @splat(unused_bus),
        output_buses: [maximum_audio_buses]DynamicAudioBus =
            @splat(unused_bus),
        input_count: u8 = 0,
        output_count: u8 = 0,
        current_generation: u64 = 0,

        pub fn init(
            main_input: ?DynamicAudioBus,
            main_output: ?DynamicAudioBus,
        ) !Self {
            var result = Self{};
            if (main_input) |bus_value| {
                if (!bus_value.valid()) return error.InvalidDynamicAudioBus;
                result.input_buses[0] = bus_value;
                result.input_count = 1;
            }
            if (main_output) |bus_value| {
                if (!bus_value.valid()) return error.InvalidDynamicAudioBus;
                result.output_buses[0] = bus_value;
                result.output_count = 1;
            }
            return result;
        }

        pub fn busCount(
            self: *const Self,
            direction: AudioBusDirection,
        ) usize {
            if (!self.valid()) return 0;
            return switch (direction) {
                .input => self.input_count,
                .output => self.output_count,
            };
        }

        pub fn bus(
            self: *const Self,
            direction: AudioBusDirection,
            index: usize,
        ) ?DynamicAudioBus {
            const count = self.busCount(direction);
            if (index >= count) return null;
            return busesForConst(self, direction)[index];
        }

        pub fn generation(self: *const Self) ?u64 {
            if (!self.valid()) return null;
            return self.current_generation;
        }

        pub fn snapshot(
            self: *const Self,
        ) !Snapshot {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            var result = Snapshot{
                .input_count = self.input_count,
                .output_count = self.output_count,
                .generation = self.current_generation,
            };
            for (self.input_buses[0..self.input_count], 0..) |bus_value, index| {
                result.input_layouts[index] = bus_value.layout;
                result.input_default_active[index] = bus_value.default_active;
                result.input_active[index] = bus_value.active;
            }
            for (self.output_buses[0..self.output_count], 0..) |bus_value, index| {
                result.output_layouts[index] = bus_value.layout;
                result.output_default_active[index] = bus_value.default_active;
                result.output_active[index] = bus_value.active;
            }
            return result;
        }

        pub fn writeState(
            self: *const Self,
            writer: anytype,
        ) !void {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            try writer.writeByte(2);
            try writer.writeByte(self.input_count);
            try writer.writeByte(self.output_count);
            for (self.input_buses[0..self.input_count]) |bus_value|
                try writeBusState(writer, bus_value);
            for (self.output_buses[0..self.output_count]) |bus_value|
                try writeBusState(writer, bus_value);
        }

        pub fn readState(reader: anytype) !Self {
            const version = try reader.takeByte();
            if (version != 1 and version != 2)
                return error.UnsupportedDynamicAudioBusState;
            const input_count = try reader.takeByte();
            const output_count = try reader.takeByte();
            if (input_count > maximum_audio_buses or
                output_count > maximum_audio_buses)
                return error.InvalidDynamicAudioBusTopology;
            var result = Self{
                .input_count = input_count,
                .output_count = output_count,
            };
            for (result.input_buses[0..input_count]) |*bus_value|
                bus_value.* = try readBusState(reader, version);
            for (result.output_buses[0..output_count]) |*bus_value|
                bus_value.* = try readBusState(reader, version);
            if (reader.seek != reader.end)
                return error.InvalidDynamicAudioBusState;
            if (!result.valid())
                return error.InvalidDynamicAudioBusTopology;
            return result;
        }

        pub fn addAuxiliary(
            self: *Self,
            direction: AudioBusDirection,
            bus_value: DynamicAudioBus,
        ) !u64 {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            if (!bus_value.valid())
                return error.InvalidDynamicAudioBus;
            const count = countFor(self, direction);
            if (count.* == 0)
                return error.DynamicAudioBusRequiresMain;
            if (count.* >= maximum_audio_buses)
                return error.TooManyDynamicAudioBuses;
            busesFor(self, direction)[count.*] = bus_value;
            count.* += 1;
            return advanceGeneration(self);
        }

        pub fn removeAuxiliary(
            self: *Self,
            direction: AudioBusDirection,
            auxiliary_index: usize,
        ) !u64 {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            const count = countFor(self, direction);
            if (count.* <= 1 or
                auxiliary_index >= @as(usize, count.* - 1))
                return error.DynamicAudioBusOutOfRange;
            const index = auxiliary_index + 1;
            const buses = busesFor(self, direction);
            var cursor = index;
            while (cursor + 1 < count.*) : (cursor += 1)
                buses[cursor] = buses[cursor + 1];
            count.* -= 1;
            buses[count.*] = unused_bus;
            return advanceGeneration(self);
        }

        pub fn setLayout(
            self: *Self,
            direction: AudioBusDirection,
            index: usize,
            layout: AudioBusLayout,
        ) !u64 {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            const count = countFor(self, direction).*;
            if (index >= count)
                return error.DynamicAudioBusOutOfRange;
            const bus_value = &busesFor(self, direction)[index];
            if (!bus_value.supported_layouts.contains(layout))
                return error.UnsupportedDynamicAudioBusLayout;
            if (bus_value.layout == layout)
                return self.current_generation;
            bus_value.layout = layout;
            return advanceGeneration(self);
        }

        pub fn setLayouts(
            self: *Self,
            input_layouts: []const AudioBusLayout,
            output_layouts: []const AudioBusLayout,
        ) !u64 {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            if (input_layouts.len != self.input_count or
                output_layouts.len != self.output_count)
                return error.DynamicAudioBusCountMismatch;
            for (input_layouts, 0..) |layout, index| {
                if (!self.input_buses[index].supported_layouts.contains(layout))
                    return error.UnsupportedDynamicAudioBusLayout;
            }
            for (output_layouts, 0..) |layout, index| {
                if (!self.output_buses[index].supported_layouts.contains(layout))
                    return error.UnsupportedDynamicAudioBusLayout;
            }
            var changed = false;
            for (input_layouts, 0..) |layout, index|
                changed = changed or self.input_buses[index].layout != layout;
            for (output_layouts, 0..) |layout, index|
                changed = changed or self.output_buses[index].layout != layout;
            if (!changed) return self.current_generation;
            for (input_layouts, 0..) |layout, index|
                self.input_buses[index].layout = layout;
            for (output_layouts, 0..) |layout, index|
                self.output_buses[index].layout = layout;
            return advanceGeneration(self);
        }

        pub fn setActive(
            self: *Self,
            direction: AudioBusDirection,
            index: usize,
            active: bool,
        ) !u64 {
            if (!self.valid())
                return error.InvalidDynamicAudioBusTopology;
            const count = countFor(self, direction).*;
            if (index >= count)
                return error.DynamicAudioBusOutOfRange;
            const bus_value = &busesFor(self, direction)[index];
            if (bus_value.active == active)
                return self.current_generation;
            bus_value.active = active;
            return advanceGeneration(self);
        }

        pub fn valid(self: *const Self) bool {
            if (@inComptime())
                @setEvalBranchQuota(100_000);
            if (self.input_count > maximum_audio_buses or
                self.output_count > maximum_audio_buses)
                return false;
            for (self.input_buses[0..self.input_count]) |bus_value|
                if (!bus_value.valid()) return false;
            for (self.output_buses[0..self.output_count]) |bus_value|
                if (!bus_value.valid()) return false;
            return true;
        }

        fn advanceGeneration(self: *Self) u64 {
            self.current_generation +%= 1;
            if (self.current_generation == 0)
                self.current_generation = 1;
            return self.current_generation;
        }

        fn countFor(
            self: *Self,
            direction: AudioBusDirection,
        ) *u8 {
            return switch (direction) {
                .input => &self.input_count,
                .output => &self.output_count,
            };
        }

        fn busesFor(
            self: *Self,
            direction: AudioBusDirection,
        ) *[maximum_audio_buses]DynamicAudioBus {
            return switch (direction) {
                .input => &self.input_buses,
                .output => &self.output_buses,
            };
        }

        fn busesForConst(
            self: *const Self,
            direction: AudioBusDirection,
        ) *const [maximum_audio_buses]DynamicAudioBus {
            return switch (direction) {
                .input => &self.input_buses,
                .output => &self.output_buses,
            };
        }

        fn writeBusState(writer: anytype, bus_value: DynamicAudioBus) !void {
            try writer.writeByte(@intFromEnum(bus_value.layout));
            try writer.writeInt(
                u64,
                bus_value.supported_layouts.bits,
                .little,
            );
            try writer.writeByte(@intFromBool(bus_value.default_active));
            try writer.writeByte(@intFromBool(bus_value.active));
        }

        fn readBusState(reader: anytype, version: u8) !DynamicAudioBus {
            const raw_layout = try reader.takeByte();
            if (raw_layout >= @typeInfo(AudioBusLayout).@"enum".fields.len)
                return error.InvalidDynamicAudioBusLayout;
            const supported_layouts = AudioBusLayoutSet{
                .bits = switch (version) {
                    1 => try reader.takeInt(u16, .little),
                    2 => try reader.takeInt(u64, .little),
                    else => return error.UnsupportedDynamicAudioBusState,
                },
            };
            const default_active = switch (try reader.takeByte()) {
                0 => false,
                1 => true,
                else => return error.InvalidDynamicAudioBusState,
            };
            const active = switch (try reader.takeByte()) {
                0 => false,
                1 => true,
                else => return error.InvalidDynamicAudioBusState,
            };
            var result = try DynamicAudioBus.init(
                @enumFromInt(raw_layout),
                supported_layouts,
                default_active,
            );
            result.active = active;
            return result;
        }
    };
}

pub const DynamicAudioBusTopology =
    BoundedDynamicAudioBusTopology(max_auxiliary_audio_buses);

fn validateDynamicAudioBusCapacity(
    comptime maximum_auxiliary_buses: usize,
) void {
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError(
            "dynamic audio bus capacity must be between 0 and 254 auxiliary buses",
        );
}

fn layoutBit(layout: AudioBusLayout) u64 {
    return @as(u64, 1) << @intFromEnum(layout);
}

const unused_bus = DynamicAudioBus{
    .layout = .mono,
    .supported_layouts = .{ .bits = layoutBit(.mono) },
    .default_active = false,
    .active = false,
};

test "audio bus layout preserves legacy identifiers and covers extended channel counts" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(AudioBusLayout.none));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(AudioBusLayout.stereo));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(AudioBusLayout.surround_7_1));
    try std.testing.expectEqual(@as(u8, 13), @intFromEnum(AudioBusLayout.ambisonic_third_order));

    inline for (@typeInfo(AudioBusLayout).@"enum".fields) |field| {
        const layout: AudioBusLayout = @enumFromInt(field.value);
        if (layout == .none) {
            try std.testing.expectEqual(@as(u8, 0), layout.channelCount());
        } else {
            try std.testing.expect(layout.channelCount() > 0);
            try std.testing.expect(layout.channelCount() <= 64);
        }
    }
    try std.testing.expectEqual(@as(u8, 2), AudioBusLayout.stereo_wide.channelCount());
    try std.testing.expectEqual(@as(u8, 10), AudioBusLayout.surround_5_1_4.channelCount());
    try std.testing.expectEqual(@as(u8, 11), AudioBusLayout.surround_7_0_4.channelCount());
    try std.testing.expectEqual(@as(u8, 25), AudioBusLayout.ambisonic_fourth_order.channelCount());
    try std.testing.expectEqual(@as(u8, 36), AudioBusLayout.ambisonic_fifth_order.channelCount());
    try std.testing.expectEqual(@as(u8, 49), AudioBusLayout.ambisonic_sixth_order.channelCount());
    try std.testing.expectEqual(@as(u8, 64), AudioBusLayout.ambisonic_seventh_order.channelCount());
}

test "audio bus layout set covers the complete extended catalog" {
    var layouts: [@typeInfo(AudioBusLayout).@"enum".fields.len - 1]AudioBusLayout = undefined;
    inline for (@typeInfo(AudioBusLayout).@"enum".fields[1..], 0..) |field, index|
        layouts[index] = @enumFromInt(field.value);
    const set = try AudioBusLayoutSet.init(&layouts);
    try std.testing.expect(set.valid());
    for (layouts) |layout|
        try std.testing.expect(set.contains(layout));
    try std.testing.expect(!set.contains(.none));

    var invalid = set;
    invalid.bits |= @as(u64, 1) << 63;
    try std.testing.expect(!invalid.valid());
}

test "dynamic bus topology restores version one layout masks" {
    var encoded = [_]u8{
        1,
        1,
        0,
        8,
        0x04,
        0x01,
        1,
        0,
    };
    var reader = std.Io.Reader.fixed(&encoded);
    const restored = try DynamicAudioBusTopology.readState(&reader);
    const bus_value = restored.bus(.input, 0).?;
    try std.testing.expectEqual(AudioBusLayout.surround_7_1, bus_value.layout);
    try std.testing.expect(bus_value.supported_layouts.contains(.stereo));
    try std.testing.expect(bus_value.supported_layouts.contains(.surround_7_1));
    try std.testing.expect(bus_value.default_active);
    try std.testing.expect(!bus_value.active);
}

test "dynamic bus topology persists extended layout masks" {
    const supported = try AudioBusLayoutSet.init(
        &.{ .stereo, .ambisonic_seventh_order },
    );
    const topology = try DynamicAudioBusTopology.init(
        try DynamicAudioBus.init(
            .ambisonic_seventh_order,
            supported,
            true,
        ),
        null,
    );
    var encoded: [DynamicAudioBusTopology.maximum_encoded_size]u8 =
        undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try topology.writeState(&writer);
    try std.testing.expectEqual(@as(u8, 2), writer.buffered()[0]);
    try std.testing.expectEqual(@as(usize, 14), writer.buffered().len);

    var reader = std.Io.Reader.fixed(writer.buffered());
    const restored = try DynamicAudioBusTopology.readState(&reader);
    try std.testing.expectEqualDeep(
        try topology.snapshot(),
        try restored.snapshot(),
    );
    const bus_value = restored.bus(.input, 0).?;
    try std.testing.expect(
        bus_value.supported_layouts.contains(.ambisonic_seventh_order),
    );
}

test "dynamic bus topology inserts negotiates activates and removes buses" {
    const stereo_or_surround = try AudioBusLayoutSet.init(
        &.{ .stereo, .surround_5_1 },
    );
    var topology = try DynamicAudioBusTopology.init(
        try DynamicAudioBus.init(.stereo, stereo_or_surround, true),
        try DynamicAudioBus.fixed(.stereo, true),
    );
    try std.testing.expectEqual(@as(usize, 1), topology.busCount(.input));
    try std.testing.expectEqual(
        @as(u64, 1),
        try topology.addAuxiliary(
            .input,
            try DynamicAudioBus.fixed(.mono, false),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        try topology.setLayout(.input, 0, .surround_5_1),
    );
    try std.testing.expectEqual(
        @as(u64, 3),
        try topology.setActive(.input, 1, true),
    );
    try std.testing.expectEqual(@as(u8, 6), topology.bus(.input, 0).?.layout.channelCount());
    try std.testing.expect(topology.bus(.input, 1).?.active);
    try std.testing.expectEqual(
        @as(u64, 4),
        try topology.removeAuxiliary(.input, 0),
    );
    try std.testing.expectEqual(@as(usize, 1), topology.busCount(.input));
}

test "dynamic bus topology rejects changes transactionally" {
    var topology = try DynamicAudioBusTopology.init(
        try DynamicAudioBus.fixed(.stereo, true),
        null,
    );
    const before = topology;
    try std.testing.expectError(
        error.UnsupportedDynamicAudioBusLayout,
        topology.setLayout(.input, 0, .mono),
    );
    try std.testing.expectEqualDeep(before, topology);
    try std.testing.expectError(
        error.DynamicAudioBusRequiresMain,
        topology.addAuxiliary(
            .output,
            try DynamicAudioBus.fixed(.mono, true),
        ),
    );
    try std.testing.expectEqualDeep(before, topology);
    try std.testing.expectError(
        error.DynamicAudioBusOutOfRange,
        topology.removeAuxiliary(.input, 0),
    );
    try std.testing.expectEqualDeep(before, topology);
}

test "dynamic bus topology publishes one transactional arrangement snapshot" {
    const main_layouts = try AudioBusLayoutSet.init(
        &.{ .mono, .stereo, .surround_5_1 },
    );
    var topology = try DynamicAudioBusTopology.init(
        try DynamicAudioBus.init(.stereo, main_layouts, true),
        try DynamicAudioBus.init(.stereo, main_layouts, true),
    );
    _ = try topology.addAuxiliary(
        .input,
        try DynamicAudioBus.fixed(.mono, false),
    );
    _ = try topology.addAuxiliary(
        .output,
        try DynamicAudioBus.fixed(.mono, true),
    );
    const before_generation = topology.current_generation;
    try std.testing.expectEqual(
        before_generation + 1,
        try topology.setLayouts(
            &.{ .surround_5_1, .mono },
            &.{ .mono, .mono },
        ),
    );
    const snapshot = try topology.snapshot();
    try std.testing.expect(snapshot.valid());
    try std.testing.expectEqual(topology.current_generation, snapshot.generation);
    try std.testing.expectEqual(
        AudioBusLayout.surround_5_1,
        snapshot.bus(.input, 0).?.layout,
    );
    try std.testing.expect(!snapshot.bus(.input, 1).?.active);
    try std.testing.expectEqual(
        AudioBusLayout.mono,
        snapshot.bus(.output, 0).?.layout,
    );
    try std.testing.expect(snapshot.bus(.output, 1).?.active);

    var encoded: [DynamicAudioBusTopology.maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try topology.writeState(&writer);
    var reader = std.Io.Reader.fixed(writer.buffered());
    const restored = try DynamicAudioBusTopology.readState(&reader);
    const restored_snapshot = try restored.snapshot();
    var expected_snapshot = try topology.snapshot();
    expected_snapshot.generation = 0;
    try std.testing.expectEqualDeep(expected_snapshot, restored_snapshot);
    try std.testing.expectEqual(@as(u64, 0), restored.current_generation);

    const before_rejection = topology;
    try std.testing.expectError(
        error.UnsupportedDynamicAudioBusLayout,
        topology.setLayouts(
            &.{ .mono, .stereo },
            &.{ .mono, .mono },
        ),
    );
    try std.testing.expectEqualDeep(before_rejection, topology);
    try std.testing.expectError(
        error.DynamicAudioBusCountMismatch,
        topology.setLayouts(&.{.mono}, &.{ .mono, .mono }),
    );
    try std.testing.expectEqualDeep(before_rejection, topology);
}

test "dynamic bus topology enforces capacity and generation rollover" {
    var topology = try DynamicAudioBusTopology.init(
        try DynamicAudioBus.fixed(.stereo, true),
        null,
    );
    for (0..max_auxiliary_audio_buses) |_|
        _ = try topology.addAuxiliary(
            .input,
            try DynamicAudioBus.fixed(.mono, false),
        );
    try std.testing.expectError(
        error.TooManyDynamicAudioBuses,
        topology.addAuxiliary(
            .input,
            try DynamicAudioBus.fixed(.mono, false),
        ),
    );
    topology.current_generation = std.math.maxInt(u64);
    try std.testing.expectEqual(
        @as(u64, 1),
        try topology.setActive(.input, 1, true),
    );
}

test "bounded dynamic bus topology exceeds the default capacity" {
    const Topology = BoundedDynamicAudioBusTopology(16);
    const Snapshot = BoundedDynamicAudioBusSnapshot(16);
    const MaximumTopology = BoundedDynamicAudioBusTopology(254);
    try std.testing.expectEqual(@as(usize, 16), Topology.auxiliary_capacity);
    try std.testing.expectEqual(@as(usize, 17), Topology.bus_capacity);
    try std.testing.expectEqual(Snapshot, Topology.SnapshotType);
    try std.testing.expectEqual(@as(usize, 17), Snapshot.bus_capacity);
    try std.testing.expectEqual(
        @as(usize, 255),
        MaximumTopology.bus_capacity,
    );

    var topology = try Topology.init(
        try DynamicAudioBus.fixed(.stereo, true),
        try DynamicAudioBus.fixed(.stereo, true),
    );
    for (0..Topology.auxiliary_capacity) |index| {
        _ = try topology.addAuxiliary(
            .input,
            try DynamicAudioBus.fixed(
                if (index % 2 == 0) .mono else .stereo,
                index % 3 == 0,
            ),
        );
    }
    try std.testing.expectEqual(
        Topology.bus_capacity,
        topology.busCount(.input),
    );
    _ = try topology.setActive(.input, 16, true);
    try std.testing.expect(topology.bus(.input, 16).?.active);

    const before_capacity_failure = topology;
    try std.testing.expectError(
        error.TooManyDynamicAudioBuses,
        topology.addAuxiliary(
            .input,
            try DynamicAudioBus.fixed(.mono, false),
        ),
    );
    try std.testing.expectEqualDeep(
        before_capacity_failure,
        topology,
    );

    const snapshot = try topology.snapshot();
    try std.testing.expect(snapshot.valid());
    try std.testing.expectEqual(
        Topology.bus_capacity,
        snapshot.busCount(.input),
    );
    try std.testing.expect(snapshot.bus(.input, 16).?.active);

    var encoded: [Topology.maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try topology.writeState(&writer);
    var reader = std.Io.Reader.fixed(writer.buffered());
    const restored = try Topology.readState(&reader);
    var expected_snapshot = snapshot;
    expected_snapshot.generation = 0;
    try std.testing.expectEqualDeep(
        expected_snapshot,
        try restored.snapshot(),
    );

    var default_reader = std.Io.Reader.fixed(writer.buffered());
    try std.testing.expectError(
        error.InvalidDynamicAudioBusTopology,
        DynamicAudioBusTopology.readState(&default_reader),
    );

    var default_topology = try DynamicAudioBusTopology.init(
        try DynamicAudioBus.fixed(.stereo, true),
        null,
    );
    _ = try default_topology.addAuxiliary(
        .input,
        try DynamicAudioBus.fixed(.mono, false),
    );
    var default_encoded: [DynamicAudioBusTopology.maximum_encoded_size]u8 = undefined;
    var default_writer = std.Io.Writer.fixed(&default_encoded);
    try default_topology.writeState(&default_writer);
    var expanded_reader =
        std.Io.Reader.fixed(default_writer.buffered());
    const expanded = try Topology.readState(&expanded_reader);
    try std.testing.expectEqual(
        @as(usize, 2),
        expanded.busCount(.input),
    );
    try std.testing.expectEqual(
        AudioBusLayout.mono,
        expanded.bus(.input, 1).?.layout,
    );
}

test "zero-auxiliary dynamic topology retains only its main bus" {
    const Topology = BoundedDynamicAudioBusTopology(0);
    try std.testing.expectEqual(@as(usize, 1), Topology.bus_capacity);
    var topology = try Topology.init(
        try DynamicAudioBus.fixed(.mono, true),
        null,
    );
    const before = topology;
    try std.testing.expectError(
        error.TooManyDynamicAudioBuses,
        topology.addAuxiliary(
            .input,
            try DynamicAudioBus.fixed(.mono, false),
        ),
    );
    try std.testing.expectEqualDeep(before, topology);
    try std.testing.expect((try topology.snapshot()).valid());
}

test "dynamic bus topology contains hostile public state" {
    var topology = try DynamicAudioBusTopology.init(null, null);
    topology.input_count = max_audio_buses_per_direction + 1;
    try std.testing.expect(!topology.valid());
    try std.testing.expectEqual(@as(usize, 0), topology.busCount(.input));
    try std.testing.expect(topology.generation() == null);
    try std.testing.expectError(
        error.InvalidDynamicAudioBusTopology,
        topology.setActive(.input, 0, true),
    );
    try std.testing.expectError(
        error.InvalidDynamicAudioBusTopology,
        topology.snapshot(),
    );

    var snapshot = DynamicAudioBusSnapshot{};
    snapshot.input_count = 1;
    snapshot.input_layouts[0] = .stereo;
    snapshot.input_layouts[1] = .mono;
    try std.testing.expect(!snapshot.valid());
    try std.testing.expectEqual(@as(usize, 0), snapshot.busCount(.input));
    try std.testing.expect(snapshot.bus(.input, 0) == null);

    var invalid_state = [_]u8{ 1, 1, 0, 255, 0, 0, 1 };
    var invalid_reader = std.Io.Reader.fixed(&invalid_state);
    try std.testing.expectError(
        error.InvalidDynamicAudioBusLayout,
        DynamicAudioBusTopology.readState(&invalid_reader),
    );
}
