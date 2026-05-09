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
    parameters: []const ProgramParameter = &.{},
    info: []const ProgramInfo = &.{},
};

pub const ProgramParameter = struct {
    parameter_id: u32,
    normalized: f64,
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

        pub fn duplicateUnitId(_: Self) ?i32 {
            for (config.units, 0..) |left, left_index| {
                for (config.units, 0..) |right, right_index| {
                    if (right_index > left_index and right.id == left.id) return left.id;
                }
            }
            return null;
        }

        pub fn duplicateProgramListId(_: Self) ?i32 {
            for (config.program_lists, 0..) |left, left_index| {
                for (config.program_lists, 0..) |right, right_index| {
                    if (right_index > left_index and right.id == left.id) return left.id;
                }
            }
            return null;
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

        pub fn hasUnit(self: Self, id: i32) bool {
            return self.unitById(id) != null;
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

        pub fn hasProgramList(self: Self, id: i32) bool {
            return self.programListById(id) != null;
        }

        pub fn programListForUnit(self: Self, unit_id: i32) ?ProgramList {
            const item = self.unitById(unit_id) orelse return null;
            if (item.program_list_id == no_program_list_id) return null;
            return self.programListById(item.program_list_id);
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

        pub fn program(self: Self, list_id: i32, program_index: usize) ?Program {
            const list = self.programListById(list_id) orelse return null;
            if (program_index >= list.programs.len) return null;
            return list.programs[program_index];
        }

        pub fn programIndexOfName(self: Self, list_id: i32, name: []const u8) ?usize {
            const list = self.programListById(list_id) orelse return null;
            for (list.programs, 0..) |item, index| {
                if (std.mem.eql(u8, item.name, name)) return index;
            }
            return null;
        }

        pub fn programParameterCount(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameter(self: Self, list_id: i32, program_index: usize, parameter_index: usize) ?ProgramParameter {
            const item = self.program(list_id, program_index) orelse return null;
            if (parameter_index >= item.parameters.len) return null;
            return item.parameters[parameter_index];
        }

        pub fn programParameterById(self: Self, list_id: i32, program_index: usize, parameter_id: u32) ?ProgramParameter {
            const item = self.program(list_id, program_index) orelse return null;
            for (item.parameters) |parameter| {
                if (parameter.parameter_id == parameter_id) return parameter;
            }
            return null;
        }

        pub fn programInfo(self: Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            if (program_index >= list.programs.len) return null;
            for (list.programs[program_index].info) |item| {
                if (std.mem.eql(u8, item.key, key)) return item.value;
            }
            return null;
        }

        pub fn programInfoByName(self: Self, list_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.programInfo(list_id, index, key);
        }

        pub fn rootUnit(self: Self) Unit {
            return self.unitById(root_unit_id) orelse Unit.root("Root");
        }

        pub fn validateUnits(self: Self) !void {
            if (config.units.len == 0) return error.MissingRootUnit;
            if (self.duplicateUnitId() != null) return error.DuplicateUnitId;
            const root = self.unitById(root_unit_id) orelse return error.MissingRootUnit;
            if (root.name.len == 0) return error.EmptyUnitName;
            if (root.parent_id != no_parent_unit_id) return error.InvalidUnitParent;
            for (config.units) |item| {
                if (item.id == no_parent_unit_id) return error.ReservedUnitId;
                if (item.name.len == 0) return error.EmptyUnitName;
                if (item.id != root_unit_id and self.unitById(item.parent_id) == null) return error.InvalidUnitParent;
                if (item.program_list_id != no_program_list_id and self.programListById(item.program_list_id) == null) {
                    return error.InvalidUnitProgramList;
                }
                if (item.id != root_unit_id) {
                    var parent_id = item.parent_id;
                    var depth: usize = 0;
                    while (parent_id != root_unit_id) {
                        if (depth >= config.units.len) return error.CyclicUnitParent;
                        const parent = self.unitById(parent_id) orelse return error.InvalidUnitParent;
                        if (parent.parent_id == no_parent_unit_id) return error.InvalidUnitParent;
                        parent_id = parent.parent_id;
                        depth += 1;
                    }
                }
            }
        }

        pub fn validateProgramLists(self: Self) !void {
            if (self.duplicateProgramListId() != null) return error.DuplicateProgramListId;
            for (config.program_lists) |list| {
                if (list.id == no_program_list_id) return error.ReservedProgramListId;
                if (list.name.len == 0) return error.EmptyProgramListName;
                for (list.programs, 0..) |item, item_index| {
                    if (item.name.len == 0) return error.EmptyProgramName;
                    for (list.programs, 0..) |other, other_index| {
                        if (other_index > item_index and std.mem.eql(u8, other.name, item.name)) {
                            return error.DuplicateProgramName;
                        }
                    }
                    for (item.parameters, 0..) |parameter, parameter_index| {
                        if (parameter.normalized < 0.0 or parameter.normalized > 1.0 or std.math.isNan(parameter.normalized)) {
                            return error.ProgramParameterOutsideNormalizedRange;
                        }
                        for (item.parameters, 0..) |other, other_index| {
                            if (other_index > parameter_index and other.parameter_id == parameter.parameter_id) {
                                return error.DuplicateProgramParameter;
                            }
                        }
                    }
                    for (item.info, 0..) |info, info_index| {
                        if (info.key.len == 0) return error.EmptyProgramInfoKey;
                        for (item.info, 0..) |other, other_index| {
                            if (other_index > info_index and std.mem.eql(u8, other.key, info.key)) {
                                return error.DuplicateProgramInfoKey;
                            }
                        }
                    }
                }
            }
        }

        pub fn validate(self: Self) !void {
            try self.validateProgramLists();
            try self.validateUnits();
        }

        pub fn validateProgramParameterIds(_: Self, parameter_set: anytype) !void {
            for (config.program_lists) |list| {
                for (list.programs) |item| {
                    for (item.parameters) |parameter| {
                        if (parameter_set.indexOfId(parameter.parameter_id) == null) return error.UnknownProgramParameter;
                    }
                }
            }
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
    try std.testing.expect(set.hasUnit(root_unit_id));
    try std.testing.expect(!set.hasUnit(99));
    try std.testing.expect(!set.hasProgramList(10));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?Unit, null), set.unit(1));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programList(0));
}

test "unit set exposes custom units and programs" {
    const programs = [_]Program{
        .{
            .name = "Clean",
            .parameters = &.{.{ .parameter_id = 3, .normalized = 0.25 }},
            .info = &.{.{ .key = "category", .value = "Clean" }},
        },
        .{
            .name = "Drive",
            .parameters = &.{.{ .parameter_id = 3, .normalized = 0.75 }},
        },
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
    try std.testing.expect(set.hasUnit(1));
    try std.testing.expect(!set.hasUnit(99));
    try std.testing.expectEqualStrings("Oscillator", set.unitById(1).?.name);
    try std.testing.expectEqual(@as(i32, 10), set.unitById(1).?.program_list_id);
    try std.testing.expectEqual(@as(?usize, 0), set.programListIndexOfId(10));
    try std.testing.expect(set.hasProgramList(10));
    try std.testing.expect(!set.hasProgramList(99));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListById(10).?.name);
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListForUnit(1).?.name);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?usize, 2), set.programCount(10));
    try std.testing.expectEqualStrings("Drive", set.programName(10, 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programName(10, 2));
    try std.testing.expectEqualStrings("Drive", set.program(10, 1).?.name);
    try std.testing.expectEqual(@as(?usize, 1), set.programIndexOfName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, 1), set.programParameterCount(10, 1));
    try std.testing.expectEqual(@as(u32, 3), set.programParameter(10, 1, 0).?.parameter_id);
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameter(10, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), set.programParameterById(10, 0, 3).?.normalized);
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameter(10, 1, 1));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterById(10, 1, 99));
    try std.testing.expectEqualStrings("Clean", set.programInfo(10, 0, "category").?);
    try std.testing.expectEqualStrings("Clean", set.programInfoByName(10, "Clean", "category").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(10, 0, "missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfoByName(10, "Missing", "category"));
    try set.validate();
}

test "unit set validates ids names and links" {
    const DuplicateUnits = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = root_unit_id, .name = "Other" } },
    });
    const MissingRoot = UnitSet(.{
        .units = &.{.{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id }},
    });
    const EmptyUnitName = UnitSet(.{
        .units = &.{Unit.root("")},
    });
    const InvalidParent = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Oscillator", .parent_id = 99 } },
    });
    const ReservedUnitId = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = no_parent_unit_id, .name = "Reserved", .parent_id = root_unit_id } },
    });
    const CyclicParent = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = 2 },
            .{ .id = 2, .name = "Filter", .parent_id = 1 },
        },
    });
    const InvalidProgramListLink = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Oscillator", .program_list_id = 99 } },
    });
    const DuplicateProgramLists = UnitSet(.{
        .program_lists = &.{ .{ .id = 1, .name = "A" }, .{ .id = 1, .name = "B" } },
    });
    const ReservedProgramListId = UnitSet(.{
        .program_lists = &.{.{ .id = no_program_list_id, .name = "Reserved" }},
    });
    const EmptyProgramListName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "" }},
    });
    const EmptyProgramName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "" }} }},
    });
    const DuplicateProgramNames = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{ .{ .name = "Clean" }, .{ .name = "Clean" } } }},
    });
    const DuplicateProgramParameters = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{ .{ .parameter_id = 1, .normalized = 0.25 }, .{ .parameter_id = 1, .normalized = 0.75 } } }} }},
    });
    const InvalidProgramParameter = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{.{ .parameter_id = 1, .normalized = 1.5 }} }} }},
    });
    const NanProgramParameter = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{.{ .parameter_id = 1, .normalized = std.math.nan(f64) }} }} }},
    });
    const EmptyProgramInfoKey = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "", .value = "x" }} }} }},
    });
    const DuplicateProgramInfoKeys = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{ .{ .key = "category", .value = "clean" }, .{ .key = "category", .value = "lead" } } }} }},
    });

    try std.testing.expectError(error.DuplicateUnitId, (DuplicateUnits{}).validate());
    try std.testing.expectError(error.MissingRootUnit, (MissingRoot{}).validate());
    try std.testing.expectError(error.EmptyUnitName, (EmptyUnitName{}).validate());
    try std.testing.expectError(error.InvalidUnitParent, (InvalidParent{}).validate());
    try std.testing.expectError(error.ReservedUnitId, (ReservedUnitId{}).validate());
    try std.testing.expectError(error.CyclicUnitParent, (CyclicParent{}).validate());
    try std.testing.expectError(error.InvalidUnitProgramList, (InvalidProgramListLink{}).validate());
    try std.testing.expectError(error.DuplicateProgramListId, (DuplicateProgramLists{}).validate());
    try std.testing.expectError(error.ReservedProgramListId, (ReservedProgramListId{}).validate());
    try std.testing.expectError(error.EmptyProgramListName, (EmptyProgramListName{}).validate());
    try std.testing.expectError(error.EmptyProgramName, (EmptyProgramName{}).validate());
    try std.testing.expectError(error.DuplicateProgramName, (DuplicateProgramNames{}).validate());
    try std.testing.expectError(error.DuplicateProgramParameter, (DuplicateProgramParameters{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (InvalidProgramParameter{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (NanProgramParameter{}).validate());
    try std.testing.expectError(error.EmptyProgramInfoKey, (EmptyProgramInfoKey{}).validate());
    try std.testing.expectError(error.DuplicateProgramInfoKey, (DuplicateProgramInfoKeys{}).validate());
}
