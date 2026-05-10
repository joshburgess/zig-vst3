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

    pub fn isRoot(self: Unit) bool {
        return self.id == root_unit_id;
    }

    pub fn hasParent(self: Unit) bool {
        return self.parent_id != no_parent_unit_id;
    }

    pub fn hasProgramList(self: Unit) bool {
        return self.program_list_id != no_program_list_id;
    }
};

pub const Program = struct {
    name: []const u8,
    parameters: []const ProgramParameter = &.{},
    info: []const ProgramInfo = &.{},

    pub fn parameterCount(self: Program) usize {
        return self.parameters.len;
    }

    pub fn infoCount(self: Program) usize {
        return self.info.len;
    }

    pub fn hasParameters(self: Program) bool {
        return self.parameters.len != 0;
    }

    pub fn parametersEmpty(self: Program) bool {
        return self.parameters.len == 0;
    }

    pub fn hasInfo(self: Program) bool {
        return self.info.len != 0;
    }

    pub fn infoEmpty(self: Program) bool {
        return self.info.len == 0;
    }
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

    pub fn programCount(self: ProgramList) usize {
        return self.programs.len;
    }

    pub fn isEmpty(self: ProgramList) bool {
        return self.programs.len == 0;
    }

    pub fn hasPrograms(self: ProgramList) bool {
        return self.programs.len != 0;
    }
};

pub const Config = struct {
    units: []const Unit = &.{Unit.root("Root")},
    program_lists: []const ProgramList = &.{},
};

fn containsNul(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, 0) != null;
}

