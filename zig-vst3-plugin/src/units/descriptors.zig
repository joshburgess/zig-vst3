const std = @import("std");

pub const root_unit_id: i32 = 0;
pub const no_parent_unit_id: i32 = -1;
pub const no_program_list_id: i32 = -1;

pub fn duplicateScalarFieldIndex(comptime T: type, items: []const T, comptime field_name: []const u8) ?usize {
    for (items, 0..) |left, left_index| {
        for (items[left_index + 1 ..], left_index + 1..) |right, right_index| {
            if (@field(right, field_name) == @field(left, field_name)) return right_index;
        }
    }
    return null;
}

pub fn duplicateStringFieldIndex(comptime T: type, items: []const T, comptime field_name: []const u8) ?usize {
    for (items, 0..) |left, left_index| {
        for (items[left_index + 1 ..], left_index + 1..) |right, right_index| {
            if (std.mem.eql(u8, @field(right, field_name), @field(left, field_name))) return right_index;
        }
    }
    return null;
}

pub fn scalarFieldIndex(comptime T: type, items: []const T, comptime field_name: []const u8, value: anytype) ?usize {
    for (items, 0..) |item, index| {
        if (@field(item, field_name) == value) return index;
    }
    return null;
}

pub fn stringFieldIndex(comptime T: type, items: []const T, comptime field_name: []const u8, value: []const u8) ?usize {
    for (items, 0..) |item, index| {
        if (std.mem.eql(u8, @field(item, field_name), value)) return index;
    }
    return null;
}

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

    pub fn duplicateParameterId(self: Program) ?u32 {
        const index = self.duplicateParameterIdIndex() orelse return null;
        return self.parameters[index].parameter_id;
    }

    pub fn duplicateParameterIdIndex(self: Program) ?usize {
        return duplicateScalarFieldIndex(ProgramParameter, self.parameters, "parameter_id");
    }

    pub fn hasDuplicateParameterIds(self: Program) bool {
        return self.duplicateParameterId() != null;
    }

    pub fn duplicateInfoKey(self: Program) ?[]const u8 {
        const index = self.duplicateInfoKeyIndex() orelse return null;
        return self.info[index].key;
    }

    pub fn duplicateInfoKeyIndex(self: Program) ?usize {
        return duplicateStringFieldIndex(ProgramInfo, self.info, "key");
    }

    pub fn hasDuplicateInfoKeys(self: Program) bool {
        return self.duplicateInfoKey() != null;
    }

    pub fn parameter(self: Program, index: usize) ?ProgramParameter {
        if (index >= self.parameters.len) return null;
        return self.parameters[index];
    }

    pub fn parameterIndexOfId(self: Program, parameter_id: u32) ?usize {
        return scalarFieldIndex(ProgramParameter, self.parameters, "parameter_id", parameter_id);
    }

    pub fn parameterById(self: Program, parameter_id: u32) ?ProgramParameter {
        const index = self.parameterIndexOfId(parameter_id) orelse return null;
        return self.parameter(index);
    }

    pub fn hasParameter(self: Program, parameter_id: u32) bool {
        return self.parameterIndexOfId(parameter_id) != null;
    }

    pub fn infoEntry(self: Program, index: usize) ?ProgramInfo {
        if (index >= self.info.len) return null;
        return self.info[index];
    }

    pub fn infoIndexOfKey(self: Program, key: []const u8) ?usize {
        return stringFieldIndex(ProgramInfo, self.info, "key", key);
    }

    pub fn infoEntryByKey(self: Program, key: []const u8) ?ProgramInfo {
        const index = self.infoIndexOfKey(key) orelse return null;
        return self.infoEntry(index);
    }

    pub fn infoValue(self: Program, key: []const u8) ?[]const u8 {
        const index = self.infoIndexOfKey(key) orelse return null;
        return self.info[index].value;
    }

    pub fn hasInfoKey(self: Program, key: []const u8) bool {
        return self.infoIndexOfKey(key) != null;
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

    pub fn duplicateProgramName(self: ProgramList) ?[]const u8 {
        const index = self.duplicateProgramNameIndex() orelse return null;
        return self.programs[index].name;
    }

    pub fn duplicateProgramNameIndex(self: ProgramList) ?usize {
        return duplicateStringFieldIndex(Program, self.programs, "name");
    }

    pub fn hasDuplicateProgramNames(self: ProgramList) bool {
        return self.duplicateProgramName() != null;
    }

    pub fn program(self: ProgramList, index: usize) ?Program {
        if (index >= self.programs.len) return null;
        return self.programs[index];
    }

    pub fn programName(self: ProgramList, index: usize) ?[]const u8 {
        const item = self.program(index) orelse return null;
        return item.name;
    }

    pub fn programIndexOfName(self: ProgramList, name: []const u8) ?usize {
        return stringFieldIndex(Program, self.programs, "name", name);
    }

    pub fn programByName(self: ProgramList, name: []const u8) ?Program {
        const index = self.programIndexOfName(name) orelse return null;
        return self.program(index);
    }

    pub fn hasProgramName(self: ProgramList, name: []const u8) bool {
        return self.programIndexOfName(name) != null;
    }
};

