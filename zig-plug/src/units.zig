const std = @import("std");

pub const root_unit_id: i32 = 0;
pub const no_parent_unit_id: i32 = -1;
pub const no_program_list_id: i32 = -1;

pub const Unit = struct {
    id: i32,
    name: []const u8,
    parent_id: i32 = root_unit_id,
    program_list_id: i32 = no_program_list_id,

    pub fn root(name: []const u8) Unit {
        return .{
            .id = root_unit_id,
            .name = name,
            .parent_id = no_parent_unit_id,
        };
    }
};

pub const Program = struct {
    name: []const u8,
    info: []const ProgramInfo = &.{},
};

pub const ProgramInfo = struct {
    key: []const u8,
    value: []const u8,
};

pub const ProgramList = struct {
    id: i32,
    name: []const u8,
    programs: []const Program = &.{},
};

pub const Config = struct {
    units: []const Unit = &.{Unit.root("Root")},
    program_lists: []const ProgramList = &.{},
};

pub fn UnitSet(comptime config: Config) type {
    return struct {
        const Self = @This();

        pub const unit_count = config.units.len;
        pub const program_list_count = config.program_lists.len;

        pub fn unitCount(_: Self) usize {
            return unit_count;
        }

        pub fn programListCount(_: Self) usize {
            return program_list_count;
        }

        pub fn unit(_: Self, index: usize) ?Unit {
            if (index >= config.units.len) return null;
            return config.units[index];
        }

        pub fn unitById(_: Self, id: i32) ?Unit {
            for (config.units) |item| {
                if (item.id == id) return item;
            }
            return null;
        }

        pub fn unitIndexOfId(_: Self, id: i32) ?usize {
            for (config.units, 0..) |item, index| {
                if (item.id == id) return index;
            }
            return null;
        }

        pub fn programList(_: Self, index: usize) ?ProgramList {
            if (index >= config.program_lists.len) return null;
            return config.program_lists[index];
        }

        pub fn programListById(_: Self, id: i32) ?ProgramList {
            for (config.program_lists) |item| {
                if (item.id == id) return item;
            }
            return null;
        }

        pub fn programListIndexOfId(_: Self, id: i32) ?usize {
            for (config.program_lists, 0..) |item, index| {
                if (item.id == id) return index;
            }
            return null;
        }

        pub fn programCount(self: Self, list_id: i32) ?usize {
            const list = self.programListById(list_id) orelse return null;
            return list.programs.len;
        }

        pub fn programName(self: Self, list_id: i32, program_index: usize) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            if (program_index >= list.programs.len) return null;
            return list.programs[program_index].name;
        }

        pub fn programInfo(self: Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            if (program_index >= list.programs.len) return null;
            for (list.programs[program_index].info) |item| {
                if (std.mem.eql(u8, item.key, key)) return item.value;
            }
            return null;
        }

        pub fn rootUnit(self: Self) Unit {
            return self.unitById(root_unit_id) orelse Unit.root("Root");
        }
    };
}

test "default unit set exposes root unit only" {
    const Set = UnitSet(.{});
    const set = Set{};

    try std.testing.expectEqual(@as(usize, 1), set.unitCount());
    try std.testing.expectEqual(@as(usize, 0), set.programListCount());
    try std.testing.expectEqual(root_unit_id, set.rootUnit().id);
    try std.testing.expectEqual(no_parent_unit_id, set.rootUnit().parent_id);
    try std.testing.expectEqual(no_program_list_id, set.rootUnit().program_list_id);
    try std.testing.expectEqualStrings("Root", set.rootUnit().name);
    try std.testing.expectEqual(@as(?Unit, null), set.unit(1));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programList(0));
}

test "unit set exposes custom units and programs" {
    const programs = [_]Program{
        .{ .name = "Clean", .info = &.{.{ .key = "category", .value = "Clean" }} },
        .{ .name = "Drive" },
    };
    const Set = UnitSet(.{
        .units = &.{
            Unit.root("Main"),
            .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id, .program_list_id = 10 },
        },
        .program_lists = &.{
            .{ .id = 10, .name = "Oscillator Presets", .programs = &programs },
        },
    });
    const set = Set{};

    try std.testing.expectEqual(@as(usize, 2), set.unitCount());
    try std.testing.expectEqual(@as(usize, 1), set.programListCount());
    try std.testing.expectEqual(@as(?usize, 1), set.unitIndexOfId(1));
    try std.testing.expectEqual(@as(?usize, null), set.unitIndexOfId(99));
    try std.testing.expectEqualStrings("Oscillator", set.unitById(1).?.name);
    try std.testing.expectEqual(@as(i32, 10), set.unitById(1).?.program_list_id);
    try std.testing.expectEqual(@as(?usize, 0), set.programListIndexOfId(10));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListById(10).?.name);
    try std.testing.expectEqual(@as(?usize, 2), set.programCount(10));
    try std.testing.expectEqualStrings("Drive", set.programName(10, 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programName(10, 2));
    try std.testing.expectEqualStrings("Clean", set.programInfo(10, 0, "category").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(10, 0, "missing"));
}