pub fn UnitSet(comptime config: Config) type {
    return struct {
        const Self = @This();

        pub const unit_count = config.units.len;
        pub const program_list_count = config.program_lists.len;

        pub fn unitCount(_: Self) usize {
            return unit_count;
        }

        pub fn unitsEmpty(_: Self) bool {
            return unit_count == 0;
        }

        pub fn hasUnits(_: Self) bool {
            return unit_count != 0;
        }

        pub fn programListCount(_: Self) usize {
            return program_list_count;
        }

        pub fn programListsEmpty(_: Self) bool {
            return program_list_count == 0;
        }

        pub fn hasProgramLists(_: Self) bool {
            return program_list_count != 0;
        }

        pub fn duplicateUnitId(_: Self) ?i32 {
            for (config.units, 0..) |left, left_index| {
                for (config.units, 0..) |right, right_index| {
                    if (right_index > left_index and right.id == left.id) return left.id;
                }
            }
            return null;
        }

        pub fn duplicateUnitName(_: Self) ?[]const u8 {
            for (config.units, 0..) |left, left_index| {
                for (config.units, 0..) |right, right_index| {
                    if (right_index > left_index and std.mem.eql(u8, right.name, left.name)) return left.name;
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

        pub fn duplicateProgramListName(_: Self) ?[]const u8 {
            for (config.program_lists, 0..) |left, left_index| {
                for (config.program_lists, 0..) |right, right_index| {
                    if (right_index > left_index and std.mem.eql(u8, right.name, left.name)) return left.name;
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

        pub fn unitByName(self: Self, name: []const u8) ?Unit {
            const index = self.unitIndexOfName(name) orelse return null;
            return self.unit(index);
        }

        pub fn hasUnit(self: Self, id: i32) bool {
            return self.unitById(id) != null;
        }

        pub fn hasUnitName(self: Self, name: []const u8) bool {
            return self.unitByName(name) != null;
        }

        pub fn unitIndexOfId(_: Self, id: i32) ?usize {
            for (config.units, 0..) |item, index| {
                if (item.id == id) return index;
            }
            return null;
        }

        pub fn unitIndexOfName(_: Self, name: []const u8) ?usize {
            for (config.units, 0..) |item, index| {
                if (std.mem.eql(u8, item.name, name)) return index;
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

        pub fn programListByName(self: Self, name: []const u8) ?ProgramList {
            const index = self.programListIndexOfName(name) orelse return null;
            return self.programList(index);
        }

        pub fn hasProgramList(self: Self, id: i32) bool {
            return self.programListById(id) != null;
        }

        pub fn hasProgramListName(self: Self, name: []const u8) bool {
            return self.programListByName(name) != null;
        }

        pub fn programListHasPrograms(self: Self, id: i32) bool {
            const list = self.programListById(id) orelse return false;
            return list.hasPrograms();
        }

        pub fn programListHasProgramsByName(self: Self, name: []const u8) bool {
            const list = self.programListByName(name) orelse return false;
            return list.hasPrograms();
        }

        pub fn programListEmpty(self: Self, id: i32) bool {
            const list = self.programListById(id) orelse return true;
            return list.isEmpty();
        }

        pub fn programListEmptyByName(self: Self, name: []const u8) bool {
            const list = self.programListByName(name) orelse return true;
            return list.isEmpty();
        }

        pub fn programListForUnit(self: Self, unit_id: i32) ?ProgramList {
            const item = self.unitById(unit_id) orelse return null;
            if (item.program_list_id == no_program_list_id) return null;
            return self.programListById(item.program_list_id);
        }

        pub fn programListForUnitName(self: Self, unit_name: []const u8) ?ProgramList {
            const item = self.unitByName(unit_name) orelse return null;
            if (item.program_list_id == no_program_list_id) return null;
            return self.programListById(item.program_list_id);
        }

        pub fn programListIdForUnit(self: Self, unit_id: i32) ?i32 {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.id;
        }

        pub fn programListIdForUnitName(self: Self, unit_name: []const u8) ?i32 {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.id;
        }

        pub fn programListNameForUnit(self: Self, unit_id: i32) ?[]const u8 {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.name;
        }

        pub fn programListNameForUnitName(self: Self, unit_name: []const u8) ?[]const u8 {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.name;
        }

        pub fn programListIndexOfId(_: Self, id: i32) ?usize {
            for (config.program_lists, 0..) |item, index| {
                if (item.id == id) return index;
            }
            return null;
        }

        pub fn programListIndexOfName(_: Self, name: []const u8) ?usize {
            for (config.program_lists, 0..) |item, index| {
                if (std.mem.eql(u8, item.name, name)) return index;
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

        pub fn programByName(self: Self, list_id: i32, name: []const u8) ?Program {
            const index = self.programIndexOfName(list_id, name) orelse return null;
            return self.program(list_id, index);
        }

        pub fn programIndexOfName(self: Self, list_id: i32, name: []const u8) ?usize {
            const list = self.programListById(list_id) orelse return null;
            for (list.programs, 0..) |item, index| {
                if (std.mem.eql(u8, item.name, name)) return index;
            }
            return null;
        }

        pub fn hasProgramName(self: Self, list_id: i32, name: []const u8) bool {
            return self.programIndexOfName(list_id, name) != null;
        }

        pub fn programParameterCount(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountByName(self: Self, list_id: i32, program_name: []const u8) ?usize {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.parameters.len;
        }

        pub fn programHasParameters(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return false;
            return item.hasParameters();
        }

        pub fn programParametersEmpty(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParameter(self: Self, list_id: i32, program_index: usize, parameter_index: usize) ?ProgramParameter {
            const item = self.program(list_id, program_index) orelse return null;
            if (parameter_index >= item.parameters.len) return null;
            return item.parameters[parameter_index];
        }

        pub fn programParameterByName(self: Self, list_id: i32, program_name: []const u8, parameter_index: usize) ?ProgramParameter {
            const item = self.programByName(list_id, program_name) orelse return null;
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

        pub fn hasProgramParameter(self: Self, list_id: i32, program_index: usize, parameter_id: u32) bool {
            return self.programParameterById(list_id, program_index, parameter_id) != null;
        }

        pub fn programParameterByNameAndId(self: Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?ProgramParameter {
            const item = self.programByName(list_id, program_name) orelse return null;
            for (item.parameters) |parameter| {
                if (parameter.parameter_id == parameter_id) return parameter;
            }
            return null;
        }

        pub fn hasProgramParameterByName(self: Self, list_id: i32, program_name: []const u8, parameter_id: u32) bool {
            return self.programParameterByNameAndId(list_id, program_name, parameter_id) != null;
        }

        pub fn programInfo(self: Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            if (program_index >= list.programs.len) return null;
            for (list.programs[program_index].info) |item| {
                if (std.mem.eql(u8, item.key, key)) return item.value;
            }
            return null;
        }

        pub fn hasProgramInfo(self: Self, list_id: i32, program_index: usize, key: []const u8) bool {
            return self.programInfo(list_id, program_index, key) != null;
        }

        pub fn programInfoByName(self: Self, list_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.programInfo(list_id, index, key);
        }

        pub fn hasProgramInfoByName(self: Self, list_id: i32, program_name: []const u8, key: []const u8) bool {
            return self.programInfoByName(list_id, program_name, key) != null;
        }

        pub fn programInfoCount(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountByName(self: Self, list_id: i32, program_name: []const u8) ?usize {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.info.len;
        }

        pub fn programHasInfoEntries(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return false;
            return item.hasInfo();
        }

        pub fn programInfoEmpty(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return true;
            return item.infoEmpty();
        }

        pub fn rootUnit(self: Self) Unit {
            return self.unitById(root_unit_id) orelse Unit.root("Root");
        }

        pub fn validateUnits(self: Self) !void {
            if (config.units.len == 0) return error.MissingRootUnit;
            if (self.duplicateUnitId() != null) return error.DuplicateUnitId;
            if (self.duplicateUnitName() != null) return error.DuplicateUnitName;
            const root = self.unitById(root_unit_id) orelse return error.MissingRootUnit;
            if (root.name.len == 0) return error.EmptyUnitName;
            if (containsNul(root.name)) return error.InvalidUnitMetadata;
            if (root.parent_id != no_parent_unit_id) return error.InvalidUnitParent;
            for (config.units) |item| {
                if (item.id == no_parent_unit_id) return error.ReservedUnitId;
                if (item.name.len == 0) return error.EmptyUnitName;
                if (containsNul(item.name)) return error.InvalidUnitMetadata;
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
            if (self.duplicateProgramListName() != null) return error.DuplicateProgramListName;
            for (config.program_lists) |list| {
                if (list.id == no_program_list_id) return error.ReservedProgramListId;
                if (list.name.len == 0) return error.EmptyProgramListName;
                if (containsNul(list.name)) return error.InvalidProgramListMetadata;
                for (list.programs, 0..) |item, item_index| {
                    if (item.name.len == 0) return error.EmptyProgramName;
                    if (containsNul(item.name)) return error.InvalidProgramMetadata;
                    for (list.programs, 0..) |other, other_index| {
                        if (other_index > item_index and std.mem.eql(u8, other.name, item.name)) {
                            return error.DuplicateProgramName;
                        }
                    }
                    for (item.parameters, 0..) |parameter, parameter_index| {
                        if (!std.math.isFinite(parameter.normalized) or parameter.normalized < 0.0 or parameter.normalized > 1.0) {
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
                        if (containsNul(info.key) or containsNul(info.value)) return error.InvalidProgramInfoMetadata;
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
    try std.testing.expect(!set.unitsEmpty());
    try std.testing.expect(set.hasUnits());
    try std.testing.expectEqual(@as(usize, 0), set.programListCount());
    try std.testing.expect(set.programListsEmpty());
    try std.testing.expect(!set.hasProgramLists());
    try std.testing.expectEqual(root_unit_id, set.rootUnit().id);
    try std.testing.expectEqual(no_parent_unit_id, set.rootUnit().parent_id);
    try std.testing.expectEqual(no_program_list_id, set.rootUnit().program_list_id);
    try std.testing.expectEqualStrings("Root", set.rootUnit().name);
    try std.testing.expect(set.rootUnit().isRoot());
    try std.testing.expect(!set.rootUnit().hasParent());
    try std.testing.expect(!set.rootUnit().hasProgramList());
    try std.testing.expect(set.hasUnit(root_unit_id));
    try std.testing.expect(!set.hasUnit(99));
    try std.testing.expect(!set.hasProgramList(10));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnitName("Root"));
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
    try std.testing.expect(!set.unitsEmpty());
    try std.testing.expect(set.hasUnits());
    try std.testing.expectEqual(@as(usize, 1), set.programListCount());
    try std.testing.expect(!set.programListsEmpty());
    try std.testing.expect(set.hasProgramLists());
    try std.testing.expectEqual(@as(?usize, 1), set.unitIndexOfId(1));
    try std.testing.expectEqual(@as(?usize, null), set.unitIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), set.unitIndexOfName("Oscillator"));
    try std.testing.expectEqual(@as(?usize, null), set.unitIndexOfName("Missing"));
    try std.testing.expect(set.hasUnit(1));
    try std.testing.expect(!set.hasUnit(99));
    try std.testing.expect(set.hasUnitName("Oscillator"));
    try std.testing.expect(!set.hasUnitName("Missing"));
    try std.testing.expectEqualStrings("Oscillator", set.unitById(1).?.name);
    try std.testing.expectEqual(@as(i32, 1), set.unitByName("Oscillator").?.id);
    try std.testing.expectEqual(@as(?Unit, null), set.unitByName("Missing"));
    try std.testing.expectEqual(@as(i32, 10), set.unitById(1).?.program_list_id);
    try std.testing.expect(!set.unitById(1).?.isRoot());
    try std.testing.expect(set.unitById(1).?.hasParent());
    try std.testing.expect(set.unitById(1).?.hasProgramList());
    try std.testing.expectEqual(@as(?usize, 0), set.programListIndexOfId(10));
    try std.testing.expectEqual(@as(?usize, null), set.programListIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 0), set.programListIndexOfName("Oscillator Presets"));
    try std.testing.expectEqual(@as(?usize, null), set.programListIndexOfName("Missing"));
    try std.testing.expect(set.hasProgramList(10));
    try std.testing.expect(!set.hasProgramList(99));
    try std.testing.expect(set.hasProgramListName("Oscillator Presets"));
    try std.testing.expect(!set.hasProgramListName("Missing"));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListById(10).?.name);
    try std.testing.expectEqual(@as(i32, 10), set.programListByName("Oscillator Presets").?.id);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListByName("Missing"));
    try std.testing.expectEqual(@as(usize, 2), set.programListById(10).?.programCount());
    try std.testing.expect(!set.programListById(10).?.isEmpty());
    try std.testing.expect(set.programListById(10).?.hasPrograms());
    try std.testing.expect(set.programListHasPrograms(10));
    try std.testing.expect(set.programListHasProgramsByName("Oscillator Presets"));
    try std.testing.expect(!set.programListHasPrograms(99));
    try std.testing.expect(!set.programListHasProgramsByName("Missing"));
    try std.testing.expect(!set.programListEmpty(10));
    try std.testing.expect(!set.programListEmptyByName("Oscillator Presets"));
    try std.testing.expect(set.programListEmpty(99));
    try std.testing.expect(set.programListEmptyByName("Missing"));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListForUnit(1).?.name);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnit(root_unit_id));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListForUnitName("Oscillator").?.name);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnitName("Main"));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnitName("Missing"));
    try std.testing.expectEqual(@as(?i32, 10), set.programListIdForUnit(1));
    try std.testing.expectEqual(@as(?i32, 10), set.programListIdForUnitName("Oscillator"));
    try std.testing.expectEqual(@as(?i32, null), set.programListIdForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?i32, null), set.programListIdForUnitName("Missing"));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListNameForUnit(1).?);
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListNameForUnitName("Oscillator").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programListNameForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programListNameForUnitName("Missing"));
    try std.testing.expectEqual(@as(?usize, 2), set.programCount(10));
    try std.testing.expectEqual(@as(?usize, null), set.programCount(99));
    try std.testing.expectEqualStrings("Drive", set.programName(10, 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programName(10, 2));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programName(99, 0));
    try std.testing.expectEqualStrings("Drive", set.program(10, 1).?.name);
    try std.testing.expectEqual(@as(?Program, null), set.program(10, 2));
    try std.testing.expectEqual(@as(?Program, null), set.program(99, 0));
    try std.testing.expectEqual(@as(usize, 1), set.program(10, 0).?.parameterCount());
    try std.testing.expectEqual(@as(usize, 1), set.program(10, 0).?.infoCount());
    try std.testing.expect(set.program(10, 0).?.hasParameters());
    try std.testing.expect(!set.program(10, 0).?.parametersEmpty());
    try std.testing.expect(set.program(10, 0).?.hasInfo());
    try std.testing.expect(!set.program(10, 0).?.infoEmpty());
    try std.testing.expect(!set.program(10, 1).?.hasInfo());
    try std.testing.expect(set.program(10, 1).?.infoEmpty());
    try std.testing.expectEqualStrings("Drive", set.programByName(10, "Drive").?.name);
    try std.testing.expectEqual(@as(?Program, null), set.programByName(10, "Missing"));
    try std.testing.expectEqual(@as(?Program, null), set.programByName(99, "Drive"));
    try std.testing.expectEqual(@as(?usize, 1), set.programIndexOfName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfName(99, "Drive"));
    try std.testing.expect(set.hasProgramName(10, "Drive"));
    try std.testing.expect(!set.hasProgramName(10, "Missing"));
    try std.testing.expect(!set.hasProgramName(99, "Drive"));
    try std.testing.expectEqual(@as(?usize, 1), set.programParameterCount(10, 1));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCount(10, 2));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCount(99, 0));
    try std.testing.expectEqual(@as(?usize, 1), set.programParameterCountByName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCountByName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCountByName(99, "Drive"));
    try std.testing.expect(set.programHasParameters(10, 0));
    try std.testing.expect(set.programHasParametersByName(10, "Drive"));
    try std.testing.expect(!set.programHasParameters(10, 2));
    try std.testing.expect(!set.programHasParametersByName(10, "Missing"));
    try std.testing.expect(!set.programParametersEmpty(10, 0));
    try std.testing.expect(!set.programParametersEmptyByName(10, "Drive"));
    try std.testing.expect(set.programParametersEmpty(10, 2));
    try std.testing.expect(set.programParametersEmptyByName(10, "Missing"));
    try std.testing.expectEqual(@as(u32, 3), set.programParameter(10, 1, 0).?.parameter_id);
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameter(10, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(u32, 3), set.programParameterByName(10, "Drive", 0).?.parameter_id);
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameterByName(10, "Drive", 0).?.normalized);
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByName(10, "Drive", 1));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByName(10, "Missing", 0));
    try std.testing.expectEqual(@as(f64, 0.25), set.programParameterById(10, 0, 3).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameterByNameAndId(10, "Drive", 3).?.normalized);
    try std.testing.expect(set.hasProgramParameter(10, 0, 3));
    try std.testing.expect(!set.hasProgramParameter(10, 0, 99));
    try std.testing.expect(!set.hasProgramParameter(99, 0, 3));
    try std.testing.expect(set.hasProgramParameterByName(10, "Drive", 3));
    try std.testing.expect(!set.hasProgramParameterByName(10, "Drive", 99));
    try std.testing.expect(!set.hasProgramParameterByName(10, "Missing", 3));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameter(10, 1, 1));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterById(10, 1, 99));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByNameAndId(10, "Drive", 99));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByNameAndId(10, "Missing", 3));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByNameAndId(99, "Drive", 3));
    try std.testing.expectEqualStrings("Clean", set.programInfo(10, 0, "category").?);
    try std.testing.expectEqualStrings("Clean", set.programInfoByName(10, "Clean", "category").?);
    try std.testing.expectEqual(@as(?usize, 1), set.programInfoCount(10, 0));
    try std.testing.expectEqual(@as(?usize, 0), set.programInfoCountByName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoCount(10, 2));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoCountByName(10, "Missing"));
    try std.testing.expect(set.programHasInfoEntries(10, 0));
    try std.testing.expect(set.programHasInfoEntriesByName(10, "Clean"));
    try std.testing.expect(!set.programHasInfoEntries(10, 1));
    try std.testing.expect(!set.programHasInfoEntriesByName(10, "Drive"));
    try std.testing.expect(!set.programInfoEmpty(10, 0));
    try std.testing.expect(set.programInfoEmpty(10, 1));
    try std.testing.expect(set.programInfoEmpty(10, 2));
    try std.testing.expect(set.programInfoEmptyByName(10, "Missing"));
    try std.testing.expect(set.hasProgramInfo(10, 0, "category"));
    try std.testing.expect(!set.hasProgramInfo(10, 0, "missing"));
    try std.testing.expect(!set.hasProgramInfo(10, 2, "category"));
    try std.testing.expect(set.hasProgramInfoByName(10, "Clean", "category"));
    try std.testing.expect(!set.hasProgramInfoByName(10, "Clean", "missing"));
    try std.testing.expect(!set.hasProgramInfoByName(10, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(10, 0, "missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(10, 2, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(99, 0, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfoByName(10, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfoByName(99, "Clean", "category"));
    try set.validate();
}

test "unit set validates ids names and links" {
    const DuplicateUnits = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = root_unit_id, .name = "Other" } },
    });
    const DuplicateUnitNames = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Root", .parent_id = root_unit_id } },
    });
    const MissingRoot = UnitSet(.{
        .units = &.{.{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id }},
    });
    const EmptyUnitName = UnitSet(.{
        .units = &.{Unit.root("")},
    });
    const InvalidUnitName = UnitSet(.{
        .units = &.{Unit.root("Ro\x00ot")},
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
    const DuplicateProgramListNames = UnitSet(.{
        .program_lists = &.{ .{ .id = 1, .name = "Programs" }, .{ .id = 2, .name = "Programs" } },
    });
    const ReservedProgramListId = UnitSet(.{
        .program_lists = &.{.{ .id = no_program_list_id, .name = "Reserved" }},
    });
    const EmptyProgramListName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "" }},
    });
    const InvalidProgramListName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Pro\x00grams" }},
    });
    const EmptyProgramName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "" }} }},
    });
    const InvalidProgramName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Cle\x00an" }} }},
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
    const InfiniteProgramParameter = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{.{ .parameter_id = 1, .normalized = std.math.inf(f64) }} }} }},
    });
    const EmptyProgramInfoKey = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "", .value = "x" }} }} }},
    });
    const InvalidProgramInfoKey = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "cat\x00egory", .value = "x" }} }} }},
    });
    const InvalidProgramInfoValue = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "category", .value = "cle\x00an" }} }} }},
    });
    const DuplicateProgramInfoKeys = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{ .{ .key = "category", .value = "clean" }, .{ .key = "category", .value = "lead" } } }} }},
    });

    try std.testing.expectError(error.DuplicateUnitId, (DuplicateUnits{}).validate());
    try std.testing.expectError(error.DuplicateUnitName, (DuplicateUnitNames{}).validate());
    try std.testing.expectError(error.MissingRootUnit, (MissingRoot{}).validate());
    try std.testing.expectError(error.EmptyUnitName, (EmptyUnitName{}).validate());
    try std.testing.expectError(error.InvalidUnitMetadata, (InvalidUnitName{}).validate());
    try std.testing.expectError(error.InvalidUnitParent, (InvalidParent{}).validate());
    try std.testing.expectError(error.ReservedUnitId, (ReservedUnitId{}).validate());
    try std.testing.expectError(error.CyclicUnitParent, (CyclicParent{}).validate());
    try std.testing.expectError(error.InvalidUnitProgramList, (InvalidProgramListLink{}).validate());
    try std.testing.expectError(error.DuplicateProgramListId, (DuplicateProgramLists{}).validate());
    try std.testing.expectError(error.DuplicateProgramListName, (DuplicateProgramListNames{}).validate());
    try std.testing.expectError(error.ReservedProgramListId, (ReservedProgramListId{}).validate());
    try std.testing.expectError(error.EmptyProgramListName, (EmptyProgramListName{}).validate());
    try std.testing.expectError(error.InvalidProgramListMetadata, (InvalidProgramListName{}).validate());
    try std.testing.expectError(error.EmptyProgramName, (EmptyProgramName{}).validate());
    try std.testing.expectError(error.InvalidProgramMetadata, (InvalidProgramName{}).validate());
    try std.testing.expectError(error.DuplicateProgramName, (DuplicateProgramNames{}).validate());
    try std.testing.expectError(error.DuplicateProgramParameter, (DuplicateProgramParameters{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (InvalidProgramParameter{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (NanProgramParameter{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (InfiniteProgramParameter{}).validate());
    try std.testing.expectError(error.EmptyProgramInfoKey, (EmptyProgramInfoKey{}).validate());
    try std.testing.expectError(error.InvalidProgramInfoMetadata, (InvalidProgramInfoKey{}).validate());
    try std.testing.expectError(error.InvalidProgramInfoMetadata, (InvalidProgramInfoValue{}).validate());
    try std.testing.expectError(error.DuplicateProgramInfoKey, (DuplicateProgramInfoKeys{}).validate());
}