pub const Config = struct {
    units: []const Unit = &.{Unit.root("Root")},
    program_lists: []const ProgramList = &.{},
};

test "unit descriptors expose root, parent, and program list flags" {
    const root = Unit.root("Main");
    try std.testing.expect(root.isRoot());
    try std.testing.expect(!root.hasParent());
    try std.testing.expect(!root.hasProgramList());
    try std.testing.expectEqual(root_unit_id, root.id);
    try std.testing.expectEqual(no_parent_unit_id, root.parent_id);

    const child = Unit{
        .id = 1,
        .name = "Voice",
        .parent_id = root_unit_id,
        .program_list_id = 7,
    };
    try std.testing.expect(!child.isRoot());
    try std.testing.expect(child.hasParent());
    try std.testing.expect(child.hasProgramList());
}

test "program descriptors expose parameters and duplicate ids" {
    const program = Program{
        .name = "Lead",
        .parameters = &.{
            .{ .parameter_id = 10, .normalized = 0.25 },
            .{ .parameter_id = 20, .normalized = 0.5 },
            .{ .parameter_id = 10, .normalized = 0.75 },
        },
    };

    try std.testing.expectEqual(@as(usize, 3), program.parameterCount());
    try std.testing.expect(program.hasParameters());
    try std.testing.expect(!program.parametersEmpty());
    try std.testing.expectEqual(@as(?usize, 2), program.duplicateParameterIdIndex());
    try std.testing.expectEqual(@as(?u32, 10), program.duplicateParameterId());
    try std.testing.expect(program.hasDuplicateParameterIds());
    try std.testing.expectEqual(ProgramParameter{ .parameter_id = 20, .normalized = 0.5 }, program.parameterById(20).?);
    try std.testing.expectEqual(@as(?ProgramParameter, null), program.parameter(99));
    try std.testing.expect(program.hasParameter(10));
    try std.testing.expect(!program.hasParameter(99));
}

test "program descriptors expose info entries and duplicate keys" {
    const program = Program{
        .name = "Bass",
        .info = &.{
            .{ .key = "author", .value = "A" },
            .{ .key = "category", .value = "Bass" },
            .{ .key = "author", .value = "B" },
        },
    };

    try std.testing.expectEqual(@as(usize, 3), program.infoCount());
    try std.testing.expect(program.hasInfo());
    try std.testing.expect(!program.infoEmpty());
    try std.testing.expectEqual(@as(?usize, 2), program.duplicateInfoKeyIndex());
    try std.testing.expectEqualStrings("author", program.duplicateInfoKey().?);
    try std.testing.expect(program.hasDuplicateInfoKeys());
    try std.testing.expectEqualStrings("Bass", program.infoValue("category").?);
    try std.testing.expectEqual(@as(?ProgramInfo, null), program.infoEntry(99));
    try std.testing.expect(program.hasInfoKey("author"));
    try std.testing.expect(!program.hasInfoKey("missing"));
}

test "program list descriptors expose programs and duplicate names" {
    const list = ProgramList{
        .id = 7,
        .name = "Voice Programs",
        .programs = &.{
            .{ .name = "Init" },
            .{ .name = "Lead" },
            .{ .name = "Lead" },
        },
    };

    try std.testing.expectEqual(@as(usize, 3), list.programCount());
    try std.testing.expect(!list.isEmpty());
    try std.testing.expect(list.hasPrograms());
    try std.testing.expectEqual(@as(?usize, 2), list.duplicateProgramNameIndex());
    try std.testing.expectEqualStrings("Lead", list.duplicateProgramName().?);
    try std.testing.expect(list.hasDuplicateProgramNames());
    try std.testing.expectEqualStrings("Init", list.programName(0).?);
    try std.testing.expectEqual(@as(?usize, 1), list.programIndexOfName("Lead"));
    try std.testing.expectEqual(@as(?Program, null), list.program(99));
    try std.testing.expect(list.hasProgramName("Lead"));
    try std.testing.expect(!list.hasProgramName("missing"));
}
